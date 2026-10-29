import AppKit
import SwiftUI

// Housekeeping — the screen that updates Housekeeping
//
// The hard part of this screen is not the check, it is being honest about what
// pressing the button does. Every other button in the app changes something
// outside itself — a file, a folder, another application. This one replaces the
// application the reader is looking at, and it does so by rebuilding it from
// source, which means it needs a source folder and a compiler and a minute of
// their time.
//
// So the screen is built as a plan first and a progress list second. Before
// anything runs it names all six steps and what each one touches; while it runs,
// the same six rows fill in, so nothing is happening that was not announced. The
// commit list is there for the same reason — "3 commits behind" is not a reason
// to replace an app, and the headlines are.
//
// Nothing here is a dialog box. The states are shown in place, on the one
// surface, because a modal asking "are you sure" on top of a page that already
// said what would happen is a second telling, not a safeguard.

struct SelfUpdateView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 14)

            hairline

            ScrollView {
                content
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            hairline

            actions
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
        }
        .frame(width: 640, height: 660)
        .background { HousekeepingBackdrop(style: style) }
        // Asked when the sheet opens rather than when the app launched: a reader
        // who came here wants the answer now, not the one from twenty minutes ago.
        .onAppear {
            if case .idle = appState.selfUpdateState {
                Task { await appState.refreshSelfUpdate() }
            }
        }
        .onChange(of: appState.selfUpdateIsHandedOff) { handedOff in
            guard handedOff else { return }
            // The swap script is already waiting on this process. Quitting is the
            // last thing the app does, and the delay is only long enough for the
            // screen to say so before the window goes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                NSApp.terminate(nil)
            }
        }
    }

    private var hairline: some View {
        Rectangle()
            .fill(style.border)
            .frame(height: 1)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            IconChip(systemImage: "arrow.triangle.2.circlepath", tint: style.accent, size: 38)

            VStack(alignment: .leading, spacing: 5) {
                Text("Housekeeping, updated")
                    .font(style.titleFont)
                    .foregroundStyle(style.text)

                Text("This copy is rebuilt from the repository's own source. Nothing is downloaded and nothing is replaced until a complete new copy has been built and checked.")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                provenanceRow
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)
        }
    }

    /// What this copy knows about itself. The commit is the one thing a version
    /// number cannot tell you here, so when it is missing the badge says so
    /// rather than leaving a gap for the reader to interpret.
    private var provenanceRow: some View {
        let provenance = appState.selfUpdateProvenance
        return HStack(spacing: 6) {
            BadgePill(
                text: provenance.version.isEmpty ? "version unknown" : provenance.version,
                systemImage: "shippingbox",
                tint: style.secondaryText
            )
            if let short = provenance.shortCommit {
                BadgePill(
                    text: short,
                    systemImage: "arrow.triangle.branch",
                    tint: style.accent
                )
            } else {
                BadgePill(
                    text: "no commit recorded",
                    systemImage: "questionmark.circle",
                    tint: style.caution
                )
            }
            if let branch = provenance.branch {
                BadgePill(text: branch, systemImage: "point.topleft.down.to.point.bottomright.curvepath", tint: style.secondaryText)
            }
            if let built = provenance.builtAt {
                BadgePill(
                    text: built.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "calendar",
                    tint: style.secondaryText
                )
            }
        }
    }

    // MARK: - Body

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            if appState.selfUpdateIsRunning || appState.selfUpdateFailure != nil {
                stepList
            }

            if let failure = appState.selfUpdateFailure {
                failurePanel(failure)
            } else if !appState.selfUpdateIsRunning {
                verdict
            }

            sourcePanel
        }
        .animation(HousekeepingMotion.entrance, value: appState.selfUpdateState)
    }

    // MARK: The verdict

    @ViewBuilder
    private var verdict: some View {
        switch appState.selfUpdateState {
        case .idle, .checking:
            checking

        case .upToDate(let report):
            upToDate(report)

        case .available(let report):
            available(report)

        case .unknown(let reason, let latest):
            unknown(reason: reason, latest: latest)
        }
    }

    private var checking: some View {
        VStack(spacing: 16) {
            HeroMeter(
                progress: nil,
                symbol: "arrow.triangle.branch",
                caption: "Asking the repository which commits exist",
                detail: "One request, no token, nothing sent about you",
                size: 150
            )
            .frame(maxWidth: .infinity)
        }
        .entrance()
    }

    private func upToDate(_ report: SelfUpdateReport) -> some View {
        VStack(spacing: 16) {
            HeroMeter(
                progress: 1,
                symbol: "checkmark",
                caption: "This copy is level with the published source",
                detail: report.localCommit.map { "built from \(String($0.prefix(7)))" },
                size: 150
            )
            .frame(maxWidth: .infinity)
        }
        .entrance()
    }

    private func available(_ report: SelfUpdateReport) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                HeroMeter(
                    progress: nil,
                    symbol: "arrow.down.circle",
                    caption: "behind the published source",
                    size: 128
                )
                .frame(width: 176)

                VStack(alignment: .leading, spacing: 8) {
                    Text(SelfUpdateView.behindSentence(report))
                        .font(style.bodyFont.weight(.semibold))
                        .foregroundStyle(style.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Updating fast-forwards the source folder to the newest commit and builds a new copy of Housekeeping from it. The copy you are using now is kept, not deleted.")
                        .font(style.smallFont)
                        .foregroundStyle(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !report.commits.isEmpty {
                commitList(report.commits)
            }

            planPanel
        }
        .entrance()
    }

    /// Shared with the welcome screen's footer, which says the same thing in one
    /// short line. Both read it from here so the two can never disagree about how
    /// far behind this copy is.
    static func behindSentence(_ report: SelfUpdateReport) -> String {
        guard let count = report.behindBy else {
            return "The published source has commits this copy does not."
        }
        switch count {
        case 0: return "This copy is level with the published source."
        case 1: return "One commit on the published source is not in this copy."
        default: return "\(count) commits on the published source are not in this copy."
        }
    }

    /// The footer's version, which has to fit on one line beside the number it is
    /// qualifying. It says where this copy stands, not what it would take to
    /// change that — the screen behind the button is where that is explained.
    static func footerLabel(for report: SelfUpdateReport) -> String {
        guard let count = report.behindBy else { return "Update available" }
        switch count {
        case 0: return "Up to date"
        case 1: return "One commit behind"
        default: return "\(count) commits behind"
        }
    }

    private func commitList(_ commits: [SelfUpdateCommit]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT WOULD COME IN")
                .font(style.labelFont)
                .foregroundStyle(style.secondaryText)

            VStack(spacing: 2) {
                ForEach(Array(commits.prefix(12).enumerated()), id: \.element.id) { index, commit in
                    commitRow(commit)
                        .entrance(delay: Double(index) * 0.035)
                }
            }

            if commits.count > 12 {
                Text("…and \(commits.count - 12) more, all included either way.")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
            }
        }
    }

    private func commitRow(_ commit: SelfUpdateCommit) -> some View {
        HStack(alignment: .top, spacing: 10) {
            IconChip(systemImage: "arrow.triangle.branch", tint: style.accent, size: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(commit.headline)
                    .font(style.bodyFont)
                    .foregroundStyle(style.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(commit.shortSHA)
                        .font(style.pathFont)
                        .foregroundStyle(style.secondaryText)
                    Text("·").foregroundStyle(style.secondaryText)
                    Text(commit.author)
                        .font(style.smallFont)
                        .foregroundStyle(style.secondaryText)
                    if let date = commit.date {
                        Text("·").foregroundStyle(style.secondaryText)
                        Text(date, style: .relative)
                            .font(style.smallFont)
                            .foregroundStyle(style.secondaryText)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .hoverHighlight(cornerRadius: 8, hovered: style.rowBackground, stroke: style.border.opacity(0.5))
    }

    // MARK: The plan

    /// The six steps, named before anything runs. This is the whole safeguard:
    /// not a confirmation dialog, but a list of what is about to be touched that
    /// the reader can read at their own speed and then agree to.
    private var planPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT PRESSING THE BUTTON DOES")
                .font(style.labelFont)
                .foregroundStyle(style.secondaryText)

            TrayBar {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(SelfUpdateStep.allCases.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(index + 1)")
                                .font(style.smallFont.weight(.semibold))
                                .foregroundStyle(style.secondaryText)
                                .frame(width: 16, alignment: .trailing)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(step.title)
                                    .font(style.bodyFont)
                                    .foregroundStyle(style.text)
                                Text(step.detail)
                                    .font(style.pathFont)
                                    .foregroundStyle(style.secondaryText.opacity(0.85))
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Unknown

    private func unknown(reason: String, latest: SelfUpdateCommit?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                IconChip(systemImage: "questionmark.circle", tint: style.caution, size: 34)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Housekeeping could not tell whether this copy is current")
                        .font(style.bodyFont.weight(.semibold))
                        .foregroundStyle(style.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(reason)
                        .font(style.bodyFont)
                        .foregroundStyle(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let latest {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The newest commit on the published source")
                        .font(style.labelFont)
                        .foregroundStyle(style.secondaryText)
                    commitRow(latest)
                }
            }

            Text("Not knowing is not the same as being up to date, so this screen will not say you are. Checking again costs nothing.")
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .entrance()
    }

    // MARK: Running

    private var stepList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appState.selfUpdateIsHandedOff ? "FINISHING" : "UPDATING")
                .font(style.labelFont)
                .foregroundStyle(style.secondaryText)

            TrayBar {
                VStack(alignment: .leading, spacing: 0) {
                    // The app's own update is six named steps, so its length is
                    // known before it starts: a bar over them is the honest picture
                    // of where it is, in one line, above the step list that says
                    // what each one is doing.
                    ProgressBar(
                        fraction: Double(doneStepCount) / Double(SelfUpdateStep.allCases.count),
                        caption: appState.selfUpdateIsRunning
                            ? "Step \(min(doneStepCount + 1, SelfUpdateStep.allCases.count)) of \(SelfUpdateStep.allCases.count)"
                            : "Update",
                        detail: runningStepTitle,
                        height: 9
                    )
                    .padding(.bottom, 4)

                    ForEach(SelfUpdateStep.allCases) { step in
                        stepRow(step)
                    }
                }
                .padding(.vertical, 2)
            }

            if appState.selfUpdateIsHandedOff {
                Text("The new copy is built and checked, and Housekeeping is about to close so it can be put in place. It reopens on its own — if it does not, the old copy is still in Application Support.")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    /// How many steps have finished. Failed and handed-off count as finished: the
    /// bar is about where the work has got to, not about how it went.
    private var doneStepCount: Int {
        SelfUpdateStep.allCases.reduce(0) { total, step in
            let state = appState.selfUpdateSteps[step] ?? .pending
            return total + (state.isPending || state.isRunning ? 0 : 1)
        }
    }

    private var runningStepTitle: String? {
        for step in SelfUpdateStep.allCases
        where (appState.selfUpdateSteps[step] ?? .pending).isRunning {
            return step.title
        }
        return nil
    }

    private func stepRow(_ step: SelfUpdateStep) -> some View {
        let state = appState.selfUpdateSteps[step] ?? .pending
        return HStack(alignment: .top, spacing: 10) {
            stepMark(state)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(style.bodyFont)
                    .foregroundStyle(state.isPending ? style.secondaryText : style.text)
                if let line = state.detailLine {
                    Text(line)
                        .font(style.pathFont)
                        .foregroundStyle(state.isFailed ? style.negative : style.secondaryText.opacity(0.85))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if case .running = state {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(state.isRunning ? style.accent.opacity(0.12) : Color.clear)
        )
        .animation(HousekeepingMotion.settle, value: state)
    }

    @ViewBuilder
    private func stepMark(_ state: SelfUpdateStepState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 11))
                .foregroundStyle(style.secondaryText.opacity(0.5))
        case .running:
            Image(systemName: "circle.dotted")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.accent)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.positive)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(style.negative)
        }
    }

    // MARK: Failure

    private func failurePanel(_ failure: SelfUpdateFailure) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconChip(systemImage: "exclamationmark.triangle", tint: style.negative, size: 34)

                VStack(alignment: .leading, spacing: 6) {
                    Text("The update stopped")
                        .font(style.bodyFont.weight(.semibold))
                        .foregroundStyle(style.text)

                    Text(failure.errorDescription ?? "No reason was given.")
                        .font(style.bodyFont)
                        .foregroundStyle(style.secondaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Nothing about the copy you are using has changed, so there is nothing to undo.")
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(style.negative.opacity(0.10))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style.negative.opacity(0.30), lineWidth: 1)
        }
        .entrance()
    }

    // MARK: - The source folder

    /// Where the update gets its source, and the one fact that decides whether it
    /// can run at all. Shown whether or not an update is available, because a
    /// reader looking at "you are current" on a copy with no source folder has
    /// been told something less useful than they think.
    private var sourcePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("THE FOLDER THIS COPY WAS BUILT FROM")
                .font(style.labelFont)
                .foregroundStyle(style.secondaryText)

            HStack(alignment: .top, spacing: 10) {
                IconChip(
                    systemImage: appState.selfUpdateSource == nil ? "folder.badge.questionmark" : "folder",
                    tint: appState.selfUpdateSource == nil ? style.caution : style.accent,
                    size: 24
                )

                VStack(alignment: .leading, spacing: 3) {
                    if let source = appState.selfUpdateSource {
                        Text(source.tree.path)
                            .font(style.pathFont)
                            .foregroundStyle(style.text)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        Text(sourceExplanation(source))
                            .font(style.smallFont)
                            .foregroundStyle(style.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Not found")
                            .font(style.bodyFont.weight(.semibold))
                            .foregroundStyle(style.text)

                        Text("Housekeeping did not ship as a download, so it can only rebuild itself from the folder that built it. It is not in any of the usual places on this Mac — it may have been built elsewhere and copied here. Point it at the folder and this becomes a one-press update again.")
                            .font(style.smallFont)
                            .foregroundStyle(style.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                if !appState.selfUpdateIsRunning {
                    ThemeButton(
                        title: appState.selfUpdateSource == nil ? "Choose…" : "Change…",
                        systemImage: "folder",
                        help: "Pick the Housekeeping source folder — the one holding .git and script/package_release.sh. Housekeeping remembers it."
                    ) {
                        chooseSourceFolder()
                    }
                }
            }
        }
    }

    private func sourceExplanation(_ source: SelfUpdateSource) -> String {
        if !source.remoteMatches {
            return "This folder's git remote is not aghamorad/Housekeeping. Updating would pull from whatever it does point at, which is not the published history — check the remote before using this."
        }
        if !source.canWriteDestination {
            return "Housekeeping cannot write next to \(source.destination.path), so it can build the new copy but not put it in place. It will tell you where the built copy is."
        }
        return "Fast-forwards from origin/\(SelfUpdateChecker.branch), then replaces \(source.destination.lastPathComponent). The copy in use now is moved to Application Support, not deleted."
    }

    private func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose the Housekeeping source folder — the one containing .git and script/package_release.sh."
        if let start = appState.selfUpdateSource?.tree {
            panel.directoryURL = start
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard SourceTreeLocator.isSourceTree(url) else {
            appState.selfUpdateSource = nil
            return
        }
        appState.adoptSelfUpdateSource(url)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 10) {
            if appState.selfUpdateIsRunning {
                Text(appState.selfUpdateIsHandedOff
                     ? "Closing in a moment…"
                     : "Working. This screen stays open until the build finishes.")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)

                Spacer()

                ThemeButton(
                    title: "Hide",
                    systemImage: "eye.slash",
                    help: "Put this window away. The update keeps running and Housekeeping reopens by itself when it is done."
                ) {
                    appState.showSelfUpdate = false
                }
            } else {
                if let tree = appState.selfUpdateSource?.tree {
                    ThemeButton(
                        title: "Open the Folder",
                        systemImage: "arrow.up.forward.app",
                        help: "Show \(tree.path) in the Finder."
                    ) {
                        NSWorkspace.shared.open(tree)
                    }
                }

                ThemeButton(
                    title: "Open on GitHub",
                    systemImage: "safari",
                    help: "The published source, in case you would rather read the commits there or update by hand."
                ) {
                    NSWorkspace.shared.open(AppState.repositoryURL)
                }

                Spacer()

                ThemeButton(
                    title: "Check Again",
                    systemImage: "arrow.clockwise",
                    help: "Ask the repository again. Costs nothing and does not change anything."
                ) {
                    Task { await appState.refreshSelfUpdate() }
                }

                if case .available = appState.selfUpdateState, appState.selfUpdateSource != nil {
                    ThemeButton(
                        title: "Update Now",
                        systemImage: "arrow.down.circle.fill",
                        isPrimary: true,
                        help: "Fast-forward the source folder, build a new copy, check it is signed, then move it into place and reopen. Housekeeping's copy in use is kept."
                    ) {
                        Task { await appState.runSelfUpdate() }
                    }
                }
            }
        }
        .frame(minHeight: 30)
    }
}

// MARK: - Reading a step's state

private extension SelfUpdateStepState {
    var isPending: Bool {
        if case .pending = self { return true }
        return false
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    /// What the row shows beside the step: a short word for a step that finished,
    /// the reason for one that did not, and nothing at all while it is going —
    /// a line that said "working" under a row already showing a spinner would be
    /// saying it twice.
    var detailLine: String? {
        switch self {
        case .pending, .running:
            return nil
        case .done(let note):
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .failed(let reason):
            return reason.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
