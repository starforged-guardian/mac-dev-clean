import Foundation

enum BackendError: LocalizedError {
    case sourceNotFound
    case pythonNotFound
    case commandFailed(operation: String, code: Int32, details: String)
    case invalidOutput(String)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound:
            return "Could not find the bundled mac-dev-clean Python engine."
        case .pythonNotFound:
            return "Python 3 was not found. Install Xcode Command Line Tools and try again."
        case let .commandFailed(operation, code, details):
            let reason = details.isEmpty
                ? "The cleanup engine did not return a reason."
                : details
            return "The \(operation) could not finish. No additional files will be removed.\n\(reason)\n\nDiagnostic code: \(code)"
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
    let terminationStatus: Int32
}

protocol CleanupBackendProtocol: Sendable {
    func scan() async throws -> ScanReport
    func clean(flags: [String]) async throws -> CleanReport
}

struct CleanupBackend: CleanupBackendProtocol, Sendable {
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
        guard result.terminationStatus == 0 else {
            throw Self.commandFailure(operation: "scan", result: result)
        }
        return try Self.decode(ScanReport.self, from: result.stdout)
    }

    func clean(flags: [String]) async throws -> CleanReport {
        guard !flags.isEmpty else {
            return CleanReport(totalBytes: 0, total: "0 B", count: 0, items: [])
        }
        let result = try await run(arguments: ["clean"] + flags + ["--json"])
        return try Self.cleanReport(from: result)
    }

    static func cleanReport(from result: CommandResult) throws -> CleanReport {
        if result.terminationStatus == 0 {
            return try Self.decode(CleanReport.self, from: result.stdout)
        }

        // The CLI intentionally returns 1 when cleanup completed but one or more
        // locations were skipped. Its JSON is still the authoritative result and
        // contains the per-location reasons the UI needs to show.
        if result.terminationStatus == 1,
           let report = try? JSONDecoder().decode(CleanReport.self, from: result.stdout)
        {
            return report
        }

        throw Self.commandFailure(operation: "cleanup", result: result)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? "No readable output"
            throw BackendError.invalidOutput("\(error.localizedDescription)\n\(raw)")
        }
    }

    static func commandFailure(operation: String, result: CommandResult) -> BackendError {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = String(data: result.stdout, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let details = [stderr, stdout]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return .commandFailed(
            operation: operation,
            code: result.terminationStatus,
            details: String(details.prefix(4_000))
        )
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

            return CommandResult(
                stdout: stdout,
                stderr: stderr,
                terminationStatus: process.terminationStatus
            )
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
