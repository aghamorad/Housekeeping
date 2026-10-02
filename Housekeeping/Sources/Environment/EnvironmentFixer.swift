// Housekeeping — doing the fixes the setup screen offers
//
// The audit is a reading: it says what is wrong and what could be done. This is
// the other half, and it is the first part of Housekeeping that runs the
// system's own tools rather than moving files it has classified. `brew link` is
// not a file operation; it is Homebrew being asked to change its mind about a
// package, and the app has to be able to hear its answer and pass it on.
//
// Three rules shape everything below.
//
// One finding, one action, one row. A finding that is really a sequence of
// things would be a script, and a script is not something the reader can judge
// from the sentence they read before ticking it. The one exception is written
// down where it happens: `unshadow` is a move followed by a link, because those
// two are the two halves of the same sentence — the name is free now, so let
// Homebrew take it — and doing one without the other would leave the Mac worse
// than before it started.
//
// Anything that moves goes through the cleanup engine's quarantine. Not its
// `cleanup(items:)` method, which judges items by category and would refuse a
// dead symlink, but its `quarantineRepairs`, which writes the same manifest and
// the same folder. The point is that there is exactly one recovery screen in
// this app. A second place where things go to be put back is a second place the
// reader has to remember.
//
// Nothing is undone silently. Every failure below is that finding's own row,
// carrying Homebrew's or the file system's words, and the run continues: a batch
// that stopped at the first refusal would leave the reader unable to tell what
// ran from what did not.

import Foundation

struct EnvironmentFixer {

    let runner: ProcessRunner
    let cleanupEngine: CleanupEngine
    /// Where `brew` is. Injected rather than looked up per call so the tests can
    /// point the whole fixer at a stand-in, and so a run cannot use one `brew`
    /// while the reading used another.
    let brewPath: String?
    let fileManager: FileManager

    /// Whether the reader has pressed Stop, shared with `cancel()`.
    ///
    /// A program that is killed comes back as an ordinary failure — a non-zero
    /// status, nothing on stderr — which is indistinguishable from a program
    /// that failed on its own. `Task.isCancelled` is not enough either: the
    /// button that stops the run and the run itself are two different pieces of
    /// work, and killing the process does not cancel the task that is waiting on
    /// it. Without this the row would report Homebrew's own error for a stop
    /// nobody asked Homebrew for. The flag is a box rather than a property
    /// because the running call has its own copy of the fixer, so storage on
    /// `self` would be written to one copy and read from another.
    private let stop = StopBox()

    /// Shared between the run and whoever stops it, which are never on the same
    /// thread, so the plain `Bool` inside is read and written under the lock the
    /// class documents rather than being reached through the property wrapper.
    final class StopBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false

        var isStopped: Bool {
            lock.lock(); defer { lock.unlock() }
            return stopped
        }

