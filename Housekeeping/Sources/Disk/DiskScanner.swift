// Housekeeping — Measuring a disk once
//
// The scanner behind the disk browser. It walks a folder once, bottom up, and
// returns a snapshot in which every folder already knows its own size. Nothing
// below here measures on demand: the cost is paid at the start, in one go, with
// progress on screen and a Stop button, and after that opening a folder is a
// dictionary lookup.
//
// Two things this deliberately does not do, because both would make the numbers
// wrong in the direction of "more space than you have":
//
//   - It does not follow symbolic links. A link to a folder elsewhere would be
//     counted twice, once where it points and once where it is. Links are passed
//     over and counted, and the screen says how many.
//
//   - It does not walk macOS's own volumes when the root is /. On a modern Mac the
//     data volume is reachable twice — once as /Users and /Applications and so on,
//     and again underneath /System/Volumes/Data — so walking both paths counts the
//     user's entire home folder twice. The second path is skipped and named.

import Foundation

final class DiskScanner {
    struct Options {
        /// The folder to measure. Everything below it is walked; nothing above it
        /// is looked at, so navigation can never leave the snapshot.
        var root: URL
        /// Folders smaller than this are folded into their parent instead of being
        /// kept. Without a floor, a browser on a full disk holds a row for every
        /// folder macOS creates, and the list becomes unreadable at exactly the
        /// moment it is most needed.
        var minimumKeptSize: Int64 = 1_000_000
        /// How long to walk before stopping and keeping what has been measured.
        /// Off by default, which is the opposite of what this did at first: a
        /// half-measured tree is not a faster answer here, it is a wrong one.
        /// The browser answers every later question — how big is this folder,
        /// what is inside it — out of what the scan already read, so a folder the
        /// walk never reached is reported as small rather than reported late, and
        /// the reader has no way to tell the difference. A wall-clock stop made
        /// the whole screen quietly untrustworthy to save four minutes. Stop is
        /// still there for anyone who wants out early.
        var timeBudget: TimeInterval? = nil
        /// A backstop on memory, separately from the clock. A deeply nested
        /// filesystem can produce folders faster than it produces bytes.
        var maximumKeptFolders = 250_000
        /// How deep to descend. Deeper than any real filesystem needs, shallow
        /// enough that a symlink loop that somehow escaped the link check cannot
        /// exhaust the stack.
        var maximumDepth = 64
        /// Files at least this large are checked for hard links before being
        /// counted. Small hard links exist but are not worth the syscall each,
        /// and no folder's total is wrong by anything a reader would notice.
        var hardLinkCheckFloor: Int64 = 1_048_576

        init(root: URL) {
            self.root = URL(fileURLWithPath: root.path)
                .standardizedFileURL
                .resolvingSymlinksInPath()
        }
    }

    /// Paths that are never descended into, and the sentence explaining each.
    /// Both halves are needed: a skip without a reason is a hole in the total
    /// that nobody can account for.
    private static let neverDescend: [(path: String, note: String)] = [
        ("/System/Volumes/Data",
         "macOS reaches your files by two paths: /Users, /Applications and /Library, and again underneath /System/Volumes/Data. Only the first is counted, so nothing here is counted twice."),
        ("/System/Volumes/VM",
         "Swap and sleep images live here. They belong to macOS and change with whatever you have open, so they are not counted as part of your files."),
        ("/.vol",
         "An internal path into the same files as their device and inode numbers. Counting it would count them twice."),
        ("/Volumes",
         "Other mounted disks — external drives, disk images, network shares. They are left out so a total from this disk is a total for this disk."),
        ("/dev", "Device files. They report no meaningful size and are not stored data."),
        ("/net", "Network mounts, resolved on access. Listed but not walked."),
        ("/home", "Managed by macOS as a mount point. Not where your home folder lives."),
        ("/.MobileBackups", "A local Time Machine cache. It is a copy of files that are counted where they actually live.")
    ]

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Running it

