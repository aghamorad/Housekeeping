import AppKit
import SwiftUI

/// Clean Up. A shelf of six kinds of thing, each with its own explanation, and a
/// footer that only ever acts on what the reader ticked. Everything but the
/// Trash goes into Quarantine and can come back; the Trash is the one exception,
/// and it says so in words before it asks for a typed confirmation.
struct CleanerView: View {
    @ObservedObject var model: CleanerModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                header
                HStack(alignment: .top, spacing: 12) {
                    sidebar
                        .frame(width: 216)
                    detailPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                footer
            }
            .padding(16)

            if let action = model.pendingAction {
                confirmation(action)
            }
        }
        .frame(minWidth: 900, maxWidth: 900, minHeight: 620)
        .preferredColorScheme(style.isRetro ? .light : nil)
        .onAppear { model.scanIfNeeded() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Clean Up")
                    .font(style.titleFont)
                Text(scanSentence)
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            ThemeButton(
                title: "Look Again",
                systemImage: "arrow.clockwise",
                isEnabled: model.phase != .scanning && model.phase != .working,
                help: "Reads the disk again. Nothing is moved by looking."
            ) { model.scan() }
        }
    }

    private var scanSentence: String {
        switch model.phase {
        case .idle:
            return "Housekeeping has not looked yet."
        case .scanning:
            return "Looking around… \(model.progressLine)"
        case .working:
            return "Moving things into Quarantine…"
        case .ready:
            let when = model.lastScan?.formatted(date: .omitted, time: .shortened) ?? "just now"
            if model.cleanerTotal == 0 {
                return "Last looked at \(when). Nothing to offer this time."
            }
            return "Last looked at \(when). \(model.cleanerTotal.sizeDescription) across \(model.candidates.count) items — none of it ticked for you."
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(CleanCategory.allCases) { category in
                    sidebarRow(category)
                }
            }
        }
    }

    private func sidebarRow(_ category: CleanCategory) -> some View {
        let isSelected = model.category == category
        return Button {
            model.category = category
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: category.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? style.accent : style.secondaryText)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(style.labelFont)
                        .foregroundColor(style.text)
                    Text(sidebarDetail(category))
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? style.rowSelection : style.rowBackground)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarDetail(_ category: CleanCategory) -> String {
        // Until the first reading lands, "Nothing found" would be a claim the
        // scan has not made yet — and it is the one claim this screen must
        // never get wrong in the direction of "there is nothing to see".
        if model.phase == .scanning || model.phase == .idle {
            return "Reading…"
        }
        switch category {
        case .uninstall:
            return model.apps.isEmpty ? "No apps found" : "\(model.apps.count) apps"
        case .trash:
            // "Empty" is a claim about what is in there. When macOS refused to
            // hand the folder over, Housekeeping has not counted anything and
            // must not say it is empty.
            if model.trash.unreadable { return "Can't read it" }
            return model.trash.isEmpty ? "Empty" : "\(model.trash.size.sizeDescription)"
        default:
            let count = model.count(in: category)
            return count == 0 ? "Nothing found" : "\(model.total(in: category).sizeDescription) · \(count) item\(count == 1 ? "" : "s")"
        }
    }

    // MARK: - The middle

    @ViewBuilder
    private var detailPane: some View {
        switch model.category {
        case .uninstall:
            uninstallPane
        case .trash:
            trashPane
        default:
            listPane(model.category)
        }
    }

    private func listPane(_ category: CleanCategory) -> some View {
        let rows = model.candidates(in: category)
        return VStack(spacing: 10) {
            ThemePanel(padding: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(category.title)
                            .font(style.labelFont)
                        Spacer()
                        let selected = model.selected(in: category)
                        let allSelected = model.allInCategorySelected
                        HStack(spacing: 6) {
                            ThemeCheckbox(
                                isChecked: allSelected,
                                isMixed: !selected.isEmpty && !allSelected,
                                help: "Ticks or unticks everything on this shelf. Nothing is moved until you press the button at the bottom."
                            ) {
                                model.setAll(in: category, selected: !allSelected)
                            }
                            Text(allSelected ? "Untick all" : "Tick all")
                                .font(style.smallFont)
                                .foregroundColor(style.secondaryText)
                                .onTapGesture {
                                    model.setAll(in: category, selected: !allSelected)
                                }
                                .help("Same as the box beside it: ticks or unticks every item on this shelf.")
                        }
                    }
                    Text(category.explanation)
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if rows.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Text(model.phase == .scanning ? "Still looking…" : "Nothing on this shelf.")
                        .font(style.bodyFont)
                    Text(model.phase == .scanning
                         ? "The answer will appear here when the reading finishes."
                         : "There is nothing here to offer right now. That usually means a cleaner Mac than average, not a failed scan.")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 440)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(rows) { candidate in
                            candidateRow(candidate)
                        }
                    }
                }
            }
        }
    }

    private func candidateRow(_ candidate: CleanCandidate) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ThemeCheckbox(isChecked: candidate.isSelected) {
                model.toggle(candidate)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(candidate.name)
                        .font(style.labelFont)
                        .foregroundColor(style.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(candidate.size.sizeDescription)
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .monospacedDigit()
                }
                Text(candidate.detail)
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(candidate.url.homeAbbreviatedPath)
                    .font(style.pathFont)
                    .foregroundColor(style.secondaryText)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Without this the row only answers a right-click where it has drawn
        // text, so the empty right half of a row would do nothing.
        .contentShape(Rectangle())
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
            }
            Button("Ask the Housekeeper About This…") {
                askHousekeeper(topic(for: candidate))
            }
            Button("Copy Path") {
                copyToPasteboard(candidate.url.path)
            }
            Divider()
            Button(candidate.isSelected ? "Remove From Selection" : "Select This Item") {
                model.toggle(candidate)
            }
            Divider()
            Button("Leave This Alone") {
                leaveAlone(candidate.url, kind: candidate.category.title)
            }
        }
    }

    private var uninstallPane: some View {
        VStack(spacing: 10) {
            ThemePanel(padding: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Uninstall Apps")
                        .font(style.labelFont)
                    Text(CleanCategory.uninstall.explanation)
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if model.apps.isEmpty {
                Spacer()
                Text(model.phase == .scanning ? "Still reading…" : "No applications found outside Apple's own.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.apps) { app in
                            appRow(app)
                        }
                    }
                }
            }
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(style.labelFont)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let version = app.version {
                            Text("Version \(version)")
                        }
                        if !app.leftovers.isEmpty {
                            Text("·")
                            Text("\(app.leftovers.count) file\(app.leftovers.count == 1 ? "" : "s") left behind")
                        }
                    }
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                }
                Spacer()
                if app.isRunning {
                    Text("Open now — quit it first")
                        .font(style.smallFont)
                        .foregroundColor(style.caution)
                }
                Text(app.totalSize.sizeDescription)
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .monospacedDigit()
                ThemeButton(
                    title: "Uninstall…",
                    isEnabled: !app.isRunning,
                    help: app.isRunning
                        ? "Quit the application first. macOS will not let it be moved while it is running."
                        : "Move the application and everything listed under it into Quarantine."
                ) { model.requestUninstall(app) }
            }

            if !app.leftovers.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(app.leftovers.prefix(6)) { leftover in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(leftover.name)
                                .font(style.pathFont)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(leftover.size.sizeDescription)
                                .font(style.pathFont)
                                .monospacedDigit()
                        }
                        .foregroundColor(style.secondaryText)
                        .contextMenu {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([leftover.url])
                            }
                            Button("Copy Path") {
                                copyToPasteboard(leftover.url.path)
                            }
                            Divider()
                            Button("Leave This Alone") {
                                leaveAlone(leftover.url, kind: "Uninstall Apps")
                            }
                        }
                    }
                    if app.leftovers.count > 6 {
                        Text("and \(app.leftovers.count - 6) more")
                            .font(style.pathFont)
                            .foregroundColor(style.secondaryText)
                    }
                }
                .padding(.leading, 38)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Without this the row only answers a right-click where it has drawn
        // text, so the empty right half of a row would do nothing.
        .contentShape(Rectangle())
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 8))
        .contextMenu {
            Button("Open") {
                NSWorkspace.shared.open(app.url)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            }
            Button("Ask the Housekeeper About This App…") {
                askHousekeeper(topic(for: app))
            }
            Divider()
            Button("Copy Path") {
                copyToPasteboard(app.url.path)
            }
            if let bundleIdentifier = app.bundleIdentifier {
                Button("Copy Bundle Identifier") {
                    copyToPasteboard(bundleIdentifier)
                }
            }
        }
    }

    // MARK: - Right-click

    private func askHousekeeper(_ topic: HousekeeperTopic) {
        appState.housekeeperTopic = topic
        WindowOpener.shared.withWindow {
            appState.showHousekeeper = true
        }
    }

    private func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Puts a row on the left-alone list and takes it off this screen. The row
    /// leaving is the confirmation: a file that stayed visible after being told
    /// to leave it alone would make the reader doubt the list, not the file.
    private func leaveAlone(_ url: URL, kind: String) {
        guard appState.protect(path: url.path, kind: kind) else { return }
        model.forget(path: url.path)
    }

    /// What the housekeeper is told about one row. It gets the same sentences the
    /// reader sees, plus the shelf's explanation and the safety promise, because a
    /// small model with a thin briefing invents a convincing one.
    private func topic(for candidate: CleanCandidate) -> HousekeeperTopic {
        var facts: [String] = [
            "This is one item on the \(candidate.category.title) shelf of Clean Up, and it measures \(candidate.size.sizeDescription).",
            "It is at \(candidate.url.path)."
        ]
        if let modified = candidate.modified {
            facts.append("It was last changed on \(modified.formatted(date: .abbreviated, time: .omitted)).")
        }
        facts.append("Housekeeping's own note about it: \(candidate.detail)")
        facts.append("What this shelf is for: \(candidate.category.explanation)")
        facts.append(candidate.isSelected
                     ? "It is ticked right now, so it is part of what the reader has chosen to clean."
                     : "It is not ticked, and nothing happens to it unless the reader ticks it.")
        facts.append("Cleaning moves it into Quarantine, where it can be put back. Housekeeping deletes nothing except when the reader empties the Trash.")
        return HousekeeperTopic(
            id: "clean-item-\(candidate.id)",
            title: candidate.name,
            label: candidate.category.title,
            tone: .plain,
            facts: facts,
            opener: "What is this item, and what would cleaning it do?"
        )
    }

    private func topic(for app: InstalledApp) -> HousekeeperTopic {
        var facts: [String] = [
            "This is an application Housekeeping found: \(app.name)\(app.version.map { ", version \($0)" } ?? "").",
            "The application itself is at \(app.url.path) and measures \(app.size.sizeDescription)."
        ]
        if let bundleIdentifier = app.bundleIdentifier {
            facts.append("Its bundle identifier is \(bundleIdentifier).")
        }
        if app.leftovers.isEmpty {
            facts.append("Housekeeping found no files left behind beside it.")
        } else {
            facts.append("Housekeeping also found \(app.leftovers.count) file\(app.leftovers.count == 1 ? "" : "s") belonging to it in the home folder, \(app.leftoverSize.sizeDescription) together.")
        }
        facts.append(app.isRunning
                     ? "It is open right now, so macOS will not let it be moved until it is quit."
                     : "It is not open.")
        facts.append("Uninstalling moves the application and everything found with it into Quarantine together, so the whole thing can be put back.")
        return HousekeeperTopic(
            id: "clean-app-\(app.id)",
            title: app.name,
            label: "Uninstall Apps",
            tone: .plain,
            facts: facts,
            opener: "What is this application, and what would uninstalling it move?"
        )
    }

    // MARK: - Trash

    private var trashPane: some View {
        VStack(spacing: 10) {
            ThemePanel(padding: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trash")
                        .font(style.labelFont)
                    Text(CleanCategory.trash.explanation)
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(model.phase == .scanning
                         ? "Counting what is in it…"
                         : (model.trash.unreadable
                            ? "macOS is keeping Housekeeping out of the Trash, so its size is unknown."
                            : (model.trash.isEmpty
                               ? "The Trash is empty."
                               : "\(model.trash.count) item\(model.trash.count == 1 ? "" : "s"), \(model.trash.size.sizeDescription).")))
                        .font(style.bodyFont)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.trash.unreadable {
                        // macOS guards the Trash with Full Disk Access. Saying so
                        // is the difference between a dead button and a reader
                        // knowing exactly what to change.
                        Text("This is a privacy setting, not a fault. macOS only lets an app see the Trash once you allow it under Full Disk Access. Until then Housekeeping cannot count it or empty it — the Finder still can.")
                            .font(style.smallFont)
                            .foregroundColor(style.caution)
                            .fixedSize(horizontal: false, vertical: true)
                        ThemeButton(
                            title: "Open Full Disk Access Settings",
                            systemImage: "hand.raised",
                            help: "Opens the Full Disk Access list in System Settings. Turn Housekeeping on there, then come back and press Look Again."
                        ) { openFullDiskAccessSettings() }
                    }
                    HStack(spacing: 8) {
                        ThemeButton(
                            title: "Empty Trash…",
                            systemImage: "trash",
                            isEnabled: !model.trash.isEmpty && model.phase != .working,
                            help: "Asks for a typed confirmation first. This is the one action in Housekeeping that cannot be undone."
                        ) { model.requestEmptyTrash() }
                        ThemeButton(
                            title: "Show Trash in Finder",
                            systemImage: "magnifyingglass",
                            help: "Opens the Trash so you can look before deciding."
                        ) {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: TrashService().trashURL.path)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !model.failures.isEmpty {
                ThemePanel(padding: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("What could not be removed")
                            .font(style.labelFont)
                        ForEach(model.failures.prefix(12), id: \.self) { line in
                            Text(line)
                                .font(style.smallFont)
                                .foregroundColor(style.caution)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            statusLine
                .font(style.smallFont)
                .foregroundColor(model.failures.isEmpty ? style.secondaryText : style.caution)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            AskHousekeeperButton(topic: housekeeperTopic, closing: { appState.showClean = false })
            ThemeButton(
                title: "Open Quarantine",
                systemImage: "archivebox",
                help: "Quarantine is where everything this screen moves ends up, and where it can be put back."
            ) {
                appState.screen = .quarantine
            }
            if model.category != .uninstall && model.category != .trash {
                ThemeButton(
                    title: cleanButtonTitle,
                    systemImage: "arrow.down.to.line",
                    isPrimary: true,
                    isEnabled: !model.selectedCandidates.isEmpty && model.phase != .working,
                    help: "Moves what is ticked into Quarantine. Nothing is deleted, and everything can be put back."
                ) { model.requestClean() }
            }
            ThemeButton(title: "Done", isPrimary: model.category == .uninstall || model.category == .trash) {
                appState.showClean = false
            }
        }
    }

    private var cleanButtonTitle: String {
        let count = model.selectedCandidates.count
        guard count > 0 else { return "Clean Up…" }
        return "Clean Up \(count) Item\(count == 1 ? "" : "s")…"
    }

    private var statusLine: Text {
        if !model.failures.isEmpty {
            return Text("\(model.failures.count) thing\(model.failures.count == 1 ? "" : "s") could not be moved. The reason is listed below or on the Trash shelf.")
        }
        if let outcome = model.outcome {
            return Text(outcome)
        }
        if !model.notes.isEmpty {
            return Text(model.notes.joined(separator: " "))
        }
        let count = model.selectedCandidates.count
        if count == 0 {
            return Text("Nothing is ticked. Ticking costs nothing; nothing moves until the button is pressed.")
        }
        return Text("\(count) item\(count == 1 ? "" : "s") ticked, \(model.selectedSize.sizeDescription).")
    }

    // MARK: - Confirmation

    private func confirmation(_ action: CleanerModel.PendingAction) -> some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()

            ThemePanel(padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(model.pendingTitle)
                        .font(style.labelFont)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(model.pendingDetail)
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Text("Type “\(action.word)” to confirm:")
                            .font(style.smallFont)
                        TextField("", text: $model.confirmationText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 150)
                            .onSubmit { if matches(action) { model.confirmPending() } }
                    }

                    if let hint = model.confirmationHint {
                        Text(hint)
                            .font(style.smallFont)
                            .foregroundColor(style.caution)
                    }

                    HStack {
                        Spacer()
                        ThemeButton(title: "Cancel") { model.cancelPending() }
                        ThemeButton(
                            title: action == .emptyTrash ? "Delete Permanently" : "Move to Quarantine",
                            isPrimary: true,
                            isEnabled: matches(action),
                            help: action == .emptyTrash
                                ? "Removes what is in the Trash for good."
                                : "Moves everything listed into Quarantine, where it can be put back."
                        ) { model.confirmPending() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: 520)
        }
    }

    private func matches(_ action: CleanerModel.PendingAction) -> Bool {
        model.confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == action.word
    }

    // MARK: - Housekeeper

    private var housekeeperTopic: HousekeeperTopic {
        var facts: [String] = []
        facts.append("This is the Clean Up screen. It finds things that can be made again — caches, logs, build folders, installers — and moves them into Quarantine when the reader ticks them and confirms.")
        facts.append("Everything except the Trash is reversible: the items are moved, not deleted, and Quarantine can put them back.")
        facts.append("The Trash is the only irreversible action on this screen. Emptying it asks for a typed confirmation and leaves no Quarantine copy.")

        for category in CleanCategory.allCases {
            switch category {
            case .uninstall:
                facts.append("Uninstall: \(model.apps.count) applications listed outside Apple's own. Ticking one moves the app and the files found beside it.")
            case .trash:
                facts.append("Trash: \(model.trash.count) items, \(model.trash.size.sizeDescription).")
            default:
                facts.append("\(category.title): \(model.count(in: category)) items, \(model.total(in: category).sizeDescription). \(category.subtitle)")
            }
        }

        facts.append("Nothing is ticked on the reader's behalf. The button at the bottom is disabled until something is ticked.")
        if !model.failures.isEmpty {
            facts.append("\(model.failures.count) items could not be moved; the reasons are shown on screen.")
        }

        return HousekeeperTopic(
            id: "clean",
            title: "Clean Up",
            label: model.cleanerTotal == 0 ? nil : model.cleanerTotal.sizeDescription,
            tone: .plain,
            facts: facts,
            opener: "What can I clean here, and what happens to the things I tick?"
        )
    }
}
