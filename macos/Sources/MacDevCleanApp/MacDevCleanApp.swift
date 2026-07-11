import AppKit
import SwiftUI

@main
struct MacDevCleanApp: App {
    @StateObject private var model = AppModel()

    init() {
        if let logo = AppAssets.logo {
            NSApplication.shared.applicationIconImage = logo
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
        .defaultSize(width: 1040, height: 760)
        .windowResizability(.contentMinSize)

        Settings {
            VStack(alignment: .leading, spacing: 8) {
                Text("mac-dev-clean")
                    .font(.headline)
                Text("The native app uses the same local cleanup engine and safety checks as the command-line utility.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 420)
        }
    }
}

enum AppAssets {
    static var logo: NSImage? {
        if let bundled = Bundle.main.url(forResource: "mac-dev-clean-logo", withExtension: "png"),
           let image = NSImage(contentsOf: bundled)
        {
            return image
        }
        if let root = ProcessInfo.processInfo.environment["MAC_DEV_CLEAN_REPO"] {
            return NSImage(contentsOfFile: URL(fileURLWithPath: root)
                .appendingPathComponent("assets/mac-dev-clean-logo.png").path)
        }
        return nil
    }

    static func ravenVectorLogo(for colorScheme: ColorScheme) -> NSImage? {
        let resource = colorScheme == .dark ? "raven-vector-dark-trans" : "raven-vector-dark"
        if let bundled = Bundle.main.url(forResource: resource, withExtension: "png"),
           let image = NSImage(contentsOf: bundled)
        {
            return image
        }
        if let root = ProcessInfo.processInfo.environment["MAC_DEV_CLEAN_REPO"] {
            return NSImage(contentsOfFile: URL(fileURLWithPath: root)
                .appendingPathComponent("raven_vector_logos/\(resource).png").path)
        }
        return nil
    }
}

enum AppMetadata {
    static let ravenVectorWebsite = URL(string: "https://ravenvector.com")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
    }
}

struct AppLogo: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let logo = AppAssets.logo {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "internaldrive.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(10)
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}

struct RavenVectorBrandLogo: View {
    @Environment(\.colorScheme) private var colorScheme
    let size: CGFloat

    var body: some View {
        Group {
            if let logo = AppAssets.ravenVectorLogo(for: colorScheme) {
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("Raven Vector")
            } else {
                AppLogo(size: size * 0.72)
            }
        }
        .frame(width: size, height: size)
    }
}
