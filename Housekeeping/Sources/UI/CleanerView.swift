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
    @State private var expandedApps: Set<String> = []
    @State private var inspectedCandidate: CleanCandidate?
    @State private var showScanDetails = false

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                header
                if model.phase == .scanning { scanProgress }
                if model.category != .trash { browsingControls }
                HStack(alignment: .top, spacing: 12) {
                    sidebar
                        .frame(width: 216)
                    detailPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if showScanDetails { scanDetails }
                footer
            }
            .padding(16)

            if let action = model.pendingAction {
                confirmation(action)
            }
        }
        .frame(minWidth: 900, maxWidth: .infinity, minHeight: 620, maxHeight: .infinity)
        .preferredColorScheme(style.isRetro ? .light : nil)
        .onAppear { model.scanIfNeeded() }
        .sheet(item: $inspectedCandidate) { candidate in
            candidateInspector(candidate)
                .housekeepingSurface(style)
        }
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
            if model.wasStopped { return "Partial scan · \(model.completedCategories.count) of \(CleanCategory.allCases.count) categories checked. Look Again to finish a fresh scan." }
            let when = model.lastScan?.formatted(date: .omitted, time: .shortened) ?? "just now"
            if model.cleanerTotal == 0 {
                return "Last looked at \(when). Nothing to offer this time."
            }
            return "Last looked at \(when). \(model.cleanerTotal.sizeDescription) across \(model.candidates.count) items. \(model.selectedCandidates.count) selected."
        }
    }


    private var scanProgress: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.progressLine).font(style.labelFont)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(Int(context.date.timeIntervalSince(model.scanStartedAt ?? context.date)))s elapsed · Reading only")
                        .font(style.smallFont).foregroundColor(style.secondaryText)
                }
            }
            Spacer()
            ThemeButton(title: "Stop Scan", systemImage: "stop.fill") { model.stopScan() }
        }.padding(10).background(style.rowBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private var browsingControls: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundColor(style.secondaryText)
            TextField("Search names, paths, or explanations", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search cleanup results")
            if !model.query.isEmpty {
                Button("Clear Search") { model.query = "" }
            }
            Picker("Sort", selection: $model.order) {
                ForEach(FileOrder.allCases.filter { model.category != .uninstall || ($0 != .oldest && $0 != .newest) }) { order in
                    Text(order.shortLabel).tag(order).help(order.rawValue)
                }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 360)
            Button(showScanDetails ? "Hide Scan Details" : "Scan Details") { showScanDetails.toggle() }
        }
        .font(style.smallFont)
        .onChange(of: model.category) { category in
            if category == .uninstall && (model.order == .oldest || model.order == .newest) { model.order = .largest }
        }
    }

    private var scanDetails: some View {
        ThemePanel(padding: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scan coverage").font(style.labelFont)
                    Text("This scan checks common user caches and logs, known developer caches and project roots, downloads and large files, installed third-party applications, and the Trash. It is not a complete inventory of every file on this Mac. Folder sizes are estimates from allocated file sizes; APFS sharing can affect the space recovered.").font(style.smallFont)
                    Text("Quarantine stays on this disk. Moving items there does not free their storage; review and remove them later when you are sure.").font(style.smallFont)
                    ForEach(model.notes, id: \.self) { Text($0).font(style.smallFont).foregroundColor(style.caution) }
                    ForEach(model.failures, id: \.self) { Text($0).font(style.smallFont).foregroundColor(style.caution).textSelection(.enabled) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 135)
        }
    }

    private func candidateInspector(_ candidate: CleanCandidate) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(candidate.name).font(style.titleFont)
            Text(candidate.category.title + " · " + candidate.size.sizeDescription).font(style.labelFont)
            Text(candidate.detail).font(style.bodyFont)
            Text(candidate.url.path).font(style.pathFont).textSelection(.enabled)
            if let modified = candidate.modified {
                Text("Last modified: " + modified.formatted(date: .abbreviated, time: .shortened)).font(style.smallFont)
            }
            Text(candidate.category == .largeFiles
                 ? "Size and age do not establish that a file is disposable. Open it before deciding."
                 : "Review the contents before moving this item. Folder modification dates do not establish when an application was last used.")
                .font(style.smallFont).foregroundColor(style.caution)
            Text("Moving to Quarantine keeps a recoverable copy on this disk and does not immediately free storage.").font(style.smallFont)
            HStack {
                ThemeButton(title: "Open") { NSWorkspace.shared.open(candidate.url) }
                ThemeButton(title: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([candidate.url]) }
                Spacer()
                ThemeButton(title: "Done", isPrimary: true) { inspectedCandidate = nil }
            }
        }.padding(20).frame(width: 620).foregroundColor(style.text)
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
        if !model.completedCategories.contains(category) {
            return model.phase == .scanning ? "Waiting / reading…" : "Not checked"
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
        let rows = model.visibleCandidates(in: category)
        return VStack(spacing: 10) {
            ThemePanel(padding: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(category.title)
                            .font(style.labelFont)
                        Spacer()
                        let selected = rows.filter(\.isSelected)
                        let allSelected = !rows.isEmpty && rows.allSatisfy(\.isSelected)
                        HStack(spacing: 6) {
                            ThemeCheckbox(
                                isChecked: allSelected,
                                isMixed: !selected.isEmpty && !allSelected,
                                help: "Ticks or unticks everything on this shelf. Nothing is moved until you press the button at the bottom."
                            ) {
                                model.setVisible(selected: !allSelected)
                            }
                            Text(allSelected ? "Untick shown" : "Tick shown")
                                .font(style.smallFont)
                                .foregroundColor(style.secondaryText)
                                .onTapGesture {
                                    model.setVisible(selected: !allSelected)
                                }
                                .help("Same as the box beside it: ticks or unticks every item on this shelf.")
                        }
                    }
                    Text("\(rows.count) shown of \(model.count(in: category)) · \(rows.reduce(Int64(0)) { $0 + $1.size }.sizeDescription)")
                        .font(style.smallFont).foregroundColor(style.secondaryText)
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
                    Text(!model.completedCategories.contains(category) ? "This category has not finished scanning." : model.query.isEmpty ? "Nothing on this shelf." : "No matching items.")
                        .font(style.bodyFont)
                    Text(!model.completedCategories.contains(category)
                         ? "Let the scan finish, or use Look Again after stopping."
                         : model.query.isEmpty ? "No candidates were reported in this category. Check Scan Details for coverage and access limits." : "Change or clear the search to see the other items.")
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
                HStack {
                    if let date = candidate.modified {
                        Text("Modified " + date.formatted(date: .abbreviated, time: .omitted))
                            .font(style.smallFont).foregroundColor(style.secondaryText)
                    }
                    Spacer()
                    Button("Inspect…") { inspectedCandidate = candidate }
                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([candidate.url]) }
                }.font(style.smallFont)
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
        .hoverHighlight(cornerRadius: 10, normal: style.rowBackground, hovered: style.groupingBackground, stroke: style.border)
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

            if model.visibleApps.isEmpty {
                Spacer()
                Text(model.phase == .scanning ? "Still reading…" : model.query.isEmpty ? "No applications found outside Apple's own." : "No applications match this search.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(model.visibleApps) { app in
                            appRow(app)
                        }
                    }
                }
            }
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(style.labelFont)
                    Text("App \(app.size.sizeDescription) · Related data \(app.leftoverSize.sizeDescription)")
                        .font(style.smallFont).foregroundColor(style.secondaryText)
                    if let version = app.version { Text("Version " + version).font(style.smallFont) }
                }
                Spacer()
                if app.isRunning { Text("Running").font(style.smallFont).foregroundColor(style.caution) }
                Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                ThemeButton(title: "Uninstall…", isEnabled: !app.isRunning && model.phase == .ready) {
                    model.requestUninstall(app)
                }
            }
            Text(app.url.homeAbbreviatedPath).font(style.pathFont).foregroundColor(style.secondaryText).textSelection(.enabled)
            if !app.leftovers.isEmpty {
                Button {
                    if !expandedApps.insert(app.id).inserted { expandedApps.remove(app.id) }
                } label: {
                    Label("\(expandedApps.contains(app.id) ? "Hide" : "Review") \(app.leftovers.count) related items · \(app.leftovers.filter { model.includedRelatedPaths.contains($0.id) }.count) chosen",
                          systemImage: expandedApps.contains(app.id) ? "chevron.down" : "chevron.right")
                        .font(style.smallFont).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if expandedApps.contains(app.id) {
                    Text("These belong to an installed app. Some can hold personal or shared data. Only checked items join the uninstall.")
                        .font(style.smallFont).foregroundColor(style.caution)
                    ForEach(app.leftovers) { related in
                        HStack(alignment: .top, spacing: 8) {
                            ThemeCheckbox(isChecked: model.includedRelatedPaths.contains(related.id)) { model.toggleRelated(related) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(related.name).font(style.labelFont)
                                Text(related.url.homeAbbreviatedPath).font(style.pathFont).textSelection(.enabled)
                                Text(related.detail).font(style.smallFont).foregroundColor(style.secondaryText)
                            }
                            Spacer()
                            Text(related.size.sizeDescription).font(style.smallFont).monospacedDigit()
                            Button("Inspect…") { inspectedCandidate = related }
                        }.padding(6).background(style.groupingBackground, in: RoundedRectangle(cornerRadius: 6))
                        .contextMenu {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([related.url]) }
                            Button("Leave This Alone") { leaveAlone(related.url, kind: "Uninstall Apps") }
                        }
                    }
                }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .hoverHighlight(cornerRadius: 10, normal: style.rowBackground, hovered: style.groupingBackground, stroke: style.border)
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(app.url) }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
            Button("Ask the Housekeeper About This App…") { askHousekeeper(topic(for: app)) }
            Button("Copy Path") { copyToPasteboard(app.url.path) }
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
            facts.append("Housekeeping also matched \(app.leftovers.count) related item\(app.leftovers.count == 1 ? "" : "s") that may belong to it in the home folder, \(app.leftoverSize.sizeDescription) together.")
        }
        facts.append(app.isRunning
                     ? "It is open right now, so macOS will not let it be moved until it is quit."
                     : "It is not open.")
        facts.append("Uninstalling moves the application and only the related items explicitly checked by the user into Quarantine. Matching support files does not prove that they are disposable.")
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
                            isEnabled: !model.trash.isEmpty && model.phase == .ready,
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
        VStack(spacing: 12) {
            Divider()
            HStack {
                statusLine
                    .font(style.smallFont)
                    .foregroundStyle(model.failures.isEmpty ? style.secondaryText : style.caution)
                    .lineLimit(2)
                Spacer()
                if !model.selectedCandidates.isEmpty {
                    Button("Clear selection") { model.clearSelection() }.font(style.smallFont)
                }
            }
            HStack(spacing: 10) {
                AskHousekeeperButton(topic: housekeeperTopic, title: "Explain this screen")
                Spacer()
                ThemeButton(title: "Quarantine", systemImage: "archivebox",
                            help: "Review or restore items previously moved into Quarantine.") {
                    appState.screen = .quarantine
                }
                if model.category != .uninstall && model.category != .trash {
                    ThemeButton(title: cleanButtonTitle, systemImage: "checklist", isPrimary: true,
                                isEnabled: !model.selectedCandidates.isEmpty && model.phase == .ready,
                                help: "Review the selected paths before anything moves.") { model.requestClean() }
                }
            }
        }
        .padding(.top, 4)
    }

    private var cleanButtonTitle: String {
        let count = model.selectedCandidates.count
        guard count > 0 else { return "Review selection…" }
        return "Review \(count) selected…"
    }

    private var statusLine: Text {
        if !model.failures.isEmpty {
            return Text("\(model.failures.count) thing\(model.failures.count == 1 ? "" : "s") could not be moved. Open Scan Details to read the reasons.")
        }
        if let outcome = model.outcome {
            return Text(outcome)
        }
        if !model.notes.isEmpty {
            return Text(model.notes.joined(separator: " "))
        }
        let count = model.selectedCandidates.count
        if count == 0 {
            return Text("Select items to review. Nothing moves until you confirm the exact paths.")
        }
        let hidden = model.selectedCandidates.filter { $0.category != model.category || !model.matches($0.name, path: $0.url.path, detail: $0.detail) }.count
        return Text("\(count) selected across all categories · \(model.selectedSize.sizeDescription)\(hidden > 0 ? " · \(hidden) outside this view" : "").")
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

                    if !model.pendingPaths.isEmpty {
                        Text("Exact paths to move (\(model.pendingPaths.count))").font(style.labelFont)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(model.pendingPaths, id: \.self) { path in
                                    Text(path).font(style.pathFont).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }.frame(maxHeight: 200)
                        Text("Quarantine retains these files on this disk. It does not immediately free storage.")
                            .font(style.smallFont).foregroundColor(style.caution)
                    }
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
