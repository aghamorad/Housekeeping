// Housekeeping — Comparing two folders and closing the distance between them
//
// Reads both sides, decides what each file is, and proposes the moves that would
// make the two agree. It never deletes: a file that comes out of a tree goes
// into Quarantine through the same engine the rest of the app uses, with the
// same manifest and the same Restore screen.
//
// The one thing this file does that the cleanup engine cannot is copy. The
// cleanup engine only ever moves things out of the way; reconciliation has to be
// able to put a file *in*, which is a new capability and the only new one.
//
// Everything is written to a journal before it happens, so a run that is
// interrupted half-way can be read back and undone from the file alone.

import Foundation

struct ReconcileProgress: Sendable {
    var phase: String
    var detail: String?
    var filesSeen: Int = 0
    var compared: Int = 0
    var hashed: Int = 0
    var fraction: Double?
}

final class ReconcileEngine {

    private struct Walked {
        var records: [String: FileRecord] = [:]
        var bytes: Int64 = 0
        var skippedSymlinks = 0
        var unreadable: [String] = []
        var truncated = false
    }

    /// Past this many files read for their contents, the move-detection pass
    /// gives up and reports the remainder as gaps. It is a stop, not a limit that
    /// is expected to be reached: the pass only ever runs over files that are
    /// missing from one side, and on a library that is merely out of date that is
    /// a small number. When it *is* reached, the two sides have diverged so far
    /// that hashing them is the wrong answer anyway.
    private let maximumFilesToHash = 40_000

    private let fileManager: FileManager

    /// The engine that carries spare copies out of the way, and the folder each
    /// run's record is written into.
    ///
    /// Both are handed in rather than made here because the default pair points
    /// at the real Home folder and the real Quarantine — which is right for the
    /// app and wrong for anything that wants to exercise a reconcile without
    /// moving the reader's files. A test passes a fixture directory and a
    /// throwaway quarantine; the app passes nothing and gets the real ones.
    private let cleanupEngine: CleanupEngine
    private let supportDirectory: URL

    init(
        cleanupEngine: CleanupEngine = CleanupEngine(),
        supportDirectory: URL = CleanupEngine.supportDirectoryURL(),
        fileManager: FileManager = .default
    ) {
        self.cleanupEngine = cleanupEngine
        self.supportDirectory = supportDirectory
        self.fileManager = fileManager
    }

    // MARK: - Is the other drive even here

