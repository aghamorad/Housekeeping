// Housekeeping — The housekeeper's weights
//
// The model is deliberately not inside the .app. Bundling it would add ~400 MB to
// each of the three release zips — around 1.2 GB re-uploaded on every release — and
// would re-download the weights on every update. Fetching it once into Application
// Support turns that into a single download, which is also the direction that is
// fast from here.
//
// The download resumes. A filtered connection that drops at 90% otherwise costs the
// whole 400 MB again, and a transfer that can never finish is the same as one that
// never started.

import Foundation
import Combine

@MainActor
final class HousekeeperWeights: ObservableObject {

    enum State: Equatable {
        case missing
        case downloading(written: Int64, expected: Int64)
        case ready(URL)
        case failed(String)

        var isReady: Bool {
            if case .ready = self { return true } else { return false }
        }

        var isLoading: Bool {
            if case .downloading = self { return true } else { return false }
        }
    }

    static let shared = HousekeeperWeights()

    /// Qwen3 0.6B at Q4_K_M. Apache 2.0, so redistribution stays clean and this is
    /// the kind of asset that can be re-hosted if the mirror ever moves.
    static let fileName = "Qwen3-0.6B-Q4_K_M.gguf"
    /// Only used before the server has said how big the file is, so the offer can
    /// name a figure rather than showing a bar with no end.
    static let approximateSize: Int64 = 396_705_472
    static let source = URL(
        string: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf"
    )!

    @Published private(set) var state: State = .missing
    /// How much of a part-finished download is already on disk, so the offer can
    /// say "carry on" rather than "start again" after the app has been quit.
    @Published private(set) var partialBytes: Int64 = 0

    private var session: URLSession?
    private var writer: ChunkWriter?

    private var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Housekeeping/Models", isDirectory: true)
    }

    private var partialURL: URL { directory.appendingPathComponent(Self.fileName + ".partial") }
    private var installedURL: URL { directory.appendingPathComponent(Self.fileName) }

    private init() {
        refresh()
    }

    /// What the disk already has. Never touches the network, so it is safe to call
    /// at launch and on every appearance of the housekeeper.
    func refresh() {
        if FileManager.default.fileExists(atPath: installedURL.path) {
            state = .ready(installedURL)
            partialBytes = 0
        } else {
            state = .missing
            partialBytes = Self.size(of: partialURL) ?? 0
        }
    }

    func download() {
        if state.isReady || state.isLoading { return }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            state = .failed("Housekeeping could not make a folder to download into: \(error.localizedDescription)")
            return
        }

        // A zero-byte .partial is left behind by an interrupted first attempt, and
        // resuming from it would ask the server for the whole file anyway. Starting
        // clean keeps the two cases from looking different.
        if let existing = Self.size(of: partialURL), existing == 0 {
            try? FileManager.default.removeItem(at: partialURL)
        }

        let already = Self.size(of: partialURL) ?? 0
        if !FileManager.default.fileExists(atPath: partialURL.path) {
            FileManager.default.createFile(atPath: partialURL.path, contents: nil)
        }

        guard let handle = try? FileHandle(forWritingTo: partialURL) else {
            state = .failed("Housekeeping could not open a file to write the download into.")
            return
        }
        if already > 0 { _ = try? handle.seekToEnd() }

        var request = URLRequest(url: Self.source)
        request.timeoutInterval = 30
        if already > 0 {
            request.setValue("bytes=\(already)-", forHTTPHeaderField: "Range")
        }

        let writer = ChunkWriter(handle: handle, startingAt: already, requestedRange: already > 0)
        writer.onRestart = { [weak self] in
            self?.partialBytes = 0
        }
        writer.onProgress = { [weak self] written, expected in
            guard let self else { return }
            self.partialBytes = written
            self.state = .downloading(
                written: written,
                expected: expected > 0 ? expected : Self.approximateSize
            )
        }
        writer.onFinish = { [weak self] error in
            self?.finish(error: error)
        }

        self.writer = writer
        partialBytes = already
        state = .downloading(written: already, expected: Self.approximateSize)

        let session = URLSession(configuration: .ephemeral, delegate: writer, delegateQueue: nil)
        self.session = session
        session.dataTask(with: request).resume()
    }

    func cancel() {
        session?.invalidateAndCancel()
        session = nil
        writer?.closeHandle()
        writer = nil
        partialBytes = Self.size(of: partialURL) ?? 0
        state = .missing
    }

    func removeInstalled() {
        try? FileManager.default.removeItem(at: installedURL)
        try? FileManager.default.removeItem(at: partialURL)
        state = .missing
        partialBytes = 0
    }

    private func finish(error: Error?) {
        let expected = writer?.expected ?? 0
        writer?.closeHandle()
        writer = nil
        session?.finishTasksAndInvalidate()
        session = nil

        if let error {
            partialBytes = Self.size(of: partialURL) ?? 0
            state = .failed(Self.describe(error))
            return
        }

        // A part-finished file is never installed under the real name. The runtime
        // trusts the path it is handed, and a truncated GGUF fails in a way that
        // looks like a broken model rather than a broken download.
        let written = Self.size(of: partialURL) ?? 0
        guard expected > 0, written == expected else {
            partialBytes = written
            state = .failed("The download stopped before it finished. What arrived has been kept, so pressing Continue picks up from there.")
            return
        }

        do {
            if FileManager.default.fileExists(atPath: installedURL.path) {
                try FileManager.default.removeItem(at: installedURL)
            }
            try FileManager.default.moveItem(at: partialURL, to: installedURL)
            partialBytes = 0
            state = .ready(installedURL)
        } catch {
            state = .failed("The download finished but Housekeeping could not put it in place: \(error.localizedDescription)")
        }
    }

    private static func describe(_ error: Error) -> String {
        guard let urlError = error as? URLError else { return error.localizedDescription }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "The connection dropped. What arrived has been kept, so Continue picks up from where it stopped."
        case .timedOut:
            return "The download timed out. What arrived has been kept, so Continue picks up from where it stopped."
        case .cancelled:
            return "The download was stopped."
        default:
            return "The download failed: \(urlError.localizedDescription)"
        }
    }

    private static func size(of url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let number = attributes[.size] as? NSNumber else { return nil }
        return number.int64Value
    }
}

