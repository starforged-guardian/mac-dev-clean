import SwiftUI

struct RepositoryShelfView: View {
    @EnvironmentObject private var model: AppModel
    @State private var pendingProject: RepositoryProject?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                title
                summary
                messages
                shelfLocation
                activeProjects
                shelvedProjects
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .confirmationDialog(
            "Move \(pendingProject?.name ?? "project") to the shelf?",
            isPresented: Binding(
                get: { pendingProject != nil },
                set: { if !$0 { pendingProject = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Move Complete Project Folder") {
                guard let project = pendingProject else { return }
                pendingProject = nil
                Task { await model.shelfProject(project) }
            }
            Button("Cancel", role: .cancel) { pendingProject = nil }
        } message: {
            Text("The entire folder moves intact, including .git, local branches, uncommitted changes, ignored files, and build data. Close editors and terminals using it first. Restore returns it to the exact original path.")
        }
    }

    private var title: some View {
        HStack(spacing: 14) {
            Image(systemName: "externaldrive.badge.icloud")
                .font(.system(size: 34))
                .foregroundStyle(.blue)
                .frame(width: 52, height: 52)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("Project Shelf")
                    .font(.title2.bold())
                Text("Rotate complete projects off this Mac and restore them in one click")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
                Text(model.activity.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            SummaryCard(
                title: "Managed on this Mac",
                value: ByteFormatter.string(model.repositoryBytesOnMac),
                symbol: "internaldrive",
                color: .cyan
            )
            SummaryCard(
                title: "On the shelf",
                value: ByteFormatter.string(model.shelvedRepositoryBytes),
                symbol: "archivebox.fill",
                color: .blue
            )
            SummaryCard(
                title: "Free space",
                value: model.diskSpace?.free ?? "—",
                symbol: "gauge.with.dots.needle.50percent",
                color: .green
            )
        }
    }

    @ViewBuilder
    private var messages: some View {
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

    private var shelfLocation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "shippingbox.and.arrow.backward.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Shelf location")
                        .font(.headline)
                    if let path = model.shelfDisplayPath {
                        Text(path)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        Text("Choose where inactive projects should live. An external disk is best for immediate SSD savings; iCloud Drive is best for anywhere access.")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if model.shelfRootURL != nil {
                    Button("Open in Finder") { model.openShelf() }
                }
                Button("Choose Folder…") { model.chooseShelfLocation() }
                    .buttonStyle(.bordered)
                Button("Use iCloud Drive") { model.useICloudShelf() }
                    .buttonStyle(.borderedProminent)
            }

            if let advice = model.shelfStorageAdvice {
                Label(advice, systemImage: "info.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            Text("Why an exact move? Re-cloning can lose unpublished commits, ignored files, local configuration, LFS objects, and other project-only state. The shelf keeps the whole folder and never rewrites the repository.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15))
        }
    }

    private var activeProjects: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On this Mac")
                        .font(.title3.bold())
                    Text("Git repositories found in your home folder, plus projects you add manually.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.findHomeRepositories() }
                } label: {
                    Label("Find Repositories", systemImage: "magnifyingglass")
                }
                .disabled(model.isBusy)
                Button {
                    Task { await model.addProjectFolder() }
                } label: {
                    Label("Add Project", systemImage: "plus")
                }
                .disabled(model.isBusy)
            }

            if model.repositoryProjects.isEmpty {
                ContentUnavailableView {
                    Label("No Projects Added", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Find Git repositories in your home folder or add any project folder manually.")
                } actions: {
                    Button("Find Repositories") {
                        Task { await model.findHomeRepositories() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ForEach(model.repositoryProjects) { project in
                    RepositoryProjectCard(project: project) {
                        pendingProject = project
                    }
                }
            }
        }
    }

    private var shelvedProjects: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to Restore")
                    .font(.title3.bold())
                Text("Restore puts the complete folder back at its recorded original path.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if model.shelvedProjects.isEmpty {
                Text("Projects you move off this Mac will appear here with a Restore button.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(model.shelvedProjects) { project in
                    ShelvedProjectCard(project: project)
                }
            }
        }
    }
}

private struct RepositoryProjectCard: View {
    @EnvironmentObject private var model: AppModel
    let project: RepositoryProject
    let moveToShelf: () -> Void

    private var isAvailable: Bool {
        FileManager.default.fileExists(atPath: project.path)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: project.isGitRepository ? "point.3.connected.trianglepath.dotted" : "folder.fill")
                .font(.title2)
                .foregroundStyle(project.isGitRepository ? .orange : .blue)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.headline)
                    if project.hasTrackedChanges {
                        Label("Tracked changes", systemImage: "pencil.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if !isAvailable {
                        Label("Missing", systemImage: "questionmark.folder")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Text(project.displayPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: 12) {
                    if let branch = project.branch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                    }
                    if let remote = project.remoteSummary {
                        Label(remote, systemImage: "network")
                    }
                    if let date = project.lastActivityAt {
                        Label(date.formatted(date: .abbreviated, time: .omitted), systemImage: "clock")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(project.size)
                .font(.headline.monospacedDigit())
            Button("Reveal") { model.revealPath(project.path) }
                .disabled(!isAvailable)
            Button("Move to Shelf", action: moveToShelf)
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || model.shelfRootURL == nil || !isAvailable)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15))
        }
    }
}

private struct ShelvedProjectCard: View {
    @EnvironmentObject private var model: AppModel
    let project: ShelvedProject

    private var shelfIsAvailable: Bool {
        FileManager.default.fileExists(atPath: project.shelfPath)
    }

    private var originalIsOccupied: Bool {
        FileManager.default.fileExists(atPath: project.originalPath)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "archivebox.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(project.name)
                        .font(.headline)
                    if !shelfIsAvailable {
                        Label("Shelf unavailable", systemImage: "externaldrive.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if originalIsOccupied {
                        Label("Original path occupied", systemImage: "exclamationmark.folder.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Text("Restore to \(project.displayOriginalPath)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: 12) {
                    if let branch = project.branch {
                        Label(branch, systemImage: "arrow.triangle.branch")
                    }
                    Label(project.shelvedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    if project.hadTrackedChanges {
                        Label("Tracked changes preserved", systemImage: "checkmark.shield.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(project.size)
                .font(.headline.monospacedDigit())
            Button("Reveal") { model.revealPath(project.shelfPath) }
                .disabled(!shelfIsAvailable)
            Button("Restore") {
                Task { await model.restoreProject(project) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isBusy || !shelfIsAvailable || originalIsOccupied)
        }
        .padding(14)
        .background(.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.blue.opacity(0.2))
        }
    }
}
