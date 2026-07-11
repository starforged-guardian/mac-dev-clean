import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    enum Activity: Equatable {
        case idle
        case scanning
        case cleaning

        var message: String {
            switch self {
            case .idle: "Ready"
            case .scanning: "Scanning developer storage…"
            case .cleaning: "Cleaning selected categories…"
            }
        }
    }

    @Published private(set) var report: ScanReport?
    @Published private(set) var diskSpace: DiskSpace?
    @Published private(set) var activity: Activity = .idle
    @Published var selectedFlags: Set<String> = []
    @Published var errorMessage: String?
    @Published var noticeMessage: String?

    private let backend: CleanupBackend?
    private let startupError: Error?

    init(backend: CleanupBackend? = nil) {
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

    func scanIfNeeded() async {
        guard report == nil else { return }
        await scan()
    }

    func scan() async {
        guard !isBusy else { return }
        guard let backend else {
            errorMessage = startupError?.localizedDescription ?? "The cleanup engine is unavailable."
            return
        }

        activity = .scanning
        errorMessage = nil
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
            errorMessage = error.localizedDescription
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
        noticeMessage = nil
        do {
            let result = try await backend.clean(flags: flags)
            let failures = result.items.filter { !$0.error.isEmpty }
            if failures.isEmpty {
                noticeMessage = "Cleanup finished. Selected \(result.total) across \(result.count) location(s)."
            } else {
                let details = failures.map { "\($0.label): \($0.error)" }.joined(separator: "\n")
                errorMessage = "Some locations could not be cleaned:\n\(details)"
            }
            activity = .idle
            selectedFlags.removeAll()
            await scan()
        } catch {
            errorMessage = error.localizedDescription
            refreshDiskSpace()
            activity = .idle
        }
    }

    func selectAll() {
        selectedFlags = Set(groups.map(\.rule.flag))
    }

    func clearSelection() {
        selectedFlags.removeAll()
    }

    func reveal(_ item: ScanItem) {
        NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
    }

    func openICloudDrive() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        NSWorkspace.shared.open(path)
    }

    private func refreshDiskSpace() {
        diskSpace = try? DiskSpace.current()
    }
}
