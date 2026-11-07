// Housekeeping — Clean Up: the things the cleaner offers, and how they are grouped

import Foundation
import AppKit

/// The six shelves the cleaner puts its findings on. Every one of them is a
/// thing a person can recognise without knowing where macOS keeps it: junk the
/// system rebuilds, things a developer's tools rebuild, installers that have
/// already been used, files that are merely big, apps, and the Trash.
enum CleanCategory: String, CaseIterable, Identifiable, Sendable {
    case everydayJunk
    case orphans
    case developerLeftovers
    case installers
    case largeFiles
    case uninstall
    case trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everydayJunk: return "Everyday Junk"
        case .orphans: return "Orphaned Leftovers"
        case .developerLeftovers: return "Developer Leftovers"
        case .installers: return "Installers"
        case .largeFiles: return "Big & Old Files"
        case .uninstall: return "Uninstall Apps"
        case .trash: return "Trash"
        }
    }

    var systemImage: String {
        switch self {
        case .everydayJunk: return "sparkles"
        case .orphans: return "person.crop.circle.badge.minus"
        case .developerLeftovers: return "hammer"
        case .installers: return "shippingbox"
        case .largeFiles: return "doc.zipper"
        case .uninstall: return "xmark.app"
        case .trash: return "trash"
        }
    }

    /// One sentence, in the sidebar, saying what the shelf is for.
    var subtitle: String {
        switch self {
        case .everydayJunk:
            return "Caches, logs and temporary files that apps rebuild on their own."
        case .orphans:
            return "Support folders, caches, and containers left by apps already uninstalled."
        case .developerLeftovers:
            return "node_modules, build folders and download caches from coding."
        case .installers:
            return "Downloaded disk images and installer packages."
        case .largeFiles:
            return "Large files that may have been forgotten."
        case .uninstall:
            return "Applications and their related support files."
        case .trash:
            return "What is already in the Trash. Emptying it cannot be undone."
        }
    }

    /// The longer explanation at the top of the shelf.
    var explanation: String {
        switch self {
        case .everydayJunk:
            return "These are the folders apps use as scratch space. macOS and the apps rebuild them when they need them again, so an app may need to rebuild or download data on its next launch. Cached offline content and saved window state may be lost; inspect anything you still use."
        case .orphans:
            return "When you drag an app to the Trash, macOS leaves behind its preferences, container sandboxes, and application support folders in ~/Library. None of the applications that created these files are installed on your Mac anymore. All moved files are protected in Quarantine."
        case .developerLeftovers:
            return "These are things a build or a package manager made. Every one of them can be made again from the project's source, usually by running the same command that made it the first time. Only folders that can be proved to belong to a project are listed."
        case .installers:
            return "These are downloaded disk images and installer packages. Housekeeping has not verified whether you ran them or can download them again. Check before moving one. Quarantine keeps a recoverable copy on this disk."
        case .largeFiles:
            return "These are simply the biggest files on your Mac. Size says nothing about importance, so nothing here is ticked for you — open one before deciding. Everything moved can be put back from Quarantine."
        case .uninstall:
            return "Inspect an app and expand its related files. These may include settings, documents, accounts, or shared vendor data. Matched related files are included with the app. Uncheck anything you want to keep, then review the exact paths before uninstalling. Quarantine can restore moved items."
        case .trash:
            return "The Trash is the one place in Housekeeping where something can be lost for good. Emptying it permanently deletes what is in it, and there is no Quarantine copy afterwards."
        }
    }

    var isDestructive: Bool { self == .trash }
}

/// One thing the cleaner can move. Values only, so the whole scan can cross
/// back from the background thread it ran on.
/// What it costs to get something back after it is moved.
///
/// "Safe to delete" and "free to delete" are different promises. A cache the app
/// rebuilds from local data is both. A download cache is only the first: it comes
/// back over the network, which on a throttled line can be hours or nothing at
/// all. The reader is told which is which before anything moves.
enum RebuildCost: Equatable, Sendable {
    /// Made again from what is already on this Mac.
    case instant
    /// Has to be fetched again. The string says by whom and when.
    case reDownload(String)

