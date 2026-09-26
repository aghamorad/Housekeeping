import Foundation

// Housekeeping — Update exceptions
//
// The same idea as the cleanup side's left-alone list, applied to updating: a way
// for the reader to say "leave this one" and have that stick across launches. It
// is deliberately the same shape — a JSON file in the application support folder,
// entries with a key and the date they were added, an atomic write, and the same
// behaviour when the file cannot be read.
//
// What it is kept most carefully from becoming is a second, quieter safety system.
// It can only ever make Housekeeping do less: an excepted row is never ticked and
// never upgraded. There is no key that means "update this without asking". A file
// that has been corrupted is moved aside rather than overwritten, and the move is
// reported, because silently discarding a reader's decisions to start fresh would
// be exactly the kind of quiet loss this app exists not to do.

/// The reader's list of things to stop offering an update for.
final class UpdateExceptions {
    struct Entry: Codable, Identifiable, Equatable {
        /// The bundle identifier, or the path when the thing has no identifier.
        /// Stable across a reinstall in place, which is what makes an entry keep
        /// meaning the same thing after a version bump.
        let key: String
        /// How the key should be read: "identifier" or "path". Stored rather than
        /// derived so the settings screen can say which without guessing.
        let kind: String
        let added: Date

        var id: String { key }

        var name: String {
            if kind == "path" { return (key as NSString).lastPathComponent }
            return key
        }

        var displayKey: String {
            kind == "path" ? URL(fileURLWithPath: key).homeAbbreviatedPath : key
        }
    }

    /// Where the list lives beside the others. Named for the feature, not the app,
    /// so the folder reads plainly.
    static func defaultFileURL(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        CleanupEngine.supportDirectoryURL(homeDirectory: homeDirectory)
            .appendingPathComponent("UpdateExceptions.json")
    }

    private(set) var entries: [Entry] = []
    /// Set when an existing file could not be read and was moved aside. The screen
    /// shows it, because a list that came back empty for a reason is not the same
    /// as a list that was empty.
    private(set) var loadFailureNote: String?

    let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        fileURL: URL = UpdateExceptions.defaultFileURL(),
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        load()
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Whether the key is on the list. This is the only question the update path
    /// asks of this type, and it can only ever answer "leave it alone".
    func isExcepted(_ key: String) -> Bool {
        entries.contains { $0.key == key }
    }

    /// Adds a key, ignoring a duplicate. Duplicates would be two rows in the
    /// settings list that remove the same entry, which is confusing for no gain.
    @discardableResult
    func exceptKey(_ key: String, kind: String) -> Bool {
        guard !key.isEmpty, !isExcepted(key) else { return false }
        entries.append(Entry(key: key, kind: kind, added: Date()))
        entries.sort { $0.added > $1.added }
        save()
        return true
    }

    @discardableResult
    func remove(key: String) -> Bool {
        let before = entries.count
        entries.removeAll { $0.key == key }
        guard entries.count != before else { return false }
        save()
        return true
    }

    func removeAll() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        save()
    }

    /// Recovers the key for an application's exception, which is its identifier
    /// when it has one and its path when it does not. Kept in one place so the
    /// write and the read cannot disagree about which it is.
    static func key(forBundleIdentifier identifier: String, path: String) -> (key: String, kind: String) {
        identifier.isEmpty ? (path, "path") : (identifier, "identifier")
    }

    // MARK: - Disk

    private func load() {
        loadFailureNote = nil
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        guard let data = try? Data(contentsOf: fileURL) else { return }

        do {
            let decoded = try decoder.decode([Entry].self, from: data)
            entries = decoded.sorted { $0.added > $1.added }
        } catch {
            // The file exists and cannot be read. Overwriting it would discard
            // decisions the reader made and cannot easily reconstruct, so it is
            // moved aside — under this app's name, in this app's own folder —
            // and the note says so.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = fileURL.appendingPathExtension("unreadable-\(stamp)")
            try? fileManager.moveItem(at: fileURL, to: aside)
            entries = []
            loadFailureNote = "The update exceptions file could not be read. It was moved to \(aside.lastPathComponent) rather than replaced, and the list has started empty."
        }
    }

    private func save() {
        let directory = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
