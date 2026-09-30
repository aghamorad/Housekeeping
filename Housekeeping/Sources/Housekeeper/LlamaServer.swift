// Housekeeping — The housekeeper's runtime
//
// `ProcessRunner` is the wrong tool here, deliberately. It runs a program to
// completion and enforces a deadline, which is exactly the property a long-lived
// server must not have. This is the small supervisor that owns the other shape: one
// child process, started once, kept alive, spoken to over loopback.
//
// Running the model as a subprocess rather than linking the library is what lets
// this app stay a swiftc-only build with no third-party dependency, and it means a
// model that runs out of memory takes down a child process instead of the window.

import Foundation
import Combine
import Darwin

@MainActor
final class LlamaServer: ObservableObject {

    enum State: Equatable {
        case idle
        case starting
        case ready(port: Int)
        case failed(String)

        var port: Int? {
            if case .ready(let port) = self { return port } else { return nil }
        }
    }

    enum Failure: LocalizedError {
        case notRunning
        case unreadableAnswer

        var errorDescription: String? {
            switch self {
            case .notRunning: return "The housekeeper is not running yet."
            case .unreadableAnswer: return "The housekeeper said something Housekeeping could not read. Asking again usually settles it."
            }
        }
    }

    @Published private(set) var state: State = .idle

    private var process: Process?
    private var logHandle: FileHandle?
    private var launching: Task<Void, Never>?
    private var isStopping = false

    /// The runtime ships inside the bundle. It links nothing but system frameworks,
    /// so there is no pile of dylibs to sign beside it.
    static var executable: URL? {
        Bundle.main.url(forResource: "llama-server", withExtension: nil)
    }

    static var isAvailable: Bool { executable != nil }

    /// Deliberately kept: when a model refuses to load, this file is the difference
    /// between a fixable bug and a mystery. It is small and it is overwritten on
    /// every start, so it never accumulates.
    var logURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Housekeeping/llama-server.log")
    }

    /// Starts the server if it is not already up. Safe to call on every appearance
    /// of the housekeeper; every call after the first does nothing.
    func start(model: URL) {
        if case .ready = state { return }
        if case .starting = state { return }

        guard let executable = Self.executable else {
            state = .failed("This copy of Housekeeping has no model runtime inside it, so the housekeeper cannot wake up. A fresh download of the app will have one.")
            return
        }
        guard FileManager.default.fileExists(atPath: model.path) else {
            state = .failed("The housekeeper's weights are not on disk yet.")
            return
        }

        state = .starting
        launching = Task { [weak self] in
            await self?.launch(executable: executable, model: model)
        }
    }

    func stop() {
        launching?.cancel()
        launching = nil
        guard let process else {
            state = .idle
            return
        }
        isStopping = true
        process.terminate()
    }

    /// Stops the server and waits for it to actually go. `terminate()` posts SIGTERM
    /// and returns, and a model that has just been asked to stop is still holding most
    /// of a gigabyte while it packs up. An app on its way out has nothing else to do
    /// with the next two seconds, so it waits rather than leaving the process — and
    /// the memory — behind with nothing left running that could reclaim it.
    func stopAndWait(timeout: TimeInterval = 3) {
        guard let process else {
            launching?.cancel()
            launching = nil
            state = .idle
            return
        }
        stop()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    /// One turn. `history` is already in OpenAI chat form, oldest first, and `system`
    /// carries the housekeeper's standing instructions.
    func complete(system: String, history: [[String: String]], maxTokens: Int = 320) async throws -> String {
        guard let port = state.port,
              let url = URL(string: "http://127.0.0.1:\(port)/v1/chat/completions") else {
            throw Failure.notRunning
        }

        let payload: [String: Any] = [
            "messages": [["role": "system", "content": system]] + history,
            "max_tokens": maxTokens,
            "temperature": 0.3,
            "top_p": 0.9,
            "stream": false,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw Failure.unreadableAnswer
        }

        let answer = Self.tidy(content)
        guard !answer.isEmpty else { throw Failure.unreadableAnswer }
        return answer
    }

    // MARK: - Launching

    private func launch(executable: URL, model: URL) async {
        let port = Self.freePort()
        guard port > 0 else {
            state = .failed("Housekeeping could not find a free port for the housekeeper to listen on.")
            return
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "-m", model.path,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--ctx-size", "4096",
            "--threads", "\(max(2, ProcessInfo.processInfo.activeProcessorCount / 2))",
            "--n-gpu-layers", "999",
            "--no-webui",
        ]

        // The log goes to a file rather than a pipe. A pipe nobody drains fills up
        // and then blocks the child mid-sentence, which looks exactly like a hang and
        // is not one.
        prepareLog()
        if let log = try? FileHandle(forWritingTo: logURL) {
            process.standardOutput = log
            process.standardError = log
            logHandle = log
        } else {
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
        }

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.childExited() }
        }

        do {
            try process.run()
        } catch {
            closeLog()
            state = .failed("The housekeeper's runtime would not start: \(error.localizedDescription)")
            return
        }

        self.process = process

        if await waitUntilAnswering(port: port) {
            state = .ready(port: port)
        } else if case .starting = state {
            state = .failed("The housekeeper's runtime started but never became ready. Its log is at \(logURL.path).")
        }
    }

    /// llama-server answers 200 on `/health` once the model is loaded, and 503 while
    /// it is still reading the file. A 0.6B takes a couple of seconds; the deadline
    /// is generous because a cold disk on an Intel Mac is not.
    private func waitUntilAnswering(port: Int) async -> Bool {
        guard let health = URL(string: "http://127.0.0.1:\(port)/health") else { return false }
        let deadline = Date().addingTimeInterval(90)

        while Date() < deadline {
            if Task.isCancelled { return false }
            if let (_, response) = try? await URLSession.shared.data(from: health),
               let http = response as? HTTPURLResponse, http.statusCode == 200 {
                return true
            }
            if process?.isRunning == false { return false }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private func childExited() {
        process = nil
        closeLog()
        if isStopping {
            isStopping = false
            state = .idle
        } else if case .ready = state {
            state = .failed("The housekeeper's runtime stopped. Closing and reopening the housekeeper will start it again.")
        }
    }

    private func closeLog() {
        try? logHandle?.close()
        logHandle = nil
    }

    private func prepareLog() {
        let manager = FileManager.default
        try? manager.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        manager.createFile(atPath: logURL.path, contents: nil)
    }

    /// Binding to port 0 and reading the port back is the only way to ask macOS for
    /// a port that is free right now. There is a gap between closing that socket and
    /// llama-server claiming it, which is why a failure to become ready is reported
    /// rather than assumed impossible.
    private static func freePort() -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return 0 }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return 0 }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard named == 0 else { return 0 }

        return Int(UInt16(bigEndian: address.sin_port))
    }

    /// Qwen3 is a reasoning model, so a ` thinking` block can arrive ahead of the
    /// answer. Someone asking what a folder is does not want to read the deliberation
    /// first, so anything before the closing tag is dropped rather than shown.
    private static func tidy(_ text: String) -> String {
        var answer = text
        if let close = answer.range(of: "<｜end▁of▁thinking｜>") {
            answer = String(answer[close.upperBound...])
        }
        return answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
