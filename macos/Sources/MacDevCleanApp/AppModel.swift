import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Activity: Equatable {
        case idle
        case scanning
        case cleaning
        case scanningSimulators
        case deletingSimulator
        case findingProjects
        case shelving(String)
        case restoring(String)

        var message: String {
            switch self {
            case .idle: "Ready"
            case .scanning: "Scanning developer storage…"
            case .cleaning: "Cleaning selected categories…"
            case .scanningSimulators: "Reading simulator storage…"
            case .deletingSimulator: "Deleting selected simulator…"
            case .findingProjects: "Finding Git repositories…"
            case let .shelving(name): "Moving \(name) to the Project Shelf…"
            case let .restoring(name): "Restoring \(name)…"
            }
        }
    }

    @Published private(set) var report: ScanReport?
    @Published private(set) var diskSpace: DiskSpace?
    @Published private(set) var activity: Activity = .idle
    @Published var selectedFlags: Set<String> = []
    @Published var errorMessage: String?
    @Published var warningMessage: String?
    @Published var noticeMessage: String?
    @Published private(set) var repositoryCatalog: RepositoryShelfCatalog = .empty
    @Published private(set) var simulatorInventory: SimulatorInventory?

    private let backend: (any CleanupBackendProtocol)?
    private let startupError: Error?
    private let repositoryShelf: any RepositoryShelfServiceProtocol
    private var didLoadRepositoryShelf = false

    init(
        backend: (any CleanupBackendProtocol)? = nil,
        repositoryShelf: any RepositoryShelfServiceProtocol = RepositoryShelfService()
    ) {
        self.repositoryShelf = repositoryShelf
        diskSpace = try? DiskSpace.current()
        if let backend {
            self.backend = backend
            startupError = nil
        } else {
            do {
                self.backend = try CleanupBackend()
                startupError = nil
            } catch {
                self.backend = nil
                startupError = error
            }
        }
    }

    var groups: [CleanupGroup] {
        CleanupGroup.make(from: report?.items ?? [])
    }

    var reviewItems: [ScanItem] {
        (report?.items ?? [])
            .filter { !$0.cleanable }
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    var selectedGroups: [CleanupGroup] {
        groups.filter { selectedFlags.contains($0.rule.flag) }
    }

    var selectedBytes: Int64 {
        selectedGroups.reduce(0) { $0 + $1.totalBytes }
    }

    var selectedLocationCount: Int {
        selectedGroups.reduce(0) { $0 + $1.items.count }
    }

    var selectedSummary: String {
        let size = ByteFormatter.string(selectedBytes)
        let unknown = selectedGroups.contains { $0.hasUnknownSize }
        return unknown ? "\(size) plus shared simulator data" : size
    }

    var isBusy: Bool { activity != .idle }

    var simulatorDevices: [SimulatorDevice] {
        (simulatorInventory?.devices ?? []).sorted { $0.totalSizeBytes > $1.totalSizeBytes }
    }

    func scanSimulators() async {
        guard !isBusy, let backend else { return }
        activity = .scanningSimulators
        dismissMessage()
        do {
            simulatorInventory = try await backend.simulatorDevices()
        } catch {
            simulatorInventory = nil
            errorMessage = error.localizedDescription
        }
        refreshDiskSpace()
        activity = .idle
    }

    func deleteSimulator(_ device: SimulatorDevice) async {
        guard !isBusy, device.canDelete, let backend else { return }
        activity = .deletingSimulator
        dismissMessage()
        do {
            let result = try await backend.deleteSimulator(udid: device.udid)
            guard !result.dryRun, result.targets.count == 1,
                  result.targets.first?.udid.caseInsensitiveCompare(device.udid) == .orderedSame else {
                throw BackendError.invalidOutput("The deletion result did not confirm the selected simulator. Refresh to check its state.")
            }
            noticeMessage = "Deleted \(device.name). Its installed apps and local data were removed. Simulator runtimes were kept."
        } catch {
            errorMessage = error.localizedDescription
        }
        // Refresh after failures too: simctl may have changed state before failing.
        do {
            simulatorInventory = try await backend.simulatorDevices()
        } catch {
            simulatorInventory = nil
            let detail = "Simulator storage could not refresh: \(error.localizedDescription)"
            if let previous = errorMessage {
                errorMessage = "\(previous)\n\n\(detail)"
            } else {
                warningMessage = "\(noticeMessage ?? "")\n\n\(detail)"
                noticeMessage = nil
            }
        }
        report = nil // The aggregate device-storage figure is now stale.
        refreshDiskSpace()
        activity = .idle
    }

    var repositoryProjects: [RepositoryProject] {
        repositoryCatalog.projects.sorted {
            if $0.sizeBytes == $1.sizeBytes {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.sizeBytes > $1.sizeBytes
        }
    }

    var shelvedProjects: [ShelvedProject] {
        repositoryCatalog.shelvedProjects.sorted { $0.shelvedAt > $1.shelvedAt }
    }

    var repositoryBytesOnMac: Int64 {
        repositoryCatalog.projects.reduce(0) { $0 + $1.sizeBytes }
    }

    var shelvedRepositoryBytes: Int64 {
        repositoryCatalog.shelvedProjects.reduce(0) { $0 + $1.sizeBytes }
    }

    var shelfRootURL: URL? {
        repositoryCatalog.shelfRootPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var shelfDisplayPath: String? {
        repositoryCatalog.shelfRootPath.map(RepositoryProject.displayPath)
    }

    var shelfStorageAdvice: String? {
        guard let shelfRootURL else { return nil }
        return repositoryShelf.storageAdvice(
            source: FileManager.default.homeDirectoryForCurrentUser,
            shelfRoot: shelfRootURL
        )
    }

    func scanIfNeeded() async {
        guard report == nil else { return }
        await scan()
    }

    func scan() async {
        await scan(preservingMessages: false)
    }

    private func scan(preservingMessages: Bool) async {
        guard !isBusy else { return }
        guard let backend else {
            errorMessage = startupError?.localizedDescription ?? "The cleanup engine is unavailable."
            warningMessage = nil
            noticeMessage = nil
            return
        }

        activity = .scanning
        if !preservingMessages {
            dismissMessage()
        }
        refreshDiskSpace()
        do {
            let newReport = try await backend.scan()
            report = newReport
            let validFlags = Set(CleanupGroup.make(from: newReport.items).map(\.rule.flag))
            if selectedFlags.isEmpty {
                selectedFlags = validFlags
            } else {
                selectedFlags.formIntersection(validFlags)
            }
        } catch {
            let refreshFailure = error.localizedDescription
            if let warningMessage {
                errorMessage = "\(warningMessage)\n\nThe cleanup finished, but storage totals could not refresh:\n\(refreshFailure)"
                self.warningMessage = nil
            } else if noticeMessage != nil {
                errorMessage = "Cleanup finished, but storage totals could not refresh:\n\(refreshFailure)"
                noticeMessage = nil
            } else {
                errorMessage = refreshFailure
            }
        }
        refreshDiskSpace()
        activity = .idle
    }

    func cleanSelected() async {
        guard !isBusy, let backend else { return }
        let flags = selectedGroups.map(\.rule.flag).sorted()
        guard !flags.isEmpty else { return }

        activity = .cleaning
        errorMessage = nil
        warningMessage = nil
        noticeMessage = nil
        do {
            let result = try await backend.clean(flags: flags)
            let failures = result.items.filter { !$0.error.isEmpty }
            if failures.isEmpty {
                noticeMessage = "Cleanup finished. Selected \(result.total) across \(result.count) location(s)."
            } else {
                warningMessage = Self.cleanupWarning(for: result)
            }
            activity = .idle
            selectedFlags.removeAll()
            await scan(preservingMessages: true)
        } catch {
            errorMessage = error.localizedDescription
            warningMessage = nil
            noticeMessage = nil
            refreshDiskSpace()
            activity = .idle
        }
    }

    func loadRepositoryShelfIfNeeded() async {
        guard !didLoadRepositoryShelf else { return }
        do {
            try ensureRepositoryShelfLoaded()
        } catch {
            errorMessage = "The Project Shelf catalog could not be loaded. No project folders were changed.\n\(error.localizedDescription)"
        }
    }

    func findHomeRepositories() async {
        guard !isBusy else { return }
        do {
            try ensureRepositoryShelfLoaded()
        } catch {
            errorMessage = "The Project Shelf catalog could not be loaded. No project folders were changed.\n\(error.localizedDescription)"
            return
        }
        activity = .findingProjects
        dismissMessage()
        do {
            let discovered = try await repositoryShelf.discoverRepositories(
                in: FileManager.default.homeDirectoryForCurrentUser,
                excluding: shelfRootURL
            )
            let shelvedOriginalPaths = Set(repositoryCatalog.shelvedProjects.map(\.originalPath))
            let outsideHome = repositoryCatalog.projects.filter {
                !$0.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path + "/")
            }
            let merged = outsideHome + discovered.filter { !shelvedOriginalPaths.contains($0.path) }
            repositoryCatalog.projects = Array(Dictionary(
                uniqueKeysWithValues: merged.map { ($0.path, $0) }
            ).values)
            try repositoryShelf.saveCatalog(repositoryCatalog)
            let count = discovered.count
            noticeMessage = "Found \(count) Git repositor\(count == 1 ? "y" : "ies") in your home folder."
        } catch {
            errorMessage = "Repository discovery could not finish. No project folders were changed.\n\(error.localizedDescription)"
        }
        activity = .idle
    }

    func chooseShelfLocation() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Project Shelf"
        panel.message = "Choose iCloud Drive, another cloud-synced folder, or an external volume."
        panel.prompt = "Use as Project Shelf"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setShelfLocation(url)
    }

    func useICloudShelf() {
        let iCloudDrive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: iCloudDrive.path) else {
            errorMessage = "iCloud Drive is not available on this Mac. Enable it in System Settings or choose another shelf location."
            warningMessage = nil
            noticeMessage = nil
            return
        }
        setShelfLocation(iCloudDrive.appendingPathComponent("Developer Project Shelf", isDirectory: true))
    }

    func addProjectFolder() async {
        guard !isBusy else { return }
        do {
            try ensureRepositoryShelfLoaded()
        } catch {
            errorMessage = "The Project Shelf catalog could not be loaded. No project folders were changed.\n\(error.localizedDescription)"
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Add a Project Folder"
        panel.message = "Git repositories and other self-contained project folders are supported."
        panel.prompt = "Add Project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        activity = .findingProjects
        dismissMessage()
        do {
            let project = try await repositoryShelf.inspectProject(at: url)
            repositoryCatalog.projects.removeAll { $0.path == project.path }
            repositoryCatalog.projects.append(project)
            try repositoryShelf.saveCatalog(repositoryCatalog)
            noticeMessage = "Added \(project.name) to Project Shelf management."
        } catch {
            errorMessage = error.localizedDescription
        }
        activity = .idle
    }

    func shelfProject(_ project: RepositoryProject) async {
        guard !isBusy else { return }
        guard let shelfRootURL else {
            errorMessage = RepositoryShelfError.shelfNotConfigured.localizedDescription
            return
        }

        activity = .shelving(project.name)
        dismissMessage()
        do {
            let shelved = try await repositoryShelf.shelf(project, in: shelfRootURL)
            repositoryCatalog.projects.removeAll { $0.path == project.path }
            repositoryCatalog.shelvedProjects.append(shelved)
            do {
                try repositoryShelf.saveCatalog(repositoryCatalog)
                noticeMessage = "Moved \(project.name) to the Project Shelf. Restore returns the complete folder to \(shelved.displayOriginalPath)."
            } catch {
                errorMessage = "\(project.name) was moved successfully, but its catalog entry could not be saved. Keep this app open and note the shelf path:\n\(shelved.shelfPath)\n\n\(error.localizedDescription)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshDiskSpace()
        activity = .idle
    }

    func restoreProject(_ project: ShelvedProject) async {
        guard !isBusy else { return }
        activity = .restoring(project.name)
        dismissMessage()
        do {
            let restored = try await repositoryShelf.restore(project)
            repositoryCatalog.shelvedProjects.removeAll { $0.id == project.id }
            repositoryCatalog.projects.removeAll { $0.path == restored.path }
            repositoryCatalog.projects.append(restored)
            do {
                try repositoryShelf.saveCatalog(repositoryCatalog)
                noticeMessage = "Restored \(project.name) to \(restored.displayPath)."
            } catch {
                errorMessage = "\(project.name) was restored successfully, but the Project Shelf catalog could not be saved.\n\(error.localizedDescription)"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refreshDiskSpace()
        activity = .idle
    }

    func selectAll() {
        selectedFlags = Set(groups.map(\.rule.flag))
    }

    func clearSelection() {
        selectedFlags.removeAll()
    }

    func dismissMessage() {
        errorMessage = nil
        warningMessage = nil
        noticeMessage = nil
    }

    static func cleanupWarning(for report: CleanReport) -> String? {
        let failures = report.items.filter { !$0.error.isEmpty }
        guard !failures.isEmpty else { return nil }

        let removedCount = report.items.filter { $0.removed && $0.error.isEmpty }.count
        let itemWord = failures.count == 1 ? "item was" : "items were"
        let locationWord = removedCount == 1 ? "location" : "locations"
        let success = removedCount == 0
            ? "No locations were cleaned."
            : "Cleaned \(report.total) across \(removedCount) \(locationWord)."
        let details = failures.map { item in
            "• \(item.label): \(item.error)\n  \(item.path)"
        }.joined(separator: "\n")

        return "Cleanup finished, but \(failures.count) \(itemWord) skipped. \(success) No additional files will be removed.\n\n\(details)"
    }

    func reveal(_ item: ScanItem) {
        NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
    }

    func revealPath(_ path: String) {
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    func openShelf() {
        guard let shelfRootURL else { return }
        NSWorkspace.shared.open(shelfRootURL)
    }

    func openICloudDrive() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        NSWorkspace.shared.open(path)
    }

    private func refreshDiskSpace() {
        diskSpace = try? DiskSpace.current()
    }

    private func setShelfLocation(_ url: URL) {
        do {
            try ensureRepositoryShelfLoaded()
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            repositoryCatalog.shelfRootPath = url.standardizedFileURL.path
            try repositoryShelf.saveCatalog(repositoryCatalog)
            errorMessage = nil
            warningMessage = nil
            noticeMessage = "Project Shelf set to \(RepositoryProject.displayPath(url.standardizedFileURL.path))."
        } catch {
            errorMessage = "The Project Shelf location could not be prepared.\n\(error.localizedDescription)"
            warningMessage = nil
            noticeMessage = nil
        }
    }

    private func ensureRepositoryShelfLoaded() throws {
        guard !didLoadRepositoryShelf else { return }
        repositoryCatalog = try repositoryShelf.loadCatalog()
        didLoadRepositoryShelf = true
    }
}
