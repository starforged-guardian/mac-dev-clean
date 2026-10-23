import AppKit
import SwiftUI

@MainActor
final class DiskMapModel: ObservableObject {
    @Published private(set) var report: DiskMapReport?
    @Published private(set) var isScanning = false
    @Published private(set) var scanningPath = ""
    @Published var message: String?
    @Published var trail: [DiskMapNode] = []
    @Published var selected: DiskMapNode?
    private var worker: Task<DiskMapReport, Error>?
    private var history: [(report: DiskMapReport, trail: [DiskMapNode])] = []

    init(report: DiskMapReport? = nil) { self.report = report }

    var current: DiskMapNode? { trail.last ?? report?.root }
    var canGoBack: Bool { !trail.isEmpty || !history.isEmpty }

    func scan(path: String = "/", wholeDisk: Bool = true, remember: Bool = false) {
        guard !isScanning else { return }
        isScanning = true
        scanningPath = wholeDisk ? "Startup disk" : path
        message = nil
        let task = Task.detached(priority: .utility) { try DiskMapScanner().scan(path: path, wholeDisk: wholeDisk) }
        worker = task
        Task {
            defer { isScanning = false; worker = nil }
            do {
                let result = try await task.value
                guard !task.isCancelled else { message = "Scan cancelled. The previous map is unchanged."; return }
                if remember, let report { history.append((report, trail)) } else { history = [] }
                report = result
                trail = []
                selected = nil
            } catch is CancellationError {
                message = "Scan cancelled. The previous map is unchanged."
            } catch {
                message = "Could not scan \(scanningPath): \(error.localizedDescription)"
            }
        }
    }

    func cancel() { worker?.cancel() }

    func open(_ node: DiskMapNode) {
        guard node.isDirectory, !isScanning else { return }
        if !node.children.isEmpty {
            trail.append(node)
            selected = nil
        } else if let path = node.path {
            scan(path: path, wholeDisk: false, remember: true)
        }
    }

    func back() {
        if !trail.isEmpty { trail.removeLast() }
        else if let previous = history.popLast() {
            report = previous.report
            trail = previous.trail
        }
        selected = nil
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Map Folder"
        if panel.runModal() == .OK, let url = panel.url {
            scan(path: url.path, wholeDisk: false)
        }
    }
}

extension DiskMapCategory {
    var color: Color {
        switch self {
        case .applications: Color(red: 0.65, green: 0.49, blue: 0.95)
        case .developer: Color(red: 0.32, green: 0.61, blue: 0.96)
        case .caches: Color(red: 0.22, green: 0.72, blue: 0.64)
        case .media: Color(red: 0.89, green: 0.47, blue: 0.65)
        case .documents: Color(red: 0.90, green: 0.64, blue: 0.33)
        case .system: Color(red: 0.49, green: 0.53, blue: 0.75)
        case .other: Color(red: 0.55, green: 0.60, blue: 0.66)
        }
    }
}

