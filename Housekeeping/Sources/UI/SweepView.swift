// Housekeeping — the sweep
//
// One button, every reading, one account of what was found.
//
// The app already had three readings, each behind its own button on its own
// screen, and a reader who wanted the whole picture had to know all three
// existed and press them in turn. The sweep is that same work under one press:
// the disk, the setup, and updates, run in sequence, then one screen saying what
// each of them found.
//
// It reads, and only reads. Nothing is ticked here, nothing is moved, nothing is
// installed, and no fix is run — every count on the results screen is a count of
// things to look at, and each one is a door to the screen that already asks
// before it changes anything. That is the whole reason the sweep can be a single
// button: it takes no decisions on the reader's behalf, so there is nothing for
// them to have wanted a say in.

import SwiftUI

/// The sweep screen, in both of its halves.
///
/// Working and results are one screen rather than two because they are one
/// action. The octopus that did the searching is the one that hands back what it
/// found; swapping to a differently-shaped screen at the end would make the
/// looking and the answer read as two separate features.
struct SweepScreen: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if appState.isSweeping {
            SweepWorkingScreen()
        } else {
            SweepResultsScreen()
        }
    }
}

// MARK: - While it is looking

/// What the window shows from the press until the last reading is back.
private struct SweepWorkingScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    var body: some View {
        ScreenChrome(title: "Housekeeping", subtitle: "The housekeeper is looking around") {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 18) {
                        masthead
                        ThemePanel { stages }
                        assurance
                    }
                    .padding(20)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }

                footer
            }
        }
    }

    private var masthead: some View {
        VStack(spacing: 10) {
            WorkingOctopus(size: 104)

            Text(stageTitle)
                .font(style.titleFont)
                .foregroundStyle(style.text)
                .multilineTextAlignment(.center)

            Text(stageDetail)
                .font(style.bodyFont)
                .foregroundStyle(style.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(elapsedLine)
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
            }
        }
    }

    /// The three readings as a list, so the reader can see that this is three
    /// things and roughly how far along it is, rather than an open-ended spinner.
    private var stages: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(SweepStage.allCases, id: \.self) { stage in
                HStack(alignment: .top, spacing: 10) {
                    marker(for: stage)
                        .frame(width: 16, height: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.shortTitle)
                            .font(style.labelFont)
                            .foregroundStyle(state(of: stage) == .waiting ? style.secondaryText : style.text)
                        Text(stage.detail)
                            .font(style.smallFont)
                            .foregroundStyle(style.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(for stage: SweepStage) -> some View {
        switch state(of: stage) {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(style.positive)
        case .working:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        case .waiting:
            Image(systemName: "circle.dotted")
                .foregroundStyle(style.secondaryText)
        }
    }

    private var assurance: some View {
        Text("Reading only. Nothing is ticked, nothing is moved, nothing is installed — when it is done you get the findings, and every one of them still asks before anything changes.")
            .font(style.smallFont)
            .foregroundStyle(style.secondaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack {
            Spacer()
            ThemeButton(
                title: "Stop",
                systemImage: "stop.fill",
                help: "Stop the sweep where it stands. The readings in flight are dropped and the window goes back to the opening screen — nothing was moved, installed or changed, so there is nothing to undo."
            ) {
                appState.cancelSweep()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(style.groupingBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(style.border).frame(height: 1)
        }
    }

    private enum StageState { case done, working, waiting }

    private func state(of stage: SweepStage) -> StageState {
        guard let current = appState.sweepStage else { return .done }
        if stage.rawValue < current.rawValue { return .done }
        if stage.rawValue == current.rawValue { return .working }
        return .waiting
    }

    private var stageTitle: String {
        appState.sweepStage?.title ?? "Writing it up"
    }

    private var stageDetail: String {
        appState.sweepStage?.detail
            ?? "Putting the three readings together into one list of what to look at."
    }

    private var elapsedLine: String {
        guard let started = appState.sweepStartedAt else { return " " }
        let seconds = max(0, Int(Date().timeIntervalSince(started)))
        if seconds < 5 { return "Just started." }
        if seconds < 60 { return "Looking for \(seconds) seconds." }
        let minutes = seconds / 60
        return minutes == 1 ? "Looking for a minute." : "Looking for \(minutes) minutes."
    }
}

// MARK: - What it found

/// The one screen the sweep leaves behind.
private struct SweepResultsScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    var body: some View {
        ScreenChrome(title: "Housekeeping", subtitle: "Everything the housekeeper found") {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 16) {
                        masthead
                        diskPanel
                        setupPanel
                        updatesPanel
                    }
                    .padding(20)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity)
                }

                footer
            }
        }
    }

    private var masthead: some View {
        VStack(spacing: 8) {
            OctopusMark(effort: 0.35)
                .frame(width: 72, height: 72)

            Text(headline)
                .font(style.titleFont)
                .foregroundStyle(style.text)
                .multilineTextAlignment(.center)

            Text("Nothing has been changed. Each section opens the screen that owns it, where you tick what you agree to.")
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: The disk

    private var diskItems: [FoundItem] { appState.recommendedCleanupItems }

    private var diskPanel: some View {
        section(
            title: "The disk",
            headline: diskHeadline,
            body: diskBody,
            // No door when there is no room behind it: if the disk reading did not
            // finish there is no findings screen to open, and a button that led
            // back to the welcome screen would read as the sweep having lost it.
            actionTitle: (diskItems.isEmpty || appState.scanResults == nil) ? nil : "Look at the Disk List",
            help: "Open the findings screen. Nothing is ticked there either until you tick it.",
            isPrimary: true
        ) {
            appState.dismissSweepResults()
            appState.advanceFlow(.review)
        }
    }

    private var diskHeadline: String {
        guard let summary = appState.scanResults?.summary else {
            return "The disk could not be read."
        }
        if diskItems.isEmpty {
            return summary.itemCount == 0
                ? "Nothing to clean up on the disk."
                : "Nothing Housekeeping would recommend moving."
        }
        let size = diskItems.reduce(Int64(0)) { $0 + $1.size }.humanReadable
        return "\(diskItems.count) thing\(diskItems.count == 1 ? "" : "s") worth a look, about \(size)."
    }

    private var diskBody: String {
        guard let summary = appState.scanResults?.summary else {
            return "The scan did not finish, so there is nothing to report here. The setup and update readings below still ran."
        }
        if diskItems.isEmpty {
            return "The scan measured \(summary.itemCount) item\(summary.itemCount == 1 ? "" : "s") and found none that Housekeeping would recommend moving. The full list is still on the disk screen if you want to look through it."
        }
        return "Of \(summary.itemCount) item\(summary.itemCount == 1 ? "" : "s") measured, these are the ones Housekeeping would recommend. Everything must still be ticked by you, and moving anything into Quarantine is reversible."
    }

    // MARK: The setup

    private var fixableFindings: Int {
        appState.environmentFindings.filter(\.canFix).count
    }

    private var setupPanel: some View {
        section(
            title: "The setup",
            headline: setupHeadline,
            body: setupBody,
            actionTitle: "Open the Setup Check",
            help: "Open the setup findings. Each one states what it will change and what would undo it before you can tick it.",
            isPrimary: false
        ) {
            appState.dismissSweepResults()
            appState.showSetupCheck = true
        }
    }

    private var setupHeadline: String {
        let count = appState.environmentFindings.count
        if count == 0 { return "Nothing wrong with the tools." }
        if fixableFindings == 0 {
            return "\(count) thing\(count == 1 ? "" : "s") about your tools, none Housekeeping can fix itself."
        }
        return "\(count) thing\(count == 1 ? "" : "s") about your tools, \(fixableFindings) with a one-step fix."
    }

    private var setupBody: String {
        let count = appState.environmentFindings.count
        if count == 0 {
            return "Every command resolved to the program it should, and every link reached it. Nothing needs doing."
        }
        let rest = count - fixableFindings
        var body = "These are the things a person debugging a broken command would find: a command shadowed by a stray copy, a link leading nowhere, a package installed but not linked. Each is one row, said in a sentence."
        if rest > 0 {
            body += " \(rest) need an administrator, or would be Housekeeping guessing at what you meant, so those are shown with the command and no button."
        }
        return body
    }

    // MARK: Updates

    private var outdatedUpdates: [UpdateRow] {
        appState.updateRows.filter {
            if case .available = $0.check { return true }
            return false
        }
    }

    private var updatesPanel: some View {
        section(
            title: "Updates",
            headline: updatesHeadline,
            body: updatesBody,
            actionTitle: "Open Update Apps",
            help: "Open the update list. Updating is never done by the sweep — each row is yours to tick.",
            isPrimary: false
        ) {
            appState.dismissSweepResults()
            appState.showUpdateList = true
        }
    }

    private var updatesHeadline: String {
        if appState.updateIsReading {
            return "Still asking about updates."
        }
        if appState.updateRows.isEmpty {
            return "Nothing was found to update."
        }
        let count = outdatedUpdates.count
        if count == 0 { return "Everything installed is up to date." }
        return "\(count) update\(count == 1 ? "" : "s") available."
    }

    private var updatesBody: String {
        if appState.updateRows.isEmpty {
            if let note = appState.updateNotes.first {
                return note
            }
            return "The reading did not return a list. Nothing has been changed."
        }
        var body = "\(appState.updateRows.count) applications and packages were read, grouped by where their updates actually come from."
        if !appState.updateNotes.isEmpty {
            body += " " + appState.updateNotes[0]
        }
        return body
    }

    // MARK: Shared chrome

    private var headline: String {
        let problems = diskItems.count + appState.environmentFindings.count + outdatedUpdates.count
        if problems == 0 {
            return "The housekeeper found nothing that needs you."
        }
        return "The housekeeper found \(problems) thing\(problems == 1 ? "" : "s") to look at."
    }

    @ViewBuilder
    private func section(
        title: String,
        headline: String,
        body: String,
        actionTitle: String?,
        help: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        ThemePanel {
            VStack(alignment: .leading, spacing: 8) {
                Text(title.uppercased())
                    .font(style.labelFont)
                    .foregroundStyle(style.secondaryText)

                Text(headline)
                    .font(style.bodyFont)
                    .foregroundStyle(style.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(body)
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle {
                    HStack {
                        ThemeButton(
                            title: actionTitle,
                            isPrimary: isPrimary,
                            help: help,
                            action: action
                        )
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            Text("The sweep never ticks anything for you.")
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
            Spacer()
            ThemeButton(
                title: "Done",
                help: "Close these results. Nothing is changed by doing this; the scan's own summary is still behind this screen."
            ) {
                appState.dismissSweepResults()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(style.groupingBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(style.border).frame(height: 1)
        }
    }
}

// MARK: - What the housekeeper is handed while the sweep is on screen

extension AppState {
    /// The sweep's own subject. The bar normally follows `scanState`, which says
    /// nothing about a sweep — during one, the disk reading has already finished
    /// and its summary would be the wrong answer to "what is on screen".
    var sweepHousekeeperTopic: HousekeeperTopic {
        var facts: [String] = []

        if isSweeping {
            facts.append("A sweep is running: Housekeeping is reading the disk, checking the setup, and asking about updates, one after another. The octopus on the screen is doing that work.")
            facts.append("A sweep only reads. Nothing is ticked, moved, cleaned or installed while it runs, and nothing will be after it finishes — it ends by showing what each reading found, and each of those screens asks per item before anything changes.")
            if let stage = sweepStage {
                facts.append("It is on: \(stage.title). \(stage.detail)")
            }
        } else {
            facts.append("This is the result of a sweep — the three readings run in one go.")
            facts.append("The disk reading recommends \(recommendedCleanupItems.count) of the \(scanResults?.summary.itemCount ?? 0) items it measured.")
            facts.append("The setup reading found \(environmentFindings.count) things, of which \(environmentFindings.filter(\.canFix).count) have a one-step fix Housekeeping can run with your agreement.")
            facts.append("The update reading found \(updateRows.filter { if case .available = $0.check { return true }; return false }.count) updates among \(updateRows.count) applications and packages.")
            facts.append("Nothing has been changed by any of it. Every count here is a door to the screen that owns that job, and each of those screens ticks nothing until the reader ticks it.")
        }

        return HousekeeperTopic(
            id: isSweeping ? "sweep-running" : "sweep-results",
            title: isSweeping ? "The sweep, running" : "What the sweep found",
            label: isSweeping ? (sweepStage?.shortTitle ?? "Looking") : "Three readings",
            tone: .plain,
            facts: facts,
            opener: isSweeping
                ? "What is Housekeeping doing right now, and does it change anything?"
                : "What did the sweep find, and what happens if I do nothing?"
        )
    }
}
