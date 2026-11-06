import Foundation
import AppKit

struct BackgroundAuditItem: Identifiable, Sendable {
    let url: URL
    let label: String
    let target: String
    let finding: String
    let canTrash: Bool
    let isSystemDaemon: Bool
    let fingerprint: Data
    var id: String { url.path }
}

/// A missing file is evidence; an unfamiliar vendor name is not.
/// Never infer that a working VPN, updater or personal service is disposable.
actor BackgroundItemAudit {
    static let shared = BackgroundItemAudit()
    static var roots: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"),
         URL(fileURLWithPath: "/Library/LaunchAgents"), URL(fileURLWithPath: "/Library/LaunchDaemons")]
    }

    func scan() -> (items: [BackgroundAuditItem], notices: [String]) {
        var items: [BackgroundAuditItem] = []
        var notices: [String] = []
        for root in Self.roots {
            do {
                let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                for url in entries where url.lastPathComponent != ".DS_Store" {
                    if let item = Self.inspect(url) { items.append(item) }
                }
            } catch { notices.append("Could not read \(root.path). The audit is incomplete.") }
        }
        return (items.sorted { ($0.canTrash ? 0 : 1, $0.label) < ($1.canTrash ? 0 : 1, $1.label) }, notices)
    }

    private static func isProtected(_ label: String) -> Bool {
        let lower = label.lowercased()
        return lower.hasPrefix("com.apple.") || lower.hasPrefix("com.morad.") || lower.contains("determinate") || lower.contains("macfuse")
    }

    private static func definitelyMissing(_ path: String) -> Bool {
        let result = access(path, F_OK)
        return result != 0 && (errno == ENOENT || errno == ENOTDIR)
    }

    static func inspect(_ url: URL) -> BackgroundAuditItem? {
        let fm = FileManager.default
        let name = url.lastPathComponent
        let daemon = url.deletingLastPathComponent().path == "/Library/LaunchDaemons"
        if let destination = try? fm.destinationOfSymbolicLink(atPath: url.path) {
            // Never trash a symlink's destination; retain the link's own path.
            let target = destination.hasPrefix("/") ? URL(fileURLWithPath: destination)
                : url.deletingLastPathComponent().appendingPathComponent(destination).standardizedFileURL
            let broken = definitelyMissing(target.path)
            return BackgroundAuditItem(url: url, label: url.deletingPathExtension().lastPathComponent, target: target.path,
                finding: broken ? "Broken link: its target is missing. Review before moving the link to Trash." : "Linked startup item. Keep unless you know its purpose.",
                canTrash: broken && !isProtected(name), isSystemDaemon: daemon, fingerprint: Data(destination.utf8))
        }
        guard name.hasSuffix(".plist") || name.contains(".plist.") else { return nil }
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return BackgroundAuditItem(url: url, label: name, target: "", finding: "Could not read this configuration. Inspect it in Finder; no automatic cleanup is offered.", canTrash: false, isSystemDaemon: daemon, fingerprint: Data())
        }
        let label = plist["Label"] as? String ?? name
        let args = plist["ProgramArguments"] as? [String] ?? []
        let target = plist["Program"] as? String ?? args.first ?? ""
        let missing = target.hasPrefix("/") && definitelyMissing(target)
        let lower = label.lowercased()
        let protected = isProtected(label)
        let isNuke = lower == "com.topazlabs.veai.nukepath"
        let isCamera = lower == "com.logitech.logirightsight.agent"
        let keepAlive = (plist["KeepAlive"] as? Bool) == true || plist["KeepAlive"] is [String: Any]
        let interval = (plist["StartInterval"] as? NSNumber)?.intValue
        let frequency = keepAlive ? " It can stay running in the background." : interval.map { " Scheduled every \($0) seconds." } ?? ""
        let finding: String
        if protected { finding = "System, personal, or shared infrastructure. Preserve this item." }
        else if missing { finding = "Its configured executable is missing. It may need repair or belong to an uninstalled app." }
        else if isNuke { finding = "Topaz’s integration with Foundry Nuke. Remove only if you do not use that integration." }
        else if isCamera { finding = "Logitech conference-camera framing helper. Remove only if you do not use that camera feature." }
        else if lower.contains("vpn") || lower.contains("shecan") || lower.contains("windscribe") || lower.contains("surfshark") {
            finding = "VPN background component. It may support your current connection. Review its app and background permission in System Settings."
        } else { finding = "Installed startup component. Keep unless you recognise it and no longer need it." }
        return BackgroundAuditItem(url: url, label: label, target: target, finding: finding + frequency,
            canTrash: !protected && (missing || isNuke || isCamera), isSystemDaemon: daemon, fingerprint: data)
    }

    /// Called only after the UI displays the exact path and asks for confirmation.
    /// A changed file must be rescanned and reviewed again.
    func trash(_ reviewed: BackgroundAuditItem) async throws {
        guard Self.roots.contains(reviewed.url.deletingLastPathComponent()),
              let current = Self.inspect(reviewed.url), current.canTrash,
              current.fingerprint == reviewed.fingerprint else {
            throw MCPError.message("This item changed or is protected. Refresh and review it again.")
        }
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: trash.path)) == nil,
              FileManager.default.fileExists(atPath: trash.path) else {
            throw MCPError.message("The Mac’s Trash is unavailable. Nothing was moved.")
        }
        let destination = trash.appendingPathComponent("Housekeeping-\(UUID().uuidString)-\(reviewed.url.lastPathComponent)")
        let domain = reviewed.isSystemDaemon ? "system" : "gui/\(getuid())"
        let job = domain + "/" + reviewed.label
        let q: (String) -> String = { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        // A loaded item must unload successfully before its configuration moves.
        // launchctl print is read-only; a missing registration needs no bootout.
        let command = "if /bin/launchctl print \(q(job)) >/dev/null 2>&1; then /bin/launchctl bootout \(q(domain)) \(q(reviewed.url.path)) || exit 1; fi; /bin/mv -n \(q(reviewed.url.path)) \(q(destination.path))"
        let runner = ProcessRunner()
        let result: ProcessRunner.Result
        if reviewed.url.path.hasPrefix("/Library/") {
            let literal = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            result = try await runner.run(executable: "/usr/bin/osascript", arguments: ["-e", "do shell script \"\(literal)\" with administrator privileges"], timeout: 120)
        } else {
            result = try await runner.run(executable: "/bin/sh", arguments: ["-c", command], timeout: 10)
        }
        guard result.succeeded, FileManager.default.fileExists(atPath: destination.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) != nil else {
            throw MCPError.message("The item could not be moved. It may still be loaded or administrator approval was cancelled. Refresh before trying again.")
        }
    }
}
