import Foundation
import Darwin
import Testing
@testable import MacDevCleanApp

private func mapFixture(_ name: String, _ bytes: Int64) -> DiskMapNode {
    DiskMapNode(id: name, name: name, path: "/test/\(name)", bytes: bytes, isDirectory: false)
}

@Test func diskMapTreemapPreservesAreaAndHasNoOverlap() {
    let nodes = [mapFixture("a", 55), mapFixture("b", 25), mapFixture("c", 15), mapFixture("d", 5), mapFixture("zero", 0)]
    let bounds = CGRect(x: 0, y: 0, width: 640, height: 400)
    let tiles = DiskMapLayout.tiles(nodes, in: bounds)
    #expect(tiles.count == 4)
    for tile in tiles {
        #expect(bounds.contains(tile.rect))
        #expect(abs(tile.rect.width * tile.rect.height / (640 * 400) - Double(tile.node.bytes) / 100) < 0.00001)
        for other in tiles where tile.id != other.id {
            let intersection = tile.rect.intersection(other.rect)
            #expect(intersection.isNull || intersection.width * intersection.height == 0)
        }
    }
    #expect(DiskMapLayout.tiles(nodes, in: .zero).isEmpty)
    #expect(DiskMapLayout.tiles([], in: bounds).isEmpty)
}

@Test func diskMapCategoriesIgnoreDataVolumePrefix() {
    #expect(DiskMapCategory.classify("/System/Volumes/Data/Users/test/Pictures/photo.heic") == .media)
    #expect(DiskMapCategory.classify("/System/Volumes/Data/Applications/Xcode.app") == .applications)
    #expect(DiskMapCategory.classify("/Users/test/Library/Developer/Xcode") == .developer)
    #expect(DiskMapCategory.classify("/Users/test/Library/Caches/tool") == .caches)
    #expect(DiskMapCategory.classify("/System/Volumes/Data/Users/test") == .other)
    #expect(DiskMapCategory.classify("/System/Volumes/Data/Library/Logs") == .system)
}

@Test func diskMapCountsAllocatedBlocksAndHardLinksOnceWithoutFollowingSymlinks() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("disk-map-\(UUID())")
    let outside = fm.temporaryDirectory.appendingPathComponent("disk-map-outside-\(UUID())")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root); try? fm.removeItem(at: outside) }
    let file = root.appendingPathComponent("original")
    try Data(repeating: 42, count: 8192).write(to: file)
    try fm.linkItem(at: file, to: root.appendingPathComponent("hardlink"))
    try Data(repeating: 1, count: 32768).write(to: outside.appendingPathComponent("external"))
    try fm.createSymbolicLink(at: root.appendingPathComponent("symbolic"), withDestinationURL: outside)
    let sparse = root.appendingPathComponent("sparse")
    fm.createFile(atPath: sparse.path, contents: nil)
    let handle = try FileHandle(forWritingTo: sparse)
    try handle.truncate(atOffset: 50_000_000)
    try handle.close()

    let report = try DiskMapScanner().scan(path: root.path)
    func allocated(_ url: URL) -> Int64 {
        var info = stat()
        #expect(lstat(url.path, &info) == 0)
        return Int64(info.st_blocks) * 512
    }
    #expect(report.root.bytes == allocated(root) + allocated(file) + allocated(sparse) + allocated(root.appendingPathComponent("symbolic")))
    #expect(report.root.children.filter { ["original", "hardlink"].contains($0.name) }.count == 1)
    let symlink = try #require(report.root.children.first { $0.name == "symbolic" })
    #expect(!symlink.isDirectory)
    #expect(symlink.children.isEmpty)
    #expect(report.skipped == 0)
    #expect(report.root.children.reduce(Int64(0)) { $0 + $1.bytes } == report.root.bytes)
}

@Test func diskMapBoundsRetainedEntriesButCountsDeepAndSmallFiles() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("disk-map-bounded-\(UUID())")
    let nested = root.appendingPathComponent("a/b/c/d")
    try fm.createDirectory(at: nested, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    for i in 0..<80 {
        try Data(repeating: 7, count: 4096).write(to: root.appendingPathComponent("item-\(i)"))
    }
    try Data(repeating: 8, count: 16384).write(to: nested.appendingPathComponent("deep"))
    let report = try DiskMapScanner().scan(path: root.path)
    #expect(report.root.children.count <= 65)
    #expect(report.root.children.contains { $0.path == nil && $0.bytes > 0 })
    #expect(report.root.children.reduce(Int64(0)) { $0 + $1.bytes } == report.root.bytes)
    let a = try #require(report.root.children.first { $0.name == "a" })
    #expect(a.bytes >= 16384)
    let b = try #require(a.children.first { $0.name == "b" })
    #expect(b.children.isEmpty)
    #expect(try DiskMapScanner().scan(path: nested.path).root.children.contains { $0.name == "deep" })
}

