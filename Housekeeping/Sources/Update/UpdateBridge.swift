// Housekeeping — the update feature, wired to AppState
//
// The types and the decisions all live in the files beside this one. What is here
// is the part that has to touch the app's state: read what is installed, turn it
// into rows, and run the updates the reader ticked.
//
// Two rules shape the whole file. The first is that nothing is guessed: a row's
// action is built from the provenance that was established on disk, never from the
// application's name, and a row whose provenance says "altered copy" or "part of
// macOS" gets no action at all. The second is that a Stop press never leaves a
// half-finished operation behind: reading stops at once, but an update in progress
// is allowed to finish, because interrupting `brew` or a bundle swap is the one way
// this feature could make a Mac worse.

import Foundation

@MainActor
extension AppState {

    // MARK: - Reading what is installed

    /// Starts a reading, replacing whatever the last one found.
    func startUpdateInventory() {
        updateTask?.cancel()
        updateRunner?.cancel()
        updateRunner = nil
        beginUpdateReading()
    }

    /// The reading itself, with no cancelling of anything. Kept separate because
    /// it is also what a finished run calls to bring the list up to date, and a run
    /// that cancelled itself on the way out would stop the reading it just asked for.
    func beginUpdateReading() {
        updateRows = []
        updateNotes = []
        updateStopRequested = false
        updateIsWorking = false
        updateIsReading = true

        let exceptions = updateExceptions

        updateTask = Task { [weak self] in
            guard let self else { return }
            let runner = ProcessRunner()
            self.updateRunner = runner
            let engine = AppUpdateEngine(runner: runner)

            do {
                let inventory = try await AppInventory.scan(using: runner)
                try Task.checkCancellation()
                // Asked once and shared by every row: `brew outdated` is a single
                // expensive call, and running it per package would be hundreds.
                // Deliberately after the inventory, not beside it — both drive
                // `brew`, and Homebrew takes a lock.
                let prepared = await engine.prepare()
                try Task.checkCancellation()

                var rows: [UpdateRow] = []
                for application in inventory.applications {
                    try Task.checkCancellation()
                    let key = UpdateExceptions.key(
                        forBundleIdentifier: application.bundleIdentifier,
                        path: application.path
                    ).key
                    let check = await engine.check(application: application, prepared: prepared)
                    rows.append(self.row(
                        for: application,
                        check: check,
                        prepared: prepared,
                        excepted: exceptions.isExcepted(key)
                    ))
                }
                for package in inventory.packages {
                    try Task.checkCancellation()
                    let check = await engine.check(package: package, prepared: prepared)
                    rows.append(self.row(
                        for: package,
                        check: check,
                        excepted: exceptions.isExcepted(package.id)
                    ))
                }

                self.updateApplications = inventory.applications
                self.updateRows = rows.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                self.updateNotes = inventory.notes
                self.updateIsReading = false
                self.updateRunner = nil
            } catch is CancellationError {
                self.updateIsReading = false
                self.updateRunner = nil
            } catch {
                self.updateNotes = ["The reading could not be finished: \(error.localizedDescription)"]
                self.updateIsReading = false
                self.updateRunner = nil
            }
        }
    }

    /// Stops whatever is happening. Reading stops at once and costs nothing.
    /// An update in progress is left to finish — see the note at the top of the
    /// file — and the loop between items notices the request and ends there.
    func cancelUpdateWork() {
        updateStopRequested = true
        guard updateIsReading else { return }
        updateTask?.cancel()
        updateRunner?.cancel()
        updateRunner = nil
        updateIsReading = false
    }

    // MARK: - Turning what was found into rows

    private func row(
        for application: InstalledApplication,
        check: UpdateCheck,
        prepared: AppUpdateEngine.Prepared,
        excepted: Bool
    ) -> UpdateRow {
        UpdateRow(
            id: application.bundleIdentifier,
            name: application.name,
            summary: application.summary,
            detail: "\(application.provenance.label) — \(application.url.homeAbbreviatedPath)",
            channel: application.channel,
            installedVersion: application.version,
            check: check,
            action: action(for: application, check: check, prepared: prepared),
            isExcepted: excepted,
            isSelected: UpdateRow.defaultSelection(
                channel: application.channel,
                check: check,
                isExcepted: excepted
            ),
            evidence: application.evidence,
            path: application.path
        )
    }

