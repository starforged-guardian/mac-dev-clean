import Foundation
import Darwin

struct DiskMapNode: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let path: String?
    let bytes: Int64
    let isDirectory: Bool
    var children: [DiskMapNode] = []

    var category: DiskMapCategory { DiskMapCategory.classify(path ?? "") }
}

enum DiskMapCategory: String, CaseIterable, Sendable {
    case applications = "Applications", developer = "Developer", caches = "Caches"
    case media = "Media", documents = "Documents", system = "System", other = "Other"

    static func classify(_ path: String) -> Self {
        let parts = path.lowercased().split(separator: "/").map(String.init)
        if parts.contains(where: { ["caches", ".cache", "_cacache"].contains($0) }) { return .caches }
        if parts.contains(where: { ["developer", "node_modules", ".git", ".build", "deriveddata", ".cargo", ".gradle"].contains($0) }) { return .developer }
        if parts.contains("applications") || parts.contains(where: { $0.hasSuffix(".app") }) { return .applications }
        if parts.contains(where: { ["pictures", "movies", "music"].contains($0) }) { return .media }
        if parts.contains(where: { ["documents", "desktop", "downloads"].contains($0) }) { return .documents }
        // The Data volume prefix is an implementation detail, not a file category.
        let normalized = path.replacingOccurrences(of: "/System/Volumes/Data", with: "")
        if ["/System", "/Library", "/usr", "/bin", "/sbin", "/private"].contains(where: {
            normalized == $0 || normalized.hasPrefix($0 + "/")
        }) { return .system }
        return .other
    }
}

struct DiskMapReport: Sendable {
    let root: DiskMapNode
    let capacity: Int64
    let free: Int64
    let skipped: Int
    let skippedMounts: Int
    let issuePaths: [String]
    let scannedAt: Date
    let wholeDisk: Bool

    var excludedCount: Int = 0
    var excludedPaths: [String] = []

    var used: Int64 { max(0, capacity - free) }
    var unaccounted: Int64 { max(0, used - root.bytes) }
    var exceedsUsed: Bool { root.bytes > used }
}

/// Pure path checks run before stat/open so exclusions cannot trigger access prompts.
/// Apply to folder scans too, including rescans and drill-down from older snapshots.
struct DiskMapExclusions: Sendable {
    var homePaths: [String] = [FileManager.default.homeDirectoryForCurrentUser.path]

    func contains(_ path: String) -> Bool {
        let normalized = Self.normalized(path)
        let parts = normalized.split(separator: "/").map(String.init)
        let personal: Set<String> = ["desktop", "documents", "downloads", "pictures", "movies", "music", ".trash"]
        // Modern file-provider roots and older provider-specific folders. Match
        // components, never substrings such as a project's OneDriveClient folder.
        if parts.contains(where: { component in
            ["cloudstorage", "mobile documents", "icloud drive", "icloud", "dropbox", "google drive",
             "googledrive", "box", "box sync", "pcloud drive", "onedrive", ".dropbox", ".onedrive"].contains(component)
                || component.hasPrefix("onedrive-") || component.hasPrefix("onedrive - ")
                || component.hasPrefix("googledrive-") || component.hasPrefix("dropbox (")
                || component.hasSuffix(".photoslibrary") || component.hasSuffix(".photolibrary")
        }) { return true }

        var relative: [String]?
        // Cover every user's home, including the startup Data-volume alias.
        if parts.count >= 3, parts[0] == "users" {
            relative = Array(parts.dropFirst(2))
        }
        for home in homePaths {
            let prefix = Self.normalized(home) + "/"
            if normalized.hasPrefix(prefix) {
                relative = String(normalized.dropFirst(prefix.count)).split(separator: "/").map(String.init)
                break
            }
        }
        guard let relative, let first = relative.first else { return false }
        if personal.contains(first) { return true }
        // User Library is mostly private app data. Only traverse the storage
        // areas needed for developer inspection; skip Mail, Messages, Safari,
        // Containers, Group Containers, Application Support, and similar stores.
        if first == "library", relative.count > 1 {
            guard ["developer", "caches", "logs"].contains(relative[1]) else { return true }
            // Safari and personal-data services can also have protected caches.
            if relative.dropFirst(2).contains(where: {
                $0.hasPrefix("com.apple.safari") || $0.hasPrefix("com.apple.mail")
                    || $0.hasPrefix("com.apple.messages") || $0.hasPrefix("com.apple.homed")
            }) { return true }
        }
        return false
    }