    /// Walks the tree. `progress` is called from the scanning thread, throttled, so
    /// the caller is responsible for hopping back to wherever it wants to draw.
    func scan(
        options: Options,
        progress: @escaping (DiskScanProgress) -> Void,
        isCancelled: @escaping () -> Bool
    ) -> DiskSnapshot {
        var context = Context(options: options, fileManager: fileManager)
        context.deadline = options.timeBudget.map { Date().addingTimeInterval($0) } ?? .distantFuture
        context.progress = progress
        context.isCancelled = isCancelled

        guard fileManager.fileExists(atPath: options.root.path) else {
            context.notes.append("\(options.root.path) is not there any more, so there was nothing to measure.")
            return context.finish()
        }

        // The root is always kept, however small it turns out to be, because it is
        // the only place the browser can define "up" against.
        let aggregate = measure(options.root.path, depth: 0, isRoot: true, context: &context)
        context.progress?(context.progressValue(path: options.root.path, force: true))

        if aggregate.isUnmeasured {
            context.notes.append("The walk was stopped before it finished, so what is shown is only what was read. Folders marked as not measured were never looked at.")
        }
        if context.totalSkippedSymlinks > 0 {
            context.notes.append("\(context.totalSkippedSymlinks) symbolic links were passed over rather than followed, so the folders they point at are counted once instead of twice.")
        }
        if context.unreadableCount > 0 {
            context.notes.append("\(context.unreadableCount) folders could not be read, so their contents are missing from the totals that contain them. Granting Housekeeping Full Disk Access in System Settings → Privacy & Security would let it read more of them.")
        }

        return context.finish()
    }

    // MARK: - The walk

    /// One folder's worth of what was found under it.
    private struct Aggregate {
        var size: Int64 = 0
        var allocatedSize: Int64 = 0
        var fileCount = 0
        var directoryCount = 0
        var isPartial = false
        var isUnmeasured = false
        var hiddenChildCount = 0
        var hiddenSize: Int64 = 0
        var keptChildren: [String] = []
        var modified: Date?
    }

    private func measure(
        _ path: String,
        depth: Int,
        isRoot: Bool,
        context: inout Context
    ) -> Aggregate {
        var aggregate = Aggregate()

        if context.shouldStop {
            aggregate.isUnmeasured = true
            return aggregate
        }
        if !isRoot, DiskScanner.neverDescend.contains(where: { $0.path == path }) {
            aggregate.isUnmeasured = true
            return aggregate
        }

        let url = URL(fileURLWithPath: path)
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
            .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey
        ]

