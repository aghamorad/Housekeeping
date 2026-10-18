// Housekeeping — Clean Up: the things the cleaner offers, and how they are grouped

import Foundation

/// The six shelves the cleaner puts its findings on. Every one of them is a
/// thing a person can recognise without knowing where macOS keeps it: junk the
/// system rebuilds, things a developer's tools rebuild, installers that have
/// already been used, files that are merely big, apps, and the Trash.
enum CleanCategory: String, CaseIterable, Identifiable, Sendable {
    case everydayJunk
    case developerLeftovers
    case installers
    case largeFiles
    case uninstall
    case trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everydayJunk: return "Everyday Junk"
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
        case .developerLeftovers: return "hammer"
        case .installers: return "shippingbox"
        case .largeFiles: return "doc.zipper"
        case .uninstall: return "app.badge.minus"
        case .trash: return "trash"
        }
    }

    /// One sentence, in the sidebar, saying what the shelf is for.
    var subtitle: String {
        switch self {
        case .everydayJunk:
            return "Caches, logs and temporary files that apps rebuild on their own."
        case .developerLeftovers:
            return "node_modules, build folders and download caches from coding."
        case .installers:
            return "Disk images and installers you have already run."
        case .largeFiles:
            return "Large files that may have been forgotten."
        case .uninstall:
            return "An app together with the files it left behind."
        case .trash:
            return "What is already in the Trash. Emptying it cannot be undone."
        }
    }

    /// The longer explanation at the top of the shelf.
    var explanation: String {
        switch self {
        case .everydayJunk:
            return "These are the folders apps use as scratch space. macOS and the apps rebuild them when they need them again, so removing one costs a little time on the next launch and nothing else. Nothing here is a document of yours."
        case .developerLeftovers:
            return "These are things a build or a package manager made. Every one of them can be made again from the project's source, usually by running the same command that made it the first time. Only folders that can be proved to belong to a project are listed."
        case .installers:
            return "An installer you have already used is a copy of something you can download again. Moving it to Quarantine frees the space without losing the app that was installed."
        case .largeFiles:
            return "These are simply the biggest files on your Mac. Size says nothing about importance, so nothing here is ticked for you — open one before deciding. Everything moved can be put back from Quarantine."
        case .uninstall:
            return "Ticking an app moves the app and the files it left behind into Quarantine together. Nothing is deleted: if you change your mind, Quarantine can put every part of it back."
        case .trash:
            return "The Trash is the one place in Housekeeping where something can be lost for good. Emptying it permanently deletes what is in it, and there is no Quarantine copy afterwards."
        }
    }

    var isDestructive: Bool { self == .trash }
}

/// One thing the cleaner can move. Values only, so the whole scan can cross
/// back from the background thread it ran on.
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
    var isSelected: Bool = false
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

    var leftoverSize: Int64 { leftovers.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { size + leftoverSize }

    /// True when the process owning this bundle is running right now. An app
    /// that is running should be quit before it is moved.
    var isRunning: Bool { Uninstaller.isRunning(self) }
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
