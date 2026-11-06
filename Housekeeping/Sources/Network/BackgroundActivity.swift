import Foundation

struct ActivityProcess: Sendable {
    let pid: Int32
    let parent: Int32
    let uid: Int
    let cpu: Double
    let residentBytes: Int64
    let path: String
}

struct ActivityRegistration: Identifiable, Sendable {
    let id: String
    let name: String
    let kind: String
    let disposition: String
    let identifier: String
    let path: String?
    let executable: String?
    let owner: String?

    var isAllowed: Bool { disposition.contains("allowed") && !disposition.contains("disallowed") }
    var isEnabled: Bool { disposition.contains("enabled") && !disposition.contains("disabled") }
    var permissionLabel: String {
        if disposition.contains("disallowed") { return "Background permission off" }
        if disposition.contains("disabled") { return "Registered, not enabled" }
        if !disposition.contains("enabled") { return "Permission unknown" }
        return isAllowed ? "Background permission allowed" : "Permission unknown"
    }
}

struct ActivityApp: Identifiable, Sendable {
    let id: String
    let name: String
    let path: String
    let processes: [ActivityProcess]
    let isOpen: Bool
    let isSystem: Bool
    let diskBytes: Int64?
    let advice: String
    var memoryBytes: Int64 { processes.reduce(0) { $0 + $1.residentBytes } }
    var cpu: Double { processes.reduce(0) { $0 + $1.cpu } }
    var isWidget: Bool { processes.allSatisfy { $0.path.lowercased().contains("widget") } }
}

struct ActivitySnapshot: Sendable {
    var apps: [ActivityApp] = []
    var registrations: [ActivityRegistration] = []
    var widgets: [ActivityWidget] = []
    var startupItems: [BackgroundAuditItem] = []
    var installedApps: [ActivityInstalledApp] = []
    var processReadingAvailable = false
    var notices: [String] = []
    var captured: Date = Date()
}

