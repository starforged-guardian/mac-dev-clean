import SwiftUI

enum SidebarPage: String, CaseIterable, Identifiable {
    case cleanup = "Cleanup"
    case diskMap = "Disk Map"
    case review = "Review Only"
    case simulators = "Simulators"
    case projects = "Project Shelf"
    case about = "About"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .cleanup: "sparkles"
        case .diskMap: "square.grid.3x3.square"
        case .review: "archivebox"
        case .simulators: "iphone.gen3"
        case .projects: "externaldrive.badge.icloud"
        case .about: "info.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var page: SidebarPage? = .cleanup
    @State private var showsConfirmation = false
    @StateObject private var diskMap = DiskMapModel()

    var body: some View {
        NavigationSplitView {
            List(SidebarPage.allCases, selection: $page) { item in
                Label(item.rawValue, systemImage: item.symbol)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
            .safeAreaInset(edge: .bottom) {
                sidebarFooter
            }
        } detail: {
            Group {
                if page == .about {
                    AboutView()
                } else if page == .diskMap {
                    DiskMapView(map: diskMap)
                } else if page == .projects {
                    RepositoryShelfView()
                } else {
                    VStack(spacing: 0) {
                        if !isInitialScan || page == .simulators {
                            header
                            Divider()
                        }
                        content
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .navigationTitle(page?.rawValue ?? SidebarPage.cleanup.rawValue)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 900, minHeight: 640)
        .toolbar {
            ToolbarItemGroup {
                if page == .simulators {
                    Button {
                        Task { await model.scanSimulators() }
                    } label: {
                        Label("Refresh Simulators", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isBusy)
                } else if page == .cleanup || page == .review || page == nil {
                    Button {
                        Task { await model.scan() }
                    } label: {
                        Label("Scan Again", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isBusy)
                    .help("Scan developer storage again")

                    if page == .cleanup && !isInitialScan {
                        Button("Select All") { model.selectAll() }
                            .disabled(model.isBusy || model.groups.isEmpty)
                            .help("Select every cleanable category")
                        Button("Clear") { model.clearSelection() }
                            .disabled(model.isBusy || model.selectedFlags.isEmpty)
                            .help("Clear the cleanup selection")
                    }
                } else if page == .projects {
                    Button {
                        Task { await model.findHomeRepositories() }
                    } label: {
                        Label("Find Repositories", systemImage: "magnifyingglass")
                    }
                    .disabled(model.isBusy)
                    .help("Find Git repositories within three levels of your home folder")

                    Button {
                        Task { await model.addProjectFolder() }
                    } label: {
                        Label("Add Project", systemImage: "plus")
                    }
                    .disabled(model.isBusy)

                    Button("Choose Shelf…") { model.chooseShelfLocation() }
                        .disabled(model.isBusy)
                }
            }
        }
        .confirmationDialog(
            "Clean selected categories?",
            isPresented: $showsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean \(model.selectedLocationCount) Locations", role: .destructive) {
                Task { await model.cleanSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.cleanupConfirmationMessage)
        }
        .task(id: page) {
            if page == .simulators {
                await model.scanSimulators()
            } else if page == .projects {
                await model.loadRepositoryShelfIfNeeded()
            } else if page != .about && page != .diskMap {
                await model.scanIfNeeded()
            }
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isBusy || diskMap.isScanning {
                ProgressView()
                    .controlSize(.small)
            }
            Text(diskMap.isScanning ? "Mapping disk storage…" : model.activity.message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.bar)
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                if page != .simulators {
                    SummaryCard(
                        title: "Cleanable",
                        value: model.report?.cleanableTotal ?? "—",
                        detail: countLabel(model.groups.count, "category", "categories"),
                        symbol: "sparkles",
                        color: .green
                    )
                    SummaryCard(
                        title: "Review only",
                        value: model.report?.reportOnlyTotal ?? "—",
                        detail: countLabel(model.reviewItems.count, "item", "items"),
                        symbol: "archivebox",
                        color: .orange
                    )
                }
                DiskUsageCard(disk: model.diskSpace)
            }
            .fixedSize(horizontal: false, vertical: true)

            if let error = model.errorMessage {
                MessageBanner(
                    text: error,
                    symbol: "exclamationmark.triangle.fill",
                    color: .red,
                    onDismiss: model.dismissMessage
                )
            } else if let warning = model.warningMessage {
                MessageBanner(
                    text: warning,
                    symbol: "exclamationmark.circle.fill",
                    color: .orange,
                    onDismiss: model.dismissMessage
                )
            } else if let notice = model.noticeMessage {
                MessageBanner(
                    text: notice,
                    symbol: "checkmark.circle.fill",
                    color: .green,
                    onDismiss: model.dismissMessage
                )
            }
        }
        .padding(20)
    }

    private var cleanupActionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectedFlags.isEmpty ? "Nothing selected" : "\(ByteFormatter.string(model.selectedBytes)) selected")
                    .font(.headline.monospacedDigit())
                Text(model.selectedFlags.isEmpty ? "Tick the categories you want to clean." : selectedDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showsConfirmation = true
            } label: {
                Label(
                    model.selectedFlags.isEmpty ? "Clean Selected" : "Clean \(ByteFormatter.string(model.selectedBytes))",
                    systemImage: "trash"
                )
                .font(.body.weight(.semibold))
                .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(model.isBusy || model.selectedFlags.isEmpty)
            .help("Clean the selected categories (⌘⌫)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var isInitialScan: Bool {
        model.report == nil && model.isBusy
    }

    private var selectedDetail: String {
        let selected = model.selectedGroups
        if selected.isEmpty { return "Choose categories below" }
        let locations = countLabel(model.selectedLocationCount, "location", "locations")
        let shared = selected.contains { $0.hasUnknownSize } ? " + shared sim data" : ""
        return locations + shared
    }

    private func countLabel(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }

    @ViewBuilder
    private var content: some View {
        if page == .simulators {
            SimulatorDevicesView()
        } else if model.report == nil && model.isBusy {
            ScanningHeroView(disk: model.diskSpace)
        } else {
            switch page {
            case .review:
                ReviewOnlyView()
            case .cleanup, .none:
                CleanupGroupsView()
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if !model.groups.isEmpty {
                            cleanupActionBar
                        }
                    }
            case .projects, .about, .simulators, .diskMap:
                EmptyView()
            }
        }
    }
}

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                RavenVectorBrandLogo(size: 270)

                VStack(spacing: 6) {
                    Text("mac-dev-clean")
                        .font(.largeTitle.bold())
                    Text("Version \(AppMetadata.version)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text("A utility for finding and safely reclaiming developer storage on macOS.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 520)

                Link(destination: AppMetadata.ravenVectorWebsite) {
                    Label("Visit ravenvector.com", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Divider()
                    .frame(maxWidth: 460)

                VStack(spacing: 5) {

                    Text("Source code under the MIT License")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .padding(.vertical, 36)
        }
        .navigationTitle("About")
    }
}

struct CleanupGroupsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if model.groups.isEmpty {
                    ContentUnavailableView(
                        "Nothing to Clean",
                        systemImage: "checkmark.circle",
                        description: Text("Run another scan after developer tools create new caches.")
                    )
                    .padding(.top, 80)
                } else {
                    ForEach(model.groups) { group in
                        CleanupGroupCard(
                            group: group,
                            isSelected: Binding(
                                get: { model.selectedFlags.contains(group.rule.flag) },
                                set: { selected in
                                    if selected {
                                        model.selectedFlags.insert(group.rule.flag)
                                    } else {
                                        model.selectedFlags.remove(group.rule.flag)
                                    }
                                }
                            )
                        )
                    }
                }
            }
            .padding(20)
        }
    }
}

struct CleanupGroupCard: View {
    @EnvironmentObject private var model: AppModel
    let group: CleanupGroup
    @Binding var isSelected: Bool
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Toggle("", isOn: $isSelected)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                Button(action: toggleExpanded) {
                    HStack(spacing: 12) {
                        Image(systemName: group.rule.symbol)
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.rule.title)
                                .font(.headline)
                            Text("\(group.items.count) location\(group.items.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(group.displaySize)
                            .font(.headline.monospacedDigit())
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .frame(width: 32, height: 32)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .frame(maxWidth: .infinity)
                .buttonStyle(.plain)
                .help(isExpanded ? "Hide locations" : "Show locations")
                .accessibilityLabel("\(isExpanded ? "Collapse" : "Expand") \(group.rule.title)")
            }

            if isExpanded {
                Divider()
                VStack(spacing: 10) {
                    ForEach(group.items) { item in
                        LocationRow(item: item) { model.reveal(item) }
                    }
                }
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.15))
        }
    }

    private func toggleExpanded() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isExpanded.toggle()
        }
    }
}