/// Writes the bytes as they arrive and keeps the count.
///
/// URLSession hands data to its own queue, and there is no reason to hop every chunk
/// onto the main actor just to add up its length — only this queue touches the file
/// handle, so nothing here needs a lock. Progress is reported on a timer rather than
/// per chunk so a fast link cannot flood the main actor with view updates.
private final class ChunkWriter: NSObject, URLSessionDataDelegate, @unchecked Sendable {

    var onProgress: (@MainActor (Int64, Int64) -> Void)?
    var onRestart: (@MainActor () -> Void)?
    var onFinish: (@MainActor (Error?) -> Void)?

    /// The size of the whole file, as the server reports it. Zero until the first
    /// response arrives.
    private(set) var expected: Int64 = 0

    private let handle: FileHandle
    private let requestedRange: Bool
    private var written: Int64
    private var lastReport = Date.distantPast
    private var isFinished = false

    init(handle: FileHandle, startingAt: Int64, requestedRange: Bool) {
        self.handle = handle
        self.written = startingAt
        self.requestedRange = requestedRange
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse {
            if requestedRange && http.statusCode == 200 {
                // The server ignored the Range header — Hugging Face redirects to a
                // CDN, and a redirect does not always carry custom headers. Appending
                // now would splice a second copy of the file onto the first, so start
                // over from nothing instead of installing two copies' worth of bytes.
                try? handle.truncate(atOffset: 0)
                try? handle.seek(toOffset: 0)
                written = 0
                if let onRestart { Task { @MainActor in onRestart() } }
            }
            expected = Self.total(from: http, fallback: response.expectedContentLength)
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        try? handle.write(contentsOf: data)
        written += Int64(data.count)

        let now = Date()
        guard now.timeIntervalSince(lastReport) > 0.1 else { return }
        lastReport = now
        let sent = written
        let total = expected
        if let onProgress { Task { @MainActor in onProgress(sent, total) } }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !isFinished else { return }
        isFinished = true
        if let onFinish { Task { @MainActor in onFinish(error) } }
    }

    func closeHandle() {
        try? handle.close()
    }

    /// A 206 answers with `Content-Range: bytes 100-999/1000`, and the number after
    /// the slash is the size of the whole thing — which is what a progress bar
    /// wants, since the reader is not resuming in their head.
    private static func total(from response: HTTPURLResponse, fallback: Int64) -> Int64 {
        if let range = response.value(forHTTPHeaderField: "Content-Range"),
           let tail = range.split(separator: "/").last,
           let total = Int64(tail) {
            return total
        }
        return fallback > 0 ? fallback : 0
    }
}
