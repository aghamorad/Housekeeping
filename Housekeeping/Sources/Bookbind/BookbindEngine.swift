// Housekeeping — Bookbind's engine
//
// Bookbind is not a second app carried inside this bundle any more: it is one
// screen here, and this file is the half of it that is not the screen. The
// engine underneath is still the Python that has always done the work — probing
// the files, merging them, writing the chapters, looking the book up, checking
// the result — and this starts that server, keeps it alive while the app runs,
// and answers the four things its page asks for that a page cannot do itself.
//
// The web view is owned here rather than by the screen for one reason: closing
// the sheet must not throw away the file list the reader has built up, or a
// merge in progress. The sheet comes and goes; the page underneath it does not.

import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKit

@MainActor
final class BookbindEngine: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case starting
        case ready
        case failed(String)
    }

    /// The engine this app made, so termination can reach it even with no window
    /// left to carry a notification to the screen.
    static private(set) weak var current: BookbindEngine?

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var url: URL?

    override init() {
        super.init()
        BookbindEngine.current = self
    }

    private var process: Process?
    private var owned = false
    private var log: FileHandle?
    private var booting = false
    private var watchdog: Timer?
    private var missedBeats = 0
    private var storedTheme: AppState.Theme = .liquidGlass

    /// Built once, on first use, and never rebuilt: this is what keeps the
    /// reader's place across a close and reopen of the sheet.
    lazy var web: WKWebView = makeWebView()

    var logPath: String { BookbindWhere.logFile }

    // MARK: - Starting

    func startIfNeeded() {
        guard !booting, phase != .ready else { return }
        booting = true
        phase = .starting
        stopWatchdog()

        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                BookbindLaunch.boot()
            }.value

            booting = false
            switch outcome {
            case .external(let url):
                // Somebody else's Bookbind is already answering; show it rather
                // than starting a second one beside it.
                self.url = url
                phase = .ready
                load(url)
                startWatchdog()
            case .owned(let process, let url, let handle):
                self.process = process
                self.owned = true
                self.log = handle
                self.url = url
                phase = .ready
                load(url)
                startWatchdog()
            case .failed(let text):
                phase = .failed(text)
            }
        }
    }

    /// Kills the server this app started. A server that was already running is
    /// somebody else's and is left alone. The engine is also handed the app's
    /// pid on launch, so a force-quit cannot leave one behind to be adopted by
    /// the next run.
    func stop() {
        stopWatchdog()
        guard owned, let process, process.isRunning else { return }
        process.terminate()
        self.process = nil
        owned = false
        // A frozen Python that is mid-encode can take a moment to answer SIGTERM.
        // Give it that moment, then take it away: a quit that waits on the engine
        // is the same bug as an engine that never starts.
        let pid = process.processIdentifier
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }

    func retry() {
        stop()
        phase = .idle
        startIfNeeded()
    }

    // MARK: - Keeping the engine honest

    /// A ready page is only useful while the server behind it is alive. The
    /// engine is a child process, and a child can die without the page noticing:
    /// the page then queues a job into a server that is no longer there and the
    /// dialog sits on "Waiting for the engine" forever. Two missed beats is long
    /// enough to tell a crash from a slow encode, because /api/health never
    /// touches the encoder.
    private func startWatchdog() {
        stopWatchdog()
        missedBeats = 0
        let timer = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let url = self.url, self.phase == .ready else { return }
                let alive = await Task.detached(priority: .utility) {
                    BookbindLaunch.health(url) != nil
                }.value
                guard self.phase == .ready, self.url == url else { return }
                if alive {
                    self.missedBeats = 0
                } else {
                    self.missedBeats += 1
                    if self.missedBeats >= 2 {
                        self.stopWatchdog()
                        self.phase = .failed("""
                        Bookbind's engine stopped answering.

                        Nothing you had queued has been lost — the page keeps \
                        its list — but the run cannot continue until the engine \
                        is back. Press Try Again.
                        """)
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func stopWatchdog() {
        watchdog?.invalidate()
        watchdog = nil
        missedBeats = 0
    }

    func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: logPath))
    }

    // MARK: - The house's appearance

    /// The page is Bookbind's own and keeps its own CSS. What Housekeeping adds
    /// is an override of the custom properties it already reads, so the merge
    /// form, the cards and the buttons land in the same maroon the rest of the
    /// app is made of without a second copy of the page.
    func applyTheme(_ theme: AppState.Theme) {
        storedTheme = theme
        applySkin(theme == .liquidGlass ? Self.glassSkin : "")
    }

    private func applySkin(_ css: String) {
        // Encoded as JSON so the CSS reaches the page as one string literal and
        // cannot be read as anything else.
        guard let data = try? JSONEncoder().encode(css),
              let literal = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("""
        (function () {
          var skin = document.getElementById('housekeeping-skin');
          if (!skin) {
            skin = document.createElement('style');
            skin.id = 'housekeeping-skin';
            document.head.appendChild(skin);
          }
          skin.textContent = \(literal);
        })();
        """, completionHandler: nil)
    }

    private static let glassSkin = """
    :root{
      color-scheme: dark;
      --bg:#280705; --card:#3A0C09; --ink:#F2E4E1; --dim:#C9A49D; --line:#7A221A;
      --accent:#CD4A3C; --ok:#6FC798; --bad:#FF6C56; --warn:#E8A84F;
      --radius:14px;
      --shadow:0 1px 2px rgba(0,0,0,.35),0 12px 30px rgba(0,0,0,.32);
    }
    body{
      background:
        radial-gradient(120% 80% at 18% 0%, rgba(144,32,24,.20), rgba(144,32,24,0) 62%),
        #280705;
      font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;
    }
    ::selection{background:rgba(205,74,60,.35)}
    """

    private func load(_ url: URL) {
        guard web.url == nil || web.url?.absoluteString != url.absoluteString else { return }
        web.load(URLRequest(url: url))
    }

    // MARK: - The web view

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "bookbind")
        // Tells the page it is in the app, so it offers Finder panels instead of
        // the fallback path box.
        config.userContentController.addUserScript(WKUserScript(
            source: "window.__bookbindNative = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true))

        let web = BookbindDropWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 760),
                                      configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        // The same two answers the standalone window gives: the veil while files
        // are held over the page, and the real paths when they land.
        web.onDrag = { [weak self] on in self?.dragHighlight(on) }
        web.onFiles = { [weak self] urls in self?.dropped(urls) }

        // Over the page and out of the way of every click: see BookbindDropCatcher.
        let catcher = BookbindDropCatcher(frame: web.bounds)
        catcher.autoresizingMask = [.width, .height]
        catcher.onDrag = { [weak self] on in self?.dragHighlight(on) }
        catcher.onFiles = { [weak self] urls in self?.dropped(urls) }
        web.addSubview(catcher)

        web.loadHTMLString("""
        <html><head><meta charset="utf-8"><style>
        body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;
             font:14px -apple-system,sans-serif;color:#6b6f76;background:#f6f6f7}
        @media(prefers-color-scheme:dark){body{background:#280705;color:#C9A49D}}
        </style></head><body>Starting Bookbind…</body></html>
        """, baseURL: nil)
        return web
    }

    // MARK: - What the page asks for

    private func reply(_ id: Int, _ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.__bookbindReply(\(id), \(json))", completionHandler: nil)
    }

    // MARK: - What a drop means

    /// Says to the page "files are over you" (or have gone again), which is what
    /// draws and clears the veil.
    private func dragHighlight(_ on: Bool) {
        web.evaluateJavaScript("window.bookbindDrag(\(on))", completionHandler: nil)
    }

    /// Hands the dropped paths to the page, which decides what each one is: a
    /// folder is a book folder, an audio file is a chapter, anything else is left
    /// alone.
    private func dropped(_ urls: [URL]) {
        let paths = urls.map { $0.path }
        guard let data = try? JSONSerialization.data(withJSONObject: paths),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.bookbindDrop(\(json))", completionHandler: nil)
    }

    private func panel() -> NSOpenPanel {
        let p = NSOpenPanel()
        p.treatsFilePackagesAsDirectories = false
        p.canCreateDirectories = false
        p.resolvesAliases = true
        return p
    }

    private func pickFolder(_ id: Int) {
        let p = panel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.prompt = "Choose"
        p.message = "Pick the folder that holds the audio files."
        attach(p) { answer in
            if answer == .OK, let u = p.url { self.reply(id, ["path": u.path]) }
            else { self.reply(id, ["cancelled": true]) }
        }
    }

    private func pickFiles(_ id: Int) {
        let p = panel()
        p.canChooseFiles = true
        p.canChooseDirectories = false
        p.allowsMultipleSelection = true
        p.allowsOtherFileTypes = true          // flac and opus are not in every type list
        p.allowedContentTypes = [.audio, .audiovisualContent]
        p.prompt = "Add"
        p.message = "Pick audio files. Hold ⌘ to add more, or ⇧ for a run of them."
        attach(p) { answer in
            if answer == .OK { self.reply(id, ["paths": p.urls.map { $0.path }]) }
            else { self.reply(id, ["cancelled": true]) }
        }
    }

    /// A sheet belongs to a window. The web view is inside the sheet when the
    /// question is asked, so its window is the right one — with the key window as
    /// the fallback for the moment before the sheet has been laid out.
    private func attach(_ p: NSOpenPanel, _ then: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = web.window ?? NSApp.keyWindow {
            p.beginSheetModal(for: window, completionHandler: then)
        } else {
            then(p.runModal())
        }
    }

    private func reveal(_ id: Int, _ path: String?) {
        guard let path, FileManager.default.fileExists(atPath: path) else {
            reply(id, ["error": "that is not there any more"]); return
        }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        let u = URL(fileURLWithPath: path)
        if isDir.boolValue { NSWorkspace.shared.open(u) }
        else { NSWorkspace.shared.activateFileViewerSelecting([u]) }
        reply(id, ["ok": true])
    }

    private func openURL(_ id: Int, _ text: String?) {
        if let text, let u = URL(string: text) { NSWorkspace.shared.open(u) }
        reply(id, ["ok": true])
    }
}

