import Foundation

struct RepositoryProject: Codable, Hashable, Identifiable, Sendable {
    let path: String
    let name: String
    let sizeBytes: Int64
    let isGitRepository: Bool
    let branch: String?
    let remoteURL: String?
    let commit: String?
    let hasTrackedChanges: Bool
    let lastActivityAt: Date?

    var id: String { path }
    var size: String { ByteFormatter.string(sizeBytes) }
    var displayPath: String { Self.displayPath(path) }

    var remoteSummary: String? {
        guard let remoteURL, !remoteURL.isEmpty else { return nil }

        if remoteURL.contains("://"), let components = URLComponents(string: remoteURL) {
            let host = components.host ?? "Remote"
            let repositoryPath = components.path
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .replacingOccurrences(of: ".git", with: "")
            return repositoryPath.isEmpty ? host : "\(host)/\(repositoryPath)"
        }

        if let separator = remoteURL.firstIndex(of: ":") {
            let hostPart = remoteURL[..<separator]
            let pathPart = remoteURL[remoteURL.index(after: separator)...]
            let host = hostPart.split(separator: "@").last.map(String.init) ?? String(hostPart)
            let repositoryPath = pathPart.replacingOccurrences(of: ".git", with: "")
            return repositoryPath.isEmpty ? host : "\(host)/\(repositoryPath)"
        }

        return URL(fileURLWithPath: remoteURL).lastPathComponent
            .replacingOccurrences(of: ".git", with: "")
    }

    static func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

struct ShelvedProject: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let originalPath: String
    let shelfPath: String
    let sizeBytes: Int64
    let isGitRepository: Bool
    let branch: String?
    let remoteURL: String?
    let commit: String?
    let hadTrackedChanges: Bool
    let shelvedAt: Date

    var size: String { ByteFormatter.string(sizeBytes) }
    var displayOriginalPath: String { RepositoryProject.displayPath(originalPath) }
    var displayShelfPath: String { RepositoryProject.displayPath(shelfPath) }
}

struct RepositoryShelfCatalog: Codable, Equatable, Sendable {
    var shelfRootPath: String?
    var projects: [RepositoryProject]
    var shelvedProjects: [ShelvedProject]

    static let empty = RepositoryShelfCatalog(
        shelfRootPath: nil,
        projects: [],
        shelvedProjects: []
    )
}

enum RepositoryShelfError: LocalizedError, Sendable {
    case projectUnavailable(String)
    case invalidProject(String)
    case shelfNotConfigured
    case unsafeRelationship
    case destinationExists(String)
    case originalLocationOccupied(String)
    case transferIncomplete(source: String, destination: String)

    var errorDescription: String? {
        switch self {
        case let .projectUnavailable(path):
            return "The project folder is not available at \(path). Connect its volume or locate it again."
        case let .invalidProject(path):
            return "Choose a project folder, not your home folder or a filesystem root.\n\(path)"
        case .shelfNotConfigured:
            return "Choose a Project Shelf location before moving a project."
        case .unsafeRelationship:
            return "The Project Shelf cannot be inside the project being moved, and a project cannot be inside its shelf."
        case let .destinationExists(path):
            return "A folder already exists at the planned shelf location. Choose another shelf or move that folder first.\n\(path)"
        case let .originalLocationOccupied(path):
            return "The original project location is already occupied. Move that folder aside before restoring.\n\(path)"
        case let .transferIncomplete(source, destination):
            return "The transfer did not reach a verifiable final state. Nothing else was changed. Inspect both locations before trying again.\nSource: \(source)\nDestination: \(destination)"
        }
    }
}

protocol RepositoryShelfServiceProtocol: Sendable {
    func loadCatalog() throws -> RepositoryShelfCatalog
    func saveCatalog(_ catalog: RepositoryShelfCatalog) throws
    func discoverRepositories(in root: URL, excluding excludedRoot: URL?) async throws -> [RepositoryProject]
    func inspectProject(at url: URL) async throws -> RepositoryProject
    func shelf(_ project: RepositoryProject, in shelfRoot: URL) async throws -> ShelvedProject
    func restore(_ project: ShelvedProject) async throws -> RepositoryProject
    func storageAdvice(source: URL, shelfRoot: URL) -> String
}

struct RepositoryShelfService: RepositoryShelfServiceProtocol, Sendable {
    let catalogURL: URL