actor BackgroundActivity {
    static let shared = BackgroundActivity()
    private var sizes: [String: (Date, Int64)] = [:]

    static func parseProcesses(_ text: String) -> [ActivityProcess] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 5, whereSeparator: { $0.isWhitespace })
            guard fields.count == 6, let pid = Int32(fields[0]), let parent = Int32(fields[1]),
                  let uid = Int(fields[2]), let cpu = Double(fields[3]), let rss = Int64(fields[4]), rss >= 0 else { return nil }
            return ActivityProcess(pid: pid, parent: parent, uid: uid, cpu: cpu, residentBytes: rss * 1024, path: String(fields[5]))
        }
    }

    static func appPath(_ path: String) -> String? {
        guard path.hasPrefix("/"), let range = path.range(of: ".app/", options: .caseInsensitive) else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    static func isSystemPath(_ path: String) -> Bool {
        ["/System/", "/usr/libexec/", "/usr/lib/", "/usr/bin/", "/usr/sbin/", "/sbin/", "/bin/", "/Library/Apple/"].contains { path.hasPrefix($0) }
    }

    /// An interpreter or helper belongs to its ancestor's app when that is
    /// observable. Unknown jobs retain their executable identity.
    static func owner(_ process: ActivityProcess, index: [Int32: ActivityProcess]) -> String {
        var current: ActivityProcess? = process
        var visited = Set<Int32>()
        while let node = current, visited.insert(node.pid).inserted {
            if !isSystemPath(node.path), let app = appPath(node.path),
               !app.hasPrefix("/opt/homebrew/"), !app.hasPrefix("/usr/local/") { return app }
            current = index[node.parent]
        }
        return appPath(process.path) ?? process.path
    }

    static func advice(name: String, path: String, widget: Bool, isSystem: Bool, isOpen: Bool) -> String {
        let lower = (name + " " + path).lowercased()
        if isSystem { return "macOS component. Keep it; resource use alone does not establish that it is unnecessary." }
        if lower.contains("vpn") || lower.contains("shecan") || lower.contains("windscribe") || lower.contains("surfshark") || lower.contains("shadowrocket") { return "Network helper. It may carry your current connection; review it in VPN Tunnels before making changes." }
        if widget { return "Widget extension. If you do not use this widget, remove it from the desktop or Notification Centre using Edit Widgets. Its owning app can stay installed." }
        if lower.contains("logioptionsplus_updater") { return "Logitech update helper. Keep automatic updates, or review its background permission if you prefer checking for updates manually. Disabling the main Options+ agent can affect mouse buttons and gestures." }
        if lower.contains("updat") || lower.contains("mau2") { return "Software update helper. It keeps its owning app patched. Review automatic-update settings only if you will check for updates yourself." }
        if lower.contains("anydesk") { return "Remote-access app. Background access is useful for unattended connections; review it if you never use that feature." }
        if lower.contains("mountain") { return "Mounted-cloud-drive helper. Keep it if you need those drives mounted or restored at login." }
        if lower.contains("unity") { return "Game-development helper. Review launch-at-login if you only need it when you open Unity Hub." }
        if lower.contains("mlx") || lower.contains("nix") || lower.contains("macfuse") || lower.contains("reaper") { return "Shared or personal infrastructure. Other tools may depend on it; preserve it unless you have checked those dependencies." }
        return isOpen ? "Its app is open. Close it normally when you no longer need it; helper memory is included here." : "Background helper or tool. Review its owning app and purpose before deciding whether to keep it. Not being visible does not make it disposable."
    }

    /// Parse only this account and shared/root registrations. Developer grouping
    /// records and normal app records are used for ownership, not counted as jobs.
    static func parseRegistrations(_ text: String, uid: Int) -> [ActivityRegistration] {
        var records: [[String: String]] = []
        var record: [String: String] = [:]
        var currentUID: Int?
        func finish() {
            if record["Identifier"] != nil, let ownerUID = currentUID, [uid, 0, -2].contains(ownerUID) {
                record["uid"] = String(ownerUID)
                records.append(record)
            }
            record = [:]
        }
        let keys = Set(["Name", "Type", "Disposition", "Identifier", "URL", "Executable Path", "Parent Identifier"])
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("Records for UID ") {
                finish()
                currentUID = Int(line.dropFirst("Records for UID ".count).split(separator: " ").first ?? "")
            } else if line.hasPrefix("#"), line.hasSuffix(":"), !line.contains(" ") { finish() }
            else if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon])
                if keys.contains(key) { record[key] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces) }
            }
        }
        finish()
        func absolute(_ raw: String?) -> String? {
            guard let raw, raw != "(null)", !raw.isEmpty else { return nil }
            if raw.hasPrefix("file://"), let url = URL(string: raw) { return url.path }
            return raw.hasPrefix("/") ? raw : nil
        }
        func parentPath(_ row: [String: String]) -> String? {
            guard let parent = row["Parent Identifier"] else { return nil }
            let sameAccount = records.first { $0["Identifier"] == parent && $0["uid"] == row["uid"] }
            return absolute(sameAccount?["URL"])
                ?? records.first { $0["Identifier"] == parent && absolute($0["URL"]) != nil }.flatMap { absolute($0["URL"]) }
        }
        var seen = Set<String>()
        return records.compactMap { row in
            let type = row["Type"] ?? ""
            guard !type.hasPrefix("developer "), !type.hasPrefix("app ") else { return nil }
            guard let identifier = row["Identifier"] else { return nil }
            let owner = parentPath(row)
            func resolve(_ value: String?) -> String? {
                if let direct = absolute(value) { return direct }
                guard let value, value != "(null)", !value.isEmpty, let owner,
                      !value.split(separator: "/").contains("..") else { return nil }
                return URL(fileURLWithPath: owner).appendingPathComponent(value).standardizedFileURL.path
            }
            let path = resolve(row["URL"])
            // A relative executable belongs to the helper bundle when the
            // registration identifies one. Do not guess a base for other forms.
            let rawExecutable = row["Executable Path"]
            let executable: String?
            if let direct = absolute(rawExecutable) { executable = direct }
            else if let rawExecutable, rawExecutable.hasPrefix("Contents/"),
                    !rawExecutable.split(separator: "/").contains(".."),
                    let path, path.lowercased().hasSuffix(".app") {
                executable = URL(fileURLWithPath: path).appendingPathComponent(rawExecutable).standardizedFileURL.path
            } else { executable = nil }
            let id = (row["uid"] ?? "") + "|" + identifier + "|" + (path ?? "")
            guard seen.insert(id).inserted else { return nil }
            return ActivityRegistration(id: id, name: row["Name"] ?? identifier, kind: type,
                disposition: row["Disposition"] ?? "", identifier: identifier, path: path, executable: executable, owner: owner)
        }
    }

    func scan(openApps: Set<String>) async -> ActivitySnapshot {
        var snapshot = ActivitySnapshot()
        let runner = ProcessRunner()
        async let processRead = runner.run(executable: "/bin/ps", arguments: ["-axo", "pid=,ppid=,uid=,%cpu=,rss=,comm="], timeout: 8)
        // Each concurrent command owns its runner and cancellation state.
        async let backgroundRead = ProcessRunner().run(executable: "/usr/bin/sfltool", arguments: ["dumpbtm"], timeout: 15)
        async let widgetRead = BackgroundWidgetControl.shared.catalog()
        async let startupRead = BackgroundItemAudit.shared.scan()
        var processes: [ActivityProcess] = []
        do {
            let result = try await processRead
            if result.succeeded { processes = Self.parseProcesses(result.stdout); snapshot.processReadingAvailable = true }
            else { snapshot.notices.append("The process reading was unavailable. Current RAM and CPU use are unknown.") }
        } catch { snapshot.notices.append("The process reading was unavailable. Current RAM and CPU use are unknown.") }
        do {
            let result = try await backgroundRead
            if result.succeeded { snapshot.registrations = Self.parseRegistrations(result.stdout, uid: Int(getuid())) }
            else { snapshot.notices.append("macOS background registrations could not be read. Use Open Login Items to review them.") }
        } catch { snapshot.notices.append("macOS background registrations could not be read. Use Open Login Items to review them.") }
        let startupResult = await startupRead
        snapshot.startupItems = startupResult.items
        snapshot.notices += startupResult.notices
        let widgetResult = await widgetRead
        snapshot.widgets = widgetResult.widgets
        if let notice = widgetResult.notice { snapshot.notices.append(notice) }
        let index = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let grouped = Dictionary(grouping: processes) { Self.owner($0, index: index) }
        let diskDeadline = Date().addingTimeInterval(12)
        for (owner, members) in grouped {
            if Task.isCancelled { break }
            let system = Self.isSystemPath(owner)
            let url = URL(fileURLWithPath: owner)
            let name = url.deletingPathExtension().lastPathComponent
            let widget = members.allSatisfy { $0.path.lowercased().contains("widget") }
            var disk: Int64?
            if !system && owner.hasPrefix("/") && Date() < diskDeadline && FileManager.default.fileExists(atPath: owner) {
                if let cached = sizes[owner], Date().timeIntervalSince(cached.0) < 300 { disk = cached.1 }
                else if let result = try? await ProcessRunner().run(executable: "/usr/bin/du", arguments: ["-sk", owner], timeout: 4), result.succeeded,
                        let field = result.stdout.split(whereSeparator: { $0.isWhitespace }).first, let kb = Int64(field) {
                    disk = kb * 1024
                    sizes[owner] = (Date(), kb * 1024)
                }
            }
            snapshot.apps.append(ActivityApp(id: owner, name: name, path: owner, processes: members,
                isOpen: openApps.contains(owner), isSystem: system, diskBytes: disk,
                advice: !owner.hasPrefix("/") ? "macOS reported a process name without its full path. Ownership is unknown; do not remove a service based on this name alone." : Self.advice(name: name, path: owner + " " + members.map(\.path).joined(separator: " "), widget: widget, isSystem: system, isOpen: openApps.contains(owner))))
        }
        let roots = ["/Applications", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        let standalone = ["Bookbind", "MediaDock 9", "DNS Easy Switcher", "RouteSweep"]
        var installedPaths = Set(snapshot.registrations.compactMap(\.owner).filter { $0.hasSuffix(".app") })
        for root in roots { for name in standalone { installedPaths.insert(root + "/" + name + ".app") } }
        for path in installedPaths.sorted() where !snapshot.apps.contains(where: { $0.path == path }) && FileManager.default.fileExists(atPath: path) {
            if Task.isCancelled { break }
            var disk: Int64?
            if let cached = sizes[path], Date().timeIntervalSince(cached.0) < 300 { disk = cached.1 }
            else if Date() < diskDeadline,
                    let result = try? await ProcessRunner().run(executable: "/usr/bin/du", arguments: ["-sk", path], timeout: 4), result.succeeded,
                    let field = result.stdout.split(whereSeparator: { $0.isWhitespace }).first, let kb = Int64(field) {
                disk = kb * 1024; sizes[path] = (Date(), kb * 1024)
            }
            snapshot.installedApps.append(ActivityInstalledApp(path: path, name: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, diskBytes: disk))
        }
        snapshot.apps.sort { $0.memoryBytes > $1.memoryBytes }
        snapshot.captured = Date()
        return snapshot
    }
}
