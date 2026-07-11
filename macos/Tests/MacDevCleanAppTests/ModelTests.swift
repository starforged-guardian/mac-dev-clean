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
    let editor = fixture(category: "editor-cache", size: 100)
    let updater = fixture(category: "updater-cache", size: 200)

    let groups = CleanupGroup.make(from: [editor, updater])

    #expect(groups.count == 1)
    #expect(groups[0].rule.flag == "--editor-caches")
    #expect(groups[0].totalBytes == 300)
    #expect(groups[0].items.first?.category == "updater-cache")
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
