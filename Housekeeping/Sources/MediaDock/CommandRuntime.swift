import Foundation

enum RuntimeEnvironment {
    static var searchPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let standard = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "\(home)/.local/bin",
            "\(home)/Library/Python/3.13/bin",
            "\(home)/Library/Python/3.12/bin",
            "\(home)/Library/Python/3.11/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let inherited = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        return Array(NSOrderedSet(array: standard + inherited)) as? [String] ?? standard + inherited
    }

    static var processEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPaths.joined(separator: ":")
        environment["PYTHONUNBUFFERED"] = "1"
        environment["NO_COLOR"] = "1"
        return environment
    }

    static func locate(_ executable: String) -> String? {
        for directory in searchPaths {
            let path = (directory as NSString).appendingPathComponent(executable)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}

private struct ShortCommandResult {
    let status: Int32
    let output: String
}

private func runShortCommand(_ executable: String, _ arguments: [String]) -> ShortCommandResult {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = RuntimeEnvironment.processEnvironment
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        let deadline = Date().addingTimeInterval(8)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
            return ShortCommandResult(status: -2, output: "Version check timed out after 8 seconds")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return ShortCommandResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    } catch {
        return ShortCommandResult(status: -1, output: error.localizedDescription)
    }
}

enum DependencyScanner {
    static func scan() async -> [DependencyStatus] {
        await Task.detached(priority: .utility) {
            let brewPath = RuntimeEnvironment.locate("brew")
            let pipxPath = RuntimeEnvironment.locate("pipx")
            let pipxListing = pipxPath.map { runShortCommand($0, ["list", "--short"]).output.lowercased() } ?? ""

            return DependencyID.allCases.map { dependency in
                let path = RuntimeEnvironment.locate(dependency.commandName)
                let version: String?
                if let path {
                    do {
                        var versionArguments = dependency.versionArguments
                        if dependency == .gamdl {
                            versionArguments = try GamdlTempDirectory.arguments(preparingDirectory: true) + versionArguments
                        }
                        let result = runShortCommand(path, versionArguments)
                        version = result.output
                            .split(whereSeparator: \.isNewline)
                            .first
                            .map(String.init)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    } catch {
                        version = error.localizedDescription
                    }
                } else {
                    version = nil
                }

                let manager: InstallManager
                if dependency == .homebrew, path != nil {
                    manager = .homebrew
                } else if let formula = dependency.brewFormula, let brewPath, path != nil {
                    let result = runShortCommand(brewPath, ["list", "--versions", formula])
                    manager = (result.status == 0 && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? .homebrew : .external
                } else if let package = dependency.pipxPackage, path != nil {
                    let packagePattern = "(?m)^package\\s+\(package)\\b"
                    manager = pipxListing.range(of: packagePattern, options: .regularExpression) != nil ? .pipx : .external
                } else if path != nil {
                    manager = .external
                } else {
                    manager = .unknown
                }

                return DependencyStatus(id: dependency, path: path, version: version, manager: manager)
            }
        }.value
    }
}

@MainActor
final class CommandRunner: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var progress: Double?
    @Published private(set) var currentItem = "Idle"
    @Published private(set) var activeCommand = "No command is running."
    @Published private(set) var entries: [LogEntry] = []
    @Published private(set) var lastExitCode: Int32?

    var onBatchFinished: ((Bool) -> Void)?

    private var queue: [CommandSpec] = []
    private var process: Process?
    private var outputBuffer = ""
    private var cancelled = false

    func run(_ commands: [CommandSpec]) {
        guard !isRunning, !commands.isEmpty else { return }
        queue = commands
        cancelled = false
        lastExitCode = nil
        progress = nil
        isRunning = true
        append("Starting \(commands.count == 1 ? "command" : "a \(commands.count)-command batch").", kind: .info)
        runNext()
    }

    func stop() {
        guard isRunning, let process else { return }
        cancelled = true
        append("Stop requested. Sending an interrupt so the tool can clean up its partial work.", kind: .error)
        process.interrupt()
    }