struct DiskMapView: View {
    @ObservedObject var map: DiskMapModel
    @EnvironmentObject private var app: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var hoveredID: String?
    @State private var showsDetails = false
    private var busy: Bool { map.isScanning || app.isBusy }
    private var accent: Color { Color(red: 0.39, green: 0.57, blue: 0.98) }
    private var surface: Color { Color(nsColor: .controlBackgroundColor) }
    private var outline: Color { Color.primary.opacity(scheme == .dark ? 0.09 : 0.07) }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if map.isScanning { scanStatus }
                    if let message = map.message {
                        Label(message, systemImage: "info.circle")
                            .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    if let report = map.report, let current = map.current {
                        capacity(report)
                        workspace(current, height: max(300, geometry.size.height - 410), compact: geometry.size.width < 650, inspectorWidth: geometry.size.width < 900 ? 220 : 270)
                        notes(report)
                    } else {
                        welcome(compact: geometry.size.width < 820)
                            .frame(minHeight: max(0, geometry.size.height - (map.isScanning ? 220 : 140)))
                    }
                }
                .padding(28)
                .frame(maxWidth: 1500)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.65))
        }
        .onDisappear { map.cancel() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Disk Map").font(.system(size: 25, weight: .bold))
                    Text(map.report == nil ? "Explore your storage, one folder at a time." : "Your storage at a glance.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            if let report = map.report {
                Menu {
                    Button("Map Startup Disk") { map.scan() }
                    Button("Choose Folder…", action: map.chooseFolder)
                } label: { Label("New Scan", systemImage: "plus") }
                    .fixedSize().disabled(busy)
                Button {
                    map.scan(path: report.root.path ?? "/", wholeDisk: report.wholeDisk)
                } label: { Image(systemName: "arrow.clockwise") }
                    .help("Refresh this scan").disabled(busy)
            } else {
                Label("Read only", systemImage: "lock.shield")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(surface.opacity(0.7), in: Capsule())
            }
        }
    }

    private func welcome(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Group {
                if compact {
                    VStack(alignment: .leading, spacing: 28) {
                        introduction
                        volumePreview(compact: true)
                    }
                } else {
                    HStack(spacing: 40) {
                        introduction.frame(maxWidth: .infinity, alignment: .leading)
                        volumePreview(compact: false).frame(width: 280)
                    }
                }
            }
            .padding(compact ? 26 : 36)
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(LinearGradient(colors: [accent.opacity(0.10), .clear, .teal.opacity(0.045)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
            }
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(outline))

            HStack(alignment: .top, spacing: 28) {
                feature("square.grid.3x3.fill", title: "Find the big files", detail: "Proportional tiles make large folders easy to spot.", color: .purple)
                feature("folder", title: "Explore every layer", detail: "Open folders in the map, then reveal them in Finder.", color: .teal)
                feature("hand.raised", title: "Stay in control", detail: "Scan locally. Nothing is moved or deleted.", color: accent)
            }
            .padding(.horizontal, 6)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle")
                Text("Protected personal folders, cloud drives and private app data are skipped. Their storage remains in unaccounted usage.")
            }
            .font(.caption).foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .frame(maxWidth: 1050)
        .frame(maxWidth: .infinity)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("STORAGE EXPLORER")
                .font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(accent)
            Text("See what’s taking\nup space.")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .tracking(-1).fixedSize(horizontal: false, vertical: true)
            Text("Turn your disk into a color-coded map. Find large folders, follow the space, and decide what deserves a closer look.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 380, alignment: .leading)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { scanActions }
                VStack(alignment: .leading, spacing: 10) { scanActions }
            }.padding(.top, 6)
            Label("On-device scan · No files changed", systemImage: "checkmark.shield")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var scanActions: some View {
        Button { map.scan() } label: {
            Label("Map Startup Disk", systemImage: "internaldrive")
                .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 8).padding(.vertical, 7)
        }.buttonStyle(DiskMapPrimaryButtonStyle(color: accent)).disabled(busy)
        Button(action: map.chooseFolder) {
            Text("Choose Folder…").font(.system(size: 13, weight: .medium)).padding(.horizontal, 5).padding(.vertical, 7)
        }.buttonStyle(.bordered).disabled(busy)
    }

    private func volumePreview(compact: Bool) -> some View {
        let disk = app.diskSpace
        let total = max(1, disk?.totalBytes ?? 1)
        let fraction = min(1, max(0, Double(disk?.freeBytes ?? 0) / Double(total)))
        return Group {
            if compact {
                HStack(spacing: 24) {
                    usageRing(fraction: fraction, free: disk?.free ?? "—").frame(width: 120, height: 120)
                    volumeLabels(disk)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 22) {
                    Label("Startup disk", systemImage: "internaldrive.fill").font(.headline)
                    usageRing(fraction: fraction, free: disk?.free ?? "—").frame(width: 180, height: 180)
                    volumeLabels(disk)
                }.frame(maxWidth: .infinity)
            }
        }
        .padding(22)
        .background(surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(outline))
    }

    private func usageRing(fraction: Double, free: String) -> some View {
        ZStack {
            Circle().stroke(accent.opacity(0.10), lineWidth: 12)
            Circle().trim(from: 0, to: fraction)
                .stroke(AngularGradient(colors: [accent, .cyan, accent], center: .center, startAngle: .degrees(0), endAngle: .degrees(360)), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 5) {
                Text(free).font(.system(size: 24, weight: .bold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                Text("AVAILABLE").font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
            }.padding(18)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(free) available on startup disk")
    }

    private func volumeLabels(_ disk: DiskSpace?) -> some View {
        VStack(spacing: 10) {
            HStack { Text("Capacity").foregroundStyle(.secondary); Spacer(); Text(disk?.total ?? "—").fontWeight(.medium) }
            HStack { Text("Used").foregroundStyle(.secondary); Spacer(); Text(disk.map { ByteFormatter.string(max(0, $0.totalBytes - $0.freeBytes)) } ?? "—").fontWeight(.medium) }
            Divider()
            Text("Folder breakdown appears after scanning.").font(.caption).foregroundStyle(.secondary)
        }.font(.callout).monospacedDigit()
    }

    private func feature(_ symbol: String, title: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(color)
            Text(title).font(.system(size: 13, weight: .semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scanStatus: some View {
        HStack(spacing: 14) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                Text("Building your disk map").font(.headline)
                Text(map.scanningPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text("Large disks can take a few minutes.").font(.caption).foregroundStyle(.secondary)
            Button("Cancel", action: map.cancel)
        }
        .padding(16).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(accent.opacity(0.18)))
    }

    private func capacity(_ report: DiskMapReport) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                metric("Mapped files", value: report.root.bytes, color: accent)
                Divider().frame(height: 40)
                metric("Available", value: report.free, color: .teal)
                Divider().frame(height: 40)
                metric("Volume used", value: report.used, color: .secondary)
            }
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    Rectangle().fill(accent).frame(width: max(0, geometry.size.width - 4) * CGFloat(min(report.root.bytes, report.used)) / CGFloat(max(1, report.capacity)))
                    Rectangle().fill(Color.secondary.opacity(0.3)).frame(width: max(0, geometry.size.width - 4) * CGFloat(report.unaccounted) / CGFloat(max(1, report.capacity)))
                    Rectangle().fill(Color.teal.opacity(0.7))
                }.clipShape(Capsule())
            }.frame(height: 7)
            HStack {
                Text("\(ByteFormatter.string(report.capacity)) total capacity")
                Spacer()
                Text("\(ByteFormatter.string(report.unaccounted)) \(report.wholeDisk ? "unaccounted / system-managed" : "outside folder / unaccounted")")
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).background(surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(outline))
    }

    private func metric(_ title: String, value: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label { Text(title) } icon: { Circle().fill(color).frame(width: 6, height: 6) }
                .font(.caption).foregroundStyle(.secondary)
            Text(ByteFormatter.string(value)).font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func workspace(_ current: DiskMapNode, height: CGFloat, compact: Bool, inspectorWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            navigation(current).padding(16)
            Divider()
            if compact {
                VStack(spacing: 0) {
                    mapPanel(current).frame(height: height)
                    Divider()
                    inspector(current).frame(height: 330)
                }
            } else {
                HStack(spacing: 0) {
                    mapPanel(current)
                    Divider()
                    inspector(current).frame(width: inspectorWidth)
                }.frame(height: height)
            }
        }
        .background(surface, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(outline))
    }

    private func navigation(_ node: DiskMapNode) -> some View {
        HStack(spacing: 12) {
            Button(action: map.back) { Image(systemName: "chevron.left") }
                .disabled(!map.canGoBack || busy).help("Back")
            Button { map.trail = []; map.selected = nil } label: { Image(systemName: "internaldrive") }
                .disabled(busy).help("Current scan overview")
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            VStack(alignment: .leading, spacing: 3) {
                Text(node.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(node.path ?? "System and Data volumes").font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(ByteFormatter.string(node.bytes)).font(.system(size: 13, weight: .semibold, design: .monospaced))
        }
    }

    private func mapPanel(_ node: DiskMapNode) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("STORAGE MAP").font(.system(size: 10, weight: .bold)).tracking(1.4)
                Spacer()
                Text("Double-click a folder to explore").font(.caption2)
            }.foregroundStyle(.secondary)
            treemap(node)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(DiskMapCategory.allCases, id: \.self) { category in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(category.color).frame(width: 7, height: 7)
                        Text(category.rawValue).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }.padding(16)
    }

    private func treemap(_ node: DiskMapNode) -> some View {
        GeometryReader { geometry in
            let tiles = DiskMapLayout.tiles(node.children, in: CGRect(origin: .zero, size: geometry.size))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.025))
                if tiles.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "folder.badge.questionmark").font(.title)
                        Text("No allocated files measured").font(.headline)
                        Text("Check scan details for access issues.").font(.caption)
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ForEach(tiles) { tile in
                    let grouped = !tile.node.children.isEmpty && tile.rect.width > 150 && tile.rect.height > 110
                    tileView(tile, grouped: grouped)
                    if grouped {
                        let interior = CGRect(x: tile.rect.minX + 5, y: tile.rect.minY + 31, width: tile.rect.width - 10, height: tile.rect.height - 36)
                        ForEach(DiskMapLayout.tiles(tile.node.children, in: interior)) { child in
                            tileView(child)
                        }
                    }
                }
            }.clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func tileView(_ tile: DiskMapTile, grouped: Bool = false) -> some View {
        let node = tile.node
        let selected = map.selected?.id == node.id
        let hovered = hoveredID == node.id
        let alpha: Double = scheme == .dark ? (grouped ? 0.16 : 0.34) : (grouped ? 0.10 : 0.22)
        return Button { map.selected = node } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(node.category.color.opacity(alpha + (selected || hovered ? 0.14 : 0)))
                RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? node.category.color : node.category.color.opacity(0.32), lineWidth: selected ? 2 : 0.75)
                if tile.rect.width > 60, tile.rect.height > 38 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(node.name).font(.system(size: grouped ? 10 : 12, weight: .semibold)).lineLimit(grouped ? 1 : 2)
                        if !grouped, tile.rect.height > 76 {
                            Text(ByteFormatter.string(node.bytes)).font(.system(size: tile.rect.width > 140 ? 18 : 11, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                        }
                    }.padding(grouped ? 9 : 11)
                }
            }.foregroundStyle(.primary).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { if !busy { map.open(node) } })
        .contextMenu {
            if node.isDirectory { Button("Open Folder") { map.open(node) }.disabled(busy) }
            if let path = node.path { Button("Show in Finder") { app.revealPath(path) } }
        }
        .onHover { hoveredID = $0 ? node.id : nil }
        .frame(width: max(0, tile.rect.width - 3), height: max(0, tile.rect.height - 3))
        .clipped().offset(x: tile.rect.minX + 1.5, y: tile.rect.minY + 1.5)
        .help("\(node.path ?? node.name)\n\(ByteFormatter.string(node.bytes))")
        .accessibilityLabel("\(node.name), \(ByteFormatter.string(node.bytes)), \(node.category.rawValue)")
    }

    private func inspector(_ current: DiskMapNode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Largest entries").font(.system(size: 14, weight: .semibold))
                Text("\(current.children.count) entries · sorted by size").font(.caption).foregroundStyle(.secondary)
            }.padding(16)
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(current.children.sorted { $0.bytes > $1.bytes }) { node in
                        entryRow(node, total: current.bytes)
                    }
                }.padding(.horizontal, 8).padding(.bottom, 8)
            }
            Divider()
            if let node = map.selected {
                selectionDetails(node)
            } else {
                Label("Select a tile to inspect its size and location.", systemImage: "cursorarrow.click")
                    .font(.caption).foregroundStyle(.secondary).padding(16)
            }
        }
    }

    private func entryRow(_ node: DiskMapNode, total: Int64) -> some View {
        let fraction = min(1, Double(node.bytes) / Double(max(1, total)))
        return Button { map.selected = node } label: {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: node.isDirectory ? "folder.fill" : "doc.fill")
                    .foregroundStyle(node.category.color).font(.system(size: 13)).frame(width: 18).padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(node.name).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    HStack {
                        Text(ByteFormatter.string(node.bytes))
                        Spacer()
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                    }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    GeometryReader { geometry in
                        Capsule().fill(node.category.color.opacity(0.6)).frame(width: max(0, geometry.size.width * fraction))
                    }.frame(height: 3).background(Color.primary.opacity(0.04), in: Capsule())
                }
            }
            .padding(10)
            .background(map.selected?.id == node.id ? node.category.color.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func selectionDetails(_ node: DiskMapNode) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(node.category.rawValue.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.2).foregroundStyle(node.category.color)
            Text(node.name).font(.headline).lineLimit(2)
            Text(ByteFormatter.string(node.bytes)).font(.system(size: 23, weight: .semibold, design: .rounded))
            if let path = node.path {
                Text(path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2).truncationMode(.middle)
                HStack {
                    if node.isDirectory {
                        Button("Open Folder") { map.open(node) }.disabled(busy).buttonStyle(.borderedProminent).tint(accent)
                    }
                    Button { app.revealPath(path) } label: { Label("Finder", systemImage: "arrow.up.forward.square") }
                        .help("Show in Finder")
                }.controlSize(.small).padding(.top, 2)
            } else {
                Text("Smaller entries and folder metadata, grouped together.").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.025))
    }

    private func notes(_ report: DiskMapReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(report.scannedAt.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                Text("·")
                Text("\(report.excludedCount) excluded · \(report.skipped) unreadable · \(report.skippedMounts) mounts skipped")
                Spacer()
                Button { showsDetails.toggle() } label: {
                    Label("Scan details", systemImage: showsDetails ? "chevron.up" : "chevron.down")
                }.buttonStyle(.plain)
            }.font(.caption).foregroundStyle(.secondary)
            if showsDetails || report.exceedsUsed {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Allocated sizes are estimates, not reclaimable space. APFS clones can share blocks; snapshots, protected files and other volumes may remain unaccounted. Colors describe location, not whether deletion is safe.")
                    if report.exceedsUsed {
                        Text("Mapped sizes exceed volume usage because shared blocks or changing files can be counted more than once.").foregroundStyle(.orange)
                    }
                    Text("Personal folders, cloud drives and private app data are intentionally excluded to reduce permission prompts. Their storage remains unaccounted.")
                    if !report.excludedPaths.isEmpty {
                        Text("Excluded locations (up to 12): " + report.excludedPaths.joined(separator: ", ")).textSelection(.enabled)
                    }
                    if !report.issuePaths.isEmpty {
                        Text("Access issues: " + report.issuePaths.joined(separator: ", ")).textSelection(.enabled)
                    }
                }.font(.caption).foregroundStyle(.secondary).padding(14)
                    .background(surface, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

private struct DiskMapPrimaryButtonStyle: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.5))
            .background(color.opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.3), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.12)))
    }
}
