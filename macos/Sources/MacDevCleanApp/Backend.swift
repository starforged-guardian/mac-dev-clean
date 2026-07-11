import Foundation

enum BackendError: LocalizedError {
    case sourceNotFound
    case pythonNotFound
    case commandFailed(Int32, String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "Could not find the bundled mac-dev-clean Python engine."
        case .pythonNotFound:
            return "Python 3 was not found. Install Xcode Command Line Tools and try again."
        case let .commandFailed(code, message):
            return "mac-dev-clean exited with status \(code).\n\(message)"
        case let .invalidOutput(message):
            return "mac-dev-clean returned invalid data.\n\(message)"
        }
    }
}

struct BackendLocation: Sendable {
    let pythonURL: URL
    let pythonPath: URL
    let workingDirectory: URL
}

struct CommandResult: Sendable {
    let stdout: Data
    let stderr: String
}

struct CleanupBackend: Sendable {
    let location: BackendLocation

    init(location: BackendLocation? = nil) throws {
        self.location = try location ?? BackendLocator.locate()
    }

    func scan() async throws -> ScanReport {
        let result = try await run(arguments: [
            "scan",
            "--json",
            "--no-node-modules",
            "--no-project-derived-data",
        ])
        return try decode(ScanReport.self, from: result.stdout)
    }

    func clean(flags: [String]) async throws -> CleanReport {
        guard !flags.isEmpty else {
            return CleanReport(totalBytes: 0, total: "0 B", count: 0, items: [])
        }
        let result = try await run(arguments: ["clean"] + flags + ["--json"])
        return try decode(CleanReport.self, from: result.stdout)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "No readable output"
            throw BackendError.invalidOutput("\(error.localizedDescription)\n\(raw)")
        }
    }

    static func pythonEnvironment(
        base: [String: String],
        pythonPath: URL
    ) -> [String: String] {
        var environment = base
        for key in environment.keys where key.hasPrefix("PYTHON") {
            environment.removeValue(forKey: key)
        }
        environment["PYTHONPATH"] = pythonPath.path
        environment["PYTHONNOUSERSITE"] = "1"
        environment["PYTHONDONTWRITEBYTECODE"] = "1"
        environment["PYTHONUNBUFFERED"] = "1"
        return environment
    }

    private func run(arguments: [String]) async throws -> CommandResult {
        let location = location
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = location.pythonURL
            process.arguments = ["-m", "mac_dev_clean"] + arguments
            process.currentDirectoryURL = location.workingDirectory
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            process.environment = Self.pythonEnvironment(
                base: ProcessInfo.processInfo.environment,
                pythonPath: location.pythonPath
            )

            try process.run()
            process.waitUntilExit()
            let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw BackendError.commandFailed(process.terminationStatus, stderr)
            }
            return CommandResult(stdout: stdout, stderr: stderr)
        }.value
    }
}

enum BackendLocator {
    static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> BackendLocation {
        let fileManager = FileManager.default
        let pythonCandidates = [
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
        ]
        guard let pythonPath = pythonCandidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            throw BackendError.pythonNotFound
        }

        if let resources = Bundle.main.resourceURL {
            let bundledPython = resources.appendingPathComponent("python", isDirectory: true)
            if fileManager.fileExists(atPath: bundledPython.appendingPathComponent("mac_dev_clean/__main__.py").path) {
                return BackendLocation(
                    pythonURL: URL(fileURLWithPath: pythonPath),
                    pythonPath: bundledPython,
                    workingDirectory: resources
                )
            }
        }

        var roots: [URL] = []
        if let configured = environment["MAC_DEV_CLEAN_REPO"], !configured.isEmpty {
            roots.append(URL(fileURLWithPath: configured, isDirectory: true))
        }
        roots.append(URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true))

        for root in roots {
            let source = root.appendingPathComponent("src", isDirectory: true)
            if fileManager.fileExists(atPath: source.appendingPathComponent("mac_dev_clean/__main__.py").path) {
                return BackendLocation(
                    pythonURL: URL(fileURLWithPath: pythonPath),
                    pythonPath: source,
                    workingDirectory: root
                )
            }
        }

        throw BackendError.sourceNotFound
    }
}
