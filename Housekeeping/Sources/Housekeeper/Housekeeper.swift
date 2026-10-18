// Housekeeping — The housekeeper
//
// Conversation is grounded in current app state. File operations and safety
// assessments stay in the app's deterministic review flow.

import Foundation
import Combine

@MainActor
final class Housekeeper: ObservableObject {

    struct Turn: Identifiable, Equatable {
        enum Speaker: Equatable { case reader, housekeeper }

        let id = UUID()
        let speaker: Speaker
        let text: String
    }

    static let shared = Housekeeper()

    @Published private(set) var turns: [Turn] = []
    @Published private(set) var isAnswering = false
    /// Set when something went wrong that the reader should see instead of an answer.
    @Published private(set) var problem: String?
    @Published private(set) var inspectedQuestionFolder: String?

    /// What the conversation is about, so the app's own verdict can stay on screen
    /// above whatever the model says. Never handed to the model as an instruction.
    @Published private(set) var subject: FoundItem?
    @Published private(set) var subjectDecision: CleanupSafetyPolicy.Decision?
    @Published private(set) var subjectReason: String?
    /// What the conversation is about when it is not about a scanned path — an
    /// app that is out of date, a command that runs the wrong copy, a folder the
    /// disk browser is standing in. Mutually exclusive with `subject`: a window
    /// opened about a setup finding must not keep showing the cleanup verdict of
    /// whatever was picked out on the main screen before it.
    @Published private(set) var topic: HousekeeperTopic?

    let weights = HousekeeperWeights.shared
    let server = LlamaServer()

    /// The briefing for the current subject. Re-sent ahead of every question so a
    /// follow-up like "what happens if it goes?" is still about the right thing.
    private var briefing: String?
    private var history: [[String: String]] = []
    private var contextID = UUID()
    private var answerTask: Task<Void, Never>?

    /// The pending shutdown of the runtime, if the window has closed and nothing has
    /// reopened it yet.
    private var idleStop: Task<Void, Never>?

    /// Keep the runtime briefly warm between questions, then release its memory.
    static let idleGrace: Duration = .seconds(45)

    private init() {}

    var runtimeIsAvailable: Bool { true }
    var canChat: Bool {
        weights.selection == .apple ? AppleHousekeeper.status.isAvailable : weights.state.isReady
    }

    func chooseModel(_ model: HousekeeperModel) {
        guard model != weights.selection else { return }
        stopAnswer()
        server.stopAndWait()
        weights.select(model)
        restartConversationKeepingSubject()
    }

    func removeModels(_ files: [URL]) throws {
        stopAnswer()
        server.stopAndWait()
        try weights.removeDownloads(files)
        restartConversationKeepingSubject()
    }

    private func restartConversationKeepingSubject() {
        answerTask?.cancel()
        answerTask = nil
        contextID = UUID()
        isAnswering = false
        history = []
        problem = nil
        turns = [Turn(speaker: .housekeeper, text: Self.greeting)]
    }

    // MARK: - Opening the conversation

    /// Opens the housekeeper. Given a finding it explains that finding; with nothing
    /// in hand it introduces itself and waits to be asked.
    ///
    /// `browsing` is what Housekeeping is holding when nothing is picked out. It
    /// exists because a question with no briefing behind it is a question the model
    /// can only answer by making something up, and a small model makes it up
    /// convincingly — the first build of this sheet answered "what is this folder"
    /// about a folder that was not there.
    func open(
        focusing item: FoundItem?,
        assessment: CleanupSafetyPolicy.Assessment?,
        browsing: String? = nil
    ) {
        if let item, let assessment {
            // A verdict that has moved — because the path was just protected, or
            // because the policy changed under it — has to rebuild the briefing.
            // Otherwise the housekeeper carries on explaining the answer
            // Housekeeping no longer gives.
            if subject?.id != item.id
                || subjectDecision != assessment.decision
                || subjectReason != assessment.reason
                || turns.isEmpty {
                begin(on: item, assessment: assessment)
            }
        } else if topic != nil || subject != nil || turns.isEmpty {
            // Nothing is picked out, so the window is not about anything in
            // particular — including not about whatever it was about last. A
            // strip left over from a screen the reader has since left would be
            // the app claiming the model is talking about something it is not.
            beginBrowsing(browsing)
        }

        wake()
    }

    /// The conversation with no subject: the housekeeper introduces itself and is
    /// handed the shape of what Housekeeping is holding, so that a question asked
    /// from here has something true to stand on.
    private func beginBrowsing(_ browsing: String?) {
        answerTask?.cancel()
        answerTask = nil
        contextID = UUID()
        isAnswering = false
        subject = nil
        subjectDecision = nil
        subjectReason = nil
        topic = nil
        inspectedQuestionFolder = nil
        briefing = browsing
        history = []
        problem = nil
        turns = [Turn(speaker: .housekeeper, text: Self.greeting)]
    }