struct LocationRow: View {
    let item: ScanItem
    let reveal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.label)
                        .font(.subheadline.weight(.medium))
                    Text(item.displaySize)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(item.displayPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if !item.note.isEmpty {
                    Text(item.note)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button("Reveal", action: reveal)
                .controlSize(.small)
        }
    }
}

struct ReviewOnlyView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Keep, archive, or remove manually")
                            .font(.headline)
                        Text("These items are never included in automatic cleanup. Older Xcode archive copies appear on Cleanup.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open iCloud Drive") { model.openICloudDrive() }
                }
                .padding(.bottom, 4)

                ForEach(model.reviewItems) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.label)
                                    .font(.headline)
                                Text(item.category)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.displaySize)
                                .font(.headline.monospacedDigit())
                        }
                        Text(item.displayPath)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if !item.note.isEmpty {
                            Text(item.note)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Spacer()
                            Button("Reveal in Finder") { model.reveal(item) }
                        }
                    }
                    .padding(14)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.15))
                    }
                }
            }
            .padding(20)
        }
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    var detail: String = ""
    let symbol: String
    let color: Color

    var body: some View {
        StatTile(title: title, symbol: symbol, color: color) {
            Text(value)
                .font(.title2.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct DiskUsageCard: View {
    let disk: DiskSpace?

    private var usedFraction: Double {
        guard let disk, disk.totalBytes > 0 else { return 0 }
        return min(1, max(0, 1 - Double(disk.freeBytes) / Double(disk.totalBytes)))
    }

    var body: some View {
        StatTile(title: "Free space", symbol: "internaldrive", color: .cyan) {
            Text(disk?.free ?? "—")
                .font(.title2.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(spacing: 8) {
                ProgressView(value: usedFraction)
                    .progressViewStyle(.linear)
                    .tint(usedFraction > 0.9 ? .red : .cyan)
                Text("of \(disk?.total ?? "—")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(disk?.free ?? "Unknown") free of \(disk?.total ?? "unknown")")
    }
}

private struct StatTile<Content: View>: View {
    let title: String
    let symbol: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 22, height: 22)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15))
        }
    }
}

/// Shown in place of the summary and list until the first scan finishes.
struct ScanningHeroView: View {
    let disk: DiskSpace?

    private static let places: [(title: String, symbol: String)] = [
        ("Xcode", "hammer.fill"),
        ("Simulators", "iphone.gen3"),
        ("Homebrew", "mug.fill"),
        ("npm, pnpm & Bun", "shippingbox.fill"),
        ("Python", "chevron.left.forwardslash.chevron.right"),
        ("SwiftPM", "swift"),
        ("Go & Rust", "gearshape.2.fill"),
        ("Gradle", "cube.fill"),
        ("Browsers & editors", "globe"),
    ]

    var body: some View {
        VStack(spacing: 22) {
            AppLogo(size: 72)

            VStack(spacing: 6) {
                Text("Scanning developer storage")
                    .font(.title2.weight(.semibold))
                Text("Measuring caches and build artifacts. Nothing is deleted until you choose what to clean.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ProgressView()
                .progressViewStyle(.linear)
                .frame(width: 280)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(Self.places, id: \.title) { place in
                    Label(place.title, systemImage: place.symbol)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .frame(maxWidth: 500)

            if let disk {
                Label("\(disk.free) free of \(disk.total)", systemImage: "internaldrive")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 520)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MessageBanner: View {
    let text: String
    let symbol: String
    let color: Color
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss message")
            .accessibilityLabel("Dismiss message")
        }
        .padding(10)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SimulatorDevicesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pendingDeletion: SimulatorDevice?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("Simulator devices")
                    .font(.title2.bold())
                Text("Review devices you no longer need. Keep the iPhone, iPad, and Apple TV configurations you still use for testing. Deleting a device permanently removes its installed apps, accounts, and local test data.")
                    .foregroundStyle(.secondary)
                Text("Sizes are reported by Xcode and may include shared data, so actual space recovered can be smaller. Installed runtimes are kept for reuse.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if model.activity == .scanningSimulators {
                    ProgressView("Reading devices…")
                } else if model.simulatorInventory != nil && model.simulatorDevices.isEmpty {
                    Text("No simulator devices found.")
                } else if model.simulatorInventory == nil {
                    Text("Refresh to load simulator devices.")
                }
                ForEach(model.simulatorDevices) { device in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "iphone.gen3")
                            .font(.title2)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(device.name).font(.headline)
                            Text("\(device.runtimeName) · \(device.state)\(device.isAvailable ? "" : " · Runtime unavailable")")
                                .foregroundStyle(.secondary)
                            Text(device.lastBootedDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(device.udid)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            if !device.canDelete {
                                Text("In use or unavailable for deletion. Shut down in Xcode when testing is finished, then refresh.")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 10) {
                            Text(ByteFormatter.string(device.totalSizeBytes))
                                .font(.headline.monospacedDigit())
                            Button("Delete Device…", role: .destructive) {
                                pendingDeletion = device
                            }
                            .disabled(model.isBusy || !device.canDelete)
                            .accessibilityLabel("Delete \(device.name), \(device.runtimeName)")
                        }
                    }
                    .padding(16)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(20)
        }
        .confirmationDialog(
            "Delete \(pendingDeletion?.name ?? "simulator")?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { device in
            Button("Delete Device and Data", role: .destructive) {
                pendingDeletion = nil
                Task { await model.deleteSimulator(device) }
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { device in
            Text("\(device.name) · \(device.runtimeName)\n\(device.udid)\n\nPermanently remove this device and all its apps, accounts, and local data. This cannot be undone. Reported size: \(ByteFormatter.string(device.totalSizeBytes)); actual recovery may be smaller. The runtime stays installed. Current device state will be checked again before deletion.")
        }
    }
}
