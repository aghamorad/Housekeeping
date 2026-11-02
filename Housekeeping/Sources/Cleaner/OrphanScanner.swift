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

        for (rootURL, reason) in searchRoots {
            guard fm.fileExists(atPath: rootURL.path) else { continue }
            guard let items = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey], options: [.skipsHiddenFiles]) else { continue }

            for item in items {
                let name = item.lastPathComponent
                let lowerName = name.lowercased()

                // Skip system and whitelisted prefixes
                if systemPrefixes.contains(where: { lowerName.hasPrefix($0) || lowerName == $0 }) {
                    continue
                }

                // Check if name is or contains a known installed bundle ID
                if installedIdentifiers.contains(lowerName) { continue }
                if installedIdentifiers.contains(where: { lowerName.contains($0) || $0.contains(lowerName) }) { continue }

                // Check if name matches any installed application name
                if installedNames.contains(lowerName) { continue }
                if installedNames.contains(where: { lowerName.contains($0) || $0.contains(lowerName) }) { continue }

                // Also check with NSWorkspace if macOS can locate an app for this identifier
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
}