    /// Opens the housekeeper about something that is not a scanned path.
    ///
    /// Kept beside `open(focusing:)` rather than folded into it because the two
    /// carry different things: that one carries a finding and the app's verdict
    /// on it, and this one carries a title and Housekeeping's own facts. The
    /// shared part is the rule both obey — a subject that has changed restarts
    /// the conversation, and one that has not is left alone, so reopening the
    /// window does not throw away what the reader has already asked.
    func open(topic newTopic: HousekeeperTopic) {
        if topic != newTopic || turns.isEmpty {
            answerTask?.cancel()
            answerTask = nil
            contextID = UUID()
            isAnswering = false
            subject = nil
            subjectDecision = nil
            subjectReason = nil
            topic = newTopic
            inspectedQuestionFolder = nil
            briefing = newTopic.briefing
            history = []
            problem = nil
            // The first explanation is a direct account from scan evidence.
            // A small model must not reinterpret an exclusion as a cleanup.
            let opening = newTopic.id.hasPrefix("scan-") ? Self.greeting : newTopic.facts.prefix(2).joined(separator: "\n\n")
            turns = [Turn(speaker: .housekeeper, text: opening)]
        }

        wake()
    }

    private func begin(on item: FoundItem, assessment: CleanupSafetyPolicy.Assessment) {
        answerTask?.cancel()
        answerTask = nil
        contextID = UUID()
        isAnswering = false
        subject = item
        inspectedQuestionFolder = nil
        subjectDecision = assessment.decision
        subjectReason = assessment.reason
        topic = nil
        briefing = Self.briefing(for: item, assessment: assessment)
        history = []
        problem = nil
        let guide = item.readerGuide
        turns = [Turn(speaker: .housekeeper, text: "\(guide.whatItIs)\n\n\(guide.whyItExists)\n\n\(assessment.reason)\n\n\(guide.riskExplanation)")]
    }

    // MARK: - Talking