    var isDownload: Bool {
        if case .reDownload = self { return true }
        return false
    }

    var explanation: String? {
        if case .reDownload(let why) = self { return why }
        return nil
    }
}

struct CleanCandidate: Identifiable, Equatable, Sendable {
    /// The path is the identity: two scans of the same disk name the same things.
    var id: String { url.path }

    let url: URL
    let size: Int64
    let modified: Date?
    let category: CleanCategory
    /// A short name — "node_modules", "Safari", "Xcode_16.dmg".
    let name: String
    /// One sentence saying why this is safe, or what to check first.
    let detail: String
    /// Whether removing this costs bandwidth to undo.
    var rebuild: RebuildCost = .instant
    var isSelected: Bool = false
}

extension CleanCandidate {
    /// A parent already contains its descendants. Offer it once so displayed
    /// totals and the eventual move plan cannot count the same data twice.
    static func nonOverlapping(_ candidates: [CleanCandidate]) -> [CleanCandidate] {
        let ordered = candidates.sorted {
            if $0.url.path.count != $1.url.path.count { return $0.url.path.count < $1.url.path.count }
            if $0.id != $1.id { return $0.id < $1.id }
            return $0.category.rawValue < $1.category.rawValue
        }
        var accepted: [CleanCandidate] = []
        var paths = Set<String>()
        for candidate in ordered {
            let path = candidate.url.standardizedFileURL.path
            if paths.contains(path) { continue }
            var parent = candidate.url.standardizedFileURL.deletingLastPathComponent()
            var overlaps = false
            while parent.path != "/" {
                if paths.contains(parent.path) { overlaps = true; break }
                parent.deleteLastPathComponent()
            }
            if !overlaps { accepted.append(candidate); paths.insert(path) }
        }
        return accepted
    }
}

/// An application as the uninstall shelf sees it: the bundle plus everything
/// found beside it in the home folder.
struct InstalledApp: Identifiable, Equatable, Sendable {
    var id: String { url.path }

    let url: URL
    let name: String
    let bundleIdentifier: String?
    let version: String?
    let size: Int64
    var leftovers: [CleanCandidate]
    var isSelected: Bool = false
    var modifiedDate: Date? = nil
    var createdDate: Date? = nil

    var leftoverSize: Int64 { leftovers.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { size + leftoverSize }

    /// True when the process owning this bundle is running right now. An app
    /// that is running should be quit before it is moved.
    var isRunning: Bool { Uninstaller.isRunning(self) }
}

/// Rich sorting options for application inventories (Uninstaller).
public enum AppSortOption: String, CaseIterable, Identifiable, Sendable {
    case sizeDescending = "Size (Largest First)"
    case sizeAscending = "Size (Smallest First)"
    case nameAscending = "Name (A–Z)"
    case nameDescending = "Name (Z–A)"
    case modifiedNewest = "Recently Modified"
    case modifiedOldest = "Oldest Modified"
    case installedNewest = "Recently Installed"
    case installedOldest = "Oldest Installed"

    public var id: String { rawValue }

    public var shortLabel: String {
        switch self {
        case .sizeDescending: return "Largest"
        case .sizeAscending: return "Smallest"
        case .nameAscending: return "A → Z"
        case .nameDescending: return "Z → A"
        case .modifiedNewest: return "Recent Mod"
        case .modifiedOldest: return "Old Mod"
        case .installedNewest: return "Recent Add"
        case .installedOldest: return "Old Add"
        }
    }

    public var systemImage: String {
        switch self {
        case .sizeDescending: return "arrow.down.circle"
        case .sizeAscending: return "arrow.up.circle"
        case .nameAscending: return "textformat.size.smaller"
        case .nameDescending: return "textformat.size.larger"
        case .modifiedNewest: return "clock.arrow.circlepath"
        case .modifiedOldest: return "clock"
        case .installedNewest: return "sparkles"
        case .installedOldest: return "calendar"
        }
    }
}

/// What the Trash holds, measured but not listed item by item.
struct TrashSummary: Equatable, Sendable {
    var count: Int = 0
    var size: Int64 = 0
    var unreadable: Bool = false