    init(catalogURL: URL? = nil) {
        if let catalogURL {
            self.catalogURL = catalogURL
            return
        }

        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        self.catalogURL = applicationSupport
            .appendingPathComponent("com.ravenvector.mac-dev-clean", isDirectory: true)
            .appendingPathComponent("repository-shelf.json")
    }

    func loadCatalog() throws -> RepositoryShelfCatalog {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: catalogURL.path) else { return .empty }
        let data = try Data(contentsOf: catalogURL)
        return try JSONDecoder().decode(RepositoryShelfCatalog.self, from: data)
    }

    func saveCatalog(_ catalog: RepositoryShelfCatalog) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: catalogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(catalog)
        try data.write(to: catalogURL, options: .atomic)
    }

    func discoverRepositories(
        in root: URL,
        excluding excludedRoot: URL?
    ) async throws -> [RepositoryProject] {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let root = root.standardizedFileURL
            guard Self.isDirectory(root, fileManager: fileManager) else {
                throw RepositoryShelfError.projectUnavailable(root.path)
            }

            var repositoryURLs: [URL] = []
            if Self.isGitRepository(root, fileManager: fileManager) {
                repositoryURLs.append(root)
            } else if let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) {
                let rootDepth = root.pathComponents.count
                while let url = enumerator.nextObject() as? URL {
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }

                    let depth = url.pathComponents.count - rootDepth
                    let excludedNames: Set<String> = [
                        "Applications", "Library", "Movies", "Music", "Pictures",
                        "node_modules", "DerivedData", ".build",
                    ]
                    if excludedNames.contains(url.lastPathComponent)
                        || excludedRoot.map({ Self.contains(url, in: $0) }) == true
                    {
                        enumerator.skipDescendants()
                        continue
                    }
                    if depth > 3 {
                        enumerator.skipDescendants()
                        continue
                    }
                    if Self.isGitRepository(url, fileManager: fileManager) {
                        repositoryURLs.append(url)
                        enumerator.skipDescendants()
                    }
                }
            }

            return try repositoryURLs
                .map { try Self.inspectProjectSynchronously(at: $0) }
                .sorted {
                    if $0.sizeBytes == $1.sizeBytes { return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                    return $0.sizeBytes > $1.sizeBytes
                }
        }.value
    }

    func inspectProject(at url: URL) async throws -> RepositoryProject {
        try await Task.detached(priority: .userInitiated) {
            try Self.inspectProjectSynchronously(at: url.standardizedFileURL)
        }.value
    }

    func shelf(_ project: RepositoryProject, in shelfRoot: URL) async throws -> ShelvedProject {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let source = URL(fileURLWithPath: project.path, isDirectory: true).standardizedFileURL
            let shelfRoot = shelfRoot.standardizedFileURL
            try Self.validateProjectRoot(source, fileManager: fileManager)
            try fileManager.createDirectory(at: shelfRoot, withIntermediateDirectories: true)

            guard !Self.contains(shelfRoot, in: source), !Self.contains(source, in: shelfRoot) else {
                throw RepositoryShelfError.unsafeRelationship
            }

            let id = UUID()
            let destination = shelfRoot.appendingPathComponent(
                Self.availableShelfName(for: project.name, id: id, shelfRoot: shelfRoot),
                isDirectory: true
            )
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw RepositoryShelfError.destinationExists(destination.path)
            }

            try fileManager.moveItem(at: source, to: destination)
            guard !fileManager.fileExists(atPath: source.path),
                  fileManager.fileExists(atPath: destination.path)
            else {
                throw RepositoryShelfError.transferIncomplete(
                    source: source.path,
                    destination: destination.path
                )
            }

            return ShelvedProject(
                id: id,
                name: project.name,
                originalPath: source.path,
                shelfPath: destination.path,
                sizeBytes: project.sizeBytes,
                isGitRepository: project.isGitRepository,
                branch: project.branch,
                remoteURL: project.remoteURL,
                commit: project.commit,
                hadTrackedChanges: project.hasTrackedChanges,
                shelvedAt: Date()
            )
        }.value
    }

    func restore(_ project: ShelvedProject) async throws -> RepositoryProject {
        try await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let source = URL(fileURLWithPath: project.shelfPath, isDirectory: true).standardizedFileURL
            let destination = URL(fileURLWithPath: project.originalPath, isDirectory: true).standardizedFileURL
            guard fileManager.fileExists(atPath: source.path) else {
                throw RepositoryShelfError.projectUnavailable(source.path)
            }
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw RepositoryShelfError.originalLocationOccupied(destination.path)
            }

            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: source, to: destination)
            guard !fileManager.fileExists(atPath: source.path),
                  fileManager.fileExists(atPath: destination.path)
            else {
                throw RepositoryShelfError.transferIncomplete(
                    source: source.path,
                    destination: destination.path
                )
            }
            return try Self.inspectProjectSynchronously(at: destination)
        }.value
    }

    func storageAdvice(source: URL, shelfRoot: URL) -> String {
        let shelfPath = shelfRoot.standardizedFileURL.path
        if shelfPath.contains("/Library/Mobile Documents/com~apple~CloudDocs") {
            return "iCloud Drive will upload the full project. To reclaim SSD space promptly, wait for upload to finish, then use Finder’s Remove Download command; otherwise macOS decides when to evict the local copy."
        }

        let keys: Set<URLResourceKey> = [.volumeIdentifierKey]
        let sourceVolume = try? source.resourceValues(forKeys: keys).volumeIdentifier
        let shelfVolume = try? shelfRoot.resourceValues(forKeys: keys).volumeIdentifier
        if let sourceVolume, let shelfVolume,
           String(describing: sourceVolume) == String(describing: shelfVolume)
        {
            return "This shelf is on the same disk as your home folder. Rotation will organize projects but will not reclaim local SSD space."
        }
        return "This shelf appears to be on another volume. Moving a project here should reclaim its local SSD space after the transfer completes. An APFS-formatted volume is recommended to preserve macOS permissions and symbolic links."
    }

    private static func inspectProjectSynchronously(at url: URL) throws -> RepositoryProject {
        let fileManager = FileManager.default
        try validateProjectRoot(url, fileManager: fileManager)
        let isGit = isGitRepository(url, fileManager: fileManager)
        let branch = isGit ? gitOutput(["rev-parse", "--abbrev-ref", "HEAD"], in: url) : nil
        let remote = isGit ? gitOutput(["config", "--get", "remote.origin.url"], in: url) : nil
        let commit = isGit ? gitOutput(["rev-parse", "HEAD"], in: url) : nil
        let hasTrackedChanges = isGit
            ? gitStatus(["diff-index", "--quiet", "HEAD", "--"], in: url) != 0
            : false

        return RepositoryProject(
            path: url.path,
            name: url.lastPathComponent,
            sizeBytes: allocatedSize(of: url, fileManager: fileManager),
            isGitRepository: isGit,
            branch: branch,
            remoteURL: remote,
            commit: commit,
            hasTrackedChanges: hasTrackedChanges,
            lastActivityAt: lastActivityDate(for: url, fileManager: fileManager)
        )
    }

    private static func validateProjectRoot(_ url: URL, fileManager: FileManager) throws {
        guard isDirectory(url, fileManager: fileManager) else {
            throw RepositoryShelfError.projectUnavailable(url.path)
        }
        let home = fileManager.homeDirectoryForCurrentUser.standardizedFileURL
        guard url.path != home.path,
              url.path != "/",
              url.deletingLastPathComponent().path != "/"
        else {
            throw RepositoryShelfError.invalidProject(url.path)
        }
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private static func isGitRepository(_ url: URL, fileManager: FileManager) -> Bool {
        fileManager.fileExists(atPath: url.appendingPathComponent(".git").path)
    }

    private static func contains(_ candidate: URL, in root: URL) -> Bool {
        let candidatePath = candidate.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    private static func availableShelfName(
        for name: String,
        id: UUID,
        shelfRoot: URL
    ) -> String {
        let direct = shelfRoot.appendingPathComponent(name).path
        if !FileManager.default.fileExists(atPath: direct) { return name }
        return "\(name)--\(id.uuidString.prefix(8).lowercased())"
    }

    private static func allocatedSize(of root: URL, fileManager: FileManager) -> Int64 {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
        ]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true
            else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    private static func lastActivityDate(for root: URL, fileManager: FileManager) -> Date? {
        let candidates = [
            root,
            root.appendingPathComponent(".git/index"),
            root.appendingPathComponent(".git/FETCH_HEAD"),
            root.appendingPathComponent(".git/logs/HEAD"),
        ]
        return candidates.compactMap { url in
            (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        }.max()
    }

    private static func gitOutput(_ arguments: [String], in directory: URL) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let value = String(
                data: output.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == true ? nil : value
        } catch {
            return nil
        }
    }

    private static func gitStatus(_ arguments: [String], in directory: URL) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
