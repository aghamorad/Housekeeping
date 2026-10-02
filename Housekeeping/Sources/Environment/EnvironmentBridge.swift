// Housekeeping — the setup check, wired to AppState
//
// The reading and the fixes all live in the files beside this one. What is here
// is the part that has to touch the app's state: run the audit, hold what it
// found, and hand the ticked findings to the fixer.
//
// Two rules shape the file, and they are the same two the update feature uses,
// because a reader should not have to learn a second set of manners for a second
// screen.
//
// The first is that a reading is cheap and a change is not. Reading runs `brew`,
// `which` and a handful of directory walks and changes nothing, so it can start
// the moment the sheet opens and be thrown away and asked again freely. Running
// the fixes is the opposite: it moves files and asks Homebrew to change its mind,
// so it only ever starts from a tick that the reader put there.
//
// The second is that Stop is honest about what it can stop. A reading stops at
// once: it costs nothing and there is nothing half-finished to leave behind. A
// fix in flight is stopped too, because unlike an update it is a single command
// rather than a swap — and anything it did get to is already in the Quarantine
// record, which is what makes stopping safe here.

import Foundation

@MainActor
extension AppState {

    // MARK: - The reading

    /// Starts a reading, replacing whatever the last one found.
    func startSetupCheck() {
        environmentTask?.cancel()
        environmentRunner?.cancel()
        environmentRunner = nil
        beginSetupReading()
    }

    /// The reading itself, with no cancelling of anything, so a Recheck from the
    /// sheet and the first open of it travel the same road.
    /// Reads the setup and hands back the task doing it, so a caller with more
    /// than one reading to run — the sweep — can wait for this one to finish
    /// rather than guess at it from the flags.
    @discardableResult
    func beginSetupReading() -> Task<Void, Never>? {
        environmentFindings = []
        environmentNotes = []
        environmentOutcomes = []
        environmentSummaryLine = nil
        environmentIsWorking = false
        environmentIsReading = true

        environmentTask = Task { [weak self] in
            guard let self else { return }
            let runner = ProcessRunner()
            self.environmentRunner = runner
            // The same `brew` for the reading and for whatever it later fixes: a
            // fix must not act on one Homebrew while the row beside it was written
            // about another.
            let brewPath = ProcessRunner.brewPath()
            let audit = EnvironmentAudit(
                runner: runner,
                homePath: NSHomeDirectory(),
                brewPath: brewPath
            )

            let report = await audit.run()

            // A reading that was stopped is not a reading that found nothing, and
            // the sheet has to be able to tell those apart — an empty list under a
            // Stop would read as a clean Mac.
            if Task.isCancelled {
                self.environmentIsReading = false
                self.environmentRunner = nil
                return
            }

            self.environmentFindings = report.findings
            self.environmentNotes = report.notes
            self.environmentHasRead = true
            self.environmentIsReading = false
            self.environmentRunner = nil
        }
        return environmentTask
    }

    /// Opens the sheet's reading, once. Reopening the sheet shows the list from
    /// the last reading rather than starting another: the reader may be partway
    /// through deciding about it, and a list that rebuilt itself under them would
    /// lose the ticks they had already made.
    func beginSetupCheckIfNeeded() {
        guard !environmentHasRead, !environmentIsReading, !environmentIsWorking else { return }
        startSetupCheck()
    }

    /// Stops whatever is happening: the reading, or the fixes. Both are stopped
    /// where they are — see the note at the top of this file for why the fix side
    /// is allowed to differ from the update feature's.
    func cancelEnvironmentWork() {
        if environmentIsReading {
            environmentTask?.cancel()
            environmentRunner?.cancel()
            environmentRunner = nil
            environmentIsReading = false
        }
        if environmentIsWorking {
            environmentFixer?.cancel()
        }
    }

    // MARK: - Doing the fixes

    /// Runs every finding the reader has ticked, and only those.
    func runEnvironmentFixes() {
        let ticked = environmentFindings.filter { $0.isSelected && $0.canFix }
        guard !ticked.isEmpty, !environmentIsWorking, !environmentIsReading else { return }

        environmentIsWorking = true
        environmentOutcomes = []
        environmentSummaryLine = nil

        let runner = ProcessRunner()
        let fixer = EnvironmentFixer(
            runner: runner,
            brewPath: ProcessRunner.brewPath()
        )
        environmentRunner = runner
        environmentFixer = fixer

        environmentTask = Task { [weak self] in
            guard let self else { return }
            let outcomes = await fixer.remediate(ticked)

            self.environmentOutcomes = outcomes
            self.environmentSummaryLine = Self.summaryLine(for: outcomes)
            self.environmentIsWorking = false
            self.environmentFixer = nil
            self.environmentRunner = nil

            // Rows that were fixed are no longer true, so they leave the list. A
            // row that failed stays, with its reason above, because the reader's
            // next move — read the message, or run the command themselves — is
            // still on that row.
            let done = Set(outcomes.filter(\.succeeded).map(\.id))
            self.environmentFindings = self.environmentFindings.filter { !done.contains($0.id) }

            // Anything moved by a fix went into the same Quarantine folder an
            // ordinary cleanup uses, so the app's idea of whether there is
            // anything to restore has just changed.
            self.refreshQuarantineAvailability()
        }
    }

    /// The one line above the outcomes. It counts what happened rather than what
    /// was asked for, because those differ exactly when something went wrong, and
    /// that is the case the line is there to make visible.
    private static func summaryLine(for outcomes: [EnvironmentOutcome]) -> String {
        let done = outcomes.filter(\.succeeded).count
        let failed = outcomes.count - done
        if failed == 0 {
            return done == 1 ? "One thing done." : "\(done) things done."
        }
        return "\(done) done, \(failed) not — each row says why."
    }
}
