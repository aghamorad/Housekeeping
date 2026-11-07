// Housekeeping — Clean Up: reading the applications and what they left behind

import AppKit
import Foundation

/// Reads what is installed and what each application left in the home folder.
/// It only reads; moving an app is the cleaner's job, and goes through the same
/// quarantine as everything else.
struct Uninstaller {
    let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home.standardizedFileURL
    }

    // MARK: - The list

    static func installed(progress: @Sendable (String) -> Void) -> [InstalledApp] {
        let uninstaller = Uninstaller()
        let index = uninstaller.leftoverIndex()

        var apps: [InstalledApp] = []
        for directory in uninstaller.applicationFolders() {
            progress("Reading \(directory.lastPathComponent)…")
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            )) ?? []

            for url in contents where url.pathExtension.lowercased() == "app" {
                if Task.isCancelled { break }
                progress("Measuring app " + url.lastPathComponent)
                guard let app = uninstaller.read(url, index: index) else { continue }
                apps.append(app)
            }
        }
        return unambiguousLeftovers(in: apps).sorted { $0.totalSize > $1.totalSize }
    }

    /// A vendor folder containing another installed app's support directory is
    /// shared too, even when the two candidates have different exact paths.
    static func unambiguousLeftovers(in apps: [InstalledApp]) -> [InstalledApp] {
        var owners: [String: Set<String>] = [:]
        for app in apps {
            for item in app.leftovers {
                var current = item.url.standardizedFileURL
                while current.path != "/" {
                    owners[current.path, default: []].insert(app.id)
                    current.deleteLastPathComponent()
                }
            }
        }
        return apps.map { app in
            var copy = app
            copy.leftovers = CleanCandidate.nonOverlapping(app.leftovers.filter {
                owners[$0.url.standardizedFileURL.path, default: []].count == 1
            })
            return copy
        }
    }

    private func applicationFolders() -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    private func read(_ url: URL, index: LeftoverIndex) -> InstalledApp? {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isPackageKey, .contentModificationDateKey, .creationDateKey])
        guard values?.isSymbolicLink != true else { return nil }
        guard let bundle = Bundle(url: url) else { return nil }

        let identifier = bundle.bundleIdentifier
        // Apple's own applications are part of the system, and removing one
        // breaks something the reader cannot see. They are not offered at all.
        if let identifier, identifier.hasPrefix("com.apple.") { return nil }
        if let own = Bundle.main.bundleIdentifier, identifier == own { return nil }
        if url.standardizedFileURL.path == Bundle.main.bundleURL.standardizedFileURL.path { return nil }

        var name = FileManager.default.displayName(atPath: url.path)
        if name.hasSuffix(".app") { name.removeLast(4) }
        guard !name.isEmpty else { return nil }

        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let size = CleanerScanner.size(of: url)
        let leftovers = index.leftovers(for: name, identifier: identifier)

        return InstalledApp(
            url: url,
            name: name,
            bundleIdentifier: identifier,
            version: version,
            size: size,
            leftovers: leftovers,
            modifiedDate: values?.contentModificationDate,
            createdDate: values?.creationDate
        )
    }

    // MARK: - Leftovers

    /// Every candidate home-folder location, read once, so that a hundred apps
    /// do not each list the same folder.
    struct LeftoverIndex {
        struct Entry {
            let url: URL
            let name: String
            let base: String
        }

        var entries: [Entry] = []

        func leftovers(for appName: String, identifier: String?) -> [CleanCandidate] {
            let lowerName = appName.lowercased()
            var found: [CleanCandidate] = []
            var seen = Set<String>()

            for entry in entries {
                if Task.isCancelled { break }
                guard matches(entry, appName: appName, lowerName: lowerName, identifier: identifier) else { continue }
                guard seen.insert(entry.url.path).inserted else { continue }
                let size = CleanerScanner.size(of: entry.url)
                guard size > 0 else { continue }
                found.append(CleanCandidate(
                    url: entry.url,
                    size: size,
                    modified: CleanerScanner.modified(entry.url),
                    category: .uninstall,
                    name: entry.name,
                    detail: "Related to installed app \(appName): \(entry.base). Matched by \(identifier.map { entry.name.lowercased().contains($0.lowercased()) ? "bundle identifier " + $0 : "application name" } ?? "application name"). Ownership is inferred; this may contain personal or shared data."
                ))
            }
            return found.sorted { $0.size > $1.size }
        }

        private func matches(_ entry: Entry, appName: String, lowerName: String, identifier: String?) -> Bool {
            let lower = entry.name.lowercased()
            if let identifier {
                let id = identifier.lowercased()
                if lower == id { return true }
                if lower == id + ".plist" { return true }
                if lower.hasPrefix(id + ".") { return true }
                if lower == "group." + id { return true }
                if lower.hasSuffix("." + id) { return true }

            }
            // A name match is weaker evidence, so it only counts where macOS
            // names the folder after the application itself.
            if entry.base == "Application Support" || entry.base == "Logs" {
                if lower == lowerName { return true }
            }
            return false
        }
    }

    private func leftoverIndex() -> LeftoverIndex {
        let roots: [String] = [
            "Library/Caches",
            "Library/Preferences",
            "Library/Preferences/ByHost",
            "Library/Saved Application State",
            "Library/Application Support",
            "Library/Application Support/CrashReporter",
            "Library/Logs",
            "Library/Containers",
            "Library/Group Containers",
            "Library/WebKit",
            "Library/HTTPStorages",
            "Library/Cookies",
            "Library/LaunchAgents",
            "Library/Application Scripts"
        ]

        var index = LeftoverIndex()
        for relative in roots {
            let directory = home.appendingPathComponent(relative, isDirectory: true)
            let children = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
                options: []
            )) ?? []
            let base = (relative as NSString).lastPathComponent
            for child in children {
                let childValues = try? child.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard childValues?.isSymbolicLink != true else { continue }
                if child.lastPathComponent == ".DS_Store" { continue }
                if child.lastPathComponent == "Housekeeping" { continue }
                index.entries.append(.init(url: child, name: child.lastPathComponent, base: base))
            }
        }

        // `Application Support` is shallow on purpose: one more level catches the
        // vendor folder that holds an app's data, without walking a whole tree.
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let vendors = (try? FileManager.default.contentsOfDirectory(
            at: support,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for vendor in vendors {
            let values = try? vendor.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            let children = (try? FileManager.default.contentsOfDirectory(
                at: vendor,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for child in children {
                index.entries.append(.init(url: child, name: child.lastPathComponent, base: "Application Support"))
            }
        }

        return index
    }

    /// True when the application is open. An open app cannot be moved without
    /// macOS putting it back or refusing outright, so the screen says so first.
    static func isRunning(_ app: InstalledApp) -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL ||
            (app.bundleIdentifier != nil && $0.bundleIdentifier == app.bundleIdentifier)
        }
    }

    static func isRemovableApp(_ url: URL, home: URL) -> Bool {
        let app = url.standardizedFileURL
        return isRemovableAppDestination(app, home: home) && isThirdPartyAppBundle(app)
    }

    static func isRemovableAppDestination(_ url: URL, home: URL) -> Bool {
        let app = url.standardizedFileURL
        let folders = ["/Applications", "/Applications/Utilities", home.appendingPathComponent("Applications").path]
        return app.pathExtension.lowercased() == "app" && folders.contains(app.deletingLastPathComponent().path)
            && app != Bundle.main.bundleURL.standardizedFileURL
    }

    static func isThirdPartyAppBundle(_ app: URL) -> Bool {
        guard app.resolvingSymlinksInPath() == app.standardizedFileURL,
              let bundle = Bundle(url: app), let identifier = bundle.bundleIdentifier,
              !identifier.hasPrefix("com.apple."), identifier != Bundle.main.bundleIdentifier else { return false }
        return true
    }
}

