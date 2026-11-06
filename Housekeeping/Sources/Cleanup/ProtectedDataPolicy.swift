// Housekeeping — the line between junk and something you cannot get back

import Foundation

/// Where a move came from. The same folder can be junk on one path and
/// irreplaceable on another, so the answer is not a property of the path — it is
/// a property of who is asking.
enum CleanupIntent: Sendable {
    /// A sweep: a shelf offered hundreds of things at once. Nothing on this path
    /// may be something the reader would have to re-record, re-download or
    /// remember, because a sweep is answered with one button and skimmed.
    case sweep
    /// A removal the reader named item by item, such as uninstalling one app
    /// and choosing which of its leftovers go with it. Containers are allowed
    /// here and only here.
    case explicitRemoval
}

/// What Housekeeping will not move on a sweep, and why.
///
/// This is the second of three gates. The scanners decide what to offer, this
/// decides what a sweep may carry, and `CleanupEngine.refusalToMove` is the last
/// word for any caller at all — including ones written after this file. It
/// exists because a cleaner's promise is not "it can be downloaded again"; it is
/// "you will not miss it". A model library fails that promise, a Voice Memo
/// fails it, and a Notes database fails it.
///
/// The test that separates them is not size and not the folder's name. It is
/// whether the thing inside would have to be made again by a person.
enum ProtectedDataPolicy {
    enum Verdict: Equatable, Sendable {
        case allowed
        case refused(String)
    }

    /// Places a sweep may never touch, relative to home. A move of the folder
    /// itself or of anything beneath it is refused.
    static let sweepProtected: [(path: String, why: String)] = [
        ("Library/Group Containers",
         "an app group container — shared application data such as Voice Memos recordings, Notes and Contacts"),
        ("Library/Containers",
         "a sandboxed application container, which holds that application's own data"),
        ("Library/Application Support",
         "application support data an app expects to find again"),
        ("Library/Mobile Documents",
         "iCloud Drive"),
        ("Library/Mail", "Mail's mailbox data"),
        ("Library/Messages", "Messages history"),
        ("Library/Calendars", "calendar data"),
        ("Library/Photos", "the Photos library"),
        ("Library/Safari", "Safari's history and bookmarks"),
        ("Library/Keychains", "keychain items"),
        ("Library/Accounts", "account credentials"),
        ("Library/IdentityServices", "signed-in account identities"),
        ("Library/CloudStorage", "cloud storage providers"),
        ("Library/Shortcuts", "the reader's shortcuts"),
        ("Documents", "documents written by a person"),
        ("Desktop", "files on the Desktop"),
        ("Music", "the music library"),
        ("Pictures", "the photo library"),
        ("Movies", "the reader's video"),
        ("Library/Metadata/CoreSpotlight", "the Spotlight index")
    ]

    /// Extensions that mean a person made this, or a person would miss it.
    /// Images are deliberately absent: a cache full of thumbnails is still a
    /// cache, and refusing on sight of a PNG would make the policy useless.
    static let userDataExtensions: Set<String> = [
        // Sound
        "m4a", "mp3", "caf", "aiff", "aif", "wav", "flac", "qta", "aac", "opus",
        // Picture and film, only in the formats a camera or an edit produces
        "mov", "mp4", "m4v", "heic", "dng", "raw", "cr2", "nef", "psd", "indd", "aep",
        // Documents
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers",
        "key", "rtf", "rtfd", "txt", "md", "tex", "epub", "mobi", "azw3",
        "csv", "odt", "ods", "fountain", "scriv",
        // Databases
        "sqlite", "sqlite3", "db", "realm"
    ]

    /// The verdict for one path on a sweep.
    static func verdict(
        for url: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        intent: CleanupIntent = .sweep
    ) -> Verdict {
        guard intent == .sweep else { return .allowed }

        let homePath = home.standardizedFileURL.path
        let path = url.standardizedFileURL.path

        // Model storage is refused wherever it lives, before anything is read.
        if ModelStorageGuard.isModelLibrary(url, home: home) {
            return .refused("it holds downloaded AI models, which cost hours to fetch again")
        }

        // Outside the home folder: an application bundle is Uninstall Apps'
        // business, and the system's own folders are nobody's.
        for root in ["/Applications/", "/System/", "/Library/", "/usr/", "/bin/", "/sbin/"] where path.hasPrefix(root) {
            return .refused("it is part of the system or an installed application — Uninstall Apps is where an application is removed")
        }
        guard path.hasPrefix(homePath + "/") else { return .allowed }
        let relative = String(path.dropFirst(homePath.count + 1))

        // An application bundle is Uninstall Apps' business. Tested after the
        // cache check below, because a cache folder may legitimately be called
        // something.app and is still a cache.
        if path.hasSuffix(".app"), !isCacheLocation(relative) {
            return .refused("it is an application — Uninstall Apps is where an application is removed")
        }

        for entry in sweepProtected where relative == entry.path || relative.hasPrefix(entry.path + "/") {
            // Application Support holds one thing this app is allowed to sweep:
            // the Caches folder inside it, which is a cache in all but name.
            if entry.path == "Library/Application Support",
               relative.hasPrefix("Library/Application Support/Caches/") {
                continue
            }
            return .refused("it is \(entry.why)")
        }

        // The content rule is for whole folders. A file the reader ticked by
        // name is their decision and the shelf already shows its size; a folder
        // swept in one click is where a month of recordings disappears.
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        if isDirectory.boolValue, !isCacheLocation(relative), containsUserData(url) {
            return .refused("it contains files a person made — recordings, documents or a database — rather than something an app can rebuild")
        }

        return .allowed
    }

    /// A place whose whole purpose is holding something disposable. Inside one
    /// of these the content rule does not apply: a download cache full of PDFs
    /// is still a download cache.
    static func isCacheLocation(_ relative: String) -> Bool {
        let cacheMarkers = [
            "Library/Caches/", "Caches/", ".cache/", "Library/Logs/", "__pycache__/",
            "node_modules/", "/tmp/", "Library/Saved Application State/"
        ]
        let padded = relative + "/"
        return cacheMarkers.contains { padded.hasPrefix($0) || padded.contains("/" + $0) }
    }

    /// Whether a tree holds anything in `userDataExtensions`.
    ///
    /// Bounded in depth and entries, and it stops at the first hit: this runs
    /// during a scan over hundreds of candidates and must not become a walk of
    /// the disk. Caches are skipped outright — a download cache full of PDFs is
    /// still a download cache.
    static func containsUserData(_ url: URL, depthLimit: Int = 8, budget: Int = 20_000) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return userDataExtensions.contains(url.pathExtension.lowercased())
        }
        if !isDirectory.boolValue {
            return userDataExtensions.contains(url.pathExtension.lowercased())
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
        guard let walk = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return false }

        let rootDepth = url.standardizedFileURL.pathComponents.count
        var remaining = budget
        while let entry = walk.nextObject() as? URL {
            remaining -= 1
            if remaining <= 0 { return false }
            if entry.standardizedFileURL.pathComponents.count - rootDepth > depthLimit {
                walk.skipDescendants()
                continue
            }
            if userDataExtensions.contains(entry.pathExtension.lowercased()) { return true }
        }
        return false
    }
}