    func clear() {
        guard !isRunning else { return }
        entries.removeAll()
        progress = nil
        currentItem = "Idle"
        activeCommand = "No command is running."
        lastExitCode = nil
    }

    var plainTextLog: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return entries.map { "[\(formatter.string(from: $0.date))] \($0.text)" }.joined(separator: "\n")
    }

    private func runNext() {
        guard !queue.isEmpty else {
            completeBatch(success: !cancelled)
            return
        }

        let command = queue.removeFirst()
        activeCommand = command.displayCommand
        currentItem = command.name
        progress = nil
        append("$ \(command.displayCommand)", kind: .command)
        append(command.explanation, kind: .info)

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.environment = RuntimeEnvironment.processEnvironment
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        self.process = process
        outputBuffer = ""

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let chunk = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.consume(chunk) }
        }

        process.terminationHandler = { [weak self] finished in
            pipe.fileHandleForReading.readabilityHandler = nil
            let trailingData = pipe.fileHandleForReading.readDataToEndOfFile()
            let trailing = String(decoding: trailingData, as: UTF8.self)
            DispatchQueue.main.async {
                self?.consume(trailing, flush: true)
                self?.commandFinished(status: finished.terminationStatus)
            }
        }

        do {
            try process.run()
        } catch {
            append("Could not launch command: \(error.localizedDescription)", kind: .error)
            commandFinished(status: -1)
        }
    }

    private func consume(_ chunk: String, flush: Bool = false) {
        outputBuffer += chunk.replacingOccurrences(of: "\r", with: "\n")
        var parts = outputBuffer.components(separatedBy: "\n")
        outputBuffer = flush ? "" : (parts.popLast() ?? "")
        if flush, !outputBuffer.isEmpty {
            parts.append(outputBuffer)
            outputBuffer = ""
        }
        for line in parts {
            let cleaned = stripANSI(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { continue }
            append(cleaned, kind: lineLooksLikeError(cleaned) ? .error : .output)
            updateProgress(from: cleaned)
        }
    }

    private func updateProgress(from line: String) {
        let percentPattern = #"(?<!\d)(\d{1,3}(?:\.\d+)?)%"#
        if let range = line.range(of: percentPattern, options: .regularExpression) {
            let token = String(line[range]).dropLast()
            if let value = Double(token), value >= 0, value <= 100 {
                progress = value / 100
            }
        }

        let meaningfulPrefixes = ["[download] Downloading", "Downloaded", "Found", "Processing", "Searching", "Track", "Song", "Album"]
        if meaningfulPrefixes.contains(where: { line.localizedCaseInsensitiveContains($0) }) {
            currentItem = String(line.prefix(180))
        }
    }

    private func commandFinished(status: Int32) {
        process = nil
        lastExitCode = status
        if status == 0 && !cancelled {
            append("Command finished successfully.", kind: .success)
            runNext()
        } else {
            let message = cancelled ? "Command stopped by the user." : "Command exited with status \(status). The remaining batch was not run."
            append(message, kind: .error)
            completeBatch(success: false)
        }
    }

    private func completeBatch(success: Bool) {
        queue.removeAll()
        isRunning = false
        progress = success ? 1 : progress
        currentItem = success ? "Finished" : (cancelled ? "Stopped" : "Needs attention")
        append(success ? "All requested work is complete." : "Work ended before completion.", kind: success ? .success : .error)
        onBatchFinished?(success)
    }

    private func append(_ text: String, kind: LogKind) {
        entries.append(LogEntry(date: Date(), text: text, kind: kind))
        if entries.count > 5_000 { entries.removeFirst(entries.count - 5_000) }
    }

    private func stripANSI(_ value: String) -> String {
        value.replacingOccurrences(of: #"\u{001B}\[[0-?]*[ -/]*[@-~]"#, with: "", options: .regularExpression)
    }

    private func lineLooksLikeError(_ line: String) -> Bool {
        let lower = line.lowercased()
        return lower.contains("error") || lower.contains("failed") || lower.contains("traceback") || lower.contains("timed out")
    }
}
