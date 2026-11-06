import SwiftUI
import AppKit

struct BackgroundReviewView: View {
    @EnvironmentObject private var appState: AppState
    let snapshot: ActivitySnapshot
    let refresh: () -> Void
    let openStartup: () -> Void
    @AppStorage("backgroundUseChoices.v1") private var choicesData = Data()
    @AppStorage("backgroundWidgetUndo.v1") private var widgetUndoData = Data()
    @State private var showAll = false
    @State private var pending: WidgetChange?
    @State private var busy = false
    @State private var notice: String?
    private struct WidgetChange: Identifiable {
        let widget: ActivityWidget
        let election: String
        var id: String { widget.id + election }
    }
    private var choices: [String: BackgroundUse] { (try? JSONDecoder().decode([String: BackgroundUse].self, from: choicesData)) ?? [:] }
    private var widgetUndo: [String: String] { (try? JSONDecoder().decode([String: String].self, from: widgetUndoData)) ?? [:] }
    private var recommendations: [BackgroundRecommendation] {
        BackgroundReview.recommendations(snapshot: snapshot, startup: snapshot.startupItems, choices: choices)
    }
    private var visible: [BackgroundRecommendation] { recommendations.filter { showAll || $0.verdict == .leftover || $0.verdict == .unused || $0.verdict == .review } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What can I do without?").font(.system(size: 24, weight: .bold))
            Text("The Housekeeper checks what is running, startup leftovers and optional features. Tell it what you use; your answers stay on this Mac and guide future reviews.")
                .font(.system(size: 16))
            Text("\(recommendations.filter { $0.verdict == .leftover }.count) likely leftovers · \(recommendations.filter { $0.verdict == .unused }.count) unneeded for you · \(recommendations.filter { $0.verdict == .review }.count) optional features to review")
                .font(.system(size: 16, weight: .semibold))
            HStack {
                Button("Ask the Housekeeper about this review") { askAboutReview() }
                    .buttonStyle(.borderedProminent).frame(minHeight: 44)
                Toggle("Include Keep and unknown items", isOn: $showAll).toggleStyle(.checkbox).frame(minHeight: 44)
            }
            Text("High memory use, an unfamiliar name or a background permission alone does not make an item unnecessary. Recommendations work without downloading an AI model. The chat receives this evidence when you ask; its suggestions cannot bypass review or run cleanup commands.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
            if let notice { Text(notice).font(.system(size: 15)).textSelection(.enabled) }
            if visible.isEmpty { Text("No likely leftovers or optional features were identified in this reading. Include Keep and unknown items to inspect the rest.") }
            LazyVStack(alignment: .leading, spacing: 16) { ForEach(visible, id: \.rowID) { item in row(item) } }
        }
        .alert(item: $pending) { change in
            Alert(title: Text(change.election == "ignore" ? "Pause this widget?" : "Restore this widget preference?"),
                  message: Text("\(change.widget.name)\n\(change.widget.identifier)\n\(change.widget.path)\n\nThis changes all installed versions of this extension for your account. \(change.election == "ignore" ? "Its matching widget processes will be asked to quit. The owning app and documents stay installed. You can restore its previous preference from this review." : "The previous widget preference will be restored. Use Edit Widgets to display it again.")"),
                  primaryButton: .default(Text(change.election == "ignore" ? "Pause Widget" : "Restore Preference"), action: { apply(change) }),
                  secondaryButton: .cancel())
        }
    }