// MARK: - The bridge

extension BookbindEngine: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let cmd = body["cmd"] as? String else { return }
        let id = body["id"] as? Int ?? 0
        let path = body["path"] as? String
        let url = body["url"] as? String
        switch cmd {
        case "pickFolder": pickFolder(id)
        case "pickFiles": pickFiles(id)
        case "reveal": reveal(id, path)
        case "openURL": openURL(id, url)
        default: reply(id, ["error": "unknown command"])
        }
    }
}

// MARK: - Keeping the page here

extension BookbindEngine: WKNavigationDelegate, WKUIDelegate {
    /// Every load is a fresh page, and a fresh page has no skin on it.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applySkin(storedTheme == .liquidGlass ? Self.glassSkin : "")
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let u = action.request.url, let host = u.host,
           host != "127.0.0.1" && host != "localhost" {
            NSWorkspace.shared.open(u)          // a link out goes to the browser
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith config: WKWebViewConfiguration,
                 for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = action.request.url { NSWorkspace.shared.open(u) }
        return nil
    }
}

// MARK: - Where the pieces are

private enum BookbindWhere {
    static let fm = FileManager.default

    /// The engine as it travels inside Housekeeping: `Contents/Resources/Bookbind`.
    static var bundled: String? {
        guard let resources = Bundle.main.resourceURL?.path else { return nil }
        let root = resources + "/Bookbind"
        return fm.fileExists(atPath: root + "/app.py") ? root : nil
    }