    private static func normalized(_ path: String) -> String {
        // Walker paths are already clean. Skipping NSString for them also avoids
        // autoreleased objects piling up during a long scan with no pool to drain them.
        let clean = path.hasPrefix("/") && !path.contains("//") && (path == "/" || !path.hasSuffix("/"))
            && !path.split(separator: "/").contains { $0 == "." || $0 == ".." }
        let standardized = (clean ? path : (path as NSString).standardizingPath).lowercased()
        let prefix = "/system/volumes/data"
        if standardized == prefix { return "/" }
        if standardized.hasPrefix(prefix + "/") { return String(standardized.dropFirst(prefix.count)) }
        return standardized
    }
}

private struct DiskMapExcludedLocation: LocalizedError {
    var errorDescription: String? {
        "This location is excluded from Disk Map to avoid personal-folder and cloud-storage permission prompts. Choose a local project or developer-storage folder instead."
    }
}

/// Filesystem identity from statfs. Volumes in an APFS group (System and Data) share
/// st_dev, so firmlinks from the System volume into Data are only visible through f_fsid.
struct DiskMapVolumeID: Hashable, Sendable {
    let major: Int32
    let minor: Int32

    init?(fd: Int32) {
        var info = Darwin.statfs()
        guard fstatfs(fd, &info) == 0 else { return nil }
        major = info.f_fsid.val.0
        minor = info.f_fsid.val.1
    }
}

/// Mount points from the kernel's mount list. They are matched by path before any
/// stat, because stat on a mount point enters that filesystem and a stale network
/// share can block in the kernel where cancellation cannot interrupt it.
struct DiskMapMountTable: Sendable {
    var paths: Set<String>

    /// MNT_NOWAIT returns cached statistics without contacting the mounted filesystems.
    static func current() -> Self {
        let count = getfsstat(nil, 0, MNT_NOWAIT)
        guard count > 0 else { return Self(paths: []) }
        // Spare room for mounts that appear between the two calls.
        var buffer = Array(repeating: Darwin.statfs(), count: Int(count) + 8)
        let filled = buffer.withUnsafeMutableBufferPointer {
            getfsstat($0.baseAddress, Int32(MemoryLayout<Darwin.statfs>.stride * $0.count), MNT_NOWAIT)
        }
        let paths = buffer.prefix(max(0, Int(filled))).map { info in
            var name = info.f_mntonname
            return withUnsafePointer(to: &name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
            }
        }
        return Self(paths: Set(paths))
    }

    /// Also matches mounts reached through the Data volume root, such as
    /// /System/Volumes/Data/Volumes/External for a disk mounted at /Volumes/External.
    func contains(_ path: String) -> Bool {
        if paths.contains(path) { return true }
        let dataRoot = "/System/Volumes/Data"
        return path.hasPrefix(dataRoot + "/") && paths.contains(String(path.dropFirst(dataRoot.count)))
    }
}

/// Keeps the largest entries without re-sorting on every insert: entries accumulate
/// to twice the limit before one sort trims them, and anything that cannot beat the
/// current smallest retained entry is dropped immediately.
struct DiskMapLargestEntries {
    let limit: Int
    private var nodes: [DiskMapNode] = []
    private var floor: DiskMapNode?

    init(limit: Int) { self.limit = limit }

    static func precedes(_ lhs: DiskMapNode, _ rhs: DiskMapNode) -> Bool {
        lhs.bytes == rhs.bytes ? lhs.id < rhs.id : lhs.bytes > rhs.bytes
    }

    /// Lets callers skip building a node that `insert` would drop.
    func mightKeep(_ bytes: Int64) -> Bool { floor.map { bytes >= $0.bytes } ?? true }