@Test func diskMapCancellationDoesNotReturnPartialSuccess() async throws {
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try DiskMapScanner().scan(path: FileManager.default.temporaryDirectory.path)
    }
    do {
        _ = try await task.value
        Issue.record("Cancelled scanner should throw")
    } catch is CancellationError {
        // Expected; cancellation is checked before enumeration.
    }
}

@Test func diskMapMissingRootFailsInsteadOfReturningAnEmptyMap() {
    #expect(throws: (any Error).self) {
        try DiskMapScanner().scan(path: "/not-a-real-disk-map-folder-\(UUID())")
    }
}

@Test func diskMapUnaccountedSpaceNeverBecomesNegative() {
    let report = DiskMapReport(root: mapFixture("root", 200), capacity: 150, free: 50,
                               skipped: 0, skippedMounts: 0, issuePaths: [], scannedAt: Date(), wholeDisk: true)
    #expect(report.unaccounted == 0)
    #expect(report.exceedsUsed)
}

@Test func diskMapReportsUnreadableFoldersWithoutPretendingTheyAreEmpty() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("disk-map-denied-\(UUID())")
    let denied = root.appendingPathComponent("private")
    try fm.createDirectory(at: denied, withIntermediateDirectories: true)
    defer {
        chmod(denied.path, 0o700)
        try? fm.removeItem(at: root)
    }
    try Data(repeating: 1, count: 4096).write(to: denied.appendingPathComponent("secret"))
    #expect(chmod(denied.path, 0) == 0)
    let report = try DiskMapScanner().scan(path: root.path)
    #expect(report.skipped == 1)
    #expect(report.issuePaths == [denied.path])
    #expect(report.root.children.contains { $0.path == denied.path })
}

@Test @MainActor func diskMapNavigationRestoresFolderAndFailedOrCancelledScansKeepSnapshot() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("disk-map-navigation-\(UUID())")
    let nested = root.appendingPathComponent("a/b/c")
    try fm.createDirectory(at: nested, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    try Data(repeating: 3, count: 4096).write(to: nested.appendingPathComponent("file"))
    let model = DiskMapModel()
    func waitForScan() async throws {
        let deadline = Date().addingTimeInterval(5)
        while model.isScanning && Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!model.isScanning)
    }
    model.scan(path: root.path, wholeDisk: false)
    try await waitForScan()
    let a = try #require(model.current?.children.first { $0.name == "a" })
    model.open(a)
    let b = try #require(model.current?.children.first { $0.name == "b" })
    model.open(b)
    try await waitForScan()
    #expect(model.current?.path == b.path)
    model.back()
    #expect(model.current?.path == a.path)
    let previous = model.report?.root
    model.scan(path: root.appendingPathComponent("missing").path, wholeDisk: false)
    try await waitForScan()
    #expect(model.report?.root == previous)
    #expect(model.message?.contains("Could not scan") == true)
    model.scan(path: root.path, wholeDisk: false)
    model.cancel()
    try await waitForScan()
    #expect(model.report?.root == previous)
    #expect(model.message?.contains("cancelled") == true)
}

private func volumeID(_ path: String) throws -> DiskMapVolumeID {
    let fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
    try #require(fd >= 0)
    defer { close(fd) }
    return try #require(DiskMapVolumeID(fd: fd))
}

@Test(.enabled(if: FileManager.default.fileExists(atPath: "/System/Volumes/Data")))
func diskMapVolumeIDSeparatesStartupSystemAndDataVolumes() throws {
    // System and Data share st_dev in an APFS volume group; only f_fsid tells them apart.
    #expect(try volumeID("/") != volumeID("/System/Volumes/Data"))
    #expect(try volumeID("/Users") == volumeID("/System/Volumes/Data"))
}