        func stop() {
            lock.lock(); defer { lock.unlock() }
            stopped = true
        }
    }

    /// The reader asked for this run to stop: either the task was cancelled, or
    /// `cancel()` was called on this fixer.
    private var stopped: Bool { stop.isStopped || Task.isCancelled }

    init(
        runner: ProcessRunner = ProcessRunner(),
        cleanupEngine: CleanupEngine = CleanupEngine(),
        brewPath: String? = ProcessRunner.brewPath(),
        fileManager: FileManager = .default
    ) {
        self.runner = runner
        self.cleanupEngine = cleanupEngine
        self.brewPath = brewPath
        self.fileManager = fileManager
    }

    /// What a quarantine run says about itself on the Manage Quarantine screen.
    /// The category is the short label; the reason is the sentence, and it is
    /// written into the record as a whole sentence because the record outlives
    /// the screen that made it.
    private static let quarantineCategory = "Setup repair"
    private static let deadLinkReason = "Moved by the setup check because the file it pointed at is gone. Put it back if you want the link again."

    // MARK: - The run

    /// Runs every finding handed to it and returns one outcome per finding, in
    /// the order they were given. It does not throw: a fix that failed is a row
    /// that says so.
    func remediate(_ findings: [EnvironmentFinding]) async -> [EnvironmentOutcome] {
        var outcomes: [String: EnvironmentOutcome] = [:]

        // Moves first, and grouped by reason — a quarantine manifest holds one
        // reason for every item in the run, so findings that are the same move
        // for the same reason become one transaction, which is also one entry on
        // the Quarantine screen rather than twenty.
        //
        // They go before the package-manager work on purpose. A move is the only
        // step here that changes something no package manager can put back, so
        // it happens while the app has a whole uninterrupted run ahead of it
        // rather than after ten minutes of `brew install` that the reader may
        // stop.
        for group in moveGroups(in: findings) {
            if stopped { break }
            let paths = group.findings.compactMap(\.subjectPath)
            guard !paths.isEmpty else { continue }

            // A cancelled move means the batch stopped partway, and the items it
            // did get to are in the manifest already — each one is recorded as it
            // is moved, so stopping cannot leave the folder and the record
            // disagreeing. `interrupted` exists only so the rows say that,
            // instead of blaming the Quarantine folder for a stop the reader
            // asked for.
            var interrupted = false
            let result: RepairMoveResult?
            do {
                result = try await cleanupEngine.quarantineRepairs(
                    paths: paths,
                    category: Self.quarantineCategory,
                    reason: group.reason
                )
            } catch is CancellationError {
                result = nil
                interrupted = true
            } catch {
                result = nil
            }

            for finding in group.findings {
                guard let subject = finding.subjectPath else { continue }
                let standardizedSubject = URL(fileURLWithPath: subject).standardizedFileURL.path
                guard let move = result?.moves.first(where: { $0.path == standardizedSubject }) else {
                    outcomes[finding.id] = outcome(
                        finding,
                        interrupted
                            ? "The run was stopped. Anything that was moved is in Quarantine, and Restore puts it back."
                            : "It was not moved: the Quarantine folder could not be written to."
                                + followUpIfMoveFailed(finding),
                        succeeded: false
                    )
                    continue
                }
                outcomes[finding.id] = outcome(
                    finding,
                    move.succeeded
                        ? "Moved to Quarantine. Restore puts it back."
                        : (move.message ?? "Housekeeping could not move it.") + followUpIfMoveFailed(finding),
                    succeeded: move.succeeded
                )
            }
        }

        // Then the package manager, one command at a time, in the order the
        // findings came in.
        for finding in findings {
            if outcomes[finding.id] != nil { continue }
            guard let fix = finding.fix else { continue }
            try? Task.checkCancellation()
            if stopped { break }

            switch fix {
            case .brewLink(let formula, let overwrite):
                var arguments = ["link"]
                if overwrite { arguments.append("--overwrite") }
                arguments.append(formula)
                outcomes[finding.id] = await brewOutcome(
                    finding,
                    arguments: arguments,
                    timeout: 300,
                    success: overwrite
                        ? "Homebrew replaced the old copy with a link to the \(formula) it installed."
                        : "Linked with Homebrew."
                )

            case .brewUntap(let tap):
                outcomes[finding.id] = await brewOutcome(
                    finding,
                    arguments: ["untap", tap],
                    timeout: 300,
                    success: "Homebrew has stopped tracking it. Anything installed from it stays installed."
                )

            case .brewInstall(let formula):
                outcomes[finding.id] = await brewOutcome(
                    finding,
                    arguments: ["install", formula],
                    timeout: 900,
                    success: "Installed with Homebrew."
                )

            case .brewUninstall(let formula):
                outcomes[finding.id] = await brewOutcome(
                    finding,
                    arguments: ["uninstall", formula],
                    timeout: 600,
                    success: "Removed. Its files stay in Homebrew's cellar, and `brew install \(formula)` puts it back."
                )

            case .unshadow(let formula, let stray):
                // With a stray path, the move is the first half and has already
                // happened above; the link only follows if it worked, because
                // linking over a file that is still there is what this fix
                // exists to avoid. Without one, the stray was inside Homebrew's
                // own folder, and `--overwrite` is the whole fix.
                if stray != nil, let previous = outcomes[finding.id], !previous.succeeded { continue }
                outcomes[finding.id] = await brewOutcome(
                    finding,
                    arguments: ["link", "--overwrite", formula],
                    timeout: 300,
                    success: "Homebrew's \(formula) now owns the name."
                )

            case .quarantine:
                // Reported by the move pass. Reaching here would mean the move
                // was skipped for want of a path, which the row below says.
                continue

            case .repointSymlink(let path, let target):
                outcomes[finding.id] = repoint(path: path, to: target, of: finding)

            case .rewriteShellConfig(let path, let newContents):
                outcomes[finding.id] = rewrite(path: path, contents: newContents, of: finding)
            }
        }

        return findings.map { finding in
            if let recorded = outcomes[finding.id] { return recorded }
            if finding.fix == nil {
                return outcome(
                    finding,
                    "Housekeeping does not run this one. The commands on the row are yours to run.",
                    succeeded: false
                )
            }
            return outcome(
                finding,
                stopped
                    ? "Stopped before this one ran."
                    : "Housekeeping did not get to this one.",
                succeeded: false
            )
        }
    }

    /// Cancel the whole run: the program in flight is stopped, and the loop
    /// above stops handing over new work.
    func cancel() {
        stop.stop()
        runner.cancel()
    }

    // MARK: - Grouping the moves

    private struct MoveGroup {
        let reason: String
        var findings: [EnvironmentFinding]
    }

    /// The findings that are a move into Quarantine, gathered by the sentence
    /// the record will carry.
    private func moveGroups(in findings: [EnvironmentFinding]) -> [MoveGroup] {
        var groups: [MoveGroup] = []
        for finding in findings {
            guard let fix = finding.fix, let reason = moveReason(for: fix) else { continue }
            if let index = groups.firstIndex(where: { $0.reason == reason }) {
                groups[index].findings.append(finding)
            } else {
                groups.append(MoveGroup(reason: reason, findings: [finding]))
            }
        }
        return groups
    }

    /// Why this fix moves something, or nil when it does not move anything. The
    /// unshadow case is narrowed to the half that moves: its other half is a
    /// link, which is not a move and is not grouped with these.
    private func moveReason(for fix: EnvironmentFix) -> String? {
        switch fix {
        case .quarantine:
            return Self.deadLinkReason
        case .unshadow(let formula, let stray) where stray != nil:
            return "Moved because Homebrew could not put its own \(formula) in place while this copy was here."
        case .unshadow, .brewLink, .brewUntap, .brewInstall, .brewUninstall, .repointSymlink, .rewriteShellConfig:
            return nil
        }
    }

    /// What to add to a failed move's message when the move was only half of the
    /// fix, so the reader is not left thinking the rest happened.
    private func followUpIfMoveFailed(_ finding: EnvironmentFinding) -> String {
        if case .unshadow = finding.fix { return " Homebrew's copy was left alone." }
        return ""
    }

    // MARK: - Not Homebrew

    /// Re-creates a link that points nowhere so that it points at the file that
    /// is inside the application now.
    ///
    /// The old link is removed rather than overwritten. `replaceItemAt` would do
    /// it in one step, but its behaviour when the thing being replaced is a dead
    /// symlink is not something the app can check for itself, and this way is
    /// exact: the old target is read first, so a failure to create the new link
    /// puts the old one back character for character. The link being replaced is
    /// one that leads nowhere — that is the reason this fix is being offered —
    /// so the moment between removing it and re-creating it cannot lose anything
    /// that was working.
    private func repoint(path: String, to target: String, of finding: EnvironmentFinding) -> EnvironmentOutcome {
        guard fileManager.fileExists(atPath: target) else {
            return outcome(
                finding,
                "The file inside the application is not there either, so there is nothing to point at. Nothing was changed.",
                succeeded: false
            )
        }

        let previous = try? fileManager.destinationOfSymbolicLink(atPath: path)
        do {
            try fileManager.removeItem(atPath: path)
            do {
                try fileManager.createSymbolicLink(atPath: path, withDestinationPath: target)
            } catch {
                if let previous {
                    try? fileManager.createSymbolicLink(atPath: path, withDestinationPath: previous)
                }
                throw error
            }
            return outcome(finding, "It points at the file inside the application now.", succeeded: true)
        } catch {
            return outcome(
                finding,
                "The link could not be replaced: \(error.localizedDescription)",
                succeeded: false
            )
        }
    }

    /// Writes a corrected profile file, keeping the original beside it under a
    /// dated name.
    ///
    /// The original is copied before the new text is written, not after: if the
    /// write fails halfway the reader still has the file they started with, and
    /// a backup taken afterwards could be a backup of the damaged thing. The
    /// file's permissions are captured and re-applied, because an atomic write
    /// replaces the file rather than editing it, and a profile that was readable
    /// only by its owner must not come back readable by everyone.
    private func rewrite(path: String, contents: String, of finding: EnvironmentFinding) -> EnvironmentOutcome {
        let url = URL(fileURLWithPath: path)
        guard let original = try? Data(contentsOf: url) else {
            return outcome(finding, "The file could not be read, so it was left alone.", succeeded: false)
        }

        let permissions = (try? fileManager.attributesOfItem(atPath: path))?[.posixPermissions]
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".housekeeping-\(Self.backupStamp()).backup")

        do {
            try original.write(to: backupURL, options: [.atomic])
            try Data(contents.utf8).write(to: url, options: [.atomic])
            if let permissions {
                try? fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
            }
            return outcome(
                finding,
                "Tidied. The original is beside it as \(backupURL.lastPathComponent).",
                succeeded: true
            )
        } catch {
            return outcome(
                finding,
                "The file could not be rewritten: \(error.localizedDescription). It is unchanged.",
                succeeded: false
            )
        }
    }

    private static func backupStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }

    // MARK: - Homebrew

    /// Runs one `brew` command and turns its answer into a row. The deadline is
    /// per command: `brew install` reaches the network and can legitimately take
    /// minutes, while `brew link` doing anything but finishing at once means
    /// something is wrong.
    private func brewOutcome(
        _ finding: EnvironmentFinding,
        arguments: [String],
        timeout: TimeInterval,
        success: String
    ) async -> EnvironmentOutcome {
        guard let brewPath else {
            return outcome(finding, "Homebrew is not installed, so there is nothing to run.", succeeded: false)
        }
        do {
            let result = try await runner.run(executable: brewPath, arguments: arguments, timeout: timeout)
            if result.timedOut {
                return outcome(
                    finding,
                    "Homebrew was still running after \(Int(timeout / 60)) minute\(timeout >= 120 ? "s" : "") and was stopped.",
                    succeeded: false
                )
            }
            if result.succeeded { return outcome(finding, success, succeeded: true) }
            // A process stopped by the reader comes back as a failure with a
            // signal for a status, and no words of its own. Reporting that as
            // Homebrew's error would blame it for something nobody asked it.
            if stopped {
                return outcome(finding, "Stopped partway through this one.", succeeded: false)
            }
            return outcome(
                finding,
                Self.lastMeaningfulLine(result.stderr)
                    ?? Self.lastMeaningfulLine(result.stdout)
                    ?? "Homebrew reported an error.",
                succeeded: false
            )
        } catch is CancellationError {
            // Stopping the run is the reader's own doing, so it is reported as
            // the plain fact rather than as Homebrew's or the system's failure.
            return outcome(finding, "Stopped before this one ran.", succeeded: false)
        } catch {
            return outcome(finding, error.localizedDescription, succeeded: false)
        }
    }

    /// Homebrew writes progress and warnings freely and its actual complaint last.
    private static func lastMeaningfulLine(_ text: String) -> String? {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
    }

    // MARK: - Rows

    /// A short name for the outcome list. The finding's own title is a sentence,
    /// and a list of sentences is not a list.
    private func outcome(
        _ finding: EnvironmentFinding,
        _ message: String,
        succeeded: Bool
    ) -> EnvironmentOutcome {
        EnvironmentOutcome(id: finding.id, name: name(of: finding), message: message, succeeded: succeeded)
    }

    private func name(of finding: EnvironmentFinding) -> String {
        guard let fix = finding.fix else { return finding.title }
        switch fix {
        case .brewLink(let formula, _), .brewInstall(let formula), .brewUninstall(let formula),
             .unshadow(let formula, _):
            return formula
        case .brewUntap(let tap):
            return tap
        case .quarantine(let path), .repointSymlink(let path, _), .rewriteShellConfig(let path, _):
            return (path as NSString).abbreviatingWithTildeInPath
        }
    }
}
