import Foundation
import Darwin

/// Usage is a reader's decision, distinct from permission or measured load.
enum BackgroundUse: String, Codable, CaseIterable { case unsure, needed, unused }
enum BackgroundVerdict: String, CaseIterable {
    case leftover = "Likely leftover", unused = "Unneeded for you", review = "Optional — review", unknown = "Need more information", keep = "Keep"
    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}
struct BackgroundRecommendation: Identifiable {
    let id: String
    let name: String
    let path: String
    let verdict: BackgroundVerdict
    let reason: String
    let consequence: String
    let question: String?
    let evidence: [String]
    let memoryBytes: Int64?
    let appPath: String?
    let widget: ActivityWidget?
    let startup: BackgroundAuditItem?
    let protected: Bool
    // Usage belongs to a feature; list identity also distinguishes installed versions.
    var rowID: String { id + "|" + path }
}

struct ActivityWidget: Identifiable, Sendable, Equatable {
    let identifier: String
    let name: String
    let path: String
    let executable: String
    let appPath: String
    let election: String
    var id: String { identifier + "|" + path }
    var isIgnored: Bool { election == "ignore" }
}
struct ActivityInstalledApp: Sendable {
    let path: String
    let name: String
    let diskBytes: Int64?
}

enum BackgroundReview {
    static func protected(_ text: String, system: Bool = false) -> Bool {
        let lower = text.lowercased()
        return system || lower.contains("com.apple.") || lower.contains("com.morad.") ||
            ["vpn", "shecan", "windscribe", "surfshark", "shadowrocket", "macfuse", "determinate", "/nix/", "mlx", "idle-reaper"].contains { lower.contains($0) }
    }
    static func optionalPurpose(_ text: String) -> (String, String, String)? {
        let lower = text.lowercased()
        if lower.contains("anydesk") || lower.contains("remote desktop") {
            return ("Remote access can work without its main window being open.", "Disabling its background access prevents unattended connections.", "Do you still use this app, including occasional remote access?")
        }
        if lower.contains("mountain duck") || lower.contains("mountainduck") {
            return ("This helper can mount cloud storage and restore mounts at login.", "Disabling it can stop automatic cloud-drive mounts.", "Do you use its mounted cloud drives?")
        }
        if lower.contains("unity hub") || lower.contains("unityhub") {
            return ("Unity Hub manages game-development tools and projects.", "Removing Hub can affect project and editor launching; existing projects must be preserved.", "Do you use Unity Hub for game development?")
        }
        if lower.contains("nukepath") {
            return ("This is Topaz's Foundry Nuke integration.", "Removing it stops that integration; it does not establish that Topaz itself is unused.", "Do you use Topaz from Foundry Nuke?")
        }
        if lower.contains("logirightsight") {
            return ("This supplies Logitech conference-camera framing.", "Removing it disables camera framing; keep your mouse and keyboard support separate.", "Do you use this camera-framing feature?")
        }
        if ["bookbind.app", "mediadock 9.app", "dns easy switcher.app", "routesweep.app"].contains(where: { lower.hasSuffix("/" + $0) }) {
            return ("This standalone utility overlaps a tool included in Housekeeping.", "Review whether you need its separate app or settings before uninstalling it.", "Do you still use the standalone app?")
        }
        return nil
    }
    static func isUpdater(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("updat") || lower.contains("mau2")
    }
    static func summary(snapshot: ActivitySnapshot, choices: [String: BackgroundUse], limit: Int = 8) -> String {
        let items = recommendations(snapshot: snapshot, startup: snapshot.startupItems, choices: choices)
        let review = items.filter { $0.verdict != .keep }
        let shown = Array(review.prefix(max(0, limit)))
        var lines = ["I checked background activity on this Mac at " + snapshot.captured.formatted() + ".",
            "\(items.filter { $0.verdict == .leftover }.count) likely leftovers, \(items.filter { $0.verdict == .unused }.count) items you marked unused, \(items.filter { $0.verdict == .review }.count) optional features to review, and \(items.filter { $0.verdict == .unknown }.count) items needing more information."]
        lines += snapshot.notices
        for item in shown {
            lines.append("\(item.name) — \(item.verdict.rawValue). \(item.reason)")
            if let memory = item.memoryBytes { lines.append("Reported RAM: " + ByteCountFormatter.string(fromByteCount: memory, countStyle: .memory) + ". This is observed use, not promised savings.") }
            lines.append("Consequence: " + item.consequence)
            if let question = item.question { lines.append(question) }
        }
        if shown.count < review.count { lines.append("Showing \(shown.count) of \(review.count) recommendations needing review or more information.") }
        lines.append("Open Background Activity > Recommendations for every item, its evidence and the I use this / I don't use this choices. Your answers guide future reviews. Pause Widget, Review Startup Removal and Review App Uninstall use separate confirmation controls. Unknown items are not proven unnecessary. This review has changed no apps or settings.")
        return lines.joined(separator: "\n\n")
    }
    static func recommendations(snapshot: ActivitySnapshot, startup: [BackgroundAuditItem], choices: [String: BackgroundUse]) -> [BackgroundRecommendation] {
        var result: [BackgroundRecommendation] = []
        let processes = snapshot.apps.flatMap(\.processes)
        let widgetApps = Set(snapshot.widgets.map(\.appPath))
        for widget in snapshot.widgets {
            let id = "widget|" + widget.identifier
            let safeguard = protected(widget.identifier + " " + widget.appPath, system: BackgroundActivity.isSystemPath(widget.path))
            let use = choices[id] ?? .unsure
            let matches = processes.filter { $0.path == widget.executable }
            let verdict: BackgroundVerdict = safeguard || widget.isIgnored || use == .needed ? .keep : use == .unused ? .unused : .review
            result.append(BackgroundRecommendation(id: id, name: widget.name, path: widget.path, verdict: verdict,
                reason: safeguard ? "Protected system or network widget; preserve it." : widget.isIgnored ? "This widget is already disabled for this account." : use == .unused ? "You said you do not use this widget. Its extension can be paused while keeping the app." : use == .needed ? "You said you use this widget." : "Widgets are optional; you can pause an unused widget without uninstalling its app.",
                consequence: "Pausing hides or prevents this widget. Its owning app and documents stay installed. You can restore the default later.",
                question: safeguard ? nil : "Do you use this widget?", evidence: ["Extension: " + widget.identifier, "Election: " + widget.election, "Owning app: " + widget.appPath, matches.isEmpty ? "No matching executable in this reading." : "\(matches.count) matching widget processes."],
                memoryBytes: snapshot.processReadingAvailable ? matches.reduce(0) { $0 + $1.residentBytes } : nil,
                appPath: nil, widget: widget, startup: nil, protected: safeguard))
        }
        var handledApps = Set<String>()
        for app in snapshot.apps where !app.isSystem {
            if app.isWidget && widgetApps.contains(app.path) { continue }
            handledApps.insert(app.path)
            let id = "app|" + app.path
            let text = app.path + " " + app.processes.map(\.path).joined(separator: " ")
            let safeguard = protected(text)
            let use = choices[id] ?? .unsure
            let purpose = optionalPurpose(app.path)
            let updater = isUpdater(text)
            let unknownPath = !app.path.hasPrefix("/")
            let unverifiedWidget = app.isWidget && !widgetApps.contains(app.path)
            let verdict: BackgroundVerdict = safeguard ? .keep : unknownPath || unverifiedWidget ? .unknown : use == .needed ? .keep : use == .unused ? .unused : updater || app.isOpen ? .keep : purpose != nil ? .review : .unknown
            let reason = safeguard ? "Network, personal or shared infrastructure: keep it until its dependencies are checked." : unverifiedWidget ? "This looks like widget activity, but its extension identity could not be verified. Keep its owning app; refresh the widget catalogue before changing it." : unknownPath ? "Ownership is unresolved. There is no evidence that it is disposable." : use == .needed ? "You said you use this app or helper." : use == .unused ? "You said you do not need this app or helper; review its removal and related data separately." : updater ? "Automatic update support. Keep it unless you have a deliberate manual-update plan." : app.isOpen ? "Its app is open. This reading cannot tell whether your work is finished." : purpose?.0 ?? "No evidence establishes that this helper is unnecessary. Its resource use alone is not a reason to remove it."
            result.append(BackgroundRecommendation(id: id, name: app.name, path: app.path, verdict: verdict, reason: reason,
                consequence: safeguard ? "Stopping it may interrupt connectivity or other tools." : updater ? "Turning off update support can leave its app unpatched. Removing the owning app may also remove features you use." : purpose?.1 ?? "Quitting can interrupt active work; uninstalling can remove app features. Review documents and support data separately.",
                question: safeguard || unknownPath || unverifiedWidget ? nil : purpose?.2 ?? "Do you still use this app or the feature supplied by this helper?",
                evidence: [app.isOpen ? "App currently open." : "No ordinary app registered as open for this group.", "\(app.processes.count) observed processes; CPU \(String(format: "%.1f", app.cpu))%.", app.diskBytes.map { "Installed footprint: \($0) bytes; not automatically reclaimable." } ?? "Installed disk footprint unknown."],
                memoryBytes: app.memoryBytes, appPath: !unverifiedWidget && app.path.hasSuffix(".app") && (app.path.hasPrefix("/Applications/") || app.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/")) ? app.path : nil, widget: nil, startup: nil, protected: safeguard))
        }
        for installed in snapshot.installedApps where !handledApps.contains(installed.path) {
            let id = "app|" + installed.path
            let safeguard = protected(installed.path)
            let use = choices[id] ?? .unsure
            let purpose = optionalPurpose(installed.path)
            guard purpose != nil || use != .unsure else { continue }
            result.append(BackgroundRecommendation(id: id, name: installed.name, path: installed.path,
                verdict: safeguard || use == .needed ? .keep : use == .unused ? .unused : .review,
                reason: safeguard ? "Preserve this network or shared component." : use == .unused ? "You said you no longer use this installed app." : use == .needed ? "You said you use this app." : purpose?.0 ?? "Review whether you still use this app.",
                consequence: purpose?.1 ?? "Review related documents and application data separately.", question: safeguard ? nil : purpose?.2 ?? "Do you still use this app?",
                evidence: [snapshot.processReadingAvailable ? "No process group assigned to this app in this reading; this does not prove it never runs." : "Process reading unavailable; current activity unknown.", installed.diskBytes.map { "Installed footprint: \($0) bytes. Space is not reclaimed by moving it to Trash." } ?? "Installed footprint unknown."],
                memoryBytes: snapshot.processReadingAvailable ? 0 : nil, appPath: installed.path, widget: nil, startup: nil, protected: safeguard))
        }
        for item in startup {
            let id = "startup|" + item.id
            let safeguard = protected(item.label + " " + item.target)
            let missing = item.canTrash && (item.finding.hasPrefix("Broken link:") || item.finding.hasPrefix("Its configured executable is missing."))
            let optional = optionalPurpose(item.label)
            let use = choices[id] ?? .unsure
            let verdict: BackgroundVerdict = safeguard ? .keep : missing ? .leftover : use == .needed ? .keep : use == .unused ? .unused : optional != nil ? .review : isUpdater(item.label + item.target) ? .keep : .unknown
            result.append(BackgroundRecommendation(id: id, name: item.label, path: item.url.path, verdict: verdict,
                reason: safeguard ? "Protected personal, network or shared startup infrastructure." : missing ? "This startup configuration points to a missing target. It may be an uninstall leftover or an app needing repair." : use == .unused ? "You said this startup feature is no longer needed." : use == .needed ? "You said you need this feature." : optional?.0 ?? item.finding,
                consequence: "Removing its startup file stops that feature at launch. An app needing repair may need the file restored.", question: safeguard ? nil : optional?.2,
                evidence: [item.finding, "Configured executable: " + item.target], memoryBytes: nil, appPath: nil, widget: nil, startup: item, protected: safeguard))
        }
        // Include app-managed permissions whose ownership could not be resolved.
        for item in snapshot.registrations where item.owner == nil && optionalPurpose(item.name + " " + item.identifier) != nil {
            let id = "registration|" + item.id
            let safeguard = protected(item.identifier + " " + item.name)
            let use = choices[id] ?? .unsure
            let purpose = optionalPurpose(item.name + " " + item.identifier)!
            result.append(BackgroundRecommendation(id: id, name: item.name, path: item.path ?? item.identifier,
                verdict: safeguard ? .keep : use == .unused ? .unused : use == .needed || !item.isAllowed ? .keep : .review,
                reason: !item.isAllowed ? "Its background permission is already off or unknown; current activity needs a separate reading." : use == .unused ? "You said you do not use this background feature." : purpose.0,
                consequence: purpose.1, question: safeguard ? nil : purpose.2, evidence: [item.permissionLabel, "Owning app unresolved."], memoryBytes: nil, appPath: nil, widget: nil, startup: nil, protected: safeguard))
        }
        return result.sorted { a, b in
            if a.verdict.rank != b.verdict.rank { return a.verdict.rank < b.verdict.rank }
            if a.memoryBytes != b.memoryBytes { return (a.memoryBytes ?? -1) > (b.memoryBytes ?? -1) }
            return a.id < b.id
        }
    }
}
