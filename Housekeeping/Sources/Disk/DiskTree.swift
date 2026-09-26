// Housekeeping — The measured disk
//
// This is the scanner's result, and the thing the browser navigates.
//
// The decision that matters here is that this is a *snapshot taken once*, not a
// measurement taken on arrival. Measuring when a folder is opened is what makes
// the other tools in this space feel like a treadmill: every step inward costs a
// wait, every step back costs the same wait again, and the disk is re-read the
// entire time. A snapshot is out of date the moment it is written — that is the
// price, and `measuredAt` is how the screen admits it — but navigation becomes
// free in both directions, which is the whole complaint being answered.
//
// Storing the tree flat, as a dictionary keyed by path, rather than as nested
// values matters more than it looks. Following a path is a lookup rather than a
// walk, so drawing a breadcrumb for the folder you are standing in costs nothing
// however deep it is, and going back up does not re-derive anything.

import Foundation

// MARK: - One measured folder or file

struct DiskNode: Codable, Equatable, Identifiable {
    let path: String
    let name: String
    let isDirectory: Bool

    /// Apparent size: the sum of the sizes the filesystem reports for the files at
    /// and below this node. This is deliberately not the same thing as what the
    /// volume gives up for them — APFS clones share blocks and hard links share
    /// inodes — so the screen says which of the two it is showing rather than
    /// letting the reader assume the larger number is space they would get back.
    var size: Int64

    /// Sum of allocated sizes, which is the closer of the two to what the volume
    /// actually spends. Kept beside `size` so the difference can be shown rather
    /// than argued about.
    var allocatedSize: Int64

    var fileCount: Int
    var directoryCount: Int

    /// Something at or below here could not be read, so `size` is a floor. Not an
    /// error and not nothing: it is the honest shape of an answer that is partly
    /// missing, and the row says so instead of printing a confident small number.
    var isPartial: Bool

    /// The walk was stopped before it reached here. A folder in this state has a
    /// size of zero that means *unknown*, which is exactly the distinction
    /// `Int64.sizeDescription` exists to preserve.
    var isUnmeasured: Bool

    /// Children too small to earn a row of their own, and what they add up to.
    /// Without this a folder's listed children would not account for its own size,
    /// and the arithmetic on screen would look broken when it is only summarised.
    var hiddenChildCount: Int
    var hiddenSize: Int64

    /// When the folder itself was last modified. Optional because a folder that
    /// could not be read has no answer, and no answer is not the same as 1970.
    var modified: Date?

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var displayName: String { name.isEmpty ? path : name }
}

// MARK: - The whole measurement

struct DiskSnapshot: Codable, Equatable {
    /// The folder the scan started from. Navigation never leaves it, so every
    /// path on screen is a descendant of this and the breadcrumb can say so.
    let root: String
    let measuredAt: Date
    let duration: TimeInterval
    /// Folders below this size were folded into their parent rather than kept.
    /// Recorded because a reader looking at a folder whose children do not add up
    /// deserves to know what the rule was.
    let minimumKeptSize: Int64
    /// False when the time budget stopped the scan before the tree was finished.
    let isComplete: Bool

    /// Kept folders, keyed by path.
    private(set) var nodes: [String: DiskNode]
    /// Kept children, keyed by the parent's path. Stored rather than derived so
    /// that opening a folder is a lookup instead of a scan of every node.
    private(set) var children: [String: [String]]

    /// How many symbolic links were passed over, and how many folders could not be
    /// read at all. Counts rather than lists, except for a short sample of the
    /// second, which is worth naming and not worth storing fifty thousand of.
    let skippedSymlinks: Int
    let unreadableCount: Int
    let unreadableSample: [String]

    /// What was deliberately left out, in the reader's words rather than the
    /// code's. Shown on screen, because a disk total that quietly omits things is
    /// worse than one that says what it omitted.
    let notes: [String]

    var rootNode: DiskNode? { nodes[root] }
    var totalSize: Int64 { nodes[root]?.size ?? 0 }
    var keptFolderCount: Int { nodes.count }

    // MARK: Following a path

    func node(at path: String) -> DiskNode? { nodes[path] }

    /// Whether there is anything recorded under this folder. A kept folder with no
    /// kept children still has a size, so it is not empty in the sense the reader
    /// cares about — but there is nothing to open, and the screen says why.
    func hasChildren(_ path: String) -> Bool { !(children[path] ?? []).isEmpty }