    /// The checkout, when this is a development build rather than a release.
    static var checkout: String? {
        let home = NSHomeDirectory() as NSString
        let c3po = home.appendingPathComponent("C3PO/Bookbind")
        if fm.fileExists(atPath: c3po + "/app.py") { return c3po }
        let claude = home.appendingPathComponent("Claude/Bookbind")
        if fm.fileExists(atPath: claude + "/app.py") { return claude }
        return nil
    }

    static var root: String? { bundled ?? checkout }

    /// A frozen server, when this copy carries one. Only the standalone app's
    /// builds have it; Housekeeping ships the plain sources and uses Python.
    static var frozenServer: String? {
        #if arch(arm64)
        let candidates = [
            bundled.map { $0 + "/bin/BookbindServer" },
            "/Applications/Bookbind.app/Contents/Resources/bin/BookbindServer",
            checkout.map { $0 + "/Bookbind.app/Contents/Resources/bin/BookbindServer" },
            checkout.map { $0 + "/bin/BookbindServer" }
        ].compactMap { $0 }

        for p in candidates where fm.isExecutableFile(atPath: p) {
            return p
        }
        #endif
        return nil
    }

    static var logFile: String {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/Bookbind")
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir + "/Bookbind.log"
    }
}

// MARK: - The launch, off the main thread

private enum BookbindLaunch {
    enum Outcome {
        case external(URL)
        case owned(Process, URL, FileHandle)
        case failed(String)
    }

