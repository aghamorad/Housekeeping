// Housekeeping — OrphanScanner: detects leftover folders from uninstalled applications

import Foundation
import AppKit

struct OrphanScanner: Sendable {
    static func scan(home: URL = FileManager.default.homeDirectoryForCurrentUser, progress: @escaping @Sendable (String) -> Void = { _ in }) -> [CleanCandidate] {
        progress("Scanning for orphaned app leftovers…")

        // 1. Gather all currently installed application bundle identifiers and display names
        var installedIdentifiers = Set<String>()
        var installedNames = Set<String>()

        let appDirs = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]

        for dir in appDirs {
            guard let contents = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for appURL in contents where appURL.pathExtension.lowercased() == "app" {
                if let bundle = Bundle(url: appURL) {
                    if let id = bundle.bundleIdentifier?.lowercased() {
                        installedIdentifiers.insert(id)
                    }
                }
                let name = appURL.deletingPathExtension().lastPathComponent.lowercased()
                installedNames.insert(name)
            }
        }

        // 2. System and framework whitelists (items that should NEVER be treated as orphans)
        let systemPrefixes = [
            "com.apple.", "apple", "system", "quick look", "addressbook", "callhistory",
            "messages", "mail", "safari", "cloudkit", "preferences", "coredata",
            "keychains", "accounts", "screentime", "feedbackassistant", "shortcuts",
            "spotlight", "siri", "photos", "music", "podcasts", "tv", "books", "notes",
            "reminders", "calendar", "contacts", "maps", "weather", "stocks", "news",
            "housekeeping", "benignmonster", "google", "microsoft", "adobe", "dropbox"
        ]

        let searchRoots: [(URL, String)] = [
            (home.appendingPathComponent("Library/Application Support", isDirectory: true), "Orphaned Application Support data from deleted app"),
            (home.appendingPathComponent("Library/Containers", isDirectory: true), "Orphaned app container sandbox from deleted app"),
            (home.appendingPathComponent("Library/Group Containers", isDirectory: true), "Orphaned app group container from deleted app"),
            (home.appendingPathComponent("Library/HTTPStorages", isDirectory: true), "Orphaned network storage and cookies from deleted app"),
            (home.appendingPathComponent("Library/WebKit", isDirectory: true), "Orphaned WebKit website data from deleted app")
        ]

        var orphans: [CleanCandidate] = []
        let fm = FileManager.default

        // 3. Known application and tool user home caches when parent app is deleted
        let homeToolChecks: [(name: String, appName: String, path: URL)] = [
            (name: ".lmstudio", appName: "LM Studio", path: home.appendingPathComponent(".lmstudio", isDirectory: true)),
            (name: ".comfyui", appName: "ComfyUI", path: home.appendingPathComponent(".comfyui", isDirectory: true)),
            (name: ".cache/comfyui", appName: "ComfyUI", path: home.appendingPathComponent(".cache/comfyui", isDirectory: true))
        ]

        for check in homeToolChecks {
            guard fm.fileExists(atPath: check.path.path) else { continue }
            let lowerApp = check.appName.lowercased()
            if !installedNames.contains(lowerApp) && !installedIdentifiers.contains(where: { $0.contains(lowerApp) }) {
                let size = CleanerScanner.size(of: check.path)
                guard size > 4096 else { continue }
                let modDate = (try? check.path.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                orphans.append(CleanCandidate(
                    url: check.path,
                    size: size,
                    modified: modDate,
                    category: .orphans,
                    name: check.name,
                    detail: "\(check.name) — Leftover folder from uninstalled \(check.appName)"
                ))
            }
        }

        for (rootURL, reason) in searchRoots {
            guard fm.fileExists(atPath: rootURL.path) else { continue }
            guard let items = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }

            for item in items {
                let name = item.lastPathComponent
                let lowerName = name.lowercased()

                // Apple's own data is never an orphan, whatever it is wrapped in.
                // This needs saying twice because macOS puts a wrapper on its own
                // group containers — `group.com.apple.VoiceMemos.shared`,
                // `5HD2ARTBFS.com.canva.affinity`, `UBF8T346G9.Office` — and a
                // test for a leading `com.apple.` misses every one of them. That
                // is how Voice Memos recordings and the Notes database came to be
                // offered as the leftovers of an app that was never uninstalled.
                if lowerName.contains("com.apple.") {
                    continue
                }

                // The same names with the wrapper taken off, so the prefix list
                // below and the installed-app match see the identifier rather
                // than the container's decoration.
                let matchName = OrphanScanner.matchName(name)

                // Skip system and whitelisted prefixes
                if systemPrefixes.contains(where: { matchName.hasPrefix($0) || matchName == $0 }) {
                    continue
                }

                // A model library is not a leftover, even when the app that
                // downloaded it is gone. The weights cost hours to fetch again,
                // and they are described on the Local Models screen rather than
                // on a shelf of things to sweep.
                if ModelStorageGuard.isModelLibrary(item, home: home) {
                    continue
                }

                // Check if name is or contains a known installed bundle ID
                if installedIdentifiers.contains(matchName) { continue }
                if installedIdentifiers.contains(where: { matchName.contains($0) || $0.contains(matchName) }) { continue }

                // Check if name matches any installed application name
                if installedNames.contains(matchName) { continue }
                if installedNames.contains(where: { matchName.contains($0) || $0.contains(matchName) }) { continue }

                // Also check with NSWorkspace if macOS can locate an app for this
                // identifier. The unwrapped name is tried as well, because that is
                // the one a bundle would actually register.
                if matchName.contains(".") && NSWorkspace.shared.urlForApplication(withBundleIdentifier: matchName) != nil {
                    continue
                }
                if lowerName.contains(".") && NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) != nil {
                    continue
                }

                // Measure size
                let size = CleanerScanner.size(of: item)
                // Filter out zero-byte or tiny empty folders (< 4KB) unless relevant
                guard size > 4096 else { continue }

                let modDate = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

                let cleanName: String
                if lowerName.contains(".") {
                    let parts = name.split(separator: ".")
                    cleanName = parts.last.map(String.init) ?? name
                } else {
                    cleanName = name
                }

                orphans.append(CleanCandidate(
                    url: item,
                    size: size,
                    modified: modDate,
                    category: .orphans,
                    name: cleanName,
                    detail: "\(name) — \(reason)"
                ))
            }
        }

        return orphans.sorted { $0.size > $1.size }
    }

    /// The identifier a container name really means, with the wrappers macOS puts
    /// round its own group containers taken off — a leading `group.`, a
    /// ten-character team id, or both:
    ///
    ///     group.com.apple.notes            → com.apple.notes
    ///     3L68KQB4HG.group.com.readdle…    → com.readdle…
    ///
    /// Without this, every match against the installed-app list and the system
    /// prefix list is made against decoration and quietly fails.
    static func matchName(_ name: String) -> String {
        var working = name.lowercased()
        while true {
            if working.hasPrefix("group.") {
                working.removeFirst("group.".count)
                continue
            }
            let parts = working.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2, parts[0].count == 10, parts[0].allSatisfy({ $0.isLetter || $0.isNumber }) {
                working = String(parts[1])
                continue
            }
            break
        }
        return working
    }
}