    /// The children worth showing, largest first. Files are not kept as nodes —
    /// only folders are walked into — so this is folders, and the small ones are
    /// accounted for by `hiddenChildCount` on the parent.
    func childNodes(of path: String) -> [DiskNode] {
        (children[path] ?? [])
            .compactMap { nodes[$0] }
            .sorted { $0.size > $1.size }
    }

    /// The folder above this one, or nil at the root. Answered from the path
    /// string rather than searched, so it is correct for a folder whose parent was
    /// never kept — in which case it is still the root, and there is no way back
    /// past it.
    func parent(of path: String) -> String? {
        guard path != root else { return nil }
        let parentPath = (path as NSString).deletingLastPathComponent
        guard parentPath.count >= root.count, root.hasPrefix(parentPath) || parentPath.hasPrefix(root) else {
            return root
        }
        return parentPath.isEmpty ? root : parentPath
    }

    /// The trail from the root to this folder, each step a place the reader can
    /// click. Built by walking the string, so it is right even for a folder whose
    /// ancestors were folded away as too small to keep.
    func breadcrumb(to path: String) -> [(name: String, path: String)] {
        guard path.hasPrefix(root) else { return [(rootName, root)] }
        var trail: [(name: String, path: String)] = [(rootName, root)]
        guard path != root else { return trail }

        let suffix = path.dropFirst(root.count)
        var accumulated = root
        for component in suffix.split(separator: "/") where !component.isEmpty {
            accumulated = (accumulated as NSString).appendingPathComponent(String(component))
            trail.append((String(component), accumulated))
        }
        return trail
    }

    /// How the root itself is named. "/" has no last path component, so it would
    /// otherwise appear in the breadcrumb as an empty clickable thing.
    var rootName: String {
        let name = (root as NSString).lastPathComponent
        if !name.isEmpty { return name }
        let home = NSHomeDirectory()
        return root == "/" ? "This Mac" : (root == home ? "Home" : root)
    }

    /// The largest folders anywhere below the root, for a "where did it all go"
    /// list that does not require drilling in to find the answer.
    func largestDescendants(limit: Int) -> [DiskNode] {
        nodes.values
            .filter { $0.path != root && $0.isDirectory && $0.size > 0 }
            .sorted { $0.size > $1.size }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: The file

    /// Kept in Housekeeping's own support folder, beside the quarantine records
    /// and the left-alone list, and read back at launch so reopening the browser
    /// does not mean measuring the disk again.
    ///
    /// A binary property list rather than the readable JSON used everywhere else
    /// in this app. The left-alone list is JSON because it records *decisions* and
    /// a person should be able to read and argue with it; this records a
    /// measurement of a machine that can be taken again at any time, and it holds
    /// hundreds of thousands of paths. The trade is deliberate.
    static func defaultFileURL(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        CleanupEngine.supportDirectoryURL(homeDirectory: homeDirectory)
            .appendingPathComponent("DiskSnapshot.plist")
    }

    func save(to url: URL, fileManager: FileManager = .default) {
        let directory = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Reads a snapshot back. Anything unreadable is treated as no snapshot at all:
    /// unlike the left-alone list, losing one costs the reader a wait and nothing
    /// else, so there is nothing here worth setting aside or complaining about.
    static func load(from url: URL) -> DiskSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? PropertyListDecoder().decode(DiskSnapshot.self, from: data),
              snapshot.nodes[snapshot.root] != nil else { return nil }
        return snapshot
    }
}

// MARK: - What the scanner reports while it works

/// Progress, for a scan that can run for minutes. A disk browser that shows
/// nothing until it is finished is indistinguishable from one that has hung, and
/// the reader has no way to tell whether to wait or give up.
struct DiskScanProgress: Equatable {
    var filesScanned: Int
    var directoriesScanned: Int
    var bytesScanned: Int64
    /// The folder being read right now. Named rather than implied, because it is
    /// the only evidence the reader has that the scan is moving.
    var currentPath: String
    var elapsed: TimeInterval

    var elapsedDescription: String {
        let seconds = Int(elapsed.rounded())
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    var currentFolderName: String {
        let name = (currentPath as NSString).lastPathComponent
        return name.isEmpty ? currentPath : name
    }
}
