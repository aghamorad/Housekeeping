// Housekeeping — What a pair of folders is, and what comparing them found
//
// Two libraries, one comparison, and the handful of rules that make the
// comparison honest: a side that may never be written to, paths that are on one
// side on purpose, and kinds of file that have to be compared apart because one
// of the two drives keeps them somewhere else.
//
// Nothing in this file reads a disk. The engine does that. These are the nouns
// it hands back, and they are values, so a report can be kept, drawn on screen,
// and written to a journal without any of the three being able to change the
// other two.

import Foundation

// MARK: - A pair

/// Which way a pair is allowed to be written, if either.
///
/// It is not a preference — it is a statement about which side is the real
/// library. Comparing two folders and then writing the older copy over the newer
/// one is the failure this whole feature exists to prevent, so the direction is
/// declared before anything is read rather than guessed from what turns up.
enum ReconcileDirection: String, Codable, CaseIterable, Sendable {
    /// A is the library; B is brought up to it.
    case aToB
    /// B is the library; A is brought up to it.
    case bToA
    /// Both sides are libraries in their own right. Everything is reported and
    /// nothing is proposed, because there is no side that gets to win.
    case reportOnly

    var title: String {
        switch self {
        case .aToB: return "Copy from A to B"
        case .bToA: return "Copy from B to A"
        case .reportOnly: return "Report only — neither side is the original"
        }
    }

    /// The side this direction would write to, regardless of whether that side is
    /// allowed to be written. Kept separate from `FolderPair.writableSide`, which
    /// answers the narrower question of whether a copy may actually be planned —
    /// the difference between the two is what lets a frozen side be explained
    /// rather than silently passed over.
    var targetSide: ReconcileSide? {
        switch self {
        case .aToB: return .b
        case .bToA: return .a
        case .reportOnly: return nil
        }
    }
}

/// One of the two sides, named so that a sentence about it reads as English
/// rather than as "the first path".
enum ReconcileSide: String, Codable, Sendable {
    case a, b

    var other: ReconcileSide { self == .a ? .b : .a }
}

/// Two folders that are supposed to hold the same things, and the rules for
/// comparing them.
///
/// The paths are stored as strings rather than URLs because this is written to a
/// file and read back on another day, and a volume that is not plugged in is a
/// normal state rather than an error.
struct FolderPair: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    /// One sentence saying what this pair is and why it is compared this way.
    /// Shown under the name, because a pair whose rules are invisible is a pair
    /// whose results cannot be trusted.
    var summary: String

    var sideAPath: String
    var sideBPath: String
    var sideAName: String
    var sideBName: String

    var direction: ReconcileDirection

    /// Relative paths that live on one side on purpose. Their absence on the
    /// other side is not a gap and is never reported as one. A file that exists
    /// under an excluded path on *both* sides is still compared normally — the
    /// exclusion suppresses absence, and nothing else.
    var exclusions: [String]

    /// Extensions (lowercase, no dot) left out of the comparison entirely.
    var ignoredExtensions: [String]

    /// Extensions this pair is *only* about. When the list is not empty,
    /// everything else is left out. It is how the two halves of a library that
    /// one drive split into two folders get compared properly instead of being
    /// reported as ten thousand moves.
    var includedExtensions: [String]

    /// A side that must never be written to. Used for an archive that has been
    /// closed: it is still worth comparing, because knowing what is in it is
    /// worthwhile, but nothing may be added to it.
    var frozenSide: ReconcileSide?

    /// Built-in pairs can be edited but not deleted by accident; the flag is
    /// what the view uses to say so.
    var isBuiltIn: Bool

    var sideAURL: URL { URL(fileURLWithPath: sideAPath) }
    var sideBURL: URL { URL(fileURLWithPath: sideBPath) }

    func name(of side: ReconcileSide) -> String {
        side == .a ? sideAName : sideBName
    }

    func root(of side: ReconcileSide) -> URL {
        side == .a ? sideAURL : sideBURL
    }

    func path(of side: ReconcileSide) -> String {
        side == .a ? sideAPath : sideBPath
    }

    /// Whether a file belongs in this comparison at all.
    func considersFile(named name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        if !includedExtensions.isEmpty { return includedExtensions.contains(ext) }
        return !ignoredExtensions.contains(ext)
    }

    /// Whether a relative path is on the deliberately-one-sided list.
    func excludes(_ relativePath: String) -> Bool {
        exclusions.contains { prefix in
            relativePath == prefix || relativePath.hasPrefix(prefix + "/")
        }
    }

    /// The side a copy may be written to, or nil when neither may be written.
    ///
    /// Two ways to earn a nil: a pair that is report-only, and a side that has
    /// been frozen. Both mean the same thing to the planning step, which is that
    /// it may not propose a copy.
    var writableSide: ReconcileSide? {
        let target: ReconcileSide
        switch direction {
        case .aToB: target = .b
        case .bToA: target = .a
        case .reportOnly: return nil
        }
        return frozenSide == target ? nil : target
    }

    var sourceSide: ReconcileSide? {
        switch direction {
        case .aToB: return .a
        case .bToA: return .b
        case .reportOnly: return nil
        }
    }
}