    static func boot() -> Outcome {
        let fm = FileManager.default
        let expected = bundledVersion

        // A server already on one of our ports is only ours to reuse when it is
        // this build. An older copy answers /api/home just as cheerfully and then
        // runs the old job engine — which is how a fixed app could still sit on
        // "Waiting for the engine" forever. So the handshake includes the version,
        // and a stale engine left behind by a dead app is cleared out.
        for port in 8765...8774 {
            guard let health = health(port) else { continue }
            let version = health["version"] as? String
            let parent = (health["parent"] as? String).flatMap(Int32.init)
            let parentAlive = parent.map { $0 > 1 && kill($0, 0) == 0 } ?? true
            if parentAlive && (expected == nil || version == expected) {
                return .external(URL(string: "http://127.0.0.1:\(port)/")!)
            }
            if parent != nil && !parentAlive, let pid = health["pid"] as? Int, pid > 1 {
                kill(pid_t(pid), SIGTERM)
                for _ in 0..<20 where kill(pid_t(pid), 0) == 0 { usleep(100_000) }
                if kill(pid_t(pid), 0) == 0 { kill(pid_t(pid), SIGKILL) }
                for _ in 0..<20 where !free(port) { usleep(100_000) }
            }
        }
        guard let port = (8765...8774).first(where: free) else {
            return .failed("Every port from 8765 to 8774 is taken.\n\nQuit whatever is using them and open Bookbind again.")
        }
        guard let root = BookbindWhere.root else {
            return .failed("Bookbind's program files are not in this copy of Housekeeping.\n\nWhile building: keep the checkout at ~/C3PO/Bookbind. From a release: download Housekeeping again.")
        }

        let url = URL(string: "http://127.0.0.1:\(port)/")!
        let process = Process()
        var env = ProcessInfo.processInfo.environment

        if let frozen = BookbindWhere.frozenServer {
            let binDir = (frozen as NSString).deletingLastPathComponent
            env["PATH"] = binDir + ":/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
            process.executableURL = URL(fileURLWithPath: frozen)
        } else {
            guard let python = findPython() else {
                return .failed("Bookbind needs Python 3.\n\nInstall it with:\n\n    brew install python3\n    python3 -m pip install mutagen")
            }
            guard runs(python, ["-c", "import mutagen"]) else {
                return .failed("Python 3 is here, but the `mutagen` library is missing — it is what reads the tags.\n\nInstall it with:\n\n    \(python) -m pip install mutagen")
            }
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [root + "/app.py"]
        }

        env["BOOKBIND_PORT"] = String(port)
        env["PYTHONUNBUFFERED"] = "1"
        // So the server quits when Housekeeping does, rather than outliving a
        // force-quit and being adopted -- stale code answering on a port the
        // next launch trusts.
        env["BOOKBIND_PARENT"] = String(ProcessInfo.processInfo.processIdentifier)
        process.environment = env

        fm.createFile(atPath: BookbindWhere.logFile, contents: nil)
        let log = (try? FileHandle(forWritingTo: URL(fileURLWithPath: BookbindWhere.logFile)))
        log?.seekToEndOfFile()
        if let log {
            process.standardOutput = log
            process.standardError = log
        }

        do { try process.run() } catch {
            return .failed("The server would not start: \(error.localizedDescription)")
        }

        for _ in 0..<120 {
            if answered(port) { return .owned(process, url, log ?? FileHandle.nullDevice) }
            if !process.isRunning { break }
            usleep(250_000)
        }
        if answered(port) { return .owned(process, url, log ?? FileHandle.nullDevice) }
        let tail = logTail()
        let detail = tail.isEmpty ? "" : "\n\nWhat it said:\n\n\(tail)"
        return .failed("The server stopped on startup.\(detail)\n\nThe whole log is at:\n\n\(BookbindWhere.logFile)")
    }

    // MARK: small tools

