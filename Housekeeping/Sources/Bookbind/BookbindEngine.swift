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
            case .owned(let process, let url, let handle):
                self.process = process
                self.owned = true
                self.log = handle
                self.url = url
                phase = .ready
                load(url)
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
        guard owned, let process, process.isRunning else { return }
        process.terminate()
        self.process = nil
        owned = false
    }

    func retry() {
        phase = .idle
        startIfNeeded()
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

        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 760),
                            configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
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
        let root = (NSHomeDirectory() as NSString).appendingPathComponent("Claude/Bookbind")
        return fm.fileExists(atPath: root + "/app.py") ? root : nil
    }

    static var root: String? { bundled ?? checkout }

    /// A frozen server, when this copy carries one. Only the standalone app's
    /// builds have it; Housekeeping ships the plain sources and uses Python.
    static var frozenServer: String? {
        guard let root = bundled else { return nil }
        let p = root + "/bin/BookbindServer"
        return fm.isExecutableFile(atPath: p) ? p : nil
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

        // An instance that is already running is somebody else's; just show it.
        for port in 8765...8774 where answered(port) {
            return .external(URL(string: "http://127.0.0.1:\(port)/")!)
        }
        guard let port = (8765...8774).first(where: free) else {
            return .failed("Every port from 8765 to 8774 is taken.\n\nQuit whatever is using them and open Bookbind again.")
        }
        guard let root = BookbindWhere.root else {
            return .failed("Bookbind's program files are not in this copy of Housekeeping.\n\nWhile building: keep the checkout at ~/Claude/Bookbind. From a release: download Housekeeping again.")
        }

        let url = URL(string: "http://127.0.0.1:\(port)/")!
        let process = Process()
        var env = ProcessInfo.processInfo.environment

        if let frozen = BookbindWhere.frozenServer {
            env["PATH"] = (root + "/bin") + ":/usr/bin:/bin:/usr/sbin:/sbin"
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
        return .failed("The server stopped on startup.\n\nWhat it said is in:\n\n\(BookbindWhere.logFile)")
    }

    // MARK: small tools

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
        var candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
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