// MARK: - What a walk found

/// One file, as measured. Deliberately without a hash: hashing is the expensive
/// part and is done only where the cheap answer is not enough.
struct FileRecord: Equatable, Sendable {
    var relativePath: String
    var size: Int64
    var modified: Date
}

// MARK: - What comparing them found

/// The five things a file can be.
///
/// Four of them are answers to "is anything missing", and the fifth exists so
/// that a library which was moved and renamed between two comparisons does not
/// read as thousands of deletions followed by thousands of new files. That
/// single verdict is the difference between a report a person can act on and a
/// wall of noise, which is why identity is content rather than path throughout.
enum ReconcileVerdict: String, Codable, CaseIterable, Sendable {
    /// Byte-for-byte the same at the same relative path.
    case identical
    /// On A, not on B. A gap on B.
    case missingFromB
    /// On B, not on A. A gap on A.
    case missingFromA
    /// The same name and relative path on both sides, holding different bytes.
    /// Never resolved automatically, in either direction.
    case sameNameDifferentBytes
    /// The same content under a different relative path — a move, not a gap.
    case movedOrRenamed

    var title: String {
        switch self {
        case .identical: return "The same on both sides"
        case .missingFromB: return "On A, missing from B"
        case .missingFromA: return "On B, missing from A"
        case .sameNameDifferentBytes: return "Same name, different contents"
        case .movedOrRenamed: return "The same file, under a different name or folder"
        }
    }

    var explanation: String {
        switch self {
        case .identical:
            return "Present at the same relative path on both sides, same size and same date."
        case .missingFromB:
            return "This file is on the first side and nowhere on the second. If the first side is the library, this is the gap to close."
        case .missingFromA:
            return "This file is on the second side and nowhere on the first. Often this is the older copy of something — but not always, which is why it is reported rather than acted on."
        case .sameNameDifferentBytes:
            return "Both sides have a file at this path and they are not the same file. Nothing about comparing them says which one is right, so Housekeeping will not pick one. Look at the dates and the sizes and decide."
        case .movedOrRenamed:
            return "The same contents, found somewhere else. Nothing is missing here — a file was renamed or put in a different folder on one side. Counting these as gaps is what makes a report of a tidy library claim that everything is gone."
        }
    }

    var iconName: String {
        switch self {
        case .identical: return "equal.circle"
        case .missingFromB: return "arrow.right.circle"
        case .missingFromA: return "arrow.left.circle"
        case .sameNameDifferentBytes: return "exclamationmark.triangle"
        case .movedOrRenamed: return "arrow.triangle.branch"
        }
    }

    /// Whether this verdict describes something absent from one side. The three
    /// that do are the ones a reconciliation exists to close.
    var isGap: Bool {
        self == .missingFromA || self == .missingFromB || self == .sameNameDifferentBytes
    }
}

/// One verdict about one relative path.
struct ReconcileFinding: Identifiable, Equatable, Sendable {
    var verdict: ReconcileVerdict
    var relativePath: String
    /// For a move: where the same contents were found instead. Nil otherwise.
    var otherRelativePath: String?
    var size: Int64
    var modified: Date?
    /// For a name collision: what the other side has at the same path.
    var otherSize: Int64?
    var otherModified: Date?

    var id: String { "\(verdict.rawValue)|\(relativePath)|\(otherRelativePath ?? "")" }

    var displayName: String { (relativePath as NSString).lastPathComponent }

    var folder: String {
        let parent = (relativePath as NSString).deletingLastPathComponent
        return parent.isEmpty ? "—" : parent
    }
}

/// Everything one comparison found.
struct ReconcileReport: Sendable {
    var pairLabel: String
    var sideAName: String
    var sideBName: String
    var sideAPath: String
    var sideBPath: String

    var sideACount: Int
    var sideBCount: Int
    var sideABytes: Int64
    var sideBBytes: Int64

    var findings: [ReconcileFinding]
    var identicalCount: Int

    var measuredAt: Date
    var duration: TimeInterval
    /// False when a side was stopped, unreadable, or not mounted. A partial
    /// reading must never be presented as a complete one, because the missing
    /// half would read as missing files.
    var isComplete: Bool
    var notes: [String]

    /// Set when one side could not be reached at all — an unplugged drive being
    /// the ordinary case. When it is set there are no findings, because a
    /// comparison against nothing would call every file in the library missing.
    var unreachableSide: ReconcileSide?

