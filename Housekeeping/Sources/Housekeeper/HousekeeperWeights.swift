// Housekeeping — The housekeeper's weights
//
// Model weights are downloaded separately, so app updates do not repeatedly
// transfer gigabytes. Previous weights are retained on disk for rollback, but
// the inadequate 0.6B model is not silently used for chat.

import Foundation
import Combine
import CryptoKit

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

    static let legacyFileName = "Qwen3-0.6B-Q4_K_M.gguf"
    @Published private(set) var selection: HousekeeperModel
    private let defaults: UserDefaults
    private let storageDirectory: URL

    @Published private(set) var state: State = .missing
    @Published private(set) var isVerifying = false
    private var verificationTask: Task<String?, Never>?
    private var transferID = UUID()
    /// How much of a part-finished download is already on disk, so the offer can
    /// say "carry on" rather than "start again" after the app has been quit.
    @Published private(set) var partialBytes: Int64 = 0

    private var session: URLSession?
    private var writer: ChunkWriter?

    private var directory: URL { storageDirectory }
    private var partialURL: URL { directory.appendingPathComponent(selection.download!.fileName + ".partial") }
    private var installedURL: URL { directory.appendingPathComponent(selection.download!.fileName) }

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selection = HousekeeperModel.savedChoice(defaults.string(forKey: HousekeeperModel.preferenceKey))
        storageDirectory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Housekeeping/Models", isDirectory: true)
        refresh()
    }

    var activeModelName: String {
        selection == .none ? "Chat is off" : selection.title
    }

    struct StoredFile: Identifiable {
        let url: URL
        let bytes: Int64
        var id: String { url.path }
        var sizeLabel: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    }

    var storedFiles: [StoredFile] {
        let names = HousekeeperModel.allCases.compactMap { $0.download?.fileName }
        return (names + names.map { $0 + ".partial" } + [Self.legacyFileName]).compactMap { name in
            let url = directory.appendingPathComponent(name)
            guard let bytes = Self.size(of: url) else { return nil }
            return StoredFile(url: url, bytes: bytes)
        }
    }
    var storedBytes: Int64 { storedFiles.reduce(0) { $0 + $1.bytes } }

    func select(_ model: HousekeeperModel) {
        guard model != selection else { return }
        cancel()
        selection = model
        defaults.set(model.rawValue, forKey: HousekeeperModel.preferenceKey)
        refresh()
    }

    /// Only exact managed model files are eligible. Never removes another app's
    /// model directory or Apple's system-managed Foundation Model.
    func removeDownloads(_ files: [URL]) throws {
        let allowed = Set(storedFiles.map(\.url))
        guard files.allSatisfy(allowed.contains) else {
            throw NSError(domain: "HousekeepingModels", code: 1, userInfo: [NSLocalizedDescriptionKey: "The removal included a file outside Housekeeping's managed downloads."])
        }
        cancel()
        for file in files { try FileManager.default.removeItem(at: file) }
        refresh()
    }

    /// What the disk already has. Never touches the network, so it is safe to call
    /// at launch and on every appearance of the housekeeper.
    func refresh() {
        guard let asset = selection.download else {
            state = .missing
            partialBytes = 0
            return
        }
        if Self.size(of: installedURL) == asset.bytes {
            state = .ready(installedURL)
            partialBytes = 0
        } else {
            state = .missing
            partialBytes = Self.size(of: partialURL) ?? 0
        }
    }

    func download() {
        guard let asset = selection.download, !state.isReady, !state.isLoading else { return }
        transferID = UUID()
        let id = transferID

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

        var request = URLRequest(url: asset.source)
        request.timeoutInterval = 30
        if already > 0 {
            request.setValue("bytes=\(already)-", forHTTPHeaderField: "Range")
        }

        let writer = ChunkWriter(handle: handle, startingAt: already, requestedRange: already > 0)
        writer.onRestart = { [weak self] in
            guard self?.transferID == id else { return }
            self?.partialBytes = 0
        }
        writer.onProgress = { [weak self] written, expected in
            guard let self, self.transferID == id else { return }
            self.partialBytes = written
            self.state = .downloading(
                written: written,
                expected: expected > 0 ? expected : asset.bytes
            )
        }
        writer.onFinish = { [weak self] error in
            guard self?.transferID == id else { return }
            self?.finish(error: error)
        }

        self.writer = writer
        partialBytes = already
        state = .downloading(written: already, expected: asset.bytes)

        let session = URLSession(configuration: .ephemeral, delegate: writer, delegateQueue: nil)
        self.session = session
        session.dataTask(with: request).resume()
    }

    func cancel() {
        transferID = UUID()
        verificationTask?.cancel()
        verificationTask = nil
        isVerifying = false
        session?.invalidateAndCancel()
        session = nil
        writer?.closeHandle()
        writer = nil
        partialBytes = selection.download == nil ? 0 : (Self.size(of: partialURL) ?? 0)
        state = .missing
    }

    func removeInstalled() {
        guard selection.download != nil else { return }
        cancel()
        try? FileManager.default.removeItem(at: installedURL)
        try? FileManager.default.removeItem(at: partialURL)
        state = .missing
        partialBytes = 0
    }

    private func finish(error: Error?) {
        guard let asset = selection.download else { return }
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

        isVerifying = true
        let id = transferID
        let url = partialURL
        let task = Task.detached(priority: .utility) { Self.digest(url) }
        verificationTask = task
        Task { @MainActor [weak self] in
            let digest = await task.value
            guard let self, self.transferID == id else { return }
            self.isVerifying = false
            self.verificationTask = nil
            guard digest == asset.sha256 else {
                self.state = .failed("The downloaded model did not match its published SHA-256 checksum. Use Start Over to fetch a fresh copy.")
                return
            }
            do {
                if FileManager.default.fileExists(atPath: self.installedURL.path) {
                    try FileManager.default.removeItem(at: self.installedURL)
                }
                try FileManager.default.moveItem(at: self.partialURL, to: self.installedURL)
                self.partialBytes = 0
                self.state = .ready(self.installedURL)
            } catch {
                self.state = .failed("The verified model could not be put in place: \(error.localizedDescription)")
            }
        }
    }

    nonisolated private static func digest(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hash = SHA256()
        while !Task.isCancelled {
            guard let bytes = try? handle.read(upToCount: 8 * 1_024 * 1_024) else { return nil }
            if bytes.isEmpty { return hash.finalize().map { String(format: "%02x", $0) }.joined() }
            hash.update(data: bytes)
        }
        return nil
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
