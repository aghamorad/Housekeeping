import SwiftUI

/// The setup sheet: what is wrong with the shape of this Mac, and the one action
/// that would fix each thing.
///
/// Organised by `EnvironmentCategory` rather than by severity, and that choice is
/// the point of the screen. "Wrong copy" and "Not working" are answers to *how
/// bad*, and a reader who opens a screen like this is asking *what kind of thing*
/// — the ones that run the wrong program, the ones where a link leads nowhere,
/// the search path, Homebrew's own health. Each group also carries its own
/// contract, which is why those sentences are drawn under the group heading
/// rather than collected into an introduction nobody reads twice.
///
/// Two kinds of row, and they look different on purpose. A row Housekeeping will
/// act on has a tick beside it and states, in one sentence, what running it does
/// and what puts it back. A row it will not act on has no tick at all and carries
/// commands instead — the honest version of a fix the app cannot do itself,
/// because an item moved by an administrator is one Housekeeping can no longer
/// put back with the same click.
struct EnvironmentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    /// Which rows have their evidence unfolded. Kept here rather than on the row
    /// so it survives a rebuild of the list after a run.
    @State private var expandedEvidence: Set<String> = []

    private var groups: [(category: EnvironmentCategory, findings: [EnvironmentFinding])] {
        EnvironmentCategory.allCases
            .sorted { $0.order < $1.order }
            .compactMap { category in
                let rows = appState.environmentFindings.filter { $0.category == category }
                return rows.isEmpty ? nil : (category, rows)
            }
    }

    private var selectedCount: Int {
        appState.environmentFindings.filter { $0.isSelected && $0.canFix }.count
    }

    /// How many rows are Housekeeping's to run at all, which is what the header's
    /// second sentence counts. A screen that says "twelve problems" and offers
    /// three buttons has to say why.
    private var fixableCount: Int {
        appState.environmentFindings.filter(\.canFix).count
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            ThemePanel(padding: 10) { toolbar }

            if appState.environmentIsReading {
                readingState
            } else if groups.isEmpty {
                emptyState
            } else {
                list
            }

            if !appState.environmentOutcomes.isEmpty {
                outcomesPanel
            }

            footer
        }
        .padding(16)
        .frame(minWidth: 780, minHeight: 580)
        .preferredColorScheme(style.isRetro ? .light : nil)
        // The reading starts when the screen does, because none of this is worth
        // knowing until someone is looking at it — and unlike a cleanup sweep it
        // is a handful of commands, not a walk of the disk.
        .task { appState.beginSetupCheckIfNeeded() }
        // Closing stops a reading, which costs nothing and answers a question
        // nobody is looking at any more. A run of fixes is left alone: it changes
        // the Mac, and the reader who closed the window did not ask for it to
        // stop halfway.
        .onDisappear {
            if appState.environmentIsReading { appState.cancelEnvironmentWork() }
        }
    }

    // MARK: - Header and footer

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Check My Setup")
                    .font(style.titleFont)
                Text("Which copy of each command actually runs, whether your links lead anywhere, and what Homebrew says about itself.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }
            Spacer()
            ThemeButton(
                title: "Check Again",
                systemImage: "arrow.clockwise",
                isEnabled: !appState.environmentIsReading && !appState.environmentIsWorking,
                help: "Read the Mac again from the start. This only reads — it runs `which`, Homebrew's own report, and walks the binary folders. Nothing is changed by a check."
            ) { appState.startSetupCheck() }
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if !appState.environmentIsReading {
                    Text(summaryLine)
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                }
                Spacer()
            }
            ForEach(appState.environmentNotes, id: \.self) { note in
                Text(note)
                    .font(style.smallFont)
                    .foregroundColor(style.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var summaryLine: String {
        let total = appState.environmentFindings.count
        guard total > 0 else { return "Nothing to report." }
        let fixable = fixableCount
        let problems = total == 1 ? "One thing" : "\(total) things"
        if fixable == 0 {
            return "\(problems) found, and Housekeeping will not change any of them — each row carries the commands instead."
        }
        return "\(problems) found. \(fixable) of them Housekeeping can do for you; the rest are reported with the commands to run."
    }

    private var readingState: some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView()
            Text("Reading which commands run, and whether anything Homebrew put here is still in place.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
            Text("This reads only. It asks `which` about each installed program, reads Homebrew's own report about itself, and follows the links in your binary folders. Nothing is moved, installed, or removed.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            ThemeButton(
                title: "Stop",
                help: "Stop reading. Nothing has been changed, and the previous list stays as it was."
            ) { appState.cancelEnvironmentWork() }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Text(appState.environmentHasRead ? "Nothing is wrong with any of it." : "Nothing came back to report.")
                .font(style.bodyFont)
            Text(appState.environmentHasRead
                 ? "Every program on your search path runs the copy its package manager installed, Homebrew's links are in place, and no profile file repeats itself."
                 : "The reading did not finish. Press Check Again to try it once more.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(groups, id: \.category) { group in
                    categoryGroup(group.category, group.findings)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - One group

    private func categoryGroup(_ category: EnvironmentCategory, _ findings: [EnvironmentFinding]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(category.title)
                        .font(style.labelFont)
                        .foregroundColor(style.text)
                    Text("\(findings.count)")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                }
                Text(category.method)
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(findings) { finding in
                    row(finding)
                    if finding.id != findings.last?.id {
                        Rectangle()
                            .fill(style.border.opacity(0.4))
                            .frame(height: 1)
                    }
                }
            }
            .background(style.groupingBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(style.border.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }

    // MARK: - One row

    private func row(_ finding: EnvironmentFinding) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // The tick is the whole difference between the two kinds of row, so a
            // finding with no fix gets no tick at all rather than a disabled one:
            // an empty box beside a row would read as "you may also do this".
            if finding.canFix {
                ThemeCheckbox(
                    isChecked: finding.isSelected,
                    help: finding.note,
                    action: { toggle(finding.id) }
                )
            } else {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundColor(style.secondaryText)
                    .frame(width: 22, height: 22)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(finding.title)
                        .font(style.labelFont)
                        .foregroundColor(style.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(finding.severity.label)
                        .font(style.smallFont)
                        .foregroundColor(severityColour(finding.severity))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(severityColour(finding.severity).opacity(0.6), lineWidth: 1)
                        )
                }

                Text(finding.summary)
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if let fix = finding.fix {
                    Text("Housekeeping will: \(fix.label). \(fix.explanation)")
                        .font(style.smallFont)
                        .foregroundColor(style.text)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(finding.note)
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 10) {
                    evidenceToggle(finding.id)
                    if !finding.steps.isEmpty, appState.environmentHasRead {
                        CopyCommandsButton(steps: finding.steps)
                    }
                    AskHousekeeperButton(
                        topic: topic(for: finding),
                        closing: { appState.showSetupCheck = false },
                        title: "Ask what this means",
                        help: "Opens the housekeeper on this row. It explains what was found and what fixing it would do; Housekeeping is the one that decides and the one that runs anything.",
                        compact: true
                    )
                }
                .padding(.top, 1)

                if expandedEvidence.contains(finding.id) {
                    evidence(finding)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func evidenceToggle(_ id: String) -> some View {
        let isExpanded = expandedEvidence.contains(id)
        return Button {
            if isExpanded {
                expandedEvidence.remove(id)
            } else {
                expandedEvidence.insert(id)
            }
        } label: {
            HStack(spacing: 4) {
                if style.isRetro {
                    RetroDisclosureTriangle(isExpanded: isExpanded)
                } else {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                Text("What this was worked out from")
                    .font(style.smallFont)
            }
            .foregroundColor(style.secondaryText)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Hide the evidence" : "Show the evidence")
    }

    /// The facts and, when there are any, the commands. The commands are drawn in
    /// a fixed-pitch font and selectable, because the row that carries them is a
    /// row the reader has to run themselves.
    private func evidence(_ finding: EnvironmentFinding) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(finding.evidence, id: \.self) { line in
                Text(line)
                    .font(style.pathFont)
                    .foregroundColor(style.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !finding.steps.isEmpty {
                Text("Run these yourself:")
                    .font(style.smallFont)
                    .foregroundColor(style.text)
                    .padding(.top, 2)
                ForEach(finding.steps, id: \.self) { step in
                    Text(step)
                        .font(style.pathFont)
                        .foregroundColor(style.text)
                        .textSelection(.enabled)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(style.rowBackground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, 2)
    }

    /// One row, as the housekeeper is handed it.
    ///
    /// Every line here is one the row already says, plus the evidence the row
    /// keeps behind its disclosure — which is the part a reader most often wants
    /// explained, and the part the model would otherwise have to invent. Nothing
    /// in it is a verdict: Housekeeping's decisions on this screen are "will run
    /// this" and "will not", and both are stated as what they are.
    private func topic(for finding: EnvironmentFinding) -> HousekeeperTopic {
        var facts: [String] = []
        facts.append(finding.summary)
        facts.append("Housekeeping calls this \(finding.severity.label.lowercased()), under \(finding.category.title.lowercased()).")

        if let fix = finding.fix {
            facts.append("What Housekeeping would do: \(fix.label). \(fix.explanation)")
            facts.append("That is a change Housekeeping makes to this Mac, and it happens only if the reader ticks this row and presses the button at the bottom of the screen.")
        } else {
            facts.append("Housekeeping will not run this one itself. The reader is the one holding the tool.")
            if !finding.steps.isEmpty {
                facts.append("The commands offered for the reader to run themselves are:")
                facts.append(contentsOf: finding.steps.map { "  \($0)" })
            }
        }

        if !finding.evidence.isEmpty {
            facts.append("What Housekeeping worked this out from:")
            facts.append(contentsOf: finding.evidence.map { "  \($0)" })
        }

        let tone: HousekeeperTopic.Tone
        switch finding.severity {
        case .broken: tone = .broken
        case .shadowed: tone = .caution
        case .untidy: tone = .plain
        }

        return HousekeeperTopic(
            id: "setup-\(finding.id)",
            title: finding.title,
            label: finding.severity.label,
            tone: tone,
            facts: facts,
            opener: finding.canFix
                ? "What is this, and what would ticking this row actually do to my Mac?"
                : "What is this, and what would I have to do about it myself?"
        )
    }

    /// The whole screen, for the footer button: not one row but the shape of what
    /// was found, so that a question about the setup as a whole has something
    /// behind it rather than a summary the model would have to invent.
    private var overviewTopic: HousekeeperTopic {
        var facts: [String] = []

        if appState.environmentIsReading {
            facts.append("Housekeeping is reading the Mac right now, so what is on screen is not the whole picture yet.")
        }

        if appState.environmentFindings.isEmpty {
            facts.append("Housekeeping found nothing to report about the setup: no commands running the wrong copy, no libraries it could not link, no shell configuration it disagreed with.")
        } else {
            facts.append("Housekeeping found \(appState.environmentFindings.count) thing\(appState.environmentFindings.count == 1 ? "" : "s") in the setup, with its own reading of each:")
            let shown = appState.environmentFindings.prefix(25)
            for finding in shown {
                facts.append("- \(finding.title) — \(finding.severity.label). \(finding.summary)")
            }
            if appState.environmentFindings.count > shown.count {
                facts.append("- and \(appState.environmentFindings.count - shown.count) more, which are not listed here.")
            }
            facts.append("Of those, Housekeeping would run \(fixableCount) itself, and the rest carry commands for the reader to run.")
        }

        facts.append(summaryLine)

        // The worst of what is on screen, so the strip's colour is the colour of
        // the thing the reader would care about first.
        let tone: HousekeeperTopic.Tone
        if appState.environmentFindings.isEmpty {
            tone = .good
        } else if appState.environmentFindings.contains(where: { $0.severity == .broken }) {
            tone = .broken
        } else if appState.environmentFindings.contains(where: { $0.severity == .shadowed }) {
            tone = .caution
        } else {
            tone = .plain
        }

        return HousekeeperTopic(
            id: "setup-overview",
            title: "What Housekeeping found in your setup",
            label: appState.environmentFindings.isEmpty ? "Nothing to fix" : "\(appState.environmentFindings.count) found",
            tone: tone,
            facts: facts,
            opener: "Go through what you found in my setup, and tell me which parts I should care about."
        )
    }

    private func severityColour(_ severity: EnvironmentSeverity) -> Color {
        switch severity {
        case .broken: return style.negative
        case .shadowed: return style.caution
        case .untidy: return style.secondaryText
        }
    }

    private func toggle(_ id: String) {
        guard let index = appState.environmentFindings.firstIndex(where: { $0.id == id }) else { return }
        appState.environmentFindings[index].isSelected.toggle()
    }

    // MARK: - What happened

    private var outcomesPanel: some View {
        ThemePanel(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(appState.environmentSummaryLine ?? "What happened")
                    .font(style.labelFont)
                ForEach(appState.environmentOutcomes) { outcome in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(outcome.succeeded ? style.positive : style.caution)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(outcome.name)
                                .font(style.smallFont)
                                .foregroundColor(style.text)
                            Text(outcome.message)
                                .font(style.smallFont)
                                .foregroundColor(style.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(selectedCount == 0
                 ? "Nothing ticked. Tick a row Housekeeping can do for you, or press Done."
                 : "\(selectedCount) ticked\(appState.environmentIsWorking ? ", running now" : "").")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
            Spacer()
            if appState.environmentHasRead {
                AskHousekeeperButton(
                    topic: overviewTopic,
                    closing: { appState.showSetupCheck = false },
                    title: "Ask About All of This"
                )
            }
            if appState.environmentIsWorking {
                ThemeButton(
                    title: "Stop",
                    help: "Stop the fix that is running, and do not start the rest. Anything already moved is in Quarantine, and Restore puts it back."
                ) { appState.cancelEnvironmentWork() }
            }
            ThemeButton(
                title: selectedCount == 1 ? "Fix One Thing" : "Fix \(selectedCount) Things",
                systemImage: "wrench.and.screwdriver",
                isPrimary: true,
                isEnabled: selectedCount > 0 && !appState.environmentIsWorking && !appState.environmentIsReading,
                help: selectedCount == 0
                    ? "Nothing is ticked yet. Rows Housekeeping will not run carry commands instead and are never included."
                    : "Do the \(selectedCount) ticked thing\(selectedCount == 1 ? "" : "s"). Anything moved goes to Housekeeping's Quarantine, where Restore puts it back."
            ) { appState.runEnvironmentFixes() }
            ThemeButton(title: "Done", isPrimary: false) { appState.showSetupCheck = false }
        }
    }
}

/// Copies the commands on a row that Housekeeping will not run.
///
/// A command meant to be typed is a command that will be mistyped, and these are
/// the rows where the reader is the one holding the tool. The button is given the
/// whole list as one block, newline-separated, so pasting it into a terminal runs
/// them in order.
private struct CopyCommandsButton: View {
    @Environment(\.uiStyle) private var style
    let steps: [String]

    @State private var copied = false

    var body: some View {
        Button {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(steps.joined(separator: "\n"), forType: .string)
            copied = true
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                copied = false
            }
        } label: {
            Text(copied ? "Copied" : "Copy the commands")
                .font(style.smallFont)
                .foregroundColor(style.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy the commands on this row")
    }
}