    private func row(
        for package: BrewPackage,
        check: UpdateCheck,
        excepted: Bool
    ) -> UpdateRow {
        UpdateRow(
            id: package.id,
            name: package.name,
            // Homebrew's own description, which is the only place a name like
            // `dav1d` or `cjson` is ever written out in words. Empty ones are
            // dropped to nil so the row shows nothing rather than an empty line.
            summary: package.summary.isEmpty ? nil : package.summary,
            detail: package.isCask ? "Homebrew cask" : "Homebrew formula",
            channel: package.channel,
            installedVersion: package.installedVersion,
            check: check,
            action: action(for: package, check: check),
            isExcepted: excepted,
            isSelected: UpdateRow.defaultSelection(
                channel: package.channel,
                check: check,
                isExcepted: excepted
            ),
            evidence: [],
            path: nil
        )
    }

    /// What Housekeeping will do about one application, from its provenance alone.
    /// An action is only ever attached when there is something to do: a row that is
    /// already current gets none, so it offers no button that would run a command
    /// to no effect.
    private func action(
        for application: InstalledApplication,
        check: UpdateCheck,
        prepared: AppUpdateEngine.Prepared
    ) -> UpdateAction? {
        guard case .available = check else { return nil }
        switch application.provenance {
        case .homebrewCask(let token):
            return .brewPackage(name: token, isCask: true)

        case .githubRelease(_), .sparkleFeed(_):
            guard case .available(_, let download) = check, let download else { return nil }
            return .replaceBundle(download: download)

        case .macAppStore:
            // The store's own tool when it is here and knows the application;
            // otherwise the page, because only the store can honour the receipt.
            if prepared.masAvailable,
               let id = prepared.masIDByName[application.name.lowercased()] {
                return .appStoreUpgrade(adamID: id)
            }
            return .openAppStoreUpdates

        case .homebrewFormula, .appleSystem, .alteredCopy, .signedByDeveloper, .unsignedOrSelfSigned:
            return nil
        }
    }

    private func action(for package: BrewPackage, check: UpdateCheck) -> UpdateAction? {
        guard case .available = check else { return nil }
        return .brewPackage(name: package.name, isCask: package.isCask)
    }

    // MARK: - Ticking

    func toggleUpdateSelection(id: String) {
        guard let index = updateRows.firstIndex(where: { $0.id == id }),
              updateRows[index].canUpdate else { return }
        updateRows[index].isSelected.toggle()
    }

    // MARK: - Doing it

    /// Runs one row's update. The row keeps its own action, so this needs no
    /// second decision about what to do — only the bundle, when the action is to
    /// replace one.
    func runUpdate(_ row: UpdateRow) {
        guard let action = row.action, !updateIsWorking, !updateIsReading else { return }
        updateOutcomes = []
        updateSummaryLine = nil
        updateStopRequested = false
        updateIsWorking = true

        let application = updateApplications.first { $0.bundleIdentifier == row.id }

        updateTask = Task { [weak self] in
            guard let self else { return }
            let runner = ProcessRunner()
            self.updateRunner = runner
            let engine = AppUpdateEngine(runner: runner)

            var outcomes: [UpdateOutcome] = []
            do {
                let outcome = try await engine.perform(action, for: application)
                outcomes.append(self.stamped(outcome, as: row))
            } catch is CancellationError {
                self.updateSummaryLine = "Stopped."
            } catch {
                outcomes.append(UpdateOutcome(
                    id: row.id,
                    name: row.name,
                    message: error.localizedDescription,
                    succeeded: false
                ))
            }
            self.updateOutcomes = outcomes
            self.finishUpdateRun(outcomes)
        }
    }

