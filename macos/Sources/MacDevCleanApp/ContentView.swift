import SwiftUI

enum SidebarPage: String, CaseIterable, Identifiable {
    case cleanup = "Cleanup"
    case review = "Review Only"
    case simulators = "Simulators"
    case projects = "Project Shelf"
    case about = "About"

    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .cleanup: "sparkles"
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
                } else if page == .projects {
                    RepositoryShelfView()
                } else {
                    VStack(spacing: 0) {
                        header
                        Divider()
                        content
                    }
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

                    if page == .cleanup {
                        Button("Select All") { model.selectAll() }
                            .disabled(model.isBusy || model.groups.isEmpty)
                            .help("Select every cleanable category")
                        Button("Clear") { model.clearSelection() }
                            .disabled(model.isBusy || model.selectedFlags.isEmpty)
                            .help("Clear the cleanup selection")
                        Button {
                            showsConfirmation = true
                        } label: {
                            Label("Clean Selected", systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(model.isBusy || model.selectedFlags.isEmpty)
                        .help("Clean the selected categories")
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
            } else if page != .about {
                await model.scanIfNeeded()
            }
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Text(model.activity.message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.bar)
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                AppLogo(size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("mac-dev-clean")
                        .font(.title2.bold())
                    Text("Mac disk cleanup tool")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if page != .simulators {
                HStack(spacing: 12) {
                    SummaryCard(
                        title: "Cleanable",
                        value: model.report?.cleanableTotal ?? "—",
                        symbol: "sparkles",
                        color: .green
                    )
                    SummaryCard(
                        title: "Review only",
                        value: model.report?.reportOnlyTotal ?? "—",
                        symbol: "archivebox",
                        color: .orange
                    )
                    SummaryCard(
                        title: "Selected",
                        value: model.selectedFlags.isEmpty ? "None" : model.selectedSummary,
                        symbol: "checkmark.circle",
                        color: .blue
                    )
                }
            }

            HStack(spacing: 12) {
                SummaryCard(
                    title: "Free space",
                    value: model.diskSpace?.free ?? "—",
                    symbol: "internaldrive",
                    color: .cyan
                )
                SummaryCard(
                    title: "Total disk size",
                    value: model.diskSpace?.total ?? "—",
                    symbol: "externaldrive",
                    color: .purple
                )
            }

            if page == .cleanup || page == .review {
                Button {
                    page = .simulators
                } label: {
                    Label("Review large simulator devices…", systemImage: "iphone.gen3")
                }
                .disabled(model.isBusy)
            }

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

    @ViewBuilder
    private var content: some View {
        if page == .simulators {
            SimulatorDevicesView()
        } else if model.report == nil && model.isBusy {
            ContentUnavailableView {
                Label("Scanning", systemImage: "internaldrive")
            } description: {
                Text("Measuring developer caches and review-only storage…")
            }
        } else {
            switch page {
            case .review:
                ReviewOnlyView()
            case .cleanup, .none:
                CleanupGroupsView()
            case .projects, .about, .simulators:
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
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
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
