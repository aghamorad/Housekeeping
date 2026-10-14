import Foundation

struct RouteProcessOutput: Sendable {
    var stdout: String
    var stderr: String
    var exitCode: Int32
    var timedOut: Bool

    var combined: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// First meaningful line — provider CLIs are chatty and the useful
    /// part is nearly always the first line that is not a log record.
    var firstMeaningfulLine: String {
        for raw in combined.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("{") { continue }
            return line
        }
        return combined.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum RouteProcessError: Error, LocalizedError {
    case launchFailed(String)
    case timedOut(Double)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let m): return m
        case .timedOut(let s): return "Timed out after \(Int(s))s"
        }
    }
}

/// Runs short-lived CLI helpers and waits for them, with a hard timeout.
///
/// The provider CLIs are all "fire a command, read the answer" tools. They
/// are captured whole rather than streamed because their output is small and
/// parsing is easier against a complete buffer.
enum RouteProcess {

    /// PATH the child sees. A GUI app launched from Finder inherits almost
    /// nothing, so the usual install locations are prepended explicitly —
    /// otherwise `expressvpnctl` (in /usr/local/bin) is invisible.
    static let augmentedPATH: String = {
        let extras = [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? ""
        return (extras + inherited.split(separator: ":").map(String.init))
            .reduce(into: [String]()) { acc, p in
                if !acc.contains(p) { acc.append(p) }
            }
            .joined(separator: ":")
    }()

    private static func makeEnvironment(_ extra: [String: String]?) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = augmentedPATH
        // Keep provider CLIs from trying to page or colourise their output.
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        if let extra {
            for (k, v) in extra { env[k] = v }
        }
        return env
    }

    static func run(
        _ launchPath: String,
        _ arguments: [String] = [],
        timeout: Double = 30,
        environment: [String: String]? = nil
    ) async throws -> RouteProcessOutput {
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: launchPath)
                    process.arguments = arguments
                    process.environment = makeEnvironment(environment)

                    let outPipe = Pipe()
                    let errPipe = Pipe()
                    process.standardOutput = outPipe
                    process.standardError = errPipe
                    process.standardInput = FileHandle.nullDevice

                    // Read on background queues. A Pipe buffer is ~64 KB and a
                    // provider that prints more than that while we are still
                    // waiting for exit would deadlock the whole run.
                    let group = DispatchGroup()
                    var outData = Data()
                    var errData = Data()
                    let lock = NSLock()

                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        let d = outPipe.fileHandleForReading.readDataToEndOfFile()
                        lock.lock(); outData = d; lock.unlock()
                        group.leave()
                    }
                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        let d = errPipe.fileHandleForReading.readDataToEndOfFile()
                        lock.lock(); errData = d; lock.unlock()
                        group.leave()
                    }

                    do {
                        try process.run()
                    } catch {
                        outPipe.fileHandleForReading.closeFile()
                        errPipe.fileHandleForReading.closeFile()
                        continuation.resume(throwing: RouteProcessError.launchFailed(error.localizedDescription))
                        return
                    }

                    let deadline = Date().addingTimeInterval(timeout)
                    var timedOut = false
                    while process.isRunning {
                        if Date() >= deadline {
                            timedOut = true
                            process.terminate()
                            // Give it a moment to die politely, then insist.
                            Thread.sleep(forTimeInterval: 0.4)
                            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                            break
                        }
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                    process.waitUntilExit()
                    group.wait()

                    lock.lock()
                    let out = outData
                    let err = errData
                    lock.unlock()

                    let result = RouteProcessOutput(
                        stdout: String(decoding: out, as: UTF8.self),
                        stderr: String(decoding: err, as: UTF8.self),
                        exitCode: process.terminationStatus,
                        timedOut: timedOut
                    )
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            // The polling loop above notices nothing about Task cancellation,
            // so cancellation is handled by the caller's own deadline; this
            // exists only so the cancellation handler is well-formed.
        }
    }

    /// Resolve a bare command name against the augmented PATH.
    static func which(_ name: String) -> String? {
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        for dir in augmentedPATH.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