    var missingFromB: [ReconcileFinding] { findings.filter { $0.verdict == .missingFromB } }
    var missingFromA: [ReconcileFinding] { findings.filter { $0.verdict == .missingFromA } }
    var collisions: [ReconcileFinding] { findings.filter { $0.verdict == .sameNameDifferentBytes } }
    var moves: [ReconcileFinding] { findings.filter { $0.verdict == .movedOrRenamed } }

    var gapCount: Int { missingFromA.count + missingFromB.count + collisions.count }

    var missingFromBBytes: Int64 { missingFromB.reduce(0) { $0 + $1.size } }
    var missingFromABytes: Int64 { missingFromA.reduce(0) { $0 + $1.size } }

    /// One sentence for the top of the screen. Written here rather than in the
    /// view so the notification, the journal and the sheet all say the same
    /// thing about the same run.
    var headline: String {
        if let unreachableSide {
            return "\(unreachableSide == .a ? sideAName : sideBName) is not there right now."
        }
        if !isComplete {
            return "The comparison did not finish, so this is a partial answer."
        }
        if gapCount == 0 {
            return "Nothing is missing on either side."
        }
        var parts: [String] = []
        if !missingFromB.isEmpty { parts.append("\(missingFromB.count) on \(sideAName) only") }
        if !missingFromA.isEmpty { parts.append("\(missingFromA.count) on \(sideBName) only") }
        if !collisions.isEmpty { parts.append("\(collisions.count) that differ") }
        return parts.joined(separator: ", ") + "."
    }
}

// MARK: - What to do about it

/// One proposed change. A proposal is not a decision: nothing is proposed as
/// already-agreed-to, and the two verdicts that need a person's judgement are
/// proposed as questions.
struct ReconcileProposal: Identifiable, Equatable, Sendable {
    enum Action: String, Codable, Sendable {
        /// Copy one file from the library side to the other.
        case copy
        /// Move a stray copy out of a tree and into Quarantine.
        case quarantine
        /// Something only a person can settle. Carried so it appears in the plan
        /// rather than vanishing from it.
        case decide

        var title: String {
            switch self {
            case .copy: return "Copy"
            case .quarantine: return "Move aside"
            case .decide: return "Your call"
            }
        }
    }

    var id: String
    var action: Action
    var relativePath: String
    var sourcePath: String
    var destinationPath: String
    var size: Int64
    var reason: String
    /// Whether the reader has ticked it. Never true for a `decide`.
    var isSelected: Bool

    var displayName: String { (relativePath as NSString).lastPathComponent }
}

/// What actually happened when a plan was carried out.
struct ReconcileApplyResult: Sendable {
    var copied: Int = 0
    var copiedBytes: Int64 = 0
    var movedAside: Int = 0
    var failures: [(path: String, message: String)] = []
    /// Where the reversible record of the run was written, if a run happened.
    var journalURL: URL?
    var didAnything: Bool { copied > 0 || movedAside > 0 }

    var summaryLine: String {
        if !didAnything && failures.isEmpty { return "Nothing to do — the plan was empty." }
        var parts: [String] = []
        if copied > 0 { parts.append("\(copied) copied (\(copiedBytes.sizeDescription))") }
        if movedAside > 0 { parts.append("\(movedAside) moved aside") }
        if !failures.isEmpty { parts.append("\(failures.count) could not be done") }
        return parts.joined(separator: ", ") + "."
    }
}

/// One line of the reversible record.
///
/// Written *before* the change it describes, so a run that is interrupted
/// half-way can still be undone from the file alone. Every field is a plain
/// string or number on purpose: the record has to be readable without this app,
/// by a person or by a different tool, years from now.
struct ReconcileJournalEntry: Codable, Sendable {
    var at: Date
    var pair: String
    var action: String
    var source: String
    var destination: String
    var reason: String
    var outcome: String
}

// MARK: - The conventions that live only in the record

/// A library the record says has no second copy anywhere.
///
/// It is a constant rather than something derived, because nothing on this Mac
/// can tell you that a folder has no backup — only the person who made the
/// copies knows that. It is here so the screen can name the real exposure, which
/// is that most of these libraries are on one drive and nowhere else, and so a
/// reader can delete an entry once it is no longer true.
struct SingleCopyLibrary: Identifiable, Sendable {
    var id: String
    var name: String
    /// Where it lives, when the record is certain. Empty when it is not — a
    /// wrong path here would be worse than no path.
    var path: String
    var note: String
}

enum ReconcileConventions {
    /// Extensions treated as video. Used both to leave video out of a comparison
    /// and to make one that is only about video, which is how the two halves of
    /// the photo library are compared after one of the two drives split them.
    static let videoExtensions: [String] = [
        "mov", "mp4", "m4v", "avi", "mkv", "mpg", "mpeg", "wmv", "flv", "webm",
        "3gp", "mts", "m2ts", "mpv", "dv", "mod", "tod", "vob", "rm", "rmvb",
        "asf", "ogv", "divx", "mxf", "braw", "r3d"
    ]