    mutating func insert(_ node: DiskMapNode) {
        if let floor, !Self.precedes(node, floor) { return }
        nodes.append(node)
        if nodes.count >= limit * 2 { trim() }
    }

    mutating func result() -> [DiskMapNode] {
        trim()
        return nodes
    }

    private mutating func trim() {
        nodes.sort(by: Self.precedes)
        if nodes.count > limit { nodes.removeLast(nodes.count - limit) }
        if nodes.count == limit { floor = nodes.last }
    }
}

/// Metadata only: never reads file contents, follows symlinks, or enters other mounts.
/// A startup-disk scan walks the Data volume and sizes the sealed, read-only System
/// volume from its reported usage; opening that tile walks it on demand.
struct DiskMapScanner: Sendable {
    var exclusions = DiskMapExclusions()
    /// Read from the kernel at scan time when nil.
    var mounts: DiskMapMountTable?
    /// Threads that list directories. SSD metadata reads scale with parallel requests,
    /// and the utility QoS keeps them behind interactive I/O.
    var workerCount = min(8, max(1, ProcessInfo.processInfo.activeProcessorCount))

    /// Cloud placeholders (dataless files and folders) download when read. With
    /// materialization off for this thread, a placeholder the path exclusions miss
    /// fails with an error instead of fetching. The scan is synchronous, so it stays
    /// on one thread for the whole body.
    static func withoutMaterializingDataless<T>(_ body: () throws -> T) rethrows -> T {
        let previous = getiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD)
        _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD,
                           IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        defer {
            if previous >= 0 {
                _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD, previous)
            }
        }
        return try body()
    }

    static func isDataless(_ info: stat) -> Bool { isDataless(flags: info.st_flags) }
    static func isDataless(flags: UInt32) -> Bool { flags & UInt32(SF_DATALESS) != 0 }

    /// Space used by one volume, as `df` reports it, without walking the volume.
    static func volumeSpaceUsed(_ path: String) -> Int64? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.volattr = attrgroup_t(ATTR_VOL_INFO) | attrgroup_t(ATTR_VOL_SPACEUSED)
        // u_int32_t length followed by a packed off_t.
        var buffer = [UInt8](repeating: 0, count: 16)
        let status = buffer.withUnsafeMutableBytes {
            getattrlist(path, &request, $0.baseAddress, $0.count, UInt32(FSOPT_NOFOLLOW))
        }
        guard status == 0 else { return nil }
        return buffer.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: Int64.self) }
    }

    func scan(path: String, wholeDisk: Bool = false) throws -> DiskMapReport {
        try Self.withoutMaterializingDataless { try scanMetadata(path: path, wholeDisk: wholeDisk) }
    }

    private func scanMetadata(path: String, wholeDisk: Bool) throws -> DiskMapReport {
        if !wholeDisk, exclusions.contains(path) { throw DiskMapExcludedLocation() }
        let walker = Walker(exclusions: exclusions, mounts: mounts ?? .current(), workerCount: workerCount)
        let dataRoot = "/System/Volumes/Data"
        let hasDataRoot = wholeDisk && FileManager.default.fileExists(atPath: dataRoot)
        let capacityPath = hasDataRoot ? dataRoot : path
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: capacityPath)
        let total = (attributes[.systemSize] as? NSNumber)?.int64Value ?? 0
        let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
        let root: DiskMapNode
        if hasDataRoot {
            let data = try walker.walk(dataRoot, name: "Data · apps & personal files")
            // The sealed System volume is read-only and holds nothing cleanable, so its
            // size comes from the volume instead of a walk of ~500k files.
            let system = DiskMapNode(id: "/", name: "macOS system", path: "/",
                                     bytes: Self.volumeSpaceUsed("/") ?? 0, isDirectory: true)
            root = DiskMapNode(id: "startup-disk", name: "Startup disk", path: nil,
                               bytes: data.bytes + system.bytes, isDirectory: true, children: data.children + [system])
        } else {
            root = try walker.walk(path)
        }
        let stats = walker.stats
        return DiskMapReport(root: root, capacity: total, free: free, skipped: stats.skipped,
                             skippedMounts: stats.skippedMounts, issuePaths: stats.issuePaths,
                             scannedAt: Date(), wholeDisk: wholeDisk,
                             excludedCount: stats.excludedCount, excludedPaths: stats.excludedPaths)
    }

    /// One entry from getattrlistbulk. Field order follows the attribute bit order,
    /// except ATTR_CMN_ERROR, which always follows ATTR_CMN_RETURNED_ATTRS.
    struct BulkEntry {
        var error: UInt32 = 0
        var name: UnsafePointer<CChar>?
        var device: Int32 = 0
        var type: UInt32 = 0
        var flags: UInt32 = 0
        var fileID: UInt64 = 0
        var mountStatus: UInt32 = 0
        var linkCount: UInt32 = 0
        var allocated: Int64 = 0

        static let request: attrlist = {
            var request = attrlist()
            request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
            request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_ERROR)
                | attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_OBJTYPE)
                | attrgroup_t(ATTR_CMN_FLAGS) | attrgroup_t(ATTR_CMN_FILEID)
            // Reported from the parent listing, so mount points are found without entering them.
            request.dirattr = attrgroup_t(ATTR_DIR_MOUNTSTATUS)
            request.fileattr = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)
            return request
        }()

        init(_ entry: UnsafeRawPointer) {
            var field = entry + MemoryLayout<UInt32>.size
            let returned = field.loadUnaligned(as: attribute_set_t.self)
            field += MemoryLayout<attribute_set_t>.size
            func has(_ set: attrgroup_t, _ bit: Int32) -> Bool { set & attrgroup_t(truncatingIfNeeded: bit) != 0 }
            func next<T>(_ type: T.Type) -> T {
                defer { field += MemoryLayout<T>.size }
                return field.loadUnaligned(as: T.self)
            }
            if has(returned.commonattr, ATTR_CMN_ERROR) { error = next(UInt32.self) }
            if has(returned.commonattr, ATTR_CMN_NAME) {
                let reference = field.loadUnaligned(as: attrreference_t.self)
                name = (field + Int(reference.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                field += MemoryLayout<attrreference_t>.size
            }
            if has(returned.commonattr, ATTR_CMN_DEVID) { device = next(Int32.self) }
            if has(returned.commonattr, ATTR_CMN_OBJTYPE) { type = next(UInt32.self) }
            if has(returned.commonattr, ATTR_CMN_FLAGS) { flags = next(UInt32.self) }
            if has(returned.commonattr, ATTR_CMN_FILEID) { fileID = next(UInt64.self) }
            if has(returned.dirattr, ATTR_DIR_MOUNTSTATUS) { mountStatus = next(UInt32.self) }
            if has(returned.fileattr, ATTR_FILE_LINKCOUNT) { linkCount = next(UInt32.self) }
            if has(returned.fileattr, ATTR_FILE_ALLOCSIZE) { allocated = next(Int64.self) }
        }
    }

    struct Stats {
        var skipped = 0
        var skippedMounts = 0
        var issuePaths: [String] = []
        var excludedCount = 0
        var excludedPaths: [String] = []
    }

    private struct FileKey: Hashable {
        let device: Int32
        let fileID: UInt64
    }

    /// A subdirectory handed to another worker. The open descriptor belongs to whoever
    /// claims the job, or to the parent that abandons it unclaimed.
    private final class Job: @unchecked Sendable {
        let fd: Int32
        let path: String
        let name: String
        let ownBytes: Int64
        let depth: Int
        // Guarded by Walker.lock.
        var claimed = false
        var result: Result<DiskMapNode, Error>?

        init(fd: Int32, path: String, name: String, ownBytes: Int64, depth: Int) {
            self.fd = fd
            self.path = path
            self.name = name
            self.ownBytes = ownBytes
            self.depth = depth
        }
    }

    /// Fork-join walk. Each thread lists directories depth-first and hands a
    /// subdirectory to the shared queue only while another thread is idle. A parent
    /// whose handed-off child has not started yet runs it itself, so the walk cannot
    /// deadlock and the queue stays no longer than the idle count.
    private final class Walker: @unchecked Sendable {
        static let bufferSize = 256 * 1024
        /// Every thread holds one descriptor per level of its current path. Leave most
        /// of the app's default 256-descriptor limit for everything else.
        static let descriptorBudget = 128
        static let maxDepth = 256

        let exclusions: DiskMapExclusions
        let mounts: DiskMapMountTable
        let workerCount: Int
        private var device: dev_t = 0
        private var volume: DiskMapVolumeID?

        // Guarded by `lock`.
        private let lock = NSCondition()
        private var queue: [Job] = []
        private var idle = 0
        private var running = 0
        private var finished = false
        private var cancelled = false
        private var openDescriptors = 0

        // Guarded by `statsLock`.
        private let statsLock = NSLock()
        private var collected = Stats()
        private var hardLinks: Set<FileKey> = []

        var stats: Stats { statsLock.withLock { collected } }

        init(exclusions: DiskMapExclusions, mounts: DiskMapMountTable, workerCount: Int) {
            self.exclusions = exclusions
            self.mounts = mounts
            self.workerCount = max(1, workerCount)
        }

        private func issue(_ path: String) {
            statsLock.withLock {
                collected.skipped += 1
                if collected.issuePaths.count < 8 { collected.issuePaths.append(path) }
            }
        }

        private func exclude(_ path: String) {
            statsLock.withLock {
                collected.excludedCount += 1
                if collected.excludedPaths.count < 12 { collected.excludedPaths.append(path) }
            }
        }

        private func skipMount() { statsLock.withLock { collected.skippedMounts += 1 } }

        private func firstLink(_ key: FileKey) -> Bool { statsLock.withLock { hardLinks.insert(key).inserted } }

        /// Task cancellation is only visible on the calling thread; it publishes it to the workers.
        private func checkCancelled() throws {
            let isCancelled = Task.isCancelled
            let stop = lock.withLock {
                if isCancelled { cancelled = true }
                return cancelled
            }
            if stop { throw CancellationError() }
        }

        private func reserveDescriptor() -> Bool {
            lock.withLock {
                guard openDescriptors < Self.descriptorBudget else { return false }
                openDescriptors += 1
                return true
            }
        }

        private func releaseDescriptor() { lock.withLock { openDescriptors -= 1 } }

        func walk(_ path: String, name: String? = nil) throws -> DiskMapNode {
            let fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EACCES) }
            var info = stat()
            guard fstat(fd, &info) == 0, let volume = DiskMapVolumeID(fd: fd) else {
                close(fd)
                throw POSIXError(.EIO)
            }
            device = info.st_dev
            self.volume = volume
            lock.withLock { openDescriptors += 1 }
            for _ in 1..<workerCount {
                let thread = Thread { [self] in work() }
                thread.qualityOfService = .utility
                thread.stackSize = 8 << 20
                thread.start()
            }
            defer { shutDown() }
            let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: Self.bufferSize, alignment: 16)
            defer { buffer.deallocate() }
            return try directory(fd: fd, path: path, name: name ?? URL(fileURLWithPath: path).lastPathComponent,
                                 ownBytes: max(0, Int64(info.st_blocks) * 512), depth: 0, buffer: buffer)
        }

        /// Stops the workers and waits until none is still touching the disk.
        private func shutDown() {
            lock.lock()
            finished = true
            for job in queue {
                close(job.fd)
                openDescriptors -= 1
            }
            queue.removeAll()
            lock.broadcast()
            while running > 0 { lock.wait() }
            lock.unlock()
        }

        private func work() {
            Self.disableMaterialization()
            let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: Self.bufferSize, alignment: 16)
            defer { buffer.deallocate() }
            lock.lock()
            while !finished {
                guard let job = queue.popLast() else {
                    idle += 1
                    lock.wait()
                    idle -= 1
                    continue
                }
                job.claimed = true
                running += 1
                lock.unlock()
                let result = Result {
                    try directory(fd: job.fd, path: job.path, name: job.name, ownBytes: job.ownBytes,
                                  depth: job.depth, buffer: buffer)
                }
                lock.lock()
                running -= 1
                job.result = result
                lock.broadcast()
            }
            lock.unlock()
        }

        private static func disableMaterialization() {
            _ = setiopolicy_np(IOPOL_TYPE_VFS_MATERIALIZE_DATALESS_FILES, IOPOL_SCOPE_THREAD,
                               IOPOL_MATERIALIZE_DATALESS_FILES_OFF)
        }

        /// Queues the subdirectory if a worker is idle; otherwise the caller walks it inline.
        private func offer(fd: Int32, path: String, name: String, ownBytes: Int64, depth: Int) -> Job? {
            lock.withLock {
                guard !finished, idle > queue.count else { return nil }
                let job = Job(fd: fd, path: path, name: name, ownBytes: ownBytes, depth: depth)
                queue.append(job)
                lock.signal()
                return job
            }
        }

        private func wait(for job: Job, buffer: UnsafeMutableRawBufferPointer) throws -> DiskMapNode {
            lock.lock()
            if !job.claimed {
                job.claimed = true
                queue.removeAll { $0 === job }
                lock.unlock()
                return try directory(fd: job.fd, path: job.path, name: job.name, ownBytes: job.ownBytes,
                                     depth: job.depth, buffer: buffer)
            }
            while job.result == nil {
                // Wake periodically so the calling thread can notice task cancellation.
                _ = lock.wait(until: Date(timeIntervalSinceNow: 0.05))
                if Task.isCancelled { cancelled = true }
            }
            lock.unlock()
            return try job.result!.get()
        }

        /// Closes handed-off descriptors that no worker has claimed. Claimed jobs stop
        /// on their own once cancellation is published.
        private func abandon(_ jobs: [Job]) {
            for job in jobs {
                let unclaimed = lock.withLock {
                    guard !job.claimed else { return false }
                    job.claimed = true
                    queue.removeAll { $0 === job }
                    return true
                }
                if unclaimed {
                    close(job.fd)
                    releaseDescriptor()
                }
            }
        }

        // fd ownership transfers to this function, including on cancellation.
        // `buffer` is free again once the listing finishes, so subdirectories reuse it.
        private func directory(fd: Int32, path: String, name: String, ownBytes: Int64, depth: Int,
                               buffer: UnsafeMutableRawBufferPointer) throws -> DiskMapNode {
            var fdOpen = true
            defer {
                if fdOpen {
                    close(fd)
                    releaseDescriptor()
                }
            }
            let retain = depth < 2
            func childPath(_ child: String) -> String { path == "/" ? "/\(child)" : "\(path)/\(child)" }
            var bytes = ownBytes
            var largest = DiskMapLargestEntries(limit: 64)
            var subdirectories: [(name: String, entry: BulkEntry)] = []
            var request = BulkEntry.request
            while true {
                try checkCancelled()
                let count = getattrlistbulk(fd, &request, buffer.baseAddress, buffer.count, 0)
                if count < 0 {
                    if errno == EINTR { continue }
                    issue(path)
                    break
                }
                if count == 0 { break }
                var offset = 0
                for _ in 0..<count {
                    let start = buffer.baseAddress! + offset
                    offset += Int(start.loadUnaligned(as: UInt32.self))
                    var entry = BulkEntry(start)
                    guard let entryName = entry.name else { continue }
                    if entry.error != 0 {
                        issue(childPath(String(cString: entryName)))
                        continue
                    }
                    if entry.type == UInt32(VDIR.rawValue) {
                        entry.name = nil
                        subdirectories.append((String(cString: entryName), entry))
                        continue
                    }
                    // Files never cross a mount, and deep files need no name or path at all.
                    if entry.type == UInt32(VREG.rawValue), entry.linkCount > 1,
                       !firstLink(FileKey(device: entry.device, fileID: entry.fileID)) { continue }
                    let size = max(0, entry.allocated)
                    bytes += size
                    if retain, largest.mightKeep(size) {
                        let child = childPath(String(cString: entryName))
                        largest.insert(DiskMapNode(id: child, name: String(cString: entryName), path: child,
                                                   bytes: size, isDirectory: false))
                    }
                }
            }

            var pending: [Job] = []
            do {
                for (childName, entry) in subdirectories {
                    let child = childPath(childName)
                    if exclusions.contains(child) || DiskMapScanner.isDataless(flags: entry.flags) {
                        exclude(child)
                        continue
                    }
                    if entry.mountStatus & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0 || mounts.contains(child)
                        || entry.device != device {
                        skipMount()
                        continue
                    }
                    // Avoid pathological nesting and running the app out of descriptors.
                    guard depth < Self.maxDepth, reserveDescriptor() else {
                        issue(child)
                        continue
                    }
                    let childFD = openat(fd, childName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    if childFD < 0 {
                        releaseDescriptor()
                        issue(child)
                        if retain {
                            largest.insert(DiskMapNode(id: child, name: childName, path: child, bytes: 0, isDirectory: true))
                        }
                        continue
                    }
                    var opened = stat()
                    if fstat(childFD, &opened) != 0 || opened.st_dev != device || UInt64(opened.st_ino) != entry.fileID {
                        close(childFD)
                        releaseDescriptor()
                        issue(child)
                        continue
                    }
                    // A firmlink from the System volume into Data keeps st_dev but not f_fsid.
                    if DiskMapVolumeID(fd: childFD) != volume {
                        close(childFD)
                        releaseDescriptor()
                        skipMount()
                        continue
                    }
                    let own = max(0, Int64(opened.st_blocks) * 512)
                    if let job = offer(fd: childFD, path: child, name: childName, ownBytes: own, depth: depth + 1) {
                        pending.append(job)
                        continue
                    }
                    let node = try directory(fd: childFD, path: child, name: childName, ownBytes: own,
                                             depth: depth + 1, buffer: buffer)
                    bytes += node.bytes
                    if retain { largest.insert(node) }
                }
                // The parent descriptor is no longer needed while waiting on handed-off children.
                close(fd)
                releaseDescriptor()
                fdOpen = false
                for (index, job) in pending.enumerated() {
                    do {
                        let node = try wait(for: job, buffer: buffer)
                        bytes += node.bytes
                        if retain { largest.insert(node) }
                    } catch {
                        abandon(Array(pending[(index + 1)...]))
                        throw error
                    }
                }
            } catch {
                abandon(pending)
                throw error
            }

            // Only two levels are retained, with at most 64 entries per folder. Every byte is
            // still counted; drilling into a deeper folder starts a new bounded scan.
            var children = largest.result()
            let remainder = bytes - children.reduce(Int64(0)) { $0 + $1.bytes }
            if retain, remainder > 0 {
                children.append(DiskMapNode(id: path + "/:other", name: "Other entries & folder data",
                                            path: nil, bytes: remainder, isDirectory: false))
            }
            return DiskMapNode(id: path, name: name, path: path, bytes: bytes, isDirectory: true, children: children)
        }
    }
}