    /// Whether a folder can be read right now.
    ///
    /// A volume that is not mounted answers no, and that answer has to stop the
    /// comparison rather than shape it. Comparing a library against a drive that
    /// is not plugged in finds a hundred thousand files "missing" and, if anyone
    /// believed it, would be the most destructive result this app could produce.
    static func isReachable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return false }
        return FileManager.default.isReadableFile(atPath: url.path)
    }

    // MARK: - Comparing

    func compare(
        pair: FolderPair,
        progress: @escaping (ReconcileProgress) -> Void,
        isCancelled: @escaping () -> Bool
    ) -> ReconcileReport {
        let started = Date()
        var notes: [String] = []

        for side in [ReconcileSide.a, ReconcileSide.b] where !Self.isReachable(pair.root(of: side)) {
            return ReconcileReport(
                pairLabel: pair.label,
                sideAName: pair.sideAName,
                sideBName: pair.sideBName,
                sideAPath: pair.sideAPath,
                sideBPath: pair.sideBPath,
                sideACount: 0, sideBCount: 0, sideABytes: 0, sideBBytes: 0,
                findings: [], identicalCount: 0,
                measuredAt: Date(),
                duration: Date().timeIntervalSince(started),
                isComplete: false,
                notes: ["\(pair.name(of: side)) is not there — \(pair.path(of: side)) could not be read."],
                unreachableSide: side
            )
        }

        var throttle = Date.distantPast
        func emit(_ phase: String, _ detail: String?, _ fraction: Double?) {
            let now = Date()
            guard now.timeIntervalSince(throttle) > 0.15 || fraction == nil else { return }
            throttle = now
            progress(ReconcileProgress(phase: phase, detail: detail, fraction: fraction))
        }

        emit("Reading \(pair.sideAName)", pair.sideAPath, 0.05)
        let walkedA = walk(root: pair.sideAURL, pair: pair, side: .a, isCancelled: isCancelled)
        if walkedA.truncated { notes.append("Reading \(pair.sideAName) was stopped early.") }

        emit("Reading \(pair.sideBName)", pair.sideBPath, 0.4)
        let walkedB = walk(root: pair.sideBURL, pair: pair, side: .b, isCancelled: isCancelled)
        if walkedB.truncated { notes.append("Reading \(pair.sideBName) was stopped early.") }

        if walkedA.skippedSymlinks > 0 || walkedB.skippedSymlinks > 0 {
            notes.append("Links were stepped over rather than followed, the same way the rest of Housekeeping treats them: \(walkedA.skippedSymlinks + walkedB.skippedSymlinks).")
        }
        for (side, walked) in [(pair.sideAName, walkedA), (pair.sideBName, walkedB)] where !walked.unreadable.isEmpty {
            notes.append("\(walked.unreadable.count) folder\(walked.unreadable.count == 1 ? "" : "s") on \(side) could not be read, so this comparison is incomplete. The first few: \(walked.unreadable.prefix(3).joined(separator: ", "))")
        }

        emit("Comparing", nil, 0.7)
        let compared = diff(pair: pair, a: walkedA.records, b: walkedB.records, isCancelled: isCancelled, emit: emit)

        let complete = !walkedA.truncated && !walkedB.truncated
            && walkedA.unreadable.isEmpty && walkedB.unreadable.isEmpty

        emit("Done", nil, 1.0)
        return ReconcileReport(
            pairLabel: pair.label,
            sideAName: pair.sideAName,
            sideBName: pair.sideBName,
            sideAPath: pair.sideAPath,
            sideBPath: pair.sideBPath,
            sideACount: walkedA.records.count,
            sideBCount: walkedB.records.count,
            sideABytes: walkedA.bytes,
            sideBBytes: walkedB.bytes,
            findings: compared.findings,
            identicalCount: compared.identicalCount,
            measuredAt: Date(),
            duration: Date().timeIntervalSince(started),
            isComplete: complete,
            notes: notes + compared.notes,
            unreachableSide: nil
        )
    }

    // MARK: - Walking one side

    private func walk(
        root: URL,
        pair: FolderPair,
        side: ReconcileSide,
        isCancelled: () -> Bool
    ) -> Walked {
        var result = Walked()
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey,
            .fileSizeKey, .contentModificationDateKey
        ]

        var stack: [(url: URL, relative: String, depth: Int)] = [(root, "", 0)]
        while let next = stack.popLast() {
            if isCancelled() { result.truncated = true; break }
            if next.depth > 64 { continue }

            let contents: [URL]
            do {
                contents = try fileManager.contentsOfDirectory(
                    at: next.url,
                    includingPropertiesForKeys: keys,
                    options: []
                )
            } catch {
                result.unreadable.append(relativePath(next.url, under: root))
                continue
            }

            for entry in contents {
                let values = try? entry.resourceValues(forKeys: Set(keys))

                if values?.isSymbolicLink == true {
                    result.skippedSymlinks += 1
                    continue
                }

                let name = entry.lastPathComponent
                let relative = next.relative.isEmpty ? name : next.relative + "/" + name

                if values?.isDirectory == true {
                    stack.append((entry, relative, next.depth + 1))
                    continue
                }

                // Anything that is not a plain file — a socket, a device, a
                // fifo — has no contents to compare and no size that means
                // anything.
                guard values?.isRegularFile == true else { continue }
                guard pair.considersFile(named: name) else { continue }

                let size = Int64(values?.fileSize ?? 0)
                result.records[relative] = FileRecord(
                    relativePath: relative,
                    size: size,
                    modified: values?.contentModificationDate ?? .distantPast
                )
                result.bytes += size
            }
        }
        return result
    }

    private func relativePath(_ url: URL, under root: URL) -> String {
        let full = url.standardizedFileURL.path
        let base = root.standardizedFileURL.path
        guard full.hasPrefix(base) else { return full }
        let trimmed = full.dropFirst(base.count)
        return trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : String(trimmed)
    }

    // MARK: - The difference

    private struct Difference {
        var findings: [ReconcileFinding] = []
        var identicalCount = 0
        var notes: [String] = []
    }

    private func diff(
        pair: FolderPair,
        a: [String: FileRecord],
        b: [String: FileRecord],
        isCancelled: () -> Bool,
        emit: (String, String?, Double?) -> Void
    ) -> Difference {
        var result = Difference()
        var hashCache: [String: String] = [:]
        var hashesDone = 0

        func digest(_ relative: String, on side: ReconcileSide) -> String? {
            let key = "\(side.rawValue)|\(relative)"
            if let cached = hashCache[key] { return cached }
            guard hashesDone < maximumFilesToHash else { return nil }
            hashesDone += 1
            let url = pair.root(of: side).appendingPathComponent(relative)
            guard let hash = ContentIdentity.sha256(of: url) else { return nil }
            hashCache[key] = hash
            return hash
        }

        // Pass one — the same relative path on both sides.
        for (path, aRecord) in a {
            guard let bRecord = b[path] else { continue }

            if aRecord.size != bRecord.size {
                result.findings.append(ReconcileFinding(
                    verdict: .sameNameDifferentBytes,
                    relativePath: path,
                    otherRelativePath: nil,
                    size: aRecord.size,
                    modified: aRecord.modified,
                    otherSize: bRecord.size,
                    otherModified: bRecord.modified
                ))
                continue
            }

            // Same length. If macOS also recorded the same date, that is the
            // answer and nothing is read.
            if ContentIdentity.agreesCheaply(aRecord, bRecord) {
                result.identicalCount += 1
                continue
            }

            // Same length, different date: the one band where the cheap answer
            // is genuinely ambiguous. Read both.
            guard let hashA = digest(path, on: .a), let hashB = digest(path, on: .b) else {
                emit("Comparing", path, nil)
                result.findings.append(ReconcileFinding(
                    verdict: .sameNameDifferentBytes,
                    relativePath: path,
                    otherRelativePath: nil,
                    size: aRecord.size,
                    modified: aRecord.modified,
                    otherSize: bRecord.size,
                    otherModified: bRecord.modified
                ))
                continue
            }
            if hashA == hashB {
                result.identicalCount += 1
            } else {
                result.findings.append(ReconcileFinding(
                    verdict: .sameNameDifferentBytes,
                    relativePath: path,
                    otherRelativePath: nil,
                    size: aRecord.size,
                    modified: aRecord.modified,
                    otherSize: bRecord.size,
                    otherModified: bRecord.modified
                ))
            }
        }

        // Pass two — what is left, which is everything that does not share a
        // relative path. Excluded paths are dropped here and nowhere else, so a
        // file that is present on both sides under an excluded prefix is still
        // compared normally. An exclusion suppresses absence, nothing more.
        var aOnly = a.filter { b[$0.key] == nil && !pair.excludes($0.key) }
        var bOnly = b.filter { a[$0.key] == nil && !pair.excludes($0.key) }

        if !aOnly.isEmpty || !bOnly.isEmpty {
            emit("Looking for files that moved", nil, 0.85)

            var bBySize: [Int64: [String]] = [:]
            for (path, record) in bOnly { bBySize[record.size, default: []].append(path) }
            for key in bBySize.keys { bBySize[key]?.sort() }

            for path in aOnly.keys.sorted() {
                if isCancelled() { break }
                guard let aRecord = aOnly[path] else { continue }

                var matched: String?
                if let candidates = bBySize[aRecord.size], !candidates.isEmpty,
                   let hashA = digest(path, on: .a) {
                    for candidate in candidates {
                        guard let bRecord = bOnly[candidate], bRecord.size == aRecord.size else { continue }
                        if digest(candidate, on: .b) == hashA {
                            matched = candidate
                            break
                        }
                    }
                }

                if let matched {
                    result.findings.append(ReconcileFinding(
                        verdict: .movedOrRenamed,
                        relativePath: path,
                        otherRelativePath: matched,
                        size: aRecord.size,
                        modified: aRecord.modified,
                        otherSize: nil,
                        otherModified: bOnly[matched]?.modified
                    ))
                    aOnly.removeValue(forKey: path)
                    bOnly.removeValue(forKey: matched)
                    bBySize[aRecord.size]?.removeAll { $0 == matched }
                }
            }

            if hashesDone >= maximumFilesToHash {
                result.notes.append("So many files were missing from one side that Housekeeping stopped reading them to look for moves after \(maximumFilesToHash). The rest are reported as gaps without checking whether they turned up somewhere else.")
            }

            for (path, record) in aOnly {
                result.findings.append(ReconcileFinding(
                    verdict: .missingFromB, relativePath: path, otherRelativePath: nil,
                    size: record.size, modified: record.modified,
                    otherSize: nil, otherModified: nil
                ))
            }
            for (path, record) in bOnly {
                result.findings.append(ReconcileFinding(
                    verdict: .missingFromA, relativePath: path, otherRelativePath: nil,
                    size: record.size, modified: record.modified,
                    otherSize: nil, otherModified: nil
                ))
            }
        }

        result.findings.sort {
            if $0.verdict != $1.verdict { return $0.verdict.rawValue < $1.verdict.rawValue }
            return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
        }
        return result
    }

    // MARK: - What to do about what was found

    /// Turn a report into a list of things that could be done.
    ///
    /// Copies come out ticked, because a copy is what the pair was declared for
    /// and nothing here runs until the reader presses the button. Moves aside and
    /// name collisions come out unticked, because both of those need a person to
    /// have looked at the row first.
    func plan(for report: ReconcileReport, pair: FolderPair) -> [ReconcileProposal] {
        var proposals: [ReconcileProposal] = []
        guard report.unreachableSide == nil else { return proposals }

        let source = pair.sourceSide
        let writable = pair.writableSide

        if let source, let writable, source != writable {
            let gaps = (source == .a) ? report.missingFromB : report.missingFromA
            let sourceName = pair.name(of: source)
            let targetName = pair.name(of: writable)
            for finding in gaps {
                let from = pair.root(of: source).appendingPathComponent(finding.relativePath).path
                let to = pair.root(of: writable).appendingPathComponent(finding.relativePath).path
                proposals.append(ReconcileProposal(
                    id: "copy|\(finding.relativePath)",
                    action: .copy,
                    relativePath: finding.relativePath,
                    sourcePath: from,
                    destinationPath: to,
                    size: finding.size,
                    reason: "On \(sourceName), not on \(targetName). Copying it across is what closes the gap.",
                    isSelected: true
                ))
            }
        } else if let target = pair.direction.targetSide, let source = pair.sourceSide,
                  target == pair.frozenSide {
            // The direction is declared but the side it would write to has been
            // frozen. Say so once rather than silently proposing nothing — the
            // frozen archive is exactly the case where a silent empty plan reads
            // as "nothing is missing", which is the opposite of the truth.
            let gaps = (source == .a) ? report.missingFromB : report.missingFromA
            if !gaps.isEmpty {
                proposals.append(ReconcileProposal(
                    id: "frozen|headline",
                    action: .decide,
                    relativePath: "",
                    sourcePath: pair.path(of: source),
                    destinationPath: pair.path(of: target),
                    size: gaps.reduce(0) { $0 + $1.size },
                    reason: "\(gaps.count) file\(gaps.count == 1 ? "" : "s") would be copied to \(pair.name(of: target)), which is closed. Nothing is proposed for it. If that side is being written to again, unfreeze it in the pair's settings.",
                    isSelected: false
                ))
            }
        }

        // A file that turned up somewhere else. The copy that came second is the
        // one worth taking out, and only ever the copy on the writable side.
        for finding in report.moves {
            // The stray copy is the one on the side that gets written to — the
            // library side is the one whose placement is taken as the truth.
            guard let straySide = pair.writableSide else { continue }
            guard let strayPath = finding.otherRelativePath else { continue }
            let full = pair.root(of: straySide).appendingPathComponent(strayPath).path
            proposals.append(ReconcileProposal(
                id: "quarantine|\(strayPath)",
                action: .quarantine,
                relativePath: strayPath,
                sourcePath: full,
                destinationPath: "",
                size: finding.size,
                reason: "The same file as \(finding.relativePath) on \(pair.name(of: straySide.other)). This copy is the spare, so it is the one to take out — into Quarantine, where it can be put back.",
                isSelected: false
            ))
        }

        // Same name, different contents, and files that exist only on the side
        // that is not the library. Both need a person.
        for finding in report.collisions {
            proposals.append(ReconcileProposal(
                id: "decide|\(finding.relativePath)",
                action: .decide,
                relativePath: finding.relativePath,
                sourcePath: pair.root(of: .a).appendingPathComponent(finding.relativePath).path,
                destinationPath: pair.root(of: .b).appendingPathComponent(finding.relativePath).path,
                size: finding.size,
                reason: "Both sides have a file here and they differ — \(finding.size.sizeDescription) on \(pair.sideAName) against \((finding.otherSize ?? 0).sizeDescription) on \(pair.sideBName). Comparing them cannot say which one is right, so Housekeeping will not choose.",
                isSelected: false
            ))
        }

        if let source = pair.sourceSide, let writable = pair.writableSide, source != writable {
            let extras = (source == .a) ? report.missingFromA : report.missingFromB
            let targetName = pair.name(of: writable)
            for finding in extras {
                proposals.append(ReconcileProposal(
                    id: "decide-extra|\(finding.relativePath)",
                    action: .decide,
                    relativePath: finding.relativePath,
                    sourcePath: pair.root(of: writable).appendingPathComponent(finding.relativePath).path,
                    destinationPath: "",
                    size: finding.size,
                    reason: "Only \(targetName) has this one. It may be the older copy of something, or it may be the only copy — nothing about the two folders says which.",
                    isSelected: false
                ))
            }
        }

        return proposals
    }

    // MARK: - Doing it

    /// Carry out the ticked proposals.
    ///
    /// The journal is written before anything moves, so the record exists even if
    /// this is interrupted. Removals go through the cleanup engine's repair path,
    /// which refuses to touch anything that is not a plain file inside the tree —
    /// including the home folder and the quarantine folder itself.
    func apply(
        _ proposals: [ReconcileProposal],
        pair: FolderPair,
        progress: @escaping (ReconcileProgress) -> Void
    ) async throws -> ReconcileApplyResult {
        let selected = proposals.filter(\.isSelected)
        var result = ReconcileApplyResult()
        guard !selected.isEmpty else { return result }

        let journal = try makeJournal(pairLabel: pair.label)
        result.journalURL = journal.url

        for proposal in selected {
            journal.write(ReconcileJournalEntry(
                at: Date(), pair: pair.label, action: proposal.action.rawValue + ":planned",
                source: proposal.sourcePath, destination: proposal.destinationPath,
                reason: proposal.reason, outcome: "planned"
            ))
        }

        let copies = selected.filter { $0.action == .copy }
        let removals = selected.filter { $0.action == .quarantine }

        var index = 0
        for proposal in copies {
            index += 1
            progress(ReconcileProgress(
                phase: "Copying", detail: proposal.relativePath,
                compared: index, fraction: Double(index) / Double(max(selected.count, 1))
            ))
            do {
                try performCopy(proposal, pair: pair)
                result.copied += 1
                result.copiedBytes += proposal.size
                journal.write(ReconcileJournalEntry(
                    at: Date(), pair: pair.label, action: "copy",
                    source: proposal.sourcePath, destination: proposal.destinationPath,
                    reason: proposal.reason, outcome: "copied"
                ))
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                result.failures.append((proposal.relativePath, message))
                journal.write(ReconcileJournalEntry(
                    at: Date(), pair: pair.label, action: "copy",
                    source: proposal.sourcePath, destination: proposal.destinationPath,
                    reason: proposal.reason, outcome: "failed: \(message)"
                ))
            }
        }

        if !removals.isEmpty {
            progress(ReconcileProgress(phase: "Moving aside", detail: nil, fraction: nil))
            let moved = try await cleanupEngine.quarantineRepairs(
                paths: removals.map(\.sourcePath),
                category: "Reconcile — \(pair.label)",
                reason: "Spare copies found by comparing \(pair.sideAName) and \(pair.sideBName)."
            )
            result.movedAside = moved.succeededCount
            for move in moved.moves {
                if !move.succeeded, let message = move.message {
                    result.failures.append((move.path, message))
                }
                journal.write(ReconcileJournalEntry(
                    at: Date(), pair: pair.label,
                    action: "quarantine", source: move.path,
                    destination: move.quarantinePath ?? "",
                    reason: "Spare copy found by comparing the pair.",
                    outcome: move.succeeded ? "moved aside" : "failed: \(move.message ?? "refused")"
                ))
            }
        }

        journal.close()
        progress(ReconcileProgress(phase: "Done", detail: nil, fraction: 1.0))
        return result
    }

    private func performCopy(_ proposal: ReconcileProposal, pair: FolderPair) throws {
        guard let writable = pair.writableSide else {
            throw ReconcileError.noWritableSide(pair.label)
        }
        let destination = URL(fileURLWithPath: proposal.destinationPath).standardizedFileURL
        let root = pair.root(of: writable).standardizedFileURL

        // The destination has to be inside the side this pair may write to. It is
        // the same shape of check the cleanup engine makes before it moves
        // anything, and it is the one that stops a bad path from writing over a
        // tree that has nothing to do with this pair.
        guard destination.path.hasPrefix(root.path + "/") else {
            throw ReconcileError.destinationOutsideThePair(destination.path)
        }
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw ReconcileError.destinationAlreadyThere(proposal.relativePath)
        }
        guard fileManager.fileExists(atPath: proposal.sourcePath) else {
            throw ReconcileError.sourceVanished(proposal.relativePath)
        }

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // A real copy, never a link. Linking and then writing to the name would
        // write through to the original.
        try fileManager.copyItem(at: URL(fileURLWithPath: proposal.sourcePath), to: destination)
    }

    // MARK: - The record

    private struct Journal {
        let url: URL
        private let handle: FileHandle
        private let encoder: JSONEncoder

        init(url: URL, handle: FileHandle) {
            self.url = url
            self.handle = handle
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            self.encoder = encoder
        }

        func write(_ entry: ReconcileJournalEntry) {
            guard let data = try? encoder.encode(entry) else { return }
            var line = data
            line.append(0x0A)
            try? handle.write(contentsOf: line)
        }

        func close() { try? handle.close() }
    }

    private func makeJournal(pairLabel: String) throws -> Journal {
        let directory = Self.runsDirectoryURL(in: supportDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let slug = pairLabel
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .lowercased()
        let url = directory.appendingPathComponent("reconcile-\(slug)-\(formatter.string(from: Date())).jsonl")

        fileManager.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            throw ReconcileError.couldNotWriteTheRecord(url.path)
        }
        return Journal(url: url, handle: handle)
    }

    /// Where past runs are kept, so a reader can go and look at one.
    static func runsDirectoryURL(in supportDirectory: URL? = nil) -> URL {
        (supportDirectory ?? CleanupEngine.supportDirectoryURL())
            .appendingPathComponent("Reconcile", isDirectory: true)
            .appendingPathComponent("Runs", isDirectory: true)
    }

    /// The folder this engine writes its run records into — the same path as
    /// `runsDirectoryURL(in:)` for the directory it was built with, so a screen
    /// that was handed a test engine reveals the test folder rather than the
    /// reader's.
    var runRecordDirectoryURL: URL {
        Self.runsDirectoryURL(in: supportDirectory)
    }
}

enum ReconcileError: LocalizedError, Equatable {
    case noWritableSide(String)
    case destinationOutsideThePair(String)
    case destinationAlreadyThere(String)
    case sourceVanished(String)
    case couldNotWriteTheRecord(String)

    var errorDescription: String? {
        switch self {
        case .noWritableSide(let label):
            return "The pair “\(label)” is set to report only, or the side it would write to is closed, so there is nowhere to copy to."
        case .destinationOutsideThePair(let path):
            return "That would have written outside the folder this pair covers, so it was stopped. \(path)"
        case .destinationAlreadyThere(let path):
            return "Something is already at that name on the other side, so it was left alone: \(path)"
        case .sourceVanished(let path):
            return "The file was there when the two sides were compared and is not there now: \(path)"
        case .couldNotWriteTheRecord(let path):
            return "The record of this run could not be opened at \(path), so nothing was changed."
        }
    }
}