    /// Runs every ticked row Housekeeping can finish itself. The App Store, macOS,
    /// and unidentified groups are never included — not because they were filtered
    /// out of the list, but because `canInstall` is false for them, and this filter
    /// and the footer's count are the same filter.
    func runUpdateAll() {
        let targets = updateRows.filter { $0.isSelected && $0.canUpdate && $0.channel.canInstall }
        guard !targets.isEmpty, !updateIsWorking, !updateIsReading else { return }

        updateOutcomes = []
        updateSummaryLine = nil
        updateStopRequested = false
        updateIsWorking = true

        let applications = updateApplications

        updateTask = Task { [weak self] in
            guard let self else { return }
            let runner = ProcessRunner()
            self.updateRunner = runner
            let engine = AppUpdateEngine(runner: runner)

            var outcomes: [UpdateOutcome] = []
            for row in targets {
                if self.updateStopRequested { break }
                guard let action = row.action else { continue }
                let application = applications.first { $0.bundleIdentifier == row.id }
                do {
                    let outcome = try await engine.perform(action, for: application)
                    outcomes.append(self.stamped(outcome, as: row))
                } catch is CancellationError {
                    break
                } catch {
                    outcomes.append(UpdateOutcome(
                        id: row.id,
                        name: row.name,
                        message: error.localizedDescription,
                        succeeded: false
                    ))
                }
                // Published as they land, so a long run shows its progress rather
                // than a spinner that could mean anything.
                self.updateOutcomes = outcomes
            }

            self.finishUpdateRun(outcomes)
        }
    }

    /// The outcome named by the row it came from. Homebrew reports a package by
    /// its own name and the store reports an id; the list the reader is looking at
    /// knows these rows by neither.
    private func stamped(_ outcome: UpdateOutcome, as row: UpdateRow) -> UpdateOutcome {
        UpdateOutcome(id: row.id, name: row.name, message: outcome.message, succeeded: outcome.succeeded)
    }

    private func finishUpdateRun(_ outcomes: [UpdateOutcome]) {
        let succeeded = outcomes.filter(\.succeeded).count
        if updateStopRequested {
            updateSummaryLine = outcomes.isEmpty
                ? "Stopped before anything was updated."
                : "Stopped after \(outcomes.count): \(succeeded) finished."
        } else if outcomes.isEmpty {
            updateSummaryLine = "Nothing was updated."
        } else {
            updateSummaryLine = "\(succeeded) of \(outcomes.count) updated."
        }
        updateIsWorking = false
        updateRunner = nil
        // The list described the Mac as it was before the updates. It is read
        // again so the rows show what is actually installed now; the outcomes
        // above stay on screen while that happens.
        beginUpdateReading()
    }

    // MARK: - Ignoring one from now on

    func ignoreUpdate(_ row: UpdateRow) {
        let (key, kind) = exceptionKey(for: row)
        guard updateExceptions.exceptKey(key, kind: kind) else { return }
        applyUpdateExceptions()
    }

    /// Puts one thing back on offer, named by the row it was ignored from. The row
    /// only reappears after the next reading — the exception decides whether a row
    /// is offered, and the reading is what builds rows — but the state change
    /// itself is immediate and is written down.
    func offerUpdateAgain(_ row: UpdateRow) {
        let (key, _) = exceptionKey(for: row)
        offerUpdateAgain(key: key)
    }

    func offerUpdateAgain(key: String) {
        guard updateExceptions.remove(key: key) else { return }
        applyUpdateExceptions()
    }

    func offerAllUpdatesAgain() {
        guard !updateExceptions.isEmpty else { return }
        updateExceptions.removeAll()
        applyUpdateExceptions()
    }

    /// The key an application is remembered by: its bundle identifier when it has
    /// one, so the entry survives a reinstall in place, and its path when it does
    /// not. A Homebrew package has no bundle, so it is remembered by the name the
    /// package manager itself uses.
    private func exceptionKey(for row: UpdateRow) -> (key: String, kind: String) {
        guard let path = row.path else { return (row.id, "package") }
        return UpdateExceptions.key(forBundleIdentifier: row.id, path: path)
    }

    /// The one place the list and the screen are brought back into step. Every
    /// change goes through here, so nothing can change one and leave the other
    /// describing the previous answer.
    private func applyUpdateExceptions() {
        updateExceptionEntries = updateExceptions.entries
        updateExceptionNote = updateExceptions.loadFailureNote
        for index in updateRows.indices {
            let (key, _) = exceptionKey(for: updateRows[index])
            let excepted = updateExceptions.isExcepted(key)
            updateRows[index].isExcepted = excepted
            if excepted { updateRows[index].isSelected = false }
        }
    }
}