    private func row(_ item: BackgroundRecommendation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.name).font(.system(size: 18, weight: .semibold))
                Spacer()
                Text(item.verdict.rawValue).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(item.verdict == .leftover || item.verdict == .unused ? Color.orange : item.verdict == .keep ? Color.green : Color.primary)
            }
            Text(item.reason).font(.system(size: 16))
            Text("What changes: " + item.consequence).font(.system(size: 15)).foregroundStyle(.secondary)
            if let memory = item.memoryBytes {
                Text("Reported RAM now: " + ByteCountFormatter.string(fromByteCount: memory, countStyle: .memory)).font(.system(size: 15))
            } else { Text("Current RAM attributable to this item: unknown").font(.system(size: 14)).foregroundStyle(.secondary) }
            if let question = item.question, !item.protected {
                Text(question).font(.system(size: 15, weight: .medium))
                HStack {
                    useButton("I use this", use: .needed, item: item)
                    useButton("I don't use this", use: .unused, item: item)
                    useButton("Not sure", use: .unsure, item: item)
                }
                Text("Your answer: \((choices[item.id] ?? .unsure) == .needed ? "use it" : (choices[item.id] ?? .unsure) == .unused ? "do not use it" : "not sure"). Answering does not change the app or its permissions.")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
            }
            DisclosureGroup("Why this recommendation?") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(item.evidence, id: \.self) { Text($0).font(.system(size: 14)).textSelection(.enabled) }
                    Text(item.path).font(.system(size: 13, design: .monospaced)).textSelection(.enabled)
                }.padding(.top, 8)
            }.font(.system(size: 15))
            HStack {
                if let widget = item.widget, !item.protected, BackgroundWidgetControl.eligible(widget) {
                    if widget.isIgnored {
                        Button("Restore Widget…") { pending = WidgetChange(widget: widget, election: widgetUndo[widget.identifier] ?? "default") }.disabled(busy)
                    } else if choices[item.id] == .unused {
                        Button("Pause Widget…") { pending = WidgetChange(widget: widget, election: "ignore") }.disabled(busy)
                    }
                }
                if let startup = item.startup, startup.canTrash, !item.protected {
                    Button("Review Startup Removal…", action: openStartup)
                }
                if let app = item.appPath, choices[item.id] == .unused, !item.protected {
                    Button("Review App Uninstall…") {
                        let model = UninstallerModel.shared
                        model.searchQuery = URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent
                        model.filterOption = .all
                        model.selectedAppURLs = []
                        appState.showUninstaller = true
                    }
                }
                if item.widget == nil && !item.protected && (item.verdict == .unused || item.verdict == .review) {
                    Button("Review Background Permission…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") { NSWorkspace.shared.open(url) }
                    }
                }
                Button("Ask the Housekeeper") { ask(item) }
            }.buttonStyle(.bordered).controlSize(.large).frame(minHeight: 44)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .contextMenu { Button("Ask the Housekeeper") { ask(item) } }
    }
    private func useButton(_ title: String, use: BackgroundUse, item: BackgroundRecommendation) -> some View {
        Button {
            var updated = choices; updated[item.id] = use
            if let encoded = try? JSONEncoder().encode(updated) { choicesData = encoded }
        } label: {
            Label(title, systemImage: choices[item.id] == use ? "checkmark.circle.fill" : "circle").frame(minHeight: 32)
        }.buttonStyle(.bordered).controlSize(.large).frame(minHeight: 44)
    }
    private func facts(_ item: BackgroundRecommendation) -> [String] {
        ["Assessment: " + item.verdict.rawValue, item.reason, "Reader's recorded use: " + (choices[item.id] ?? .unsure).rawValue,
         "Reported RAM: " + (item.memoryBytes.map { String($0) + " bytes" } ?? "unknown"), "Consequence: " + item.consequence, "Path: " + item.path] + item.evidence
    }
    private func ask(_ item: BackgroundRecommendation) {
        HousekeeperTopic.ask(HousekeeperTopic(id: "background-review-" + item.id, title: item.name, label: item.verdict.rawValue,
            tone: item.verdict == .leftover || item.verdict == .unused ? .caution : .plain, facts: facts(item),
            opener: "Explain why this is recommended, what depends on it and the available reviewed action. Respect unknowns and my recorded usage."))
    }
    private func askAboutReview() {
        let prioritized = recommendations.filter { $0.verdict != .keep }
        // A bounded, representative briefing. Do not silently pretend it covers
        // omitted details; include the counts and every category's totals.
        let selected = Array(prioritized.prefix(24))
        let summary = "The review found \(recommendations.filter { $0.verdict == .leftover }.count) likely leftovers, \(recommendations.filter { $0.verdict == .unused }.count) items the reader marked unused, and \(recommendations.filter { $0.verdict == .review }.count) optional items needing a usage decision."
        var briefing = [summary, "A large process or registered permission alone does not establish that it is unnecessary. No cleanup has been executed by this review.", "Reading: \(snapshot.captured.formatted()). Showing \(selected.count) of \(prioritized.count) non-Keep recommendations in this briefing."]
        briefing += snapshot.notices
        for item in selected { briefing.append("Item: " + item.name); briefing += facts(item) }
        HousekeeperTopic.ask(HousekeeperTopic(id: "background-review-overview", title: "What can I do without?", label: "Background recommendations", tone: .plain,
            facts: briefing, opener: "Summarise the evidence-based recommendations. Explain what can be paused or removed, what needs a usage answer, what to keep, and what remains unknown. Never infer unused from size or claim to execute changes."))
    }
    private func apply(_ change: WidgetChange) {
        busy = true
        Task {
            // Save the undo preference before a command can partially succeed.
            if change.election == "ignore" {
                var saved = widgetUndo
                if saved[change.widget.identifier] == nil { saved[change.widget.identifier] = change.widget.election }
                if let data = try? JSONEncoder().encode(saved) { widgetUndoData = data }
            }
            do {
                let result = try await BackgroundWidgetControl.shared.setElection(change.election, for: change.widget)
                var saved = widgetUndo
                if change.election != "ignore" { saved.removeValue(forKey: change.widget.identifier) }
                widgetUndoData = (try? JSONEncoder().encode(saved)) ?? widgetUndoData
                notice = result
            } catch { notice = error.localizedDescription }
            busy = false
            refresh()
        }
    }
}
