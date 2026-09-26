import Foundation

/// Housekeeping has never run another program before this feature. It has read
/// files, measured them, and moved them, and that was the whole of it. Updating
/// software cannot be done that way: `brew`, `hdiutil`, `codesign`, and `xattr`
/// are programs, and the app has to be able to run one, wait for it, and hear
/// what it said.
///
/// So this is deliberately the smallest thing that will do. It runs one
/// executable with one argument list, captures the two output streams separately
/// because `codesign` writes its answer to the error stream and a helper that
/// merged them would hand back an empty result, and enforces a deadline so a
/// program that hangs cannot hang the app.
///
/// `Foundation.Process` is not safe to touch from more than one thread at once.
/// Every access below therefore goes through the lock, and the pipe reads are
/// handed to their own queues: a program that writes more than a pipe buffer
/// holds — and `brew outdated` across a few hundred packages does — would
/// deadlock a reader that waited for the process to exit before draining it.
final class ProcessRunner: @unchecked Sendable {
    struct Result {
        let status: Int32
        let stdout: String
        let stderr: String
        /// True when the deadline passed and the program was stopped. Distinct
        /// from a non-zero status, because a program killed for running long did
        /// not answer, and a caller that reported its empty output as an answer
        /// would be inventing one.
        let timedOut: Bool

        var succeeded: Bool { status == 0 && !timedOut }
    }

    enum Failure: Error, LocalizedError {
        case launchFailed(executable: String, reason: String)

        var errorDescription: String? {
            switch self {
            case .launchFailed(let executable, let reason):
                return "Housekeeping could not run \(executable): \(reason)"
            }
        }
    }

    /// Where Homebrew installed itself. A windowed application launched from the
    /// Finder inherits the login environment only loosely and never sources a
    /// shell profile, so `brew` is generally not on its `PATH` even when the
    /// reader uses it all day. The two prefixes below are where the installer puts
    /// it on Apple silicon and on Intel; the `PATH` search is the last resort for
    /// anyone who moved it.
    static func brewPath(fileManager: FileManager = .default) -> String? {
        let fixed = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        for candidate in fixed where fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
        let searchPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        for directory in searchPath.split(separator: ":") {
            let candidate = "\(directory)/brew"
            if fileManager.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// Whether a program exists at a path, for the runtime checks the App Store
    /// channel needs. `mas` is not installed on every Mac, and the channel that
    /// depends on it has to ask rather than assume.
    static func isExecutable(_ path: String, fileManager: FileManager = .default) -> Bool {
        fileManager.isExecutableFile(atPath: path)
    }

    private let lock = NSLock()
    private var activeProcess: Process?
    private var cancelled = false

    /// Runs a program to completion and returns what it said. Cancelling the
    /// surrounding task stops the program; that path is what keeps a Stop press
    /// from leaving `brew` half-done in the background.
    func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        timeout: TimeInterval = 60
    ) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        // A program that decides to read from the terminal would otherwise block
        // on a terminal that is not there. `brew` and the rest do not, but the
        // cost of being wrong is a hang, so the hole is closed.
        process.standardInput = FileHandle.nullDevice

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                launch(
                    process,
                    stdout: outPipe,
                    stderr: errPipe,
                    timeout: timeout,
                    continuation: continuation
                )
            }
        } onCancel: {
            self.cancel()
        }
    }

    /// Stops whatever is running. Safe to call when nothing is; the flag it sets
    /// is read again at launch, so a cancellation that arrives before the program
    /// starts is honoured rather than lost.
    func cancel() {
        lock.lock()
        cancelled = true
        let running = activeProcess
        lock.unlock()
        running?.terminate()
    }

    // MARK: - The mechanics

    private func launch(
        _ process: Process,
        stdout: Pipe,
        stderr: Pipe,
        timeout: TimeInterval,
        continuation: CheckedContinuation<Result, Error>
    ) {
        lock.lock()
        if cancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        activeProcess = process
        lock.unlock()

        let completion = OnceCompletion(continuation)
        let capture = OutputCapture()
        let group = DispatchGroup()

        // Both streams are drained on their own queues and joined only once the
        // program has exited, so a large report cannot wedge the process writing
        // to a full pipe while this side waits for it to exit.
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            capture.stdout = stdout.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            capture.stderr = stderr.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let deadline = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let running = self.activeProcess
            self.lock.unlock()
            guard let running, running.isRunning else { return }
            capture.timedOut = true
            running.terminate()
            // A program that ignores the polite signal gets the impolite one, so a
            // deadline is a deadline and not a suggestion.
            let identifier = running.processIdentifier
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                if running.isRunning { kill(identifier, SIGKILL) }
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)

        group.enter()
        process.terminationHandler = { _ in group.leave() }

        do {
            try process.run()
        } catch {
            deadline.cancel()
            lock.lock()
            activeProcess = nil
            lock.unlock()
            // The write ends are held by this side; closing them releases the
            // readers that would otherwise wait forever for an end that never comes.
            try? stdout.fileHandleForWriting.close()
            try? stderr.fileHandleForWriting.close()
            continuation.resume(
                throwing: Failure.launchFailed(
                    executable: process.executableURL?.path ?? "the program",
                    reason: error.localizedDescription
                )
            )
            return
        }

        group.notify(queue: .global(qos: .utility)) { [weak self] in
            deadline.cancel()
            self?.lock.lock()
            self?.activeProcess = nil
            self?.lock.unlock()
            completion.finish(.success(Result(
                status: process.terminationStatus,
                stdout: capture.stdoutText,
                stderr: capture.stderrText,
                timedOut: capture.timedOut
            )))
        }
    }
}

/// Holds the two output streams and the timeout flag while the reader queues and
/// the completion queue hand them to one another. Locked for the same reason
/// everything here is: two threads touch it and neither may see a half-written
/// value.
private final class OutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stdoutData = Data()
    private var stderrData = Data()
    private var didTimeOut = false

    var stdout: Data {
        get { lock.lock(); defer { lock.unlock() }; return stdoutData }
        set { lock.lock(); stdoutData = newValue; lock.unlock() }
    }

    var stderr: Data {
        get { lock.lock(); defer { lock.unlock() }; return stderrData }
        set { lock.lock(); stderrData = newValue; lock.unlock() }
    }

    var timedOut: Bool {
        get { lock.lock(); defer { lock.unlock() }; return didTimeOut }
        set { lock.lock(); didTimeOut = newValue; lock.unlock() }
    }

    /// Lossy on purpose. A program that emits a byte that is not valid UTF-8
    /// should have its output reported with that byte replaced, not thrown away.
    var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

/// Resumes a continuation at most once. The launch path, the timeout path, and
/// the normal completion can between them try to finish twice, and resuming a
/// continuation twice is a crash rather than an error.
private final class OnceCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProcessRunner.Result, Error>?

    init(_ continuation: CheckedContinuation<ProcessRunner.Result, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Swift.Result<ProcessRunner.Result, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(with: result)
    }
}