    func ask(_ question: String, context: String? = nil, assessment: CleanupSafetyPolicy.Assessment? = nil, folderRequest: HousekeeperFolderEvidence.Request? = nil) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isAnswering else { return }
        guard trimmed.count <= (weights.selection == .apple ? 3_000 : 16_000) else {
            problem = "This message is too long for the local model. Send the specific question or a shorter excerpt."
            return
        }
        if let context { briefing = context }
        if subject != nil, let assessment {
            subjectDecision = assessment.decision
            subjectReason = assessment.reason
        }
        turns.append(Turn(speaker: .reader, text: trimmed))
        // Set synchronously, before spawning work, so rapid double submission
        // cannot start two generations against the same history.
        isAnswering = true
        let requestContext = contextID
        answerTask = Task { [weak self] in
            guard let self else { return }
            await self.send(trimmed, requestContext: requestContext, folderRequest: folderRequest)
        }
    }

    func clear() {
        answerTask?.cancel()
        answerTask = nil
        contextID = UUID()
        isAnswering = false
        turns = []
        history = []
        briefing = nil
        inspectedQuestionFolder = nil
        subject = nil
        subjectDecision = nil
        subjectReason = nil
        topic = nil
        problem = nil
        turns = [Turn(speaker: .housekeeper, text: Self.greeting)]
    }

    func retry() {
        guard case .failed = weights.state else { return }
        weights.download()
    }

    func stopAnswer() {
        guard isAnswering else { return }
        answerTask?.cancel()
        answerTask = nil
        contextID = UUID()
        isAnswering = false
        problem = nil
        turns.append(Turn(speaker: .housekeeper, text: "Response stopped."))
    }

    private func send(_ question: String, requestContext: UUID, folderRequest: HousekeeperFolderEvidence.Request?) async {
        guard contextID == requestContext, !Task.isCancelled else { return }
        let answeringContext = requestContext
        isAnswering = true
        problem = nil
        defer {
            if contextID == answeringContext {
                isAnswering = false
                answerTask = nil
            }
        }

        let selectedModel = weights.selection
        guard canChat else {
            problem = selectedModel == .apple ? AppleHousekeeper.status.message : "Choose an optional model and download it before chatting. Housekeeping works without the chatbot."
            return
        }
        var hasFolderEvidence = false
        if let folderRequest {
            let report = await Task.detached(priority: .userInitiated) {
                HousekeeperFolderEvidence.inspect(question: question, request: folderRequest)
            }.value
            guard contextID == answeringContext, !Task.isCancelled else { return }
            if let report {
                inspectedQuestionFolder = report.focusedPath
                briefing = report.context + "\n\nGENERAL APP STATUS:\n" + (briefing ?? "")
                hasFolderEvidence = true
                if let answer = report.clarification {
                    history.append(contentsOf: [["role": "user", "content": question], ["role": "assistant", "content": answer]])
                    if history.count > 8 { history.removeFirst(history.count - 8) }
                    turns.append(Turn(speaker: .housekeeper, text: answer))
                    return
                }
            }
        }
        if let item = subject, let decision = subjectDecision, let reason = subjectReason,
           let answer = HousekeeperConversation.assessmentReply(
            question: question, name: item.path.lastPathComponent,
            verdict: Verdict.of(decision).shortLabel, reason: reason,
            risk: item.readerGuide.riskExplanation
           ) {
            history.append(contentsOf: [["role": "user", "content": question], ["role": "assistant", "content": answer]])
            if history.count > 8 { history.removeFirst(history.count - 8) }
            turns.append(Turn(speaker: .housekeeper, text: answer))
            return
        }
        if selectedModel != .apple {
            guard case .ready(let model) = weights.state else { return }
            server.start(model: model)
            guard await waitForRuntime(context: answeringContext) else {
                guard contextID == answeringContext, !Task.isCancelled else { return }
                if problem == nil { problem = "The housekeeper is still waking up. Ask again in a moment." }
                return
            }
        }

        guard contextID == answeringContext else { return }
        let isApple = selectedModel == .apple
        var messages = HousekeeperConversation.messages(context: briefing, history: history, question: question, contextBudget: isApple ? (hasFolderEvidence ? 4_000 : 2_000) : 8_000, historyBudget: isApple ? 2_000 : 6_000)
        if isApple || selectedModel == .gemma1b || selectedModel == .gemma2b {
            messages[0]["content"] = messages[0]["content"]?.replacingOccurrences(of: "/no_think", with: "")
        }
        do {
            var answer = try await generate(messages, using: selectedModel)
            guard contextID == answeringContext else { return }
            if HousekeeperConversation.repeats(answer, history: history, question: question) {
                var retry = messages
                retry[0]["content", default: ""] += "\nYour previous attempt repeated an earlier answer. Respond to the latest message directly and do not summarize app context unless the user asked for it."
                answer = try await generate(retry, using: selectedModel)
                guard contextID == answeringContext else { return }
                guard !HousekeeperConversation.repeats(answer, history: history, question: question) else {
                    problem = "The local model repeated an earlier answer. That reply was discarded. Try a more specific question or start a new conversation."
                    return
                }
            }
            history.append(contentsOf: [["role": "user", "content": question], ["role": "assistant", "content": answer]])
            if history.count > 8 { history.removeFirst(history.count - 8) }
            turns.append(Turn(speaker: .housekeeper, text: answer))
        } catch {
            // Failed generations never enter model history. The visible question
            // remains available to read or copy while retrying.
            guard contextID == answeringContext else { return }
            problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func generate(_ messages: [[String: String]], using model: HousekeeperModel) async throws -> String {
        if model == .apple { return try await AppleHousekeeper.complete(messages: messages) }
        return try await server.complete(messages: HousekeeperConversation.transportMessages(messages, for: model))
    }

    /// Called when the housekeeper's window closes. The conversation survives — it is
    /// only the runtime that goes, and only after a delay, so that shutting the sheet
    /// to look at something and opening it again is not a cold start every time.
    func suspend() {
        idleStop?.cancel()
        idleStop = Task { [weak self] in
            try? await Task.sleep(for: Self.idleGrace)
            guard !Task.isCancelled else { return }
            self?.server.stop()
        }
    }

    private func wake() {
        idleStop?.cancel()
        idleStop = nil
        // Loading is deferred until a question is sent. Opening a recorded
        // explanation does not need to reserve several gigabytes of memory.
    }

    private func waitForRuntime(context: UUID) async -> Bool {
        for _ in 0..<120 {
            guard contextID == context, !Task.isCancelled else { return false }
            if case .ready = server.state { return true }
            if case .failed(let reason) = server.state {
                problem = reason
                return false
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        problem = "The housekeeper's runtime is taking longer than usual to wake up."
        return false
    }

    // MARK: - What the model is told

    /// The one place the housekeeper's character is defined. Everything it knows
    /// about a particular finding arrives separately, as a briefing.
    static let systemPrompt = HousekeeperConversation.systemPrompt

    static let greeting = "Hi. I can help you find what is taking up space, understand app data, compare folders, or work through a Mac problem. What are you trying to do?"

    static func openingLine(for item: FoundItem) -> String {
        "\(item.path.lastPathComponent) — let me take a look at that one for you."
    }

    /// The briefing is the app's own hand-written account of the finding, handed over
    /// as facts rather than as instructions. It is deliberately the last thing built
    /// and the first thing sent, so nothing the model produces can feed back into it.
    static func briefing(for item: FoundItem, assessment: CleanupSafetyPolicy.Assessment) -> String {
        let guide = item.readerGuide
        let size = ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
        let verdict = Verdict.of(assessment.decision)

        var lines: [String] = []
        lines.append("Housekeeping is showing this finding to the reader right now. This briefing was written by Housekeeping, and it is the only information you have about it.")
        lines.append("")
        lines.append("Path: \(item.path.path)")
        lines.append("Name: \(item.path.lastPathComponent)")
        lines.append("Size: \(size)")
        lines.append("Kind of data: \(item.category.displayName)")
        lines.append("Kind of finding: \(item.findingKind.tagline)")
        if let application = item.primaryApplication {
            lines.append("Belongs to: \(application.isInstalled ? application.name : "\(application.name), which is no longer installed")")
        } else {
            // "Nothing Housekeeping can name" read as "Housekeeping owns it" and the
            // model said so. A small model needs the negative spelled out.
            lines.append("Belongs to: no installed application. Housekeeping did not create this, and it does not belong to Housekeeping.")
        }
        if item.isUndeclared {
            lines.append("Note: this was not mentioned in any rule Housekeeping ships with, so Housekeeping is treating it with more caution than usual.")
        }
        lines.append("What it is: \(guide.whatItIs)")
        lines.append("Why it exists: \(guide.whyItExists)")
        lines.append("Whether it is needed: \(guide.necessity)")
        lines.append("Risk: \(guide.risk.rawValue). \(guide.riskExplanation)")
        lines.append("Housekeeping's verdict: \(verdict.shortLabel)")
        lines.append("Why Housekeeping decided that: \(assessment.reason)")
        lines.append("")
        lines.append("Explain this to the reader in plain English.")
        return lines.joined(separator: "\n")
    }

    // MARK: - What the model is told when nothing is picked out

    /// One finding as the app states it, for a session with no subject. Built by
    /// the caller, which is the only place that can compute a verdict.
    struct BrowsingFact {
        let name: String
        let verdict: String
        let reason: String
    }

    /// A scan can hold thousands of findings and the briefing is re-sent with every
    /// question, so the list is a sample rather than the whole of it. Named in the
    /// briefing as a sample, so the model cannot mistake it for everything.
    static let browsingFactLimit = 40

    /// The briefing for a session with nothing picked out. There is no finding to
    /// explain, so the housekeeper is given the shape of what Housekeeping is
    /// holding instead: enough that a question about the Mac has something true to
    /// stand on, and nothing more, because everything here is a fact it may repeat.
    static func browsingBriefing(facts: [BrowsingFact], remaining: Int, scanning: Bool) -> String {
        var lines: [String] = []
        lines.append("The reader has opened you with no single finding picked out, so there is no particular folder you are looking at. This briefing was written by Housekeeping, and it is the only information you have about their Mac.")
        lines.append("")
        if scanning {
            lines.append("Housekeeping is scanning the Mac right now, so what it has found so far is not the whole picture.")
        }
        if facts.isEmpty {
            if scanning {
                lines.append("Housekeeping has not found anything yet. The scan is still running, so there is nothing in front of you to describe.")
            } else {
                lines.append("Housekeeping has nothing on screen. Either it has not been run yet, or it ran and found nothing it wanted to offer.")
            }
        } else {
            lines.append("Housekeeping is holding these findings, with its own verdict on each:")
            for fact in facts {
                lines.append("- \(fact.name) — \(fact.verdict). Because: \(fact.reason)")
            }
            if remaining > 0 {
                lines.append("- and \(remaining) more, which are not listed here.")
            }
        }
        lines.append("")
        if facts.isEmpty {
            // A tiny model reaches for a plausible folder — "My Documents" — when it
            // is only told what not to do, so the empty case is handed the sentence
            // to say instead. Asking a question about nothing found is a question
            // with one true answer, and it is written here rather than left to the
            // rules to imply.
            lines.append("Nothing was found, so there is nothing for you to describe. If the reader asks what you found on their Mac, your whole answer is this sentence and then you stop: \"Housekeeping has not found anything yet, so there is nothing in front of me.\"")
            lines.append("Instruction, not part of that answer: do not name a folder, a file, an application, or a size. Nothing was found, so there is nothing to name, and a folder that sounds typical — the sort of folder every Mac is expected to have — is still invented. If the reader asks about one folder in particular, tell them to pick it out on screen and use Talk to the Housekeeper, so that you can actually see it.")
        } else {
            lines.append("This is a sample, not a complete inventory. If the reader asks about something that is not in this briefing, you do not have it in front of you: say so plainly, and tell them to pick it out on screen and use Talk to the Housekeeper so that you can see it. Never describe a folder, a size, or a file you were not given.")
        }
        return lines.joined(separator: "\n")
    }
}
