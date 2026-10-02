import AppKit
import Foundation

/// The only mutating component used by the app. Every request is fully
/// preflighted before the first move, and every destination is recorded before
/// data leaves its original path.
final class CleanupEngine {
    /// Quarantine deliberately lives in plain sight. It used to sit inside the
    /// application-support folder, where Finder hides things, so the one place
    /// Housekeeping puts your files was the one place you could not look at.
    /// Anything Housekeeping takes now sits in a folder anyone can see, open, and
    /// pull things back out of by hand.
    static let quarantineFolderName = "Housekeeping Quarantine"

    /// The plain-language note Housekeeping leaves inside the quarantine folder.
    static let quarantineGuideFileName = "READ ME — what is this folder.txt"

    /// Where Housekeeping keeps its own state: quarantine transactions and the
    /// left-alone list. Written down in one place, so the two share a home and
    /// the rename below is the only path that has to know about both names.
    static func supportDirectoryURL(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support/Housekeeping", isDirectory: true)
    }

    /// The same folder under the app's former name. Nothing reads this except the
    /// one-time move below: it is somewhere to migrate *from*, not a second place
    /// to look, and it disappears once there is nothing left in it.
    static func legacySupportDirectoryURL(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        homeDirectory.appendingPathComponent("Library/Application Support/Scrub99", isDirectory: true)
    }

    static func quarantineURL(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        homeDirectory.appendingPathComponent(quarantineFolderName, isDirectory: true)
    }

    /// The same visible folder under the app's former name. A place to move
    /// *from*, exactly like `legacySupportDirectoryURL`: a rename is not a reason
    /// to stop offering someone their files back.
    static func legacyVisibleQuarantineURL(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        homeDirectory.appendingPathComponent("Scrub99 Quarantine", isDirectory: true)
    }

    /// Moves the whole support folder across from the app's former name in one
    /// go, rather than teaching every path about both names: a folder renamed is
    /// one move, while a folder read from two places is two chances to disagree.
    ///
    /// If a folder already exists under the new name the situation is ambiguous —
    /// something has already been written there — so the old one is left exactly
    /// where it is. Deliberately the timid choice: doing nothing costs a folder
    /// moved by hand, while guessing costs the reader a file they cannot find.
    @discardableResult
    static func migrateLegacySupportDirectoryIfNeeded(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        fileManager: FileManager = .default
    ) -> Bool {
        let legacy = legacySupportDirectoryURL(homeDirectory: homeDirectory)
        let current = supportDirectoryURL(homeDirectory: homeDirectory)
        guard legacy.standardizedFileURL != current.standardizedFileURL,
              fileManager.fileExists(atPath: legacy.path),
              !fileManager.fileExists(atPath: current.path) else { return false }

        do {
            try fileManager.moveItem(at: legacy, to: current)
            return true
        } catch {
            return false
        }
    }

    /// Where quarantine used to live inside the support folder, before it was
    /// brought out into plain sight. Kept only so existing transactions can be
    /// walked out into the open on first launch.
    static func legacyQuarantineURL(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        supportDirectoryURL(homeDirectory: homeDirectory)
            .appendingPathComponent("Quarantine", isDirectory: true)
    }