    /// Paths that are one-sided on purpose in the photo library. Written out as
    /// the record has them, so a reader can see exactly what is being excused.
    static let photosOneSidedPaths = ["Other Photos/Marjan's Photos"]

    static let knownSingleCopyLibraries: [SingleCopyLibrary] = [
        SingleCopyLibrary(
            id: "music",
            name: "My Music",
            path: "",
            note: "Around 66,000 files, organised and filed, and the record has no second copy of it anywhere. This is the largest thing on this Mac that exists in one place."
        ),
        SingleCopyLibrary(
            id: "iranian-tv",
            name: "Iranian TV archive",
            path: "/Volumes/TOSHIBA/Iranian TV",
            note: "566 files, 116 GB, filed by broadcaster. It sits on the external drive and nowhere else, and its organisation journal is inside the tree — so the tree and its history are on the same single drive."
        )
    ]

    /// The pairs this app knows about before anyone adds one. They are ordinary
    /// pairs in every other respect: editable, and removable.
    static func builtInPairs() -> [FolderPair] {
        [
            FolderPair(
                id: "photos-stills",
                label: "Photos · still images",
                summary: "The working photo library against the drive it was archived to. Video is left out of this one because the archived side keeps it in a folder of its own, which the next pair covers.",
                sideAPath: "/Volumes/Music : Pictures : Academics/My Pictures",
                sideBPath: "/Volumes/BACKUP DRIVE/Pictures & Videos/My Pictures",
                sideAName: "MAIN",
                sideBName: "BACKUP",
                direction: .aToB,
                exclusions: ReconcileConventions.photosOneSidedPaths,
                ignoredExtensions: ReconcileConventions.videoExtensions,
                includedExtensions: [],
                frozenSide: .b,
                isBuiltIn: true
            ),
            FolderPair(
                id: "photos-video",
                label: "Photos · video",
                summary: "The video half, compared between the folder it lives in on the working drive and the folder the archive split it out into. Only video is looked at here.",
                sideAPath: "/Volumes/Music : Pictures : Academics/My Pictures",
                sideBPath: "/Volumes/BACKUP DRIVE/Pictures & Videos/My Videos",
                sideAName: "MAIN",
                sideBName: "BACKUP",
                direction: .aToB,
                exclusions: ReconcileConventions.photosOneSidedPaths,
                ignoredExtensions: [],
                includedExtensions: ReconcileConventions.videoExtensions,
                frozenSide: .b,
                isBuiltIn: true
            )
        ]
    }
}

// MARK: - Where the pairs are kept

/// The pairs, read once and written back on every change.
///
/// The same shape as the left-alone list, for the same reasons: a plain JSON file
/// in the app's support folder, sorted keys, and a file that cannot be read is
/// moved aside rather than overwritten — a list somebody typed in by hand is not
/// something to lose to a parse error.
final class FolderPairStore {
    private struct Stored: Codable {
        var version: Int
        var pairs: [FolderPair]
    }

    private(set) var pairs: [FolderPair] = []
    /// Set when a file existed and could not be read. A list that came back
    /// empty for a reason is not the same as one that was never made.
    private(set) var loadFailureNote: String?

    let fileURL: URL

    static func defaultFileURL(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        CleanupEngine.supportDirectoryURL(homeDirectory: homeDirectory)
            .appendingPathComponent("Reconcile", isDirectory: true)
            .appendingPathComponent("Pairs.json")
    }

    init(fileURL: URL = FolderPairStore.defaultFileURL()) {
        self.fileURL = fileURL
        load()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            pairs = ReconcileConventions.builtInPairs()
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let stored = try decoder.decode(Stored.self, from: data)
            pairs = stored.pairs
        } catch {
            // Move it aside rather than overwrite it. It is a list somebody
            // typed in, and a parse failure is not a reason to lose it.
            let aside = fileURL.appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: fileURL, to: aside)
            loadFailureNote = "The list of folder pairs could not be read (\(error.localizedDescription)). It has been kept next to where it was, and the built-in pairs are being used instead."
            pairs = ReconcileConventions.builtInPairs()
        }
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Stored(version: 1, pairs: pairs)) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: .atomic)
    }

    func add(_ pair: FolderPair) {
        guard !pairs.contains(where: { $0.id == pair.id }) else { return }
        pairs.append(pair)
        save()
    }

    func update(_ pair: FolderPair) {
        guard let index = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs[index] = pair
        save()
    }

    func remove(_ pair: FolderPair) {
        guard let index = pairs.firstIndex(where: { $0.id == pair.id }) else { return }
        pairs.remove(at: index)
        save()
    }
}