struct DiskMapTile: Identifiable {
    let node: DiskMapNode
    let rect: CGRect
    var id: String { node.id }
}

/// Balanced binary treemap: area is proportional to allocated bytes.
enum DiskMapLayout {
    static func tiles(_ nodes: [DiskMapNode], in rect: CGRect) -> [DiskMapTile] {
        let positive = nodes.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        guard !positive.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        return split(positive[...], rect)
    }

    private static func split(_ nodes: ArraySlice<DiskMapNode>, _ rect: CGRect) -> [DiskMapTile] {
        guard nodes.count > 1 else { return [DiskMapTile(node: nodes.first!, rect: rect)] }
        let total = nodes.reduce(0.0) { $0 + Double($1.bytes) }
        var subtotal = 0.0
        var cut = nodes.startIndex
        for index in nodes.indices.dropLast() {
            subtotal += Double(nodes[index].bytes)
            cut = index + 1
            if subtotal >= total / 2 { break }
        }
        let fraction = subtotal / total
        var first = rect
        var second = rect
        if rect.width >= rect.height {
            first.size.width = rect.width * fraction
            second.origin.x += first.width
            second.size.width -= first.width
        } else {
            first.size.height = rect.height * fraction
            second.origin.y += first.height
            second.size.height -= first.height
        }
        return split(nodes[..<cut], first) + split(nodes[cut...], second)
    }
}