/// A short-lived, system-authorized operation on one reviewed app bundle.
/// Foundation does the move/delete; arguments are encoded, never executable text.
/// No helper is installed and no ownership or access permissions are rewritten.
enum AppFileAuthorization {
    static func isPermissionError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(error.code) { return true }
        if error.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(error.code) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error { return isPermissionError(underlying) }
        return false
    }

    static func javaScript(source: URL, destination: URL?) throws -> String {
        let arguments = try JSONSerialization.data(withJSONObject: [source.path, destination?.path ?? ""])
        let json = String(decoding: arguments, as: UTF8.self)
        return """
        ObjC.import('Foundation');
        var args = \(json), fm = $.NSFileManager.defaultManager, error = Ref();
        if (args[1] && fm.fileExistsAtPath(args[1])) throw Error('The destination already exists. Nothing was overwritten.');
        var ok = args[1] ? fm.moveItemAtPathToPathError(args[0], args[1], error) : fm.removeItemAtPathError(args[0], error);
        if (!ok) throw Error(ObjC.unwrap(error[0].localizedDescription));
        """
    }

    static func appleScript(source: URL, destination: URL?) throws -> String {
        let javascript = try javaScript(source: source, destination: destination)
        let command = "/usr/bin/osascript -l JavaScript -e " + shellQuote(javascript)
        let literal = command.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "do shell script \"\(literal)\" with administrator privileges"
    }

    static func run(source: URL, destination: URL?) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", try appleScript(source: source, destination: destination)]
        // Suppress raw AppleScript errors; the UI gives a useful recovery message.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(120)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning {
            process.terminate()
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw CleanupError.restoreError("The permission request timed out. Try again and approve the macOS prompt.")
        }
        guard process.terminationStatus == 0 else {
            throw CleanupError.restoreError("macOS did not approve this change. Try again and approve the administrator prompt. If access is still blocked, reveal the app in Finder to check whether it is locked or managed.")
        }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