        guard let entries = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            // Hidden files are included on purpose. They take up space like
            // anything else, and a browser that hid them would show a folder's
            // children failing to add up to the folder.
            options: []
        ) else {
            // Not readable: a permissions refusal, most often. Recorded as a
            // partial answer rather than a zero, because those are different
            // claims and only one of them is true.
            aggregate.isPartial = true
            context.noteUnreadable(path)
            return aggregate
        }

        if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) {
            aggregate.modified = values.contentModificationDate
        }

        for entry in entries {
            if context.shouldStop {
                aggregate.isUnmeasured = true
                break
            }

            context.filesScanned += 1
            let childPath = entry.path
            let values = try? entry.resourceValues(forKeys: Set(keys))

            // A link is passed over, never followed. Following one is how a
            // browser reports a folder as bigger than the disk it is on.
            if values?.isSymbolicLink == true {
                context.skippedSymlinks += 1
                continue
            }

            let isDirectory = values?.isDirectory == true

            if isDirectory {
                aggregate.directoryCount += 1
                if depth >= context.options.maximumDepth {
                    aggregate.isPartial = true
                    continue
                }

                let child = measure(childPath, depth: depth + 1, isRoot: false, context: &context)

                aggregate.size += child.size
                aggregate.allocatedSize += child.allocatedSize
                aggregate.fileCount += child.fileCount
                aggregate.directoryCount += child.directoryCount
                if child.isPartial { aggregate.isPartial = true }

                // A folder earns a row of its own by being worth looking at — big
                // enough, or near the top where the reader is orienting. Everything
                // else is counted into its parent and summarised as a single line,
                // so the folder's own size still accounts for all of it.
                let worthKeeping = child.size >= context.options.minimumKeptSize
                    || depth < 1
                    || isRoot
                if worthKeeping, context.keptFolders < context.options.maximumKeptFolders {
                    aggregate.keptChildren.append(childPath)
                } else {
                    aggregate.hiddenChildCount += 1 + child.hiddenChildCount
                    aggregate.hiddenSize += child.size
                }
            } else {
                aggregate.fileCount += 1

                let size = Int64(values?.fileSize ?? 0)
                let allocated = Int64(values?.totalFileAllocatedSize ?? Int(size))

                // A file with more than one link on disk is stored once and
                // counted once. Skipping this is how a browser reports a Time
                // Machine cache or a container layer as several times its size.
                if size >= context.options.hardLinkCheckFloor, context.isAlreadyCounted(childPath) {
                    continue
                }

                aggregate.size += size
                aggregate.allocatedSize += allocated
                context.bytesScanned += size
            }

            context.maybeReportProgress(path: path)
        }

        context.store(path: path, aggregate: aggregate, isRoot: isRoot)
        return aggregate
    }

    // MARK: - Running state

    private struct Context {
        let options: Options
        let fileManager: FileManager

        var deadline = Date.distantFuture
        var progress: ((DiskScanProgress) -> Void)?
        var isCancelled: (() -> Bool)?

        var nodes: [String: DiskNode] = [:]
        var children: [String: [String]] = [:]
        var notes: [String] = []

        var filesScanned = 0
        var directoriesScanned = 0
        var bytesScanned: Int64 = 0
        var keptFolders = 0
        var skippedSymlinks = 0
        var totalSkippedSymlinks = 0
        var unreadableCount = 0
        var unreadableSample: [String] = []
        var seenHardLinks: Set<HardLinkIdentity> = []
        var startedAt = Date()
        var didStop = false

        private var lastReport = Date.distantPast

        /// Mutating because the first lookup is what records the stop: the clock
        /// and the cancel button are both checked here, and once either has fired
        /// every later lookup has to give the same answer without re-asking.
        var shouldStop: Bool {
            mutating get {
                if didStop { return true }
                if isCancelled?() == true || Date() >= deadline {
                    didStop = true
                }
                return didStop
            }
        }

        func progressValue(path: String, force: Bool) -> DiskScanProgress {
            DiskScanProgress(
                filesScanned: filesScanned,
                directoriesScanned: directoriesScanned,
                bytesScanned: bytesScanned,
                currentPath: path,
                elapsed: Date().timeIntervalSince(startedAt)
            )
        }

        mutating func maybeReportProgress(path: String) {
            // Throttled to a comfortable redraw. Reporting every folder would spend
            // more time updating a label than reading the disk.
            let now = Date()
            guard now.timeIntervalSince(lastReport) >= 0.12 else { return }
            lastReport = now
            progress?(progressValue(path: path, force: false))
        }

        mutating func noteUnreadable(_ path: String) {
            unreadableCount += 1
            if unreadableSample.count < 20 { unreadableSample.append(path) }
        }

        /// True when this file has been counted already, under another name.
        mutating func isAlreadyCounted(_ path: String) -> Bool {
            var info = stat()
            guard lstat(path, &info) == 0, info.st_nlink > 1 else { return false }
            return !seenHardLinks.insert(HardLinkIdentity(device: info.st_dev, inode: info.st_ino)).inserted
        }

        mutating func store(path: String, aggregate: Aggregate, isRoot: Bool) {
            let worthKeeping = isRoot
                || aggregate.size >= options.minimumKeptSize
                || !aggregate.keptChildren.isEmpty

            guard worthKeeping, keptFolders < options.maximumKeptFolders else { return }

            let node = DiskNode(
                path: path,
                name: (path as NSString).lastPathComponent,
                isDirectory: true,
                size: aggregate.size,
                allocatedSize: aggregate.allocatedSize,
                fileCount: aggregate.fileCount,
                directoryCount: aggregate.directoryCount,
                isPartial: aggregate.isPartial,
                isUnmeasured: aggregate.isUnmeasured,
                hiddenChildCount: aggregate.hiddenChildCount,
                hiddenSize: aggregate.hiddenSize,
                modified: aggregate.modified
            )
            nodes[path] = node
            children[path] = aggregate.keptChildren
            keptFolders += 1
            directoriesScanned += 1
        }

        mutating func finish() -> DiskSnapshot {
            for skip in DiskScanner.neverDescend where unknownSkip(path: skip.path) {
                notes.append(skip.note)
            }

            return DiskSnapshot(
                root: options.root.path,
                measuredAt: Date(),
                duration: Date().timeIntervalSince(startedAt),
                minimumKeptSize: options.minimumKeptSize,
                isComplete: !didStop,
                nodes: nodes,
                children: children,
                skippedSymlinks: skippedSymlinks,
                unreadableCount: unreadableCount,
                unreadableSample: unreadableSample,
                notes: notes
            )
        }

        /// A skip note is only worth printing when the path it describes was
        /// actually in the way — that is, when the scan started at or above it.
        private func unknownSkip(path: String) -> Bool {
            options.root.path == "/" || options.root.path.hasPrefix(path)
        }
    }
}

/// A file identified by where it lives rather than what it is called. Two names
/// for one file are one file, and this is how the scan knows.
private struct HardLinkIdentity: Hashable {
    let device: dev_t
    let inode: ino_t
}