    var isEmpty: Bool { count == 0 }
}

struct CleanerSnapshot: Sendable {
    let candidates: [CleanCandidate]
    let apps: [InstalledApp]
    let trash: TrashSummary
    /// Problems worth mentioning but not worth stopping for — a folder that
    /// could not be read, a Trash that could not be counted.
    let notes: [String]
}

/// Shared ordering for measured paths. Unknown dates always follow known dates.
enum FileOrder: String, CaseIterable, Identifiable {
    case largest = "Largest first"
    case smallest = "Smallest first"
    case name = "Name A–Z"
    case oldest = "Oldest modified"
    case newest = "Newest modified"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .largest: return "Largest"
        case .smallest: return "Smallest"
        case .name: return "Name"
        case .oldest: return "Oldest"
        case .newest: return "Newest"
        }
    }

    func precedes(name lhs: String, size leftSize: Int64, modified leftDate: Date?, path leftPath: String,
                  name rhs: String, size rightSize: Int64, modified rightDate: Date?, path rightPath: String) -> Bool {
        switch self {
        case .largest, .smallest:
            if leftSize != rightSize { return self == .largest ? leftSize > rightSize : leftSize < rightSize }
        case .oldest, .newest:
            if let leftDate, let rightDate, leftDate != rightDate {
                return self == .oldest ? leftDate < rightDate : leftDate > rightDate
            }
            if (leftDate == nil) != (rightDate == nil) { return leftDate != nil }
        case .name: break
        }
        let comparison = lhs.localizedStandardCompare(rhs)
        return comparison == .orderedSame ? leftPath < rightPath : comparison == .orderedAscending
    }
}

/// Retains the reviewed plan and icons even after their bundles leave Applications.
/// The activity screen survives navigation, and only engine events advance its rows.
struct UninstallSession {
    let apps: [InstalledApp]
    let icons: [String: NSImage]
    var event = UninstallProgress(phase: .checking)
    var outcomes: [String: Bool] = [:]
    var messages: [String: String] = [:]
    var isFinished = false
    var interruption: String?

    init(apps: [InstalledApp]) {
        self.apps = apps
        icons = Dictionary(uniqueKeysWithValues: apps.map {
            ($0.id, NSWorkspace.shared.icon(forFile: $0.id))
        })
    }

    var total: Int { event.total > 0 ? event.total : apps.reduce(0) { $0 + 1 + $1.leftovers.count } }
    var removedCount: Int { outcomes.values.filter { $0 }.count }
    var failedCount: Int { outcomes.values.filter { !$0 }.count }
    var removedApps: Int { apps.filter { outcomes[$0.id] == true }.count }
    var removedRelated: Int { removedCount - removedApps }
    var movedSize: Int64 {
        apps.reduce(0) { total, app in
            total + (outcomes[app.id] == true ? app.size : 0)
                + app.leftovers.filter { outcomes[$0.id] == true }.reduce(0) { $0 + $1.size }
        }
    }
    var needsAttention: Bool { failedCount > 0 || interruption != nil }
    var activeApp: InstalledApp? {
        apps.first { app in app.id == event.path || app.leftovers.contains { $0.id == event.path } }
            ?? apps.first
    }
    var headline: String {
        if isFinished {
            if interruption != nil { return "Removal stopped" }
            return needsAttention ? "Some items need attention" : "Uninstall complete"
        }
        switch event.phase {
        case .checking: return "Checking your selection…"
        case .preparing: return "Preparing a recovery record…"
        case .permission: return "Waiting for macOS permission"
        case .moving: return "Uninstalling \(activeApp?.name ?? "apps")…"
        case .recording, .finished: return "Saving removal results…"
        }
    }

    mutating func receive(_ event: UninstallProgress) {
        self.event = event
        if let path = event.path, let succeeded = event.succeeded {
            outcomes[path] = succeeded
            messages[path] = event.message
        }
    }

    mutating func finish(result: RepairMoveResult) {
        for move in result.moves {
            outcomes[move.path] = move.succeeded
            messages[move.path] = move.message
        }
        isFinished = true
    }

    mutating func finish(error: String) {
        interruption = error
        isFinished = true
    }
}