@Test(.enabled(if: FileManager.default.fileExists(atPath: "/System/Volumes/Data")))
func diskMapDoesNotCrossFromSystemVolumeIntoData() throws {
    // /System/Volumes/Data shares the System volume's st_dev. Without the f_fsid check
    // this walks the entire Data volume; with an empty mount table only f_fsid stops it.
    for mounts in [DiskMapMountTable(paths: []), nil] {
        let report = try DiskMapScanner(mounts: mounts).scan(path: "/System/Volumes")
        #expect(!report.root.children.contains { $0.name == "Data" })
        #expect(report.skippedMounts >= 1)
        #expect(report.root.bytes < 10_000_000)
    }
}

@Test func diskMapMountTableMatchesDirectAndDataVolumePaths() {
    let mounts = DiskMapMountTable(paths: ["/Volumes/External", "/System/Volumes/Data/home"])
    #expect(mounts.contains("/Volumes/External"))
    #expect(mounts.contains("/System/Volumes/Data/Volumes/External"))
    #expect(mounts.contains("/System/Volumes/Data/home"))
    #expect(!mounts.contains("/Volumes"))
    #expect(!mounts.contains("/Volumes/External2"))
    #expect(!mounts.contains("/Volumes/External/inside"))
    #expect(DiskMapMountTable.current().contains("/"))
}

@Test func diskMapSkipsMountPointsByPathBeforeStat() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("disk-map-mounts-\(UUID())")
    let mounted = root.appendingPathComponent("mounted")
    try fm.createDirectory(at: mounted, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    try Data(repeating: 9, count: 65536).write(to: mounted.appendingPathComponent("remote"))
    try Data(repeating: 9, count: 4096).write(to: root.appendingPathComponent("local"))
    let report = try DiskMapScanner(mounts: DiskMapMountTable(paths: [mounted.path])).scan(path: root.path)
    #expect(report.skippedMounts == 1)
    #expect(report.skipped == 0)
    #expect(!report.root.children.contains { $0.name == "mounted" })
    #expect(report.root.children.contains { $0.name == "local" })
    #expect(report.root.bytes < 65536)
}

@Test func diskMapScanDisablesDatalessMaterializationAndRestoresPolicy() {
    let before = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
    let inside = DiskMapScanner.withoutMaterializingDataless {
        getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
    }
    #expect(inside == IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
    #expect(getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD) == before)

    var info = stat()
    #expect(!DiskMapScanner.isDataless(info))
    info.st_flags = UInt32(SF_DATALESS)
    #expect(DiskMapScanner.isDataless(info))
}

@Test func diskMapLargestEntriesMatchesFullSortForLargeFolders() {
    // Ties on size exercise the id tie-break that keeps retention deterministic.
    let nodes = (0..<10_000).map { mapFixture(String(format: "n%05d", $0), Int64($0 % 997)) }.shuffled()
    var largest = DiskMapLargestEntries(limit: 64)
    for node in nodes { largest.insert(node) }
    let expected = Array(nodes.sorted(by: DiskMapLargestEntries.precedes).prefix(64))
    #expect(largest.result().map(\.id) == expected.map(\.id))

    var few = DiskMapLargestEntries(limit: 64)
    for node in nodes.prefix(10) { few.insert(node) }
    #expect(few.result().map(\.id) == nodes.prefix(10).sorted(by: DiskMapLargestEntries.precedes).map(\.id))
}

@Test func diskMapParallelWalkMatchesSingleThreadedWalk() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("disk-map-parallel-\(UUID())")
    defer { try? fm.removeItem(at: root) }
    for folder in 0..<12 {
        let nested = root.appendingPathComponent("f\(folder)/a/b")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        for file in 0..<5 {
            try Data(repeating: 1, count: 4096 * (file + 1)).write(to: nested.appendingPathComponent("x\(file)"))
        }
    }
    var single = DiskMapScanner()
    single.workerCount = 1
    var parallel = DiskMapScanner()
    parallel.workerCount = 8
    let expected = try single.scan(path: root.path)
    for _ in 0..<5 {
        let report = try parallel.scan(path: root.path)
        #expect(report.root == expected.root)
        #expect(report.skipped == 0)
    }
}

@Test func diskMapReportsVolumeSpaceUsedWithoutWalking() throws {
    let used = try #require(DiskMapScanner.volumeSpaceUsed("/"))
    #expect(used > 0)
    #expect(DiskMapScanner.volumeSpaceUsed("/not-a-real-volume-\(UUID())") == nil)
}
