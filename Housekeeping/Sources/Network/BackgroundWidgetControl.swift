import Foundation
import Darwin

/// Widget elections are independent of their owning app's installation.
actor BackgroundWidgetControl {
    static let shared = BackgroundWidgetControl()

    static func pluginRows(_ text: String) -> [(identifier: String, path: String, election: String)] {
        text.split(separator: "\n").compactMap { raw in
            let fields = raw.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2, let pathField = fields.last else { return nil }
            let path = pathField.trimmingCharacters(in: .whitespaces)
            guard path.hasPrefix("/"), path.hasSuffix(".appex") else { return nil }
            let first = String(fields[0]).trimmingCharacters(in: .whitespaces)
            let marker = first.first
            let identifierVersion = ["+", "-", "!", "=", "?"].contains(String(marker ?? " ")) ? String(first.dropFirst()).trimmingCharacters(in: .whitespaces) : first
            guard let version = identifierVersion.firstIndex(of: "(") else { return nil }
            let identifier = String(identifierVersion[..<version]).trimmingCharacters(in: .whitespaces)
            guard !identifier.isEmpty, identifier.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_").contains($0) }) else { return nil }
            let election = marker == "-" ? "ignore" : marker == "+" ? "use" : marker == "!" || marker == "=" || marker == "?" ? "unknown" : "default"
            return (identifier, path, election)
        }
    }

    static func inspect(identifier: String, path: String, election: String) -> ActivityWidget? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.path == path, path.hasSuffix(".appex"),
              let owner = BackgroundActivity.appPath(path),
              let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == identifier,
              let ext = info["NSExtension"] as? [String: Any],
              ext["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension",
              let executable = info["CFBundleExecutable"] as? String,
              !executable.isEmpty, !executable.contains("/"), executable != ".", executable != ".." else { return nil }
        let binary = url.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable).path
        let ownerName = URL(fileURLWithPath: owner).deletingPathExtension().lastPathComponent
        let widgetName = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? executable
        return ActivityWidget(identifier: identifier, name: ownerName + " — " + widgetName, path: path, executable: binary, appPath: owner, election: election)
    }

    static func eligible(_ widget: ActivityWidget) -> Bool {
        let roots = ["/Applications/", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/"]
        guard ["ignore", "default", "use"].contains(widget.election), roots.contains(where: { widget.appPath.hasPrefix($0) }),
              !BackgroundReview.protected(widget.identifier + " " + widget.appPath),
              widget.path.hasPrefix(widget.appPath + "/Contents/PlugIns/"),
              URL(fileURLWithPath: widget.path).resolvingSymlinksInPath().path == widget.path,
              let current = inspect(identifier: widget.identifier, path: widget.path, election: widget.election),
              current.executable == widget.executable, current.appPath == widget.appPath else { return false }
        return true
    }

    func catalog() async -> (widgets: [ActivityWidget], notice: String?) {
        guard let result = try? await ProcessRunner().run(executable: "/usr/bin/pluginkit", arguments: ["-m", "-A", "-D", "-v"], timeout: 10), result.succeeded else {
            return ([], "The widget catalogue could not be read. Optional widgets may be missing from this review.")
        }
        var seen = Set<String>()
        let widgets = Self.pluginRows(result.stdout).compactMap { row -> ActivityWidget? in
            guard let widget = Self.inspect(identifier: row.identifier, path: row.path, election: row.election), seen.insert(widget.id).inserted else { return nil }
            return widget
        }
        return (widgets, nil)
    }

    /// UI must show the exact extension, consequence and election before calling.
    /// No model-generated command or path is accepted.
    func setElection(_ election: String, for reviewed: ActivityWidget) async throws -> String {
        guard ["ignore", "default", "use"].contains(election), Self.eligible(reviewed) else {
            throw MCPError.message("This widget is protected or changed since the reading. Refresh and review it again.")
        }
        let before = try await ProcessRunner().run(executable: "/usr/bin/pluginkit", arguments: ["-m", "-A", "-D", "-v", "-i", reviewed.identifier], timeout: 10)
        let rows = Self.pluginRows(before.stdout).filter { $0.identifier == reviewed.identifier }
        // Elections affect every installed version with this identifier. Every
        // registered target must be eligible, not just the visible version.
        guard before.succeeded, !rows.isEmpty,
              rows.contains(where: { $0.path == reviewed.path && $0.election == reviewed.election }),
              rows.allSatisfy({ row in
                  guard let widget = Self.inspect(identifier: row.identifier, path: row.path, election: row.election) else { return false }
                  return Self.eligible(widget)
              }) else { throw MCPError.message("The widget registration changed or includes an unreviewable version. Refresh before making a change.") }
        let changed = try await ProcessRunner().run(executable: "/usr/bin/pluginkit", arguments: ["-e", election, "-i", reviewed.identifier], timeout: 10)
        guard changed.succeeded else { throw MCPError.message("macOS did not accept the widget change. Refresh to check its current state.") }
        let after = try await ProcessRunner().run(executable: "/usr/bin/pluginkit", arguments: ["-m", "-A", "-D", "-v", "-i", reviewed.identifier], timeout: 10)
        let verified = Self.pluginRows(after.stdout).filter { $0.identifier == reviewed.identifier }
        guard after.succeeded, !verified.isEmpty, verified.allSatisfy({ $0.election == election }) else {
            throw MCPError.message("A widget change was requested, but its final setting could not be verified. Refresh before retrying.")
        }
        guard election == "ignore" else { return "Widget preference restored. Add the widget again in Edit Widgets if you want it displayed." }
        let exactExecutables = Set(rows.compactMap { Self.inspect(identifier: $0.identifier, path: $0.path, election: $0.election)?.executable })
        let reading = try await ProcessRunner().run(executable: "/bin/ps", arguments: ["-axo", "pid=,ppid=,uid=,%cpu=,rss=,comm="], timeout: 8)
        guard reading.succeeded else { return "Widget disabled. Its running processes could not be checked; refresh to verify activity." }
        for process in BackgroundActivity.parseProcesses(reading.stdout) where process.uid == Int(getuid()) && exactExecutables.contains(process.path) {
            var buffer = [CChar](repeating: 0, count: 4096)
            guard proc_pidpath(process.pid, &buffer, UInt32(buffer.count)) > 0,
                  String(cString: buffer) == process.path else { continue }
            _ = kill(process.pid, SIGTERM)
        }
        return "Widget disabled. Its exact matching processes were asked to quit; refresh to check whether any remain. The owning app and documents were kept."
    }
}