    /// The version of the Python that travels with this copy, read from the same
    /// file the engine runs. A copy with no readable app.py gets no opinion.
    static var bundledVersion: String? {
        guard let root = BookbindWhere.root,
              let text = try? String(contentsOfFile: root + "/app.py", encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("VERSION = ") {
            return line.split(separator: "\"").dropFirst().first.map(String.init)
        }
        return nil
    }

    /// What a server says about itself, or nil when nothing is listening there.
    static func health(_ port: Int) -> [String: Any]? {
        guard let body = httpGet("http://127.0.0.1:\(port)/api/health", timeout: 0.8),
              let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    static func health(_ url: URL) -> [String: Any]? {
        guard let body = httpGet(url.appendingPathComponent("api/health").absoluteString, timeout: 0.8),
              let data = body.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// The last few lines the engine wrote, so a failure can say what happened
    /// instead of only where to look.
    static func logTail(lines: Int = 8) -> String {
        let path = BookbindWhere.logFile
        guard let handle = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? handle.close() }
        // A log that has been appended to for months should not be read whole
        // just to show eight lines.
        let size = (try? handle.seekToEnd()) ?? 0
        let window: UInt64 = 65_536
        try? handle.seek(toOffset: size > window ? size - window : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        let tail = text.split(separator: "\n").suffix(lines).joined(separator: "\n")
        return tail.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func httpGet(_ url: String, timeout: TimeInterval = 1.5) -> String? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        var body: String?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data { body = String(data: data, encoding: .utf8) }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + timeout + 1)
        return body
    }

    static func answered(_ port: Int) -> Bool {
        httpGet("http://127.0.0.1:\(port)/api/home", timeout: 0.6)?.contains("\"home\"") == true
    }

    /// Nothing listening on this port? Then it is ours to take.
    static func free(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let r = withUnsafePointer(to: &addr) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return r != 0
    }

    static func runs(_ exe: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardError = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// The first python3 that can import mutagen -- it is what reads the tags --
    /// falling back to any python3 at all, so the error can say what is missing
    /// rather than pretending there is no Python here.
    static func findPython() -> String? {
        var candidates = [
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.10/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
            candidates.append(String(dir) + "/python3")
        }
        var any: String?
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            if any == nil { any = c }
            if runs(c, ["-c", "import mutagen"]) { return c }
        }
        return any
    }
}

// MARK: - Dropping files on the page

/// Takes files dropped on Bookbind's page.
///
/// A web page is deliberately never told where a dropped file lives, and the
/// engine cannot work without that: a dropped folder has to become the folder the
/// book is written into. So the drop is caught here and handed to the page as a
/// list of real paths. Only file URLs are registered, so dragging text into the
/// title field still reaches WebKit as it always did.
///
/// Two catchers, on purpose: this view sits above the page, and the web view's own
/// subclass answers too. WebKit keeps its drag destination on a private subview,
/// so which of the two AppKit asks first is not something this app decides -- and
/// a second call is harmless, because the page checks each path against its list
/// before adding it.
final class BookbindDropCatcher: NSView {
    var onFiles: (([URL]) -> Void)?
    var onDrag: ((Bool) -> Void)?
    private var inside = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    /// Clicks, scrolls and everything else belong to the page underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The dropped paths, minus any that have already gone.
    static func files(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func entering(_ info: NSDraggingInfo) -> NSDragOperation {
        guard !Self.files(info).isEmpty else { return [] }
        if !inside { inside = true; onDrag?(true) }
        return .copy
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation { entering(info) }
    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation { entering(info) }

    override func draggingExited(_ info: NSDraggingInfo?) { left() }
    override func draggingEnded(_ info: NSDraggingInfo) { left() }

    override func prepareForDragOperation(_ info: NSDraggingInfo) -> Bool {
        !Self.files(info).isEmpty
    }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        let urls = Self.files(info)
        left()
        guard !urls.isEmpty else { return false }
        onFiles?(urls)
        return true
    }

    private func left() {
        guard inside else { return }
        inside = false
        onDrag?(false)
    }
}

/// The same catcher, worn by the web view itself.
final class BookbindDropWebView: WKWebView {
    var onFiles: (([URL]) -> Void)?
    var onDrag: ((Bool) -> Void)?
    private var inside = false

    private func entering(_ info: NSDraggingInfo) -> NSDragOperation {
        guard !BookbindDropCatcher.files(info).isEmpty else { return super.draggingEntered(info) }
        if !inside { inside = true; onDrag?(true) }
        return .copy
    }

    override func draggingEntered(_ info: NSDraggingInfo) -> NSDragOperation { entering(info) }
    override func draggingUpdated(_ info: NSDraggingInfo) -> NSDragOperation { entering(info) }

    override func draggingExited(_ info: NSDraggingInfo?) {
        if inside { inside = false; onDrag?(false) }
        super.draggingExited(info)
    }

    override func performDragOperation(_ info: NSDraggingInfo) -> Bool {
        let urls = BookbindDropCatcher.files(info)
        if inside { inside = false; onDrag?(false) }
        guard !urls.isEmpty else { return super.performDragOperation(info) }
        onFiles?(urls)
        return true
    }
}
