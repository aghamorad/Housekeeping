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
    @State private var showContext = false

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
        .background { HousekeepingBackdrop(style: style) }
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
                Text("Ask about your Mac, your files, or the task you want to do.")
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
                    if let path = housekeeper.inspectedQuestionFolder {
                        Text("Discussing: " + path).font(style.smallFont).foregroundStyle(style.secondaryText).textSelection(.enabled)
                    }
                    DisclosureGroup("Context from Housekeeping", isExpanded: $showContext) { topicStrip }
                        .font(style.smallFont)
                    if housekeeper.turns.count <= 1 {
                        HStack(spacing: 8) {
                            Button("What can you help me with?") { ask("What can you help me with?") }
                            Button("Help me free space") { ask("Help me free space. Where should I start?") }
                        }.font(style.smallFont).disabled(!runtimeReady)
                    }

                    ForEach(housekeeper.turns) { turn in
                        TurnRow(turn: turn).id(turn.id)
                    }

                    if housekeeper.isAnswering {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Thinking…")
                                .font(style.smallFont)
                                .foregroundStyle(style.secondaryText)
                            Spacer()
                            Button("Stop") { housekeeper.stopAnswer() }.font(style.smallFont)
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

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let problem = housekeeper.problem { note(problem, colour: style.negative) }
            HousekeeperModelControls(onNotNow: { appState.showHousekeeper = false })
            HStack {
                Button("New conversation") { housekeeper.clear() }
                    .disabled(housekeeper.isAnswering)
                Spacer()
                Menu("Open a tool") {
                    Button("Disk Browser") { appState.screen = .diskBrowser }
                    Button("Clean Up") { appState.screen = .clean }
                    Button("Update Apps") { appState.screen = .updateList }
                    Button("Terminal Health") { appState.screen = .setupCheck }
                    Button("Two Folders") { appState.screen = .reconcile }
                    Button("Quarantine") { appState.screen = .quarantine }
                }
            }.font(style.smallFont)
            if housekeeper.canChat { askRow }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            ? "Talk to the Housekeeper…"
            : "Ask a question…"
    }

    /// The model is here and not already busy. This is what the question field
    /// itself waits on, and it is the whole of what the Ask button needs minus
    /// the question.
    private var runtimeReady: Bool {
        housekeeper.canChat && !housekeeper.isAnswering
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
        ask(question)
    }

    private func ask(_ question: String) {
        guard runtimeReady else { return }
        housekeeper.ask(question, context: liveContext, assessment: housekeeper.subject.map { appState.cleanupAssessment(for: $0) }, folderRequest: folderRequest)
    }

    private var folderRequest: HousekeeperFolderEvidence.Request {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var locations: [HousekeeperFolderEvidence.Location] = []
        for rule in RuleEngine.shared.applications {
            for known in rule.knownPaths {
                locations.append(.init(path: known.expand(to: home).path, purpose: known.description, owner: rule.name, source: rule.documentationURL ?? rule.homepageURL))
            }
        }
        if let snapshot = appState.diskBrowser.snapshot {
            locations.append(contentsOf: snapshot.nodes.values.map { .init(path: $0.path, bytes: $0.isUnmeasured ? nil : $0.size, measuredAt: snapshot.measuredAt, isPartial: $0.isPartial) })
        }
        locations.append(contentsOf: appState.cleaner.candidates.map { .init(path: $0.url.path, bytes: $0.size) })
        locations.append(contentsOf: (appState.scanResults?.foundItems ?? []).map { .init(path: $0.path.path, bytes: $0.size) })
        let topicPath = housekeeper.topic.flatMap { topic -> String? in
            let prefix = "disk-browser-"
            guard topic.id.hasPrefix(prefix) else { return nil }
            let path = String(topic.id.dropFirst(prefix.count))
            return path.hasPrefix("/") ? path : nil
        }
        let focus = housekeeper.inspectedQuestionFolder ?? housekeeper.subject?.path.path ?? topicPath
            ?? (appState.workspace == .diskBrowser ? appState.diskBrowser.currentPath : nil)
        return .init(focusedPath: focus, locations: locations, home: home.path)
    }

    /// Read at submission time, not frozen when the panel first opened.
    private var liveContext: String {
        var lines = ["CURRENT STATUS (refreshed for this question):", "Active local model: " + weights.activeModelName + ". Chat runs on this Mac. No internet browsing or arbitrary file access is available to the model."]
        lines.append("Screen behind this panel: " + (appState.workspace?.rawValue ?? (appState.showOverview ? "Overview" : "Scan results")))
        switch appState.scanState {
        case .idle: lines.append("Main scan: idle; no main scan has run in this session.")
        case .scanning: lines.append("Main scan: running. " + appState.scanProgress.title)
        case .complete: lines.append("Main scan: complete; \(appState.scanResults?.foundItems.count ?? 0) findings. This was a bounded scan, not a complete inventory of the entire Mac.")
        case .error: lines.append("Main scan: failed. " + (appState.lastErrorMessage ?? "No error details recorded."))
        }
        let disk = appState.diskBrowser
        if let snapshot = disk.snapshot {
            lines.append("Disk Browser snapshot: root \(snapshot.root), measured \(snapshot.measuredAt.formatted()), complete: \(snapshot.isComplete). Recorded apparent size: \(snapshot.totalSize.sizeDescription). This is a dated measurement of folders, not a list of every file or space recoverable by deletion.")
            lines.append("Disk Browser current folder: \(disk.currentPath). Measurement currently running: \(disk.isScanning). Visible rows below are a sample, in the user's chosen order/filter:")
            for node in disk.visibleChildren.prefix(6) {
                lines.append("Folder: \(node.path), \(node.isUnmeasured ? "size unknown" : node.size.sizeDescription), partial: \(node.isPartial).")
            }
        } else {
            lines.append("Disk Browser has no recorded measurement. Measurement currently running: \(disk.isScanning).")
        }
        let cleaner = appState.cleaner
        lines.append("Clean Up scan: \(cleaner.phase). \(cleaner.progressLine) \(cleaner.candidates.count) candidates, \(cleaner.completedCategories.count) of 6 categories checked. \(cleaner.selectedCandidates.count) selected. Partial/stopped: \(cleaner.wasStopped). These numbers are distinct from the main scan.")
        if cleaner.completedCategories.contains(.trash) {
            lines.append(cleaner.trash.unreadable ? "Trash count and size are unknown: macOS denied access." : "Trash: \(cleaner.trash.count) items, \(cleaner.trash.size.sizeDescription).")
        }
        lines.append(contentsOf: cleaner.notes.prefix(4))
        lines.append(contentsOf: cleaner.failures.prefix(4))
        lines.append("Updates: \(appState.updateIsReading ? "reading" : "not reading"), \(appState.updateRows.count) rows currently held.")
        lines.append("Housekeeper chat cannot run commands or file operations. The Open a tool menu provides navigation. No action has happened just because it was discussed here.")
        if let item = housekeeper.subject {
            lines.append("SELECTED FILE:")
            lines.append(Housekeeper.briefing(for: item, assessment: appState.cleanupAssessment(for: item)))
        } else if let topic = housekeeper.topic,
                  !topic.id.hasPrefix("scan-"), !topic.id.hasPrefix("sweep") {
            lines.append("SUBJECT NOTES (captured when this panel opened; current status above takes priority):")
            lines.append(contentsOf: topic.facts)
        }
        if let results = appState.scanResults {
            lines.append("MAIN SCAN SAMPLE (up to six findings, not a complete inventory):")
            for item in results.foundItems.sorted(by: { $0.size > $1.size }).prefix(6) {
                let assessment = appState.cleanupAssessment(for: item)
                lines.append("\(item.path.path), \(item.size.sizeDescription). App assessment: \(assessment.decision). \(assessment.reason)")
            }
        }
        lines.append("The following candidates are a sample of up to six measured items, not a full disk inventory:")
        for candidate in cleaner.candidates.sorted(by: { $0.size > $1.size }).prefix(6) {
            lines.append("Clean Up candidate: \(candidate.name), \(candidate.size.sizeDescription), \(candidate.category.title). \(candidate.detail)")
        }
        if let item = housekeeper.subject {
            lines.insert(Housekeeper.briefing(for: item, assessment: appState.cleanupAssessment(for: item)), at: 0)
        } else if let topic = housekeeper.topic, !topic.id.hasPrefix("scan-"), !topic.id.hasPrefix("sweep") {
            lines.insert(topic.facts.joined(separator: "\n"), at: 0)
        }
        return lines.joined(separator: "\n")
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
                    Text((try? AttributedString(markdown: turn.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(turn.text))
                        .font(style.bodyFont)
                        .foregroundStyle(style.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 520, alignment: .leading)
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
                    .background(style.rowSelection, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
}

/// Shared between the chat panel and Settings. All network transfers begin at
/// the explicit Download/Continue button, never at selection or appearance.
struct HousekeeperModelControls: View {
    @Environment(\.uiStyle) private var style
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var weights = HousekeeperWeights.shared
    @ObservedObject private var housekeeper = Housekeeper.shared
    var onNotNow: (() -> Void)? = nil
    var showsDownloadsInline = false
    @State private var showDownloads = false
    @State private var confirmRemoval = false
    @State private var pendingRemoval: [HousekeeperWeights.StoredFile] = []
    @State private var removalProblem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Optional local chatbot").font(style.labelFont)
            Text("Would you like a local model to help with your questions? You can ask general questions too. Housekeeping works fully without chat.")
                .font(style.smallFont).foregroundStyle(style.secondaryText).fixedSize(horizontal: false, vertical: true)
            Picker("Model", selection: Binding(get: { weights.selection }, set: housekeeper.chooseModel)) {
                ForEach(HousekeeperModel.allCases) { model in Text(model.choiceLabel).tag(model) }
            }.disabled(housekeeper.isAnswering || weights.state.isLoading)

            if weights.selection == .none {
                Text("No model is selected. Nothing will be downloaded unless you choose a model and press Download.")
                    .font(style.smallFont).foregroundStyle(style.secondaryText)
                notNow
            } else if weights.selection == .apple {
                Text(AppleHousekeeper.status.message).font(style.smallFont).foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("macOS manages the system model's storage. Housekeeping does not download a second copy.")
                    .font(style.smallFont).foregroundStyle(style.secondaryText)
                if !AppleHousekeeper.status.isAvailable {
                    HStack { Button("Check again") { weights.refresh() }; notNow }.font(style.smallFont)
                }
            } else if let asset = weights.selection.download {
                Text(asset.detail).font(style.smallFont).foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                downloadState(asset)
                Link("Model details and terms", destination: asset.sourcePage).font(style.smallFont)
            }

            if let removalProblem { Text(removalProblem).font(style.smallFont).foregroundStyle(style.negative) }
            if showsDownloadsInline {
                Text("Downloaded models · \(bytes(weights.storedBytes)) on disk").font(style.labelFont)
                if weights.storedFiles.isEmpty {
                    Text("No downloaded models. Apple's system model is managed by macOS.")
                        .font(style.smallFont).foregroundStyle(style.secondaryText)
                } else {
                    downloadedModelRows
                }
            } else if !weights.storedFiles.isEmpty {
                DisclosureGroup("Downloaded models · \(bytes(weights.storedBytes)) on disk", isExpanded: $showDownloads) {
                    downloadedModelRows.padding(.top, 6)
                }.font(style.smallFont)
            }
        }
        .foregroundStyle(style.text)
        .onChange(of: scenePhase) { phase in
            if phase == .active && !weights.state.isLoading { weights.refresh() }
        }
        .alert("Delete downloaded models?", isPresented: $confirmRemoval) {
            Button("Cancel", role: .cancel) { pendingRemoval = [] }
            Button("Delete", role: .destructive) {
                do { try housekeeper.removeModels(pendingRemoval.map(\.url)); removalProblem = nil }
                catch { removalProblem = error.localizedDescription }
                pendingRemoval = []
            }
        } message: {
            Text("Delete \(bytes(pendingRemoval.reduce(0) { $0 + $1.bytes })) of Housekeeping model downloads?\n\n" + pendingRemoval.map { $0.url.lastPathComponent }.joined(separator: "\n") + "\n\nThese can be downloaded again. Apple's system model and your personal files are not included.")
        }
    }

    private var downloadedModelRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(weights.storedFiles) { file in
                HStack(alignment: .top) {
                    Text(fileLabel(file)).font(style.smallFont).textSelection(.enabled)
                    Spacer()
                    Button("Delete model", role: .destructive) { requestRemoval([file]) }
                        .font(style.smallFont)
                        .help("Delete this downloaded model after confirmation. It can be downloaded again.")
                }
            }
            if weights.storedFiles.count > 1 {
                Button("Delete all downloaded models", role: .destructive) { requestRemoval(weights.storedFiles) }
                    .font(style.smallFont)
            }
        }.disabled(housekeeper.isAnswering || weights.state.isLoading)
    }

    @ViewBuilder private var notNow: some View {
        if let onNotNow { Button("Not now", action: onNotNow).font(style.smallFont) }
    }

    @ViewBuilder private func downloadState(_ asset: HousekeeperModel.Download) -> some View {
        switch weights.state {
        case .ready:
            Text("Installed · \(asset.sizeLabel) on disk. Runs locally when you ask a question.")
                .font(style.smallFont).foregroundStyle(style.secondaryText)
        case .missing:
            HStack {
                Button(weights.partialBytes > 0 ? "Continue download · \(asset.sizeLabel) total" : "Download · \(asset.sizeLabel)") { weights.download() }
                    .disabled(!LlamaServer.isAvailable)
                notNow
            }.font(style.smallFont)
            if weights.partialBytes > 0 {
                Text("\(bytes(weights.partialBytes)) already downloaded. You can remove it under Downloaded models.")
                    .font(style.smallFont).foregroundStyle(style.secondaryText)
            }
            if !LlamaServer.isAvailable {
                Text("This app copy is missing its downloadable-model runtime. Apple Intelligence is a separate option.")
                    .font(style.smallFont).foregroundStyle(style.caution)
            }
        case .downloading(let written, let expected):
            HStack {
                if weights.isVerifying {
                    ProgressView().controlSize(.small)
                    Text("Verifying model checksum…").font(style.smallFont)
                } else {
                    ProgressView(value: Double(written), total: Double(max(expected, 1))) {
                        Text("\(bytes(written)) of \(bytes(expected))").font(style.smallFont)
                    }
                }
                Button(weights.isVerifying ? "Cancel" : "Pause") { weights.cancel() }.font(style.smallFont)
            }
        case .failed(let reason):
            Text(reason).font(style.smallFont).foregroundStyle(style.negative)
            HStack {
                Button("Continue download") { weights.download() }
                Button("Start over") { weights.removeInstalled(); weights.download() }
                notNow
            }.font(style.smallFont)
        }
    }

    private func requestRemoval(_ files: [HousekeeperWeights.StoredFile]) {
        pendingRemoval = files
        confirmRemoval = true
    }
    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
    private func fileLabel(_ file: HousekeeperWeights.StoredFile) -> String {
        let model = HousekeeperModel.allCases.first { file.url.lastPathComponent.hasPrefix($0.download?.fileName ?? "\u{0}") }
        let name = model?.title ?? "Previous Qwen 0.6B model"
        return name + (file.url.pathExtension == "partial" ? " (partial download)" : "") + " · " + file.sizeLabel
    }
}
