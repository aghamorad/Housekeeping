// Housekeeping — The Housekeeper's window
//
// A sheet rather than a tab, because the housekeeper belongs to whatever is on
// screen at the moment: you open it about a folder, not in a room of its own.
//
// The verdict strip at the top is the app's own, drawn from
// `CleanupSafetyPolicy` on every redraw and recomputed rather than remembered,
// so protecting a path while this is open cannot leave a stale verdict sitting
// above the model's prose. The model's sentences go below it. That ordering is
// the whole design: the thing that authorises a deletion is Housekeeping's, and
// the model is only ever the explanation beneath it.

import SwiftUI

struct HousekeeperView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style
    @ObservedObject private var housekeeper = Housekeeper.shared
    /// Observed in its own right. The conversation object holds the weights store
    /// as a plain `let`, so a download that starts, or finishes, or fails changes
    /// nothing the view is watching — and the sheet would sit on "Download the
    /// Housekeeper" while the file arrived behind it.
    @ObservedObject private var weights = HousekeeperWeights.shared

    @State private var draft = ""

    /// Whether there is anything for the housekeeper to be asked about. Set once,
    /// as the sheet opens, from what is on screen at that moment.
    @State private var hasGrounding = false

    /// Both the reader's turn and the "reading…" row scroll to here, so the
    /// newest thing is always the thing at the bottom edge.
    private static let bottomAnchor = "housekeeper-bottom"

    var body: some View {
        VStack(spacing: 0) {
            header
            rule
            transcript
            rule
            footer
        }
        .background(style.windowBackground)
        .frame(minWidth: 620, idealWidth: 680, minHeight: 540, idealHeight: 660)
        .onAppear {
            // A screen that is not about a scanned path hands over its own topic
            // as it opens the window, and it is taken rather than remembered: the
            // next time the housekeeper is opened from somewhere else, the topic
            // this one left behind is not still sitting on the strip.
            if let topic = appState.housekeeperTopic {
                appState.housekeeperTopic = nil
                hasGrounding = true
                housekeeper.open(topic: topic)
                return
            }
            hasGrounding = appState.inspectedItem != nil
                || !(appState.scanResults?.foundItems.isEmpty ?? true)
            // Handing over the item that is on screen is what makes the sheet
            // feel like it opened about a folder rather than beside one. With
            // nothing picked out, the housekeeper introduces itself — and is
            // handed the shape of what Housekeeping is holding, so that a
            // question asked from here has something true behind it.
            housekeeper.open(
                focusing: appState.inspectedItem,
                assessment: appState.inspectedItem.map { appState.cleanupAssessment(for: $0) },
                browsing: Self.browsingBriefing(in: appState)
            )
        }
        .onDisappear {
            // The model is put away on a delay rather than at once, so that closing
            // the housekeeper to look at something and opening it again does not pay
            // for a cold start every time.
            housekeeper.suspend()
        }
    }

    /// What Housekeeping is holding right now, as the housekeeper's facts. Built
    /// here rather than on `Housekeeper` because a verdict can only be computed by
    /// the app, and the housekeeper is deliberately not allowed to compute one.
    private static func browsingBriefing(in appState: AppState) -> String {
        let all = appState.scanResults?.foundItems ?? []
        let shown = all.prefix(Housekeeper.browsingFactLimit)
        let facts = shown.map { item -> Housekeeper.BrowsingFact in
            let assessment = appState.cleanupAssessment(for: item)
            return Housekeeper.BrowsingFact(
                name: item.path.lastPathComponent,
                verdict: Verdict.of(assessment.decision).shortLabel,
                reason: assessment.reason
            )
        }
        return Housekeeper.browsingBriefing(
            facts: facts,
            remaining: all.count - shown.count,
            scanning: appState.scanState == .scanning
        )
    }

    private var rule: some View {
        Rectangle().fill(style.border.opacity(0.5)).frame(height: 1)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            // The same mark as the menu bar, at a size where the eyes read. It
            // animates on its own clock rather than the app's, so opening the
            // sheet does not restart the octopus in the menu bar.
            TimelineView(.periodic(from: .now, by: 1.0 / 12)) { context in
                OctopusMark(time: context.date.timeIntervalSinceReferenceDate)
                    .frame(width: 34, height: 34)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("The Housekeeper")
                    .font(style.titleFont)
                    .foregroundStyle(style.text)
                Text("I explain what Housekeeping found. Housekeeping is the one that decides.")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
            }

            Spacer(minLength: 12)

            ThemeButton(title: "Close", help: "Closes the housekeeper. Nothing is cleaned either way.") {
                appState.showHousekeeper = false
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - The conversation

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    verdictStrip
                    topicStrip

                    ForEach(housekeeper.turns) { turn in
                        TurnRow(turn: turn).id(turn.id)
                    }

                    if housekeeper.isAnswering {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("The Housekeeper is reading…")
                                .font(style.smallFont)
                                .foregroundStyle(style.secondaryText)
                        }
                    }

                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Driven by the transcript rather than by a count, so the scroll
            // also happens when a turn is replaced in place.
            .onReceive(housekeeper.$turns) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
            .onReceive(housekeeper.$isAnswering) { answering in
                guard answering else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    /// Housekeeping's answer about the item on screen, above the housekeeper's
    /// own. Recomputed from the current policy on every redraw, so it cannot go
    /// stale behind the reader's back.
    @ViewBuilder
    private var verdictStrip: some View {
        if let item = housekeeper.subject {
            let assessment = appState.cleanupAssessment(for: item)
            let verdict = Verdict.of(assessment.decision)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: verdict.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(verdict.colour(in: style))

                VStack(alignment: .leading, spacing: 3) {
                    Text(verdict.shortLabel)
                        .font(style.labelFont)
                        .foregroundStyle(verdict.colour(in: style))
                    Text(assessment.reason)
                        .font(style.bodyFont)
                        .foregroundStyle(style.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.path.path)
                        .font(style.pathFont)
                        .foregroundStyle(style.secondaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.rowSelection.opacity(0.4))
        }
    }

    /// The same strip for a screen that is not about a scanned path. It carries no
    /// verdict, because these screens have none to give — Housekeeping's own policy
    /// is the only thing that can call a folder safe to remove, and a setup finding
    /// is not that. What it carries is Housekeeping's account of the thing, and it
    /// is the same account the model was handed, so the reader can see that the
    /// prose below is standing on something.
    @ViewBuilder
    private var topicStrip: some View {
        if let topic = housekeeper.topic {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: topic.tone.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(topic.tone.colour(in: style))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(topic.title)
                            .font(style.labelFont)
                            .foregroundStyle(topic.tone.colour(in: style))
                            .fixedSize(horizontal: false, vertical: true)
                        if let label = topic.label {
                            Text(label)
                                .font(style.smallFont)
                                .foregroundStyle(topic.tone.colour(in: style))
                        }
                    }
                    ForEach(topic.facts, id: \.self) { fact in
                        Text(fact)
                            .font(style.bodyFont)
                            .foregroundStyle(style.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.rowSelection.opacity(0.4))
        }
    }

    // MARK: - Getting the model, and talking to it

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let problem = housekeeper.problem {
                note(problem, colour: style.negative)
            }

            if housekeeper.runtimeIsAvailable {
                // Nothing found yet is a state the reader can still talk in — the
                // octopus in the menu bar opens the housekeeper with no window and
                // often no scan behind it, and a sheet that greets you and then
                // offers no way to answer is worse than one that says what it is
                // missing.
                //
                // The honesty is not left to the field being absent. The model is
                // told the same thing in its briefing — that Housekeeping has
                // nothing on screen, that the list is a sample, and never to
                // describe a folder it was not given — and it is told what to say
                // when it is asked about something it cannot see.
                if !hasGrounding {
                    note(
                        "Housekeeping has not found anything yet, so there is nothing in front of me. Ask anyway — but if your question is about a particular folder, point it out on screen with Ask About This, so that I can actually see it.",
                        colour: style.secondaryText
                    )
                }
                weightsArea
                askRow
            } else {
                note(
                    "This copy of Housekeeping has no model runtime inside it, so the housekeeper cannot wake up. A fresh download of the app will have one.",
                    colour: style.caution
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var weightsArea: some View {
        switch weights.state {
        case .ready:
            EmptyView()

        case .missing:
            offer(resuming: weights.partialBytes)

        case .downloading(let written, let expected):
            RetroProgressView(
                progress: Float(Double(written) / Double(max(expected, 1))),
                label: "Downloading the Housekeeper — \(Self.bytes(written)) of \(Self.bytes(expected))"
            )

        case .failed(let reason):
            VStack(alignment: .leading, spacing: 8) {
                note(reason, colour: style.negative)
                ThemeButton(
                    title: "Continue",
                    systemImage: "arrow.clockwise",
                    isPrimary: true,
                    help: "Picks the download up from what has already arrived."
                ) {
                    housekeeper.retry()
                }
            }
        }
    }

    private func offer(resuming partial: Int64) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            note(
                partial > 0
                    ? "The Housekeeper's model is partway here — \(Self.bytes(partial)) of about 380 MB. Continuing picks up from where it stopped rather than starting again."
                    : "The Housekeeper is a small language model, about 380 MB, that runs on this Mac. Housekeeping downloads it once, and from then on it works with no connection at all.",
                colour: style.secondaryText
            )

            HStack(spacing: 10) {
                ThemeButton(
                    title: partial > 0 ? "Continue the Download" : "Download the Housekeeper",
                    systemImage: "arrow.down.circle",
                    isPrimary: true,
                    help: "Downloads the model into your Library. It is a download and nothing else — no scan, no cleanup, no change to any file of yours."
                ) {
                    weights.download()
                }

                if partial > 0 {
                    ThemeButton(
                        title: "Start Over",
                        help: "Throws away what has arrived and downloads the model from the beginning. Worth trying if the connection keeps stopping in the same place."
                    ) {
                        weights.removeInstalled()
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    private var askRow: some View {
        HStack(spacing: 8) {
            // Deliberately not gated on `canAsk`. A disabled field cannot take
            // focus, so a field disabled while empty can never be typed into and
            // can never stop being empty — the reader would sit in front of a
            // greyed box with no way to ask anything. The field is live whenever
            // the model is; only the button waits for a question.
            TextField(placeholder, text: $draft)
                .textFieldStyle(.roundedBorder)
                .font(style.bodyFont)
                .disabled(!runtimeReady)
                .onSubmit(send)

            ThemeButton(
                title: "Ask",
                systemImage: "paperplane.fill",
                isPrimary: true,
                isEnabled: canAsk,
                help: "Asks the Housekeeper. It runs on this Mac and nothing you type leaves it."
            ) {
                send()
            }
        }
    }

    private var placeholder: String {
        // Both cases where something is actually in front of it — a picked-out
        // folder, or a screen's own topic — read the same to the reader, because
        // from the reader's side they are the same situation.
        housekeeper.subject == nil && housekeeper.topic == nil
            ? "Ask the Housekeeper…"
            : "Ask about this…"
    }

    /// The model is here and not already busy. This is what the question field
    /// itself waits on, and it is the whole of what the Ask button needs minus
    /// the question.
    private var runtimeReady: Bool {
        weights.state.isReady && !housekeeper.isAnswering
    }

    /// Nothing to send, or the model is not up yet, or it is still answering the
    /// last one. The button says which by being greyed rather than by explaining.
    private var canAsk: Bool {
        runtimeReady && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canAsk else { return }
        let question = draft
        draft = ""
        housekeeper.ask(question)
    }

    private func note(_ text: String, colour: Color) -> some View {
        Text(text)
            .font(style.smallFont)
            .foregroundStyle(colour)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

// MARK: - One thing said

private struct TurnRow: View {
    @Environment(\.uiStyle) private var style
    let turn: Housekeeper.Turn

    var body: some View {
        switch turn.speaker {
        case .housekeeper:
            HStack(alignment: .top, spacing: 10) {
                OctopusMark()
                    .frame(width: 22, height: 22)
                ThemePanel(padding: 10) {
                    Text(turn.text)
                        .font(style.bodyFont)
                        .foregroundStyle(style.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 430, alignment: .leading)
                }
                Spacer(minLength: 0)
            }

        case .reader:
            // The reader's own words, right-aligned and unadorned, so the two
            // voices are told apart by shape rather than by a label.
            HStack {
                Spacer(minLength: 0)
                Text(turn.text)
                    .font(style.bodyFont)
                    .foregroundStyle(style.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: 400, alignment: .leading)
                    .background(style.rowSelection)
            }
        }
    }
}
