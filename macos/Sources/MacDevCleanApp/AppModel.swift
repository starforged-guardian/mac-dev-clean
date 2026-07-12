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
    @Published var warningMessage: String?
    @Published var noticeMessage: String?

    private let backend: (any CleanupBackendProtocol)?
    private let startupError: Error?

    init(backend: (any CleanupBackendProtocol)? = nil) {
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

    func openICloudDrive() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        NSWorkspace.shared.open(path)
    }

    private func refreshDiskSpace() {
        diskSpace = try? DiskSpace.current()
    }
}
