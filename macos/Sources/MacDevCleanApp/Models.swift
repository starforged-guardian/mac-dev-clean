import Foundation

struct ScanReport: Decodable, Sendable {
    let totalBytes: Int64
    let total: String
    let cleanableTotalBytes: Int64
    let cleanableTotal: String
    let reportOnlyTotalBytes: Int64
    let reportOnlyTotal: String
    let count: Int
    let items: [ScanItem]

    enum CodingKeys: String, CodingKey {
        case totalBytes = "total_bytes"
        case total
        case cleanableTotalBytes = "cleanable_total_bytes"
        case cleanableTotal = "cleanable_total"
        case reportOnlyTotalBytes = "report_only_total_bytes"
        case reportOnlyTotal = "report_only_total"
        case count
        case items
    }
}

struct ScanItem: Decodable, Identifiable, Hashable, Sendable {
    let category: String
    let label: String
    let path: String
    let sizeBytes: Int64
    let size: String
    let modifiedAt: String?
    let cleanable: Bool
    let deleteMode: String
    let note: String

    var id: String { "\(category)|\(path)" }

    var displaySize: String {
        category == "xcode-test-devices" ? "Shared / unknown" : size
    }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    enum CodingKeys: String, CodingKey {
        case category
        case label
        case path
        case sizeBytes = "size_bytes"
        case size
        case modifiedAt = "modified_at"
        case cleanable
        case deleteMode = "delete_mode"
        case note
    }
}

struct CleanReport: Decodable, Sendable {
    let totalBytes: Int64
    let total: String
    let count: Int
    let items: [CleanResultItem]

    enum CodingKeys: String, CodingKey {
        case totalBytes = "total_bytes"
        case total
        case count
        case items
    }
}

struct CleanResultItem: Decodable, Sendable {
    let category: String
    let label: String
    let path: String
    let sizeBytes: Int64
    let size: String
    let removed: Bool
    let error: String

    enum CodingKeys: String, CodingKey {
        case category
        case label
        case path
        case sizeBytes = "size_bytes"
        case size
        case removed
        case error
    }
}

struct CleanupRule: Hashable, Sendable {
    let flag: String
    let title: String
    let symbol: String

    static func rule(for category: String) -> CleanupRule? {
        rules[category]
    }

    private static let rules: [String: CleanupRule] = [
        "xcode-derived-data": .init(flag: "--xcode-derived-data", title: "Xcode build artifacts", symbol: "hammer.fill"),
        "xcode-module-cache": .init(flag: "--xcode-derived-data", title: "Xcode build artifacts", symbol: "hammer.fill"),
        "xcode-documentation-cache": .init(flag: "--xcode-documentation-cache", title: "Xcode documentation", symbol: "books.vertical.fill"),
        "xcode-device-support": .init(flag: "--xcode-device-support", title: "Device support", symbol: "iphone.gen3"),
        "xcode-device-logs": .init(flag: "--xcode-device-logs", title: "Device logs", symbol: "doc.text.magnifyingglass"),
        "xcode-test-devices": .init(flag: "--xcode-test-devices", title: "XCTest simulator clones", symbol: "square.stack.3d.up.fill"),
        "simulator-caches": .init(flag: "--simulator-caches", title: "Simulator caches", symbol: "iphone.and.arrow.forward"),
        "simulator-dyld-cache": .init(flag: "--simulator-dyld-cache", title: "Simulator runtime caches", symbol: "memorychip.fill"),
        "project-derived-data": .init(flag: "--project-derived-data", title: "Project DerivedData", symbol: "folder.badge.gearshape"),
        "brew-cache": .init(flag: "--brew-cache", title: "Homebrew cache", symbol: "shippingbox.fill"),
        "npm-cache": .init(flag: "--npm-cache", title: "npm cache", symbol: "shippingbox.fill"),
        "pnpm-cache": .init(flag: "--pnpm-cache", title: "pnpm cache", symbol: "shippingbox.fill"),
        "node-tool-cache": .init(flag: "--node-tool-caches", title: "Node and Bun caches", symbol: "shippingbox.fill"),
        "python-cache": .init(flag: "--python-caches", title: "Python caches", symbol: "shippingbox.fill"),
        "swiftpm-cache": .init(flag: "--swiftpm-cache", title: "SwiftPM cache", symbol: "swift"),
        "go-cache": .init(flag: "--go-cache", title: "Go caches", symbol: "shippingbox.fill"),
        "rust-cache": .init(flag: "--rust-cache", title: "Rust caches", symbol: "shippingbox.fill"),
        "gradle-cache": .init(flag: "--gradle-cache", title: "Gradle caches", symbol: "shippingbox.fill"),
        "browser-cache": .init(flag: "--browser-caches", title: "Browser and model caches", symbol: "globe"),
        "editor-cache": .init(flag: "--editor-caches", title: "Editor and updater caches", symbol: "chevron.left.forwardslash.chevron.right"),
        "updater-cache": .init(flag: "--editor-caches", title: "Editor and updater caches", symbol: "chevron.left.forwardslash.chevron.right"),
        "wallpaper-cache": .init(flag: "--wallpaper-cache", title: "Downloaded wallpapers", symbol: "photo.on.rectangle.angled"),
    ]
}

struct CleanupGroup: Identifiable, Hashable, Sendable {
    let rule: CleanupRule
    let items: [ScanItem]

    var id: String { rule.flag }
    var totalBytes: Int64 {
        items.reduce(0) { total, item in
            total + (item.category == "xcode-test-devices" ? 0 : item.sizeBytes)
        }
    }
    var hasUnknownSize: Bool { items.contains { $0.category == "xcode-test-devices" } }
    var displaySize: String {
        let value = ByteFormatter.string(totalBytes)
        return hasUnknownSize && totalBytes == 0 ? "Shared / unknown" : value
    }

    static func make(from items: [ScanItem]) -> [CleanupGroup] {
        let cleanable = items.filter(\.cleanable)
        let grouped = Dictionary(grouping: cleanable) { item in
            CleanupRule.rule(for: item.category)?.flag ?? "unsupported:\(item.category)"
        }

        return grouped.compactMap { _, items in
            guard let first = items.first, let rule = CleanupRule.rule(for: first.category) else {
                return nil
            }
            return CleanupGroup(
                rule: rule,
                items: items.sorted { $0.sizeBytes > $1.sizeBytes }
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalBytes == rhs.totalBytes { return lhs.rule.title < rhs.rule.title }
            return lhs.totalBytes > rhs.totalBytes
        }
    }
}

enum ByteFormatter {
    static func string(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return "\(bytes) B"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}
