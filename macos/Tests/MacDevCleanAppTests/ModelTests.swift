import Foundation
import Testing
@testable import MacDevCleanApp

@Test func scanReportDecodesPythonJSON() throws {
    let json = #"""
    {
      "total_bytes": 1073741824,
      "total": "1.0 GB",
      "cleanable_total_bytes": 1073741824,
      "cleanable_total": "1.0 GB",
      "report_only_total_bytes": 0,
      "report_only_total": "0 B",
      "count": 1,
      "items": [{
        "category": "browser-cache",
        "label": "Chrome model",
        "path": "/Users/test/Library/Caches/Chrome",
        "size_bytes": 1073741824,
        "size": "1.0 GB",
        "modified_at": "2026-07-11T12:00:00+00:00",
        "cleanable": true,
        "delete_mode": "contents",
        "note": "Downloaded model"
      }]
    }
    """#

    let report = try JSONDecoder().decode(ScanReport.self, from: Data(json.utf8))

    #expect(report.cleanableTotal == "1.0 GB")
    #expect(report.items.first?.category == "browser-cache")
    #expect(report.items.first?.cleanable == true)
}

@Test func cleanupGroupsCombineCategoriesThatShareAFlag() {
    let editor = fixture(category: "editor-cache", size: 50 * 1024 * 1024)
    let updater = fixture(category: "updater-cache", size: 60 * 1024 * 1024)

    let groups = CleanupGroup.make(from: [editor, updater])

    #expect(groups.count == 1)
    #expect(groups[0].rule.flag == "--editor-caches")
    #expect(groups[0].totalBytes == 110 * 1024 * 1024)
    #expect(groups[0].items.first?.category == "updater-cache")
}

@Test func cleanupGroupsBelowOneHundredMegabytesAreNotOffered() {
    let item = fixture(
        category: "python-cache",
        size: CleanupGroup.minimumOfferedBytes - 1
    )

    #expect(CleanupGroup.make(from: [item]).isEmpty)
}

@Test func cleanupGroupsAtOneHundredMegabytesAreOffered() {
    let item = fixture(
        category: "python-cache",
        size: CleanupGroup.minimumOfferedBytes
    )

    #expect(CleanupGroup.make(from: [item]).count == 1)
}

@Test func reportOnlyItemsNeverBecomeCleanupGroups() {
    let item = ScanItem(
        category: "xcode-archives",
        label: "Xcode Archives",
        path: "/Users/test/Archives",
        sizeBytes: 1000,
        size: "1000 B",
        modifiedAt: nil,
        cleanable: false,
        deleteMode: "none",
        note: "Keep"
    )

    #expect(CleanupGroup.make(from: [item]).isEmpty)
}

@Test func xctestCloneSizeIsPresentedAsShared() {
    let item = fixture(category: "xcode-test-devices", size: 22 * 1024 * 1024)
    let group = CleanupGroup.make(from: [item])[0]

    #expect(item.displaySize == "Shared / unknown")
    #expect(group.displaySize == "Shared / unknown")
    #expect(group.totalBytes == 0)
}

@Test func byteFormattingMatchesThePythonCLI() {
    #expect(ByteFormatter.string(699 * 1024 * 1024) == "699.0 MB")
    #expect(ByteFormatter.string(1024 * 1024 * 1024) == "1.0 GB")
}

@Test func diskSpaceFormatsFreeAndTotalCapacity() {
    let diskSpace = DiskSpace(
        freeBytes: 250 * 1024 * 1024 * 1024,
        totalBytes: 1_000 * 1024 * 1024 * 1024
    )

    #expect(diskSpace.free == "250.0 GB")
    #expect(diskSpace.total == "1000.0 GB")
}

@Test func repositoryRemoteSummaryRemovesEmbeddedCredentials() {
    let project = RepositoryProject(
        path: "/Users/test/project",
        name: "project",
        sizeBytes: 1,
        isGitRepository: true,
        branch: "main",
        remoteURL: "https://private-token@github.com/example/project.git",
        commit: nil,
        hasTrackedChanges: false,
        lastActivityAt: nil
    )

    #expect(project.remoteSummary == "github.com/example/project")
    #expect(project.remoteSummary?.contains("private-token") == false)
}

@Test func repositoryShelfCatalogRoundTripsThroughDisk() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("mac-dev-clean-catalog-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let service = RepositoryShelfService(
        catalogURL: root.appendingPathComponent("catalog.json")
    )
    let project = RepositoryProject(
        path: "/Users/test/project",
        name: "project",
        sizeBytes: 42,
        isGitRepository: true,
        branch: "main",
        remoteURL: "git@github.com:example/project.git",
        commit: "abc123",
        hasTrackedChanges: true,
        lastActivityAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let catalog = RepositoryShelfCatalog(
        shelfRootPath: "/Volumes/Archive/Project Shelf",
        projects: [project],
        shelvedProjects: []
    )

    try service.saveCatalog(catalog)

    #expect(try service.loadCatalog() == catalog)
}

@Test func projectShelfMovesAndRestoresCompleteFolder() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("mac-dev-clean-shelf-\(UUID().uuidString)", isDirectory: true)
    let projects = root.appendingPathComponent("Projects", isDirectory: true)
    let source = projects.appendingPathComponent("SampleApp", isDirectory: true)
    let gitDirectory = source.appendingPathComponent(".git", isDirectory: true)
    let shelf = root.appendingPathComponent("Shelf", isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }

    try fileManager.createDirectory(at: gitDirectory, withIntermediateDirectories: true)
    try Data("LOCAL_ONLY=preserve-me".utf8).write(
        to: source.appendingPathComponent(".env")
    )
    try Data("# Sample".utf8).write(
        to: source.appendingPathComponent("README.md")
    )

    let service = RepositoryShelfService(
        catalogURL: root.appendingPathComponent("catalog.json")
    )
    let project = try await service.inspectProject(at: source)
    let shelved = try await service.shelf(project, in: shelf)

    #expect(!fileManager.fileExists(atPath: source.path))
    #expect(fileManager.fileExists(atPath: shelved.shelfPath + "/.git"))
    #expect(fileManager.fileExists(atPath: shelved.shelfPath + "/.env"))

    let restored = try await service.restore(shelved)

    #expect(restored.path == source.path)
    #expect(fileManager.fileExists(atPath: source.appendingPathComponent(".git").path))
    let environment = try String(
        contentsOf: source.appendingPathComponent(".env"),
        encoding: .utf8
    )
    #expect(environment == "LOCAL_ONLY=preserve-me")
    #expect(!fileManager.fileExists(atPath: shelved.shelfPath))
}

@Test func repositoryDiscoveryFindsNestedReposAndExcludesShelf() async throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory
        .appendingPathComponent("mac-dev-clean-discovery-\(UUID().uuidString)", isDirectory: true)
    let first = root.appendingPathComponent("First", isDirectory: true)
    let second = root.appendingPathComponent("Work/Second", isDirectory: true)
    let shelf = root.appendingPathComponent("Shelf", isDirectory: true)
    let excluded = shelf.appendingPathComponent("Shelved", isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }

    for repository in [first, second, excluded] {
        try fileManager.createDirectory(
            at: repository.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    let service = RepositoryShelfService(
        catalogURL: root.appendingPathComponent("catalog.json")
    )
    let projects = try await service.discoverRepositories(in: root, excluding: shelf)
    #expect(Set(projects.map(\.name)) == Set(["First", "Second"]))
    #expect(projects.allSatisfy { !$0.path.contains("/Shelf/") })
}

@Test func ravenVectorWebsiteUsesSecureCanonicalURL() {
    #expect(AppMetadata.ravenVectorWebsite.scheme == "https")
    #expect(AppMetadata.ravenVectorWebsite.host == "ravenvector.com")
}

@Test func backendDoesNotInheritPythonCodeInjectionSettings() {
    let environment = CleanupBackend.pythonEnvironment(
        base: [
            "PATH": "/usr/bin:/bin",
            "PYTHONPATH": "/tmp/untrusted-modules",
            "PYTHONINSPECT": "1",
            "PYTHONSTARTUP": "/tmp/startup.py",
            "PYTHONHOME": "/tmp/untrusted-runtime",
        ],
        pythonPath: URL(fileURLWithPath: "/Applications/mac-dev-clean.app/Contents/Resources/python")
    )

    #expect(environment["PATH"] == "/usr/bin:/bin")
    #expect(environment["PYTHONPATH"] == "/Applications/mac-dev-clean.app/Contents/Resources/python")
    #expect(environment["PYTHONNOUSERSITE"] == "1")
    #expect(environment["PYTHONDONTWRITEBYTECODE"] == "1")
    #expect(environment["PYTHONINSPECT"] == nil)
    #expect(environment["PYTHONSTARTUP"] == nil)
    #expect(environment["PYTHONHOME"] == nil)
}

@Test func backendDecodesCleanupDetailsFromPartialFailureExit() throws {
    let json = #"""
    {
      "total_bytes": 104857600,
      "total": "100.0 MB",
      "count": 2,
      "items": [
        {
          "category": "browser-cache",
          "label": "Google browser caches",
          "path": "/Users/test/Library/Caches/Google",
          "size_bytes": 104857600,
          "size": "100.0 MB",
          "removed": true,
          "error": ""
        },
        {
          "category": "npm-cache",
          "label": "npm download cache",
          "path": "/Users/test/.npm/_cacache",
          "size_bytes": 209715200,
          "size": "200.0 MB",
          "removed": false,
          "error": "Operation not permitted"
        }
      ]
    }
    """#
    let result = CommandResult(
        stdout: Data(json.utf8),
        stderr: "Scanning developer cache locations. This can take a moment...",
        terminationStatus: 1
    )

    let report = try CleanupBackend.cleanReport(from: result)

    #expect(report.items.count == 2)
    #expect(report.items[1].error == "Operation not permitted")
}

@Test func backendShowsDiagnosticsWhenPartialFailureHasNoValidReport() {
    let result = CommandResult(
        stdout: Data(),
        stderr: "Permission denied while reading the selected cache.",
        terminationStatus: 1
    )

    do {
        _ = try CleanupBackend.cleanReport(from: result)
        Issue.record("Expected malformed cleanup output to throw")
    } catch {
        #expect(error.localizedDescription.contains("Permission denied"))
        #expect(error.localizedDescription.contains("No additional files will be removed"))
    }
}

@Test @MainActor func partialCleanupWarningSurvivesRefreshAndCanBeDismissed() async {
    let scanItem = fixture(category: "browser-cache", size: 200 * 1024 * 1024)
    let scanReport = ScanReport(
        totalBytes: scanItem.sizeBytes,
        total: scanItem.size,
        cleanableTotalBytes: scanItem.sizeBytes,
        cleanableTotal: scanItem.size,
        reportOnlyTotalBytes: 0,
        reportOnlyTotal: "0 B",
        count: 1,
        items: [scanItem]
    )
    let cleanReport = CleanReport(
        totalBytes: 0,
        total: "0 B",
        count: 1,
        items: [
            CleanResultItem(
                category: "browser-cache",
                label: "Google browser caches",
                path: "/Users/test/Library/Caches/Google",
                sizeBytes: scanItem.sizeBytes,
                size: scanItem.size,
                removed: false,
                error: "The browser is still using this cache"
            ),
        ]
    )
    let model = AppModel(
        backend: StubBackend(scanReport: scanReport, cleanReport: cleanReport)
    )

    await model.scan()
    model.selectedFlags = ["--browser-caches"]
    await model.cleanSelected()

    #expect(model.errorMessage == nil)
    #expect(model.warningMessage?.contains("1 item was skipped") == true)
    #expect(model.warningMessage?.contains("The browser is still using this cache") == true)
    #expect(model.warningMessage?.contains("/Users/test/Library/Caches/Google") == true)

    model.dismissMessage()

    #expect(model.errorMessage == nil)
    #expect(model.warningMessage == nil)
    #expect(model.noticeMessage == nil)

    model.errorMessage = "Old error"
    model.warningMessage = "Old warning"
    model.noticeMessage = "Old notice"
    await model.scan()

    #expect(model.errorMessage == nil)
    #expect(model.warningMessage == nil)
    #expect(model.noticeMessage == nil)
}

private func fixture(category: String, size: Int64) -> ScanItem {
    ScanItem(
        category: category,
        label: category,
        path: "/Users/test/\(category)",
        sizeBytes: size,
        size: ByteFormatter.string(size),
        modifiedAt: nil,
        cleanable: true,
        deleteMode: "contents",
        note: ""
    )
}

private struct StubBackend: CleanupBackendProtocol {
    let scanReport: ScanReport
    let cleanReport: CleanReport

    func scan() async throws -> ScanReport {
        scanReport
    }

    func clean(flags: [String]) async throws -> CleanReport {
        cleanReport
    }

    func simulatorDevices() async throws -> SimulatorInventory {
        SimulatorInventory(devices: [])
    }

    func deleteSimulator(udid: String) async throws -> SimulatorActionReport {
        throw BackendError.invalidOutput("Unexpected simulator deletion")
    }
}

@Test func simulatorInventoryDecodesAndProtectsActiveDevices() throws {
    let json = #"""
    {"devices":[{"udid":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","name":"iPhone","runtime_identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-5","state":"Booted","is_available":true,"last_booted_at":"2026-09-12T21:04:46+00:00","total_size_bytes":5844062208}]}
    """#
    let inventory = try CleanupBackend.decode(SimulatorInventory.self, from: Data(json.utf8))
    #expect(inventory.devices.count == 1)
    #expect(!inventory.devices[0].canDelete)
    #expect(inventory.devices[0].runtimeName == "iOS 26.5")
    #expect(inventory.devices[0].lastBootedDescription.hasPrefix("Last boot:"))
    #expect(!simulatorFixture(state: "Booting").canDelete)
    #expect(!simulatorFixture(state: "").canDelete)
    #expect(simulatorFixture().canDelete)
}

@Test @MainActor func simulatorDeletionRefreshesInventoryAndInvalidatesStorageReport() async {
    let device = simulatorFixture()
    let backend = SimulatorStubBackend(device: device)
    let model = AppModel(backend: backend)
    await model.scan()
    await model.scanSimulators()
    #expect(model.simulatorDevices.count == 1)
    await model.deleteSimulator(device)
    #expect(model.simulatorDevices.isEmpty)
    #expect(model.report == nil)
    #expect(model.noticeMessage?.contains("Deleted iPhone") == true)
    #expect(model.errorMessage == nil)
    #expect(model.activity == .idle)
    #expect(await backend.deletedIDs == [device.udid])
}

@Test @MainActor func activeSimulatorCannotReachDeletionBackend() async {
    let device = simulatorFixture(state: "Booted")
    let backend = SimulatorStubBackend(device: device)
    let model = AppModel(backend: backend)
    await model.deleteSimulator(device)
    #expect(await backend.deletedIDs.isEmpty)
}

@Test @MainActor func simulatorFailureRefreshesStateAndNeverClaimsSuccess() async {
    let device = simulatorFixture()
    let backend = SimulatorStubBackend(device: device, failsDeletion: true)
    let model = AppModel(backend: backend)
    await model.deleteSimulator(device)
    #expect(model.noticeMessage == nil)
    #expect(model.errorMessage?.contains("now booted") == true)
    #expect(model.simulatorDevices.count == 1)
    #expect(model.activity == .idle)
}

@Test @MainActor func simulatorDryRunCannotBeReportedAsSuccessfulDeletion() async {
    let device = simulatorFixture()
    let backend = SimulatorStubBackend(device: device, dryRun: true)
    let model = AppModel(backend: backend)
    await model.deleteSimulator(device)
    #expect(model.noticeMessage == nil)
    #expect(model.errorMessage?.contains("did not confirm") == true)
}

private func simulatorFixture(state: String = "Shutdown") -> SimulatorDevice {
    SimulatorDevice(
        udid: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA", name: "iPhone",
        runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
        state: state, isAvailable: true, lastBootedAt: nil, totalSizeBytes: 2_000_000_000
    )
}

private actor SimulatorStubBackend: CleanupBackendProtocol {
    let device: SimulatorDevice
    let failsDeletion: Bool
    let dryRun: Bool
    var deletedIDs: [String] = []

    init(device: SimulatorDevice, failsDeletion: Bool = false, dryRun: Bool = false) {
        self.device = device
        self.failsDeletion = failsDeletion
        self.dryRun = dryRun
    }

    func scan() async throws -> ScanReport {
        ScanReport(totalBytes: 0, total: "0 B", cleanableTotalBytes: 0, cleanableTotal: "0 B",
                   reportOnlyTotalBytes: 0, reportOnlyTotal: "0 B", count: 0, items: [])
    }
    func clean(flags: [String]) async throws -> CleanReport {
        CleanReport(totalBytes: 0, total: "0 B", count: 0, items: [])
    }
    func simulatorDevices() async throws -> SimulatorInventory {
        SimulatorInventory(devices: deletedIDs.isEmpty ? [device] : [])
    }
    func deleteSimulator(udid: String) async throws -> SimulatorActionReport {
        if failsDeletion { throw BackendError.invalidOutput("Device is now booted") }
        if !dryRun { deletedIDs.append(udid) }
        return SimulatorActionReport(dryRun: dryRun, targets: [device])
    }
}

@Test func backendDrainsLargeReportsAndDiagnosticsWithoutBlocking() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mac-dev-clean-pipes-\(UUID())")
    let module = root.appendingPathComponent("mac_dev_clean")
    try FileManager.default.createDirectory(at: module, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try "".write(to: module.appendingPathComponent("__init__.py"), atomically: true, encoding: .utf8)
    let script = """
    import json, sys
    sys.stderr.write('diagnostic ' * 20000)
    sys.stderr.flush()
    print(json.dumps({'devices': [{'udid': 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA',
        'name': 'iPhone' * 40000, 'runtime_identifier': 'iOS', 'state': 'Shutdown',
        'is_available': True, 'last_booted_at': None, 'total_size_bytes': 1}]}))
    """
    try script.write(to: module.appendingPathComponent("xcode_sim_prune.py"), atomically: true, encoding: .utf8)
    let backend = try CleanupBackend(location: BackendLocation(
        pythonURL: URL(fileURLWithPath: "/usr/bin/python3"), pythonPath: root, workingDirectory: root
    ))
    let result = try await backend.simulatorDevices()
    #expect(result.devices.first?.name.count == 240000)
}