    /// Every folder an older build may have quarantined into. Both are read once
    /// at launch and then left alone; the visible one goes first only because it
    /// is the more likely of the two to still hold something of the reader's.
    static func legacyQuarantineURLs(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())) -> [URL] {
        [
            legacyVisibleQuarantineURL(homeDirectory: homeDirectory),
            legacyQuarantineURL(homeDirectory: homeDirectory),
        ]
    }

    let quarantineURL: URL
    let homeDirectory: URL

    private let fileManager: FileManager
    private let safetyPolicy: CleanupSafetyPolicy
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        quarantineRoot: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory
        self.quarantineURL = quarantineRoot ?? CleanupEngine.quarantineURL(homeDirectory: homeDirectory)
        self.fileManager = fileManager
        self.safetyPolicy = CleanupSafetyPolicy(
            homeDirectory: homeDirectory,
            quarantineRoot: self.quarantineURL
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func assessment(for item: FoundItem) -> CleanupSafetyPolicy.Assessment {
        safetyPolicy.assess(item, fileManager: fileManager)
    }

    // MARK: - Bringing quarantine into the open

    /// Walks every transaction inside an older quarantine folder out into the
    /// current one. Two folders count as older: the hidden one inside application
    /// support, and the visible one under the app's former name — the folder the
    /// app itself used to write to before it was renamed. Each transaction moves
    /// as a whole, and its manifest is re-pointed at the new location before the
    /// move is considered done — a manifest that still names the old path would
    /// make its items unrestorable, so if the rewrite fails the move is undone
    /// rather than left half-finished.
    ///
    /// Returns how many transactions were moved. Safe to call on every launch:
    /// with nothing left to move it does nothing and costs one `fileExists` per
    /// old name.
    @discardableResult
    func adoptLegacyQuarantineIfNeeded() -> Int {
        guard !didAdoptLegacyQuarantine else { return 0 }

        var movedCount = 0
        for legacyURL in CleanupEngine.legacyQuarantineURLs(homeDirectory: homeDirectory)
        where legacyURL.standardizedFileURL != quarantineURL.standardizedFileURL {
            movedCount += adoptQuarantine(from: legacyURL)
        }

        didAdoptLegacyQuarantine = true
        writeQuarantineGuide()
        return movedCount
    }

    /// Moves everything out of one older quarantine folder. Returns how many
    /// transactions arrived intact.
    private func adoptQuarantine(from legacyURL: URL) -> Int {
        guard fileManager.fileExists(atPath: legacyURL.path) else { return 0 }

        let transactions = (try? fileManager.contentsOfDirectory(
            at: legacyURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        } ?? []

        guard !transactions.isEmpty else { return 0 }
        try? fileManager.createDirectory(at: quarantineURL, withIntermediateDirectories: true)

        var movedCount = 0
        for source in transactions {
            let destination = quarantineURL.appendingPathComponent(source.lastPathComponent, isDirectory: true)
            guard !itemExists(atPath: destination.path) else { continue }

            do {
                try fileManager.moveItem(at: source, to: destination)
            } catch {
                continue
            }

            do {
                try repointManifest(in: destination, from: legacyURL, to: quarantineURL)
                movedCount += 1
            } catch {
                // Leaving it here would strand its items, so put it back where it
                // came from; it will be picked up on the next launch instead.
                try? fileManager.moveItem(at: destination, to: source)
            }
        }

        // The note left in the old folder describes a folder that is now empty,
        // so it goes with the items. It is Housekeeping's own note rather than
        // anything of the user's, and the current folder gets a fresh one.
        let legacyGuide = legacyURL.appendingPathComponent(CleanupEngine.quarantineGuideFileName, isDirectory: false)
        if fileManager.fileExists(atPath: legacyGuide.path) {
            try? fileManager.removeItem(at: legacyGuide)
        }
        // With the transactions gone the old folder has no reason to exist, and
        // leaving it behind would keep the old path around forever. It is only
        // removed when it is genuinely empty, so anything unexpected inside it —
        // a `.DS_Store`, say — stays put and is picked up on the next launch.
        if let remaining = try? fileManager.contentsOfDirectory(atPath: legacyURL.path), remaining.isEmpty {
            try? fileManager.removeItem(at: legacyURL)
        }

        return movedCount
    }

    /// Whether this engine instance has already tried the move, so a second
    /// call does not walk a partly-migrated folder twice.
    private var didAdoptLegacyQuarantine = false

    /// Rewrites the recorded paths inside a transaction's manifest so they name
    /// the transaction's new home.
    ///
    /// This goes through the model rather than searching and replacing the file's
    /// text. A text substitution looks tempting and does not work: `JSONEncoder`
    /// escapes every `/` in a path as `\/`, so a search for a literal
    /// `/Users/...` prefix matches nothing and the manifest silently keeps naming
    /// the old location. Reading the manifest, rewriting the two path fields, and
    /// writing it back through the same coder is exact.
    private func repointManifest(in transactionURL: URL, from oldRoot: URL, to newRoot: URL) throws {
        let manifestURL = transactionURL.appendingPathComponent("manifest.json", isDirectory: false)
        guard fileManager.fileExists(atPath: manifestURL.path) else { return }

        let data = try Data(contentsOf: manifestURL)
        guard var manifest = try? decoder.decode(DurableManifest.self, from: data) else {
            throw CleanupError.restoreError("The quarantine record could not be read.")
        }

        let oldPrefix = oldRoot.standardizedFileURL.path
        let newPrefix = newRoot.standardizedFileURL.path
        for index in manifest.items.indices {
            let current = manifest.items[index].quarantinePath
            guard current == oldPrefix || current.hasPrefix(oldPrefix + "/") else { continue }
            manifest.items[index].quarantinePath = newPrefix + current.dropFirst(oldPrefix.count)
        }

        try save(manifest, to: manifestURL)
    }

    /// Drops a note in the folder explaining, in plain words, what it is and how
    /// to get things back out — so someone who finds it in Finder six months
    /// from now is not left guessing. Rewritten on every launch so its text
    /// always matches the build that is running.
    func writeQuarantineGuide() {
        guard fileManager.fileExists(atPath: quarantineURL.path) else { return }
        let guideURL = quarantineURL.appendingPathComponent(
            CleanupEngine.quarantineGuideFileName,
            isDirectory: false
        )
        let text = """
        Housekeeping Quarantine
        ==================

        This folder is where Housekeeping puts things when you clean them.

        Nothing here has been deleted. Every item below is a full copy of what
        used to be on your Mac, sitting exactly as it was. If you change your
        mind, open Housekeeping, choose Manage Quarantine, and press Restore: the
        item goes back to the exact path it came from.

        You can also put things back by hand. Open one of the dated folders,
        then "Items", and drag what you want back to where it belongs. Housekeeping
        will not mind — it re-checks what is actually there every time it opens.

        Nothing in here is secret and nothing is hidden. Feel free to look.

        Deleting things from this folder by hand is permanent. Housekeeping cannot
        bring something back that it can no longer find. If you want the space
        back but you are not certain, leave it: this folder is the safety net,
        and it only costs the space the item already took.

        Each transaction keeps a manifest.json recording where every item came
        from. That file is how Restore knows the way home. Please leave it alone.
        """
        try? Data(text.utf8).write(to: guideURL, options: [.atomic])
    }

    func cleanup(
        items: [FoundItem],
        useTrash: Bool = false,
        allowReviewOnly: Bool = false
    ) async throws -> CleanupResult {
        guard !useTrash else {
            throw CleanupError.trashError("Direct Trash cleanup is disabled in this safety release. Use reversible quarantine.")
        }
        guard !items.isEmpty else {
            return CleanupResult(
                date: Date(), movedItems: [], totalSize: 0,
                successCount: 0, failureCount: 0, usedTrash: false
            )
        }

        let approvedItems = try safetyPolicy.preflight(
            items,
            allowReviewOnly: allowReviewOnly,
            fileManager: fileManager
        )
        let runningApps = try await checkRunningApps(approvedItems)
        guard runningApps.isEmpty else {
            throw CleanupError.applicationsRunning(runningApps)
        }

        let recordID = UUID()
        let date = Date()
        let transactionURL = quarantineURL.appendingPathComponent(recordID.uuidString, isDirectory: true)
        let itemsURL = transactionURL.appendingPathComponent("Items", isDirectory: true)
        let manifestURL = transactionURL.appendingPathComponent("manifest.json", isDirectory: false)

        var manifest = DurableManifest(
            version: 3,
            id: recordID,
            date: date,
            createdAtUnixNanoseconds: Int64(date.timeIntervalSince1970 * 1_000_000_000),
            items: approvedItems.map { item in
                let destination = itemsURL
                    .appendingPathComponent(item.id.uuidString, isDirectory: true)
                    .appendingPathComponent(item.path.lastPathComponent, isDirectory: false)
                return DurableItem(
                    id: item.id,
                    originalPath: item.path.path,
                    quarantinePath: destination.path,
                    size: item.size,
                    category: item.category.displayName,
                    appName: item.primaryApplication?.name,
                    state: .planned,
                    errorMessage: nil
                )
            }
        )

        try fileManager.createDirectory(at: itemsURL, withIntermediateDirectories: true)
        try save(manifest, to: manifestURL)
        writeQuarantineGuide()

        var movedItems: [MovedItem] = []
        for index in manifest.items.indices {
            try Task.checkCancellation()
            let item = approvedItems[index]
            let destination = URL(fileURLWithPath: manifest.items[index].quarantinePath)

            do {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                guard !itemExists(atPath: destination.path) else {
                    throw CleanupError.restoreError("Quarantine destination already exists: \(destination.path)")
                }
                try fileManager.moveItem(at: item.path, to: destination)
                manifest.items[index].state = .moved
                manifest.items[index].errorMessage = nil
                movedItems.append(.quarantine(item, destination))
            } catch {
                manifest.items[index].state = .failed
                manifest.items[index].errorMessage = error.localizedDescription
                movedItems.append(.failed(item, error.localizedDescription))
            }

            try save(manifest, to: manifestURL)
        }

        return CleanupResult(
            date: date,
            movedItems: movedItems,
            totalSize: movedItems.filter(\.success).reduce(0) { $0 + $1.size },
            successCount: movedItems.filter(\.success).count,
            failureCount: movedItems.filter(\.failed).count,
            usedTrash: false
        )
    }

    /// Moves paths that a setup repair has decided to take off the disk into the
    /// same quarantine folder, recorded in the same manifest an ordinary cleanup
    /// writes — so the same Manage Quarantine screen lists them and the same
    /// Restore puts them back.
    ///
    /// It does not go through `cleanup(items:)`, and cannot. That method runs
    /// every item through `CleanupSafetyPolicy`, which judges by the item's
    /// *category* — what kind of file it is. A dangling symlink in `~/.local/bin`
    /// classifies as a leftover and comes back refused, which is precisely the
    /// item this needs to move; a stray copy of a program winning the search
    /// path classifies as unknown and is refused too. Making those categories
    /// approvable in order to let this through would loosen the cleaner's rules
    /// for every ordinary sweep as well.
    ///
    /// So the guard here is a different one rather than a weaker one, short
    /// enough to state in full. A path is skipped, with the refusal kept as the
    /// row's message, when:
    ///
    ///   * nothing is there — neither a file nor a symlink, even a dead one;
    ///   * it is the disk root, the home folder, or the quarantine folder;
    ///   * it *contains* the home folder or the quarantine folder. This is the
    ///     rule whose cost would be unrecoverable: a repair handed a bad path
    ///     could otherwise take someone's whole home folder away in one move,
    ///     leaving the app with nothing to put back.
    ///
    /// Everything else is the caller's judgement, since the caller is the only
    /// party that knows why it is moving these paths, and the reason it gives is
    /// written into the record — which is the sentence the reader needs when
    /// deciding later whether to put the thing back.
    func quarantineRepairs(
        paths: [String],
        category: String,
        reason: String
    ) async throws -> RepairMoveResult {
        let recordID = UUID()
        let date = Date()
        let transactionURL = quarantineURL.appendingPathComponent(recordID.uuidString, isDirectory: true)
        let itemsURL = transactionURL.appendingPathComponent("Items", isDirectory: true)
        let manifestURL = transactionURL.appendingPathComponent("manifest.json", isDirectory: false)

        let home = homeDirectory.standardizedFileURL.path
        let quarantine = quarantineURL.standardizedFileURL.path

        // `standardizedFileURL`, not `resolvingSymlinksInPath`: the link itself
        // is the thing being moved, so following it would turn a dead link into
        // whatever it fails to reach.
        var accepted: [(path: String, id: UUID, size: Int64, destination: URL)] = []
        var moves: [RepairMoveResult.RepairMove] = []

        for path in paths {
            let standard = URL(fileURLWithPath: path).standardizedFileURL.path
            if let refusal = refusalToMove(standard, home: home, quarantine: quarantine) {
                moves.append(RepairMoveResult.RepairMove(
                    path: standard, quarantinePath: nil, succeeded: false, message: refusal
                ))
                continue
            }
            let id = UUID()
            let destination = itemsURL
                .appendingPathComponent(id.uuidString, isDirectory: true)
                .appendingPathComponent((standard as NSString).lastPathComponent, isDirectory: false)
            accepted.append((standard, id, sizeToRecord(atPath: standard), destination))
        }

        guard !accepted.isEmpty else {
            return RepairMoveResult(
                transactionID: recordID, date: date, manifestURL: manifestURL, moves: moves
            )
        }

        // The manifest's `appName` slot is the free-text subtitle under a row in
        // the Quarantine list. An ordinary cleanup puts the application it
        // belongs to there; a setup repair has no application behind it, so the
        // reason for the move goes there instead, and it is written as a whole
        // sentence so the record still explains itself if it is ever read
        // without this app.
        var manifest = DurableManifest(
            version: 3,
            id: recordID,
            date: date,
            createdAtUnixNanoseconds: Int64(date.timeIntervalSince1970 * 1_000_000_000),
            items: accepted.map { entry in
                DurableItem(
                    id: entry.id,
                    originalPath: entry.path,
                    quarantinePath: entry.destination.path,
                    size: entry.size,
                    category: category,
                    appName: reason,
                    state: .planned,
                    errorMessage: nil
                )
            }
        )

        try fileManager.createDirectory(at: itemsURL, withIntermediateDirectories: true)
        try save(manifest, to: manifestURL)
        writeQuarantineGuide()

        for index in manifest.items.indices {
            try Task.checkCancellation()
            let entry = accepted[index]
            let destination = entry.destination

            do {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                guard !itemExists(atPath: destination.path) else {
                    throw CleanupError.restoreError("Quarantine destination already exists: \(destination.path)")
                }
                try fileManager.moveItem(at: URL(fileURLWithPath: entry.path), to: destination)
                manifest.items[index].state = .moved
                manifest.items[index].errorMessage = nil
                moves.append(RepairMoveResult.RepairMove(
                    path: entry.path, quarantinePath: destination.path, succeeded: true, message: nil
                ))
            } catch {
                manifest.items[index].state = .failed
                manifest.items[index].errorMessage = error.localizedDescription
                moves.append(RepairMoveResult.RepairMove(
                    path: entry.path, quarantinePath: nil, succeeded: false, message: error.localizedDescription
                ))
            }
            try save(manifest, to: manifestURL)
        }

        return RepairMoveResult(
            transactionID: recordID, date: date, manifestURL: manifestURL, moves: moves
        )
    }

    /// Why this path will not be moved, or nil when it may be. The rules are
    /// set out in `quarantineRepairs` above; this is only their wording.
    private func refusalToMove(_ path: String, home: String, quarantine: String) -> String? {
        // `fileExists` follows links, so it answers "is there something at the
        // far end of this" — false for exactly the dead links this method exists
        // to move. The link itself is checked for on its own.
        let isLink = (try? fileManager.destinationOfSymbolicLink(atPath: path)) != nil
        guard isLink || fileManager.fileExists(atPath: path) else {
            return "Nothing is at this path any more, so there was nothing to move."
        }
        guard path != "/", path != home, path != quarantine else {
            return "Housekeeping will not move this folder."
        }
        for protected in [home, quarantine] where protected.hasPrefix(path + "/") {
            let what = protected == quarantine ? "the Quarantine folder" : "your home folder"
            return "Moving this would take \(what) with it, so Housekeeping refused."
        }
        return nil
    }

    /// The size to record for a path. Only ever shown, never acted on, so a
    /// symlink or something that disappears between being read and being
    /// measured records nothing rather than failing over a number.
    private func sizeToRecord(atPath path: String) -> Int64 {
        (try? fileManager.attributesOfItem(atPath: path))?[.size] as? Int64 ?? 0
    }

    /// Whether an item is at this path *as itself* — a symlink counts even when
    /// the file it points at is gone.
    ///
    /// `fileExists` follows links, so it answers "is anything at the far end of
    /// this", which is the wrong question for the items this app promises to
    /// hand back. A symlink whose target has already disappeared is exactly the
    /// kind of thing Housekeeping quarantines, and following the link would call
    /// that item missing at the moment the reader asks for it — the one answer
    /// this app must never give wrongly. This check is made against the
    /// directory entry, the same way `sizeToRecord` above measures a link rather
    /// than its target.
    private func itemExists(atPath path: String) -> Bool {
        (try? fileManager.attributesOfItem(atPath: path)) != nil
    }

    func undoLastCleanup() async throws -> RestoreResult {
        let (manifestURL, _) = try loadLatestRestorableManifest()
        return try await restoreTransaction(at: manifestURL)
    }

    /// Puts back one recorded cleanup. `undoLastCleanup` is this narrowed to the
    /// most recent restorable run; the history screen offers it per run. Both
    /// paths go through here so there is one restore, not two that can drift.
    func restoreTransaction(_ transaction: CleanupTransaction) async throws -> RestoreResult {
        try await restoreTransaction(at: transaction.manifestURL)
    }

    func restoreTransaction(at manifestURL: URL) async throws -> RestoreResult {
        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? decoder.decode(DurableManifest.self, from: data) else {
            throw CleanupError.restoreError("The record of this cleanup could not be read.")
        }
        var restoredItems: [RestoredItem] = []

        for index in manifest.items.indices {
            try Task.checkCancellation()
            guard manifest.items[index].state == .moved || manifest.items[index].state == .planned else {
                continue
            }

            let record = manifest.items[index]
            let source = URL(fileURLWithPath: record.quarantinePath)
            let destination = URL(fileURLWithPath: record.originalPath)
            let publicRecord = record.publicRecord

            guard itemExists(atPath: source.path) else {
                manifest.items[index].errorMessage = "The quarantined item is missing."
                restoredItems.append(.failed(publicRecord, "The quarantined item is missing."))
                try save(manifest, to: manifestURL)
                continue
            }
            guard !itemExists(atPath: destination.path) else {
                let message = "Restore refused because the original path now exists. Nothing was overwritten."
                manifest.items[index].errorMessage = message
                restoredItems.append(.failed(publicRecord, message))
                try save(manifest, to: manifestURL)
                continue
            }

            do {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.moveItem(at: source, to: destination)
                manifest.items[index].state = .restored
                manifest.items[index].errorMessage = nil
                restoredItems.append(.success(publicRecord))
            } catch {
                manifest.items[index].errorMessage = error.localizedDescription
                restoredItems.append(.failed(publicRecord, error.localizedDescription))
            }
            try save(manifest, to: manifestURL)
        }

        return RestoreResult(
            restoredItems: restoredItems,
            totalRestored: restoredItems.filter(\.success).count,
            totalSize: restoredItems.filter(\.success).reduce(0) { $0 + $1.size }
        )
    }

    func restoreItem(_ itemRecord: MovedItemRecord) async throws {
        guard let originalPath = itemRecord.originalPath,
              let quarantinePath = itemRecord.quarantinePath else {
            throw CleanupError.restoreError("Missing path information")
        }
        let source = URL(fileURLWithPath: quarantinePath)
        let destination = URL(fileURLWithPath: originalPath)
        guard itemExists(atPath: source.path) else {
            throw CleanupError.restoreError("Item no longer exists in quarantine")
        }
        guard !itemExists(atPath: destination.path) else {
            throw CleanupError.restoreError("Restore refused because the original path exists. Nothing was overwritten.")
        }
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: source, to: destination)
    }

    func quarantineEntries() -> [QuarantineEntry] {
        guard let manifests = try? manifestURLs() else { return [] }
        return manifests.flatMap { manifestURL in
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(DurableManifest.self, from: data) else {
                return [QuarantineEntry]()
            }
            return manifest.items.compactMap { item in
                guard item.state == .moved,
                      itemExists(atPath: item.quarantinePath) else { return nil }
                return QuarantineEntry(
                    id: item.id,
                    date: manifest.date,
                    originalPath: item.originalPath,
                    quarantinePath: item.quarantinePath,
                    size: item.size,
                    category: item.category,
                    appName: item.appName,
                    manifestURL: manifestURL
                )
            }
        }
        .sorted {
            if $0.date == $1.date { return $0.originalPath < $1.originalPath }
            return $0.date > $1.date
        }
    }

    /// Every cleanup Housekeeping has run on this Mac, newest first, rebuilt from the
    /// records on disk. An item the record says was moved but which is no longer
    /// in the folder is reported as gone rather than waiting — otherwise this
    /// screen would promise to put back something the folder does not have, and
    /// "still waiting" would disagree with the Quarantine list beside it.
    func transactionHistory() -> [CleanupTransaction] {
        guard let manifests = try? manifestURLs() else { return [] }
        return manifests.compactMap { manifestURL in
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(DurableManifest.self, from: data) else { return nil }
            return CleanupTransaction(
                id: manifest.id,
                date: manifest.date,
                items: manifest.items.map { item in
                    CleanupTransaction.Item(
                        id: item.id,
                        originalPath: item.originalPath,
                        size: item.size,
                        category: item.category,
                        appName: item.appName,
                        state: {
                            switch item.state {
                            case .moved:
                                return itemExists(atPath: item.quarantinePath) ? .waiting : .gone
                            case .restored:
                                return .putBack
                            case .purged:
                                return .deletedForever
                            case .planned, .failed:
                                return .neverMoved
                            }
                        }()
                    )
                },
                manifestURL: manifestURL
            )
        }
        .sorted { $0.date > $1.date }
    }

    func restore(_ entry: QuarantineEntry) throws {
        guard let loaded = loadManifest(containing: entry) else {
            throw CleanupError.restoreError("The quarantine record could not be found.")
        }
        let manifestURL = loaded.0
        var manifest = loaded.1
        guard
              let index = manifest.items.firstIndex(where: { $0.id == entry.id }) else {
            throw CleanupError.restoreError("The quarantine record could not be found.")
        }
        let source = URL(fileURLWithPath: manifest.items[index].quarantinePath)
        let destination = URL(fileURLWithPath: manifest.items[index].originalPath)
        guard itemExists(atPath: source.path) else {
            throw CleanupError.restoreError("The quarantined item is missing.")
        }
        guard !itemExists(atPath: destination.path) else {
            throw CleanupError.restoreError("Restore refused because the original path exists. Nothing was overwritten.")
        }
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: source, to: destination)
        manifest.items[index].state = .restored
        manifest.items[index].errorMessage = nil
        try save(manifest, to: manifestURL)
    }

    func permanentlyDelete(_ entries: [QuarantineEntry]) throws -> PermanentDeletionResult {
        var deleted: [QuarantineEntry] = []
        var failed: [(QuarantineEntry, String)] = []
        for entry in entries {
            do {
                guard let loaded = loadManifest(containing: entry) else {
                    throw CleanupError.restoreError("The quarantine record could not be found.")
                }
                let manifestURL = loaded.0
                var manifest = loaded.1
                guard
                      let index = manifest.items.firstIndex(where: { $0.id == entry.id }) else {
                    throw CleanupError.restoreError("The quarantine record could not be found.")
                }
                let source = URL(fileURLWithPath: manifest.items[index].quarantinePath).standardizedFileURL
                let rootComponents = quarantineURL.standardizedFileURL.pathComponents
                guard source != quarantineURL.standardizedFileURL,
                      source.pathComponents.starts(with: rootComponents),
                      itemExists(atPath: source.path) else {
                    throw CleanupError.restoreError("The quarantined item is missing or outside Housekeeping Quarantine.")
                }
                try fileManager.removeItem(at: source)
                manifest.items[index].state = .purged
                manifest.items[index].errorMessage = nil
                try save(manifest, to: manifestURL)
                deleted.append(entry)
            } catch {
                failed.append((entry, error.localizedDescription))
            }
        }
        return PermanentDeletionResult(deleted: deleted, failed: failed)
    }

    /// Opens Finder at the folder holding one batch, with its record beside the
    /// items. Reading that record is the point: it is the same file the history
    /// screen reads, and anyone can check the app against it.
    func revealTransaction(_ transaction: CleanupTransaction) {
        NSWorkspace.shared.activateFileViewerSelecting([transaction.manifestURL.deletingLastPathComponent()])
    }

    func revealQuarantine() {
        // Before anything has been cleaned there is no folder to select, and
        // opening Finder on a path that does not exist shows the user nothing.
        // Home is one step away from where quarantine will appear, so show that
        // and say so in the UI rather than failing silently.
        let target = fileManager.fileExists(atPath: quarantineURL.path)
            ? quarantineURL
            : homeDirectory
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    var quarantineExists: Bool {
        fileManager.fileExists(atPath: quarantineURL.path)
    }

    private func loadManifest(containing entry: QuarantineEntry) -> (URL, DurableManifest)? {
        guard let data = try? Data(contentsOf: entry.manifestURL),
              let manifest = try? decoder.decode(DurableManifest.self, from: data) else { return nil }
        return (entry.manifestURL, manifest)
    }

    internal func checkRunningApps(_ items: [FoundItem]) async throws -> [ApplicationRef] {
        let running = NSWorkspace.shared.runningApplications
        let runningIDs = Set(running.compactMap(\.bundleIdentifier))
        var matches: Set<ApplicationRef> = []

        for app in items.compactMap(\.primaryApplication) {
            if let bundleIdentifier = app.bundleIdentifier, runningIDs.contains(bundleIdentifier) {
                matches.insert(app)
            } else if running.contains(where: { CleanupEngine.ownerName(app.name, describes: $0.localizedName) }) {
                matches.insert(app)
            }
        }
        return matches.sorted { $0.name < $1.name }
    }

    /// Whether a running process is the application that owns an item.
    ///
    /// This is used only when the owner has no bundle identifier to compare, and
    /// it used to be `localizedName.contains(owner)`. A substring test over every
    /// running process is not a name check: a folder called `log` matched
    /// `loginwindow`, which is always running, so those items were refused on
    /// every scan, forever, with an explanation that was not true. `NGL` matched
    /// `Single Sign-On` and eight other processes the same way.
    ///
    /// A running process counts as the owner when it *is* the application, or
    /// when it belongs to it and says so at the front of its name — `Google
    /// Chrome Helper (Renderer)` belongs to `Google Chrome`. Both forms are
    /// anchored and ended by a word boundary, so a match has to be the name
    /// rather than a coincidence of spelling.
    static func ownerName(_ owner: String, describes runningName: String?) -> Bool {
        guard let runningName else { return false }
        let owner = owner.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !owner.isEmpty else { return false }
        let name = runningName.lowercased()

        if name == owner { return true }
        return name.hasPrefix(owner) && name.dropFirst(owner.count).first == " "
    }

    var hasQuarantineItems: Bool {
        (try? allManifests().contains { manifest in
            manifest.items.contains { item in
                item.state == .moved &&
                itemExists(atPath: item.quarantinePath)
            }
        }) == true
    }

    var quarantineTotalSize: Int64 {
        (try? allManifests().flatMap(\.items).filter { item in
            item.state == .moved &&
            itemExists(atPath: item.quarantinePath)
        }.reduce(0) { $0 + $1.size }) ?? 0
    }

    private func save(_ manifest: DurableManifest, to url: URL) throws {
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: [.atomic])
    }

    private func loadLatestRestorableManifest() throws -> (URL, DurableManifest) {
        let candidates = try manifestURLs().compactMap { url -> (URL, DurableManifest)? in
            guard let data = try? Data(contentsOf: url),
                  let manifest = try? decoder.decode(DurableManifest.self, from: data),
                  manifest.items.contains(where: { item in
                      (item.state == .moved || item.state == .planned) &&
                      itemExists(atPath: item.quarantinePath)
                  }) else { return nil }
            return (url, manifest)
        }
        guard let latest = candidates.max(by: {
            let leftOrder = $0.1.createdAtUnixNanoseconds
                ?? Int64($0.1.date.timeIntervalSince1970 * 1_000_000_000)
            let rightOrder = $1.1.createdAtUnixNanoseconds
                ?? Int64($1.1.date.timeIntervalSince1970 * 1_000_000_000)
            if leftOrder == rightOrder { return $0.0.path < $1.0.path }
            return leftOrder < rightOrder
        }) else {
            throw CleanupError.restoreError("No restorable quarantine manifest found")
        }
        return latest
    }

    private func allManifests() throws -> [DurableManifest] {
        try manifestURLs().compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(DurableManifest.self, from: data)
        }
    }

    private func manifestURLs() throws -> [URL] {
        guard fileManager.fileExists(atPath: quarantineURL.path) else { return [] }
        return try fileManager.contentsOfDirectory(
            at: quarantineURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).map { $0.appendingPathComponent("manifest.json", isDirectory: false) }
    }
}

private struct DurableManifest: Codable {
    let version: Int
    let id: UUID
    let date: Date
    let createdAtUnixNanoseconds: Int64?
    var items: [DurableItem]
}

private struct DurableItem: Codable {
    enum State: String, Codable {
        case planned
        case moved
        case failed
        case restored
        case purged
    }

    let id: UUID
    let originalPath: String
    /// Mutable because adopting an older quarantine folder relocates a whole
    /// transaction and has to re-point this at the item's new home.
    var quarantinePath: String
    let size: Int64
    let category: String
    let appName: String?
    var state: State
    var errorMessage: String?

    var publicRecord: MovedItemRecord {
        MovedItemRecord(
            id: id,
            originalPath: originalPath,
            quarantinePath: quarantinePath,
            size: size,
            category: category,
            appName: appName
        )
    }
}
