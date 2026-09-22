// Housekeeping — Main interface
//
// This is one interface with two appearances, not two interfaces. Every screen
// below is built once and reads its colours, fonts, and chrome from `UIStyle`,
// so no appearance can quietly grow a button — or lose one — that the other
// does not have. Anything a reader sees is decided here, in one place.

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let style = UIStyle.resolve(appState.currentTheme)

        Screen()
            .environment(\.uiStyle, style)
            .background(WindowBackground(isRetro: style.isRetro, color: style.windowBackground))
            .preferredColorScheme(style.isRetro ? .light : nil)
            .frame(minWidth: 1040, minHeight: 680)
            // Each sheet is given the appearance explicitly. A sheet is presented
            // in its own window, and one attached here — outside the
            // `.environment(\.uiStyle, …)` call above — does not inherit it: the
            // content silently falls back to `UIStyleKey.defaultValue`, which is
            // Classic 9. The effect was a Liquid Glass window opening a retro
            // sheet, with every colour and font in it hardcoded to Mac OS 9.
            .sheet(isPresented: $appState.showCleanupConfirmation) {
                CleanupView()
                    .environment(\.uiStyle, style)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showGuidedCleanup) {
                GuidedCleanupView(items: appState.guidedCleanupItems)
                    .environment(\.uiStyle, style)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showCleanupPreview) {
                CleanupPreviewView(items: appState.recommendedCleanupItems)
                    .environment(\.uiStyle, style)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showQuarantineManagement) {
                QuarantineView()
                    .environment(\.uiStyle, style)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $appState.showProtectionList) {
                ProtectionView()
                    .environment(\.uiStyle, style)
                    .environmentObject(appState)
            }
    }
}

private struct WindowBackground: View {
    let isRetro: Bool
    let color: Color

    var body: some View {
        if isRetro {
            color
        } else {
            LinearGradient(
                colors: [color, Color.accentColor.opacity(0.12), color],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
}

private struct Screen: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        switch appState.scanState {
        case .idle: WelcomeScreen()
        case .scanning: ScanningScreen()
        case .complete:
            switch appState.flowStep {
            case .summary: SummaryScreen()
            case .review: ResultsScreen()
            case .confirm: ConfirmScreen()
            }
        case .error: ErrorScreen()
        }
    }
}

/// Every screen hangs off this so the two appearances differ in exactly one
/// place: Platinum draws a title bar, Liquid Glass sits on its own background.
private struct ScreenChrome<Content: View>: View {
    @Environment(\.uiStyle) private var style
    let title: String
    let subtitle: String?
    private let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            if style.isRetro {
                TitleBarView(title: title, subtitle: subtitle)
                    .frame(height: 28)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

// MARK: - The three steps

/// Three dots for the three questions. This is the navigation model made
/// visible: at any point the reader can see how much of this is left, which is
/// the thing a bar of seven buttons could never tell them.
private struct FlowDots: View {
    @Environment(\.uiStyle) private var style
    let step: AppState.FlowStep

    private var index: Int {
        switch step {
        case .summary: return 0
        case .review: return 1
        case .confirm: return 2
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { position in
                Circle()
                    .fill(position <= index ? style.accent : style.border)
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of 3")
    }
}

/// The first question, and the only one that is purely good news. It says what
/// was found in the words a person would use, and asks for exactly one thing:
/// leave to show the list.
private struct SummaryScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    private var items: [FoundItem] { appState.scanResults?.foundItems ?? [] }
    private var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    /// The biggest kind of thing found, so the number arrives already explained.
    /// Someone doing housekeeping for you leads with where the mess actually is,
    /// rather than handing you a total to work out for yourself.
    private var biggestGroup: (kind: FindingKind, size: Int64, count: Int)? {
        var totals: [FindingKind: (size: Int64, count: Int)] = [:]
        for item in items {
            let running = totals[item.findingKind] ?? (0, 0)
            totals[item.findingKind] = (running.size + item.size, running.count + 1)
        }
        return totals
            .max { $0.value.size < $1.value.size }
            .map { (kind: $0.key, size: $0.value.size, count: $0.value.count) }
    }

    var body: some View {
        ScreenChrome(title: "Housekeeping", subtitle: "Done") {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(headline)
                            .font(style.titleFont)
                            .foregroundStyle(style.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(detail)
                            .font(style.bodyFont)
                            .foregroundStyle(style.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if let biggestGroup, !items.isEmpty {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: biggestGroup.kind.iconName)
                                    .font(.system(size: 15))
                                    .foregroundStyle(style.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Most of it is \(biggestGroup.kind.plainName) — \(biggestGroup.size.sizeDescription) across \(biggestGroup.count) item\(biggestGroup.count == 1 ? "" : "s").")
                                        .font(style.bodyFont)
                                        .foregroundStyle(style.text)
                                    Text(biggestGroup.kind.tagline)
                                        .font(style.smallFont)
                                        .foregroundStyle(style.secondaryText)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .background(style.rowSelection, in: RoundedRectangle(cornerRadius: 10))
                        }

                        Text("I have not touched anything. Reading the list changes nothing — it is a list, and you can walk away from it.")
                            .font(style.smallFont)
                            .foregroundStyle(style.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(32)
                }

                Rectangle().fill(style.border.opacity(0.5)).frame(height: 1)

                HStack(spacing: 12) {
                    FlowDots(step: .summary)
                    Spacer()
                    if items.isEmpty {
                        ThemeButton(
                            title: "Scan Again",
                            isPrimary: true,
                            help: "Read the disk again from the start. Nothing was moved, so there is nothing to undo."
                        ) { appState.startScan() }
                        .keyboardShortcut(.defaultAction)
                    } else {
                        ThemeButton(
                            title: "Look at them",
                            systemImage: "arrow.right",
                            isPrimary: true,
                            help: "Open the list. Nothing is ticked and nothing moves until you ask for it."
                        ) { appState.advanceFlow(.review) }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
        }
    }

    private var headline: String {
        items.isEmpty
            ? "Nothing worth cleaning up."
            : "I found \(items.count) thing\(items.count == 1 ? "" : "s") worth a look."
    }

    private var detail: String {
        items.isEmpty
            ? "Your Mac is in good shape. Nothing turned up that would be worth doing anything about."
            : "That is \(totalSize.sizeDescription), and most of it is the sort of thing that piles up quietly: apps you stopped using, and the leftovers they leave behind."
    }
}

// MARK: - Welcome

private struct WelcomeScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    private let scannedAreas = [
        "~/Library — application data, caches, logs, preferences, and containers",
        "Tool caches and hidden folders in your home directory (.cache, .npm, .ollama, .claude and similar)",
        "Desktop housekeeping files left behind by Office and similar apps",
        "Your Applications folders, to work out which apps are still installed"
    ]

    var body: some View {
        ScreenChrome(title: "Housekeeping", subtitle: "Safety-first cleanup") {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    masthead
                    ThemePanel { scanControls }
                    ThemePanel { scope }
                    footer
                }
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(style.accent)
            Text("Housekeeping")
                .font(style.titleFont)
                .foregroundStyle(style.text)
            Text("Finds the storage your Mac is holding on to, explains what each thing actually is, and moves nothing until you say so.")
                .font(style.bodyFont)
                .foregroundStyle(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scanControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            // One button, because there is one thing to do here. Quarantine and
            // Left Alone used to sit beside it and both are still in the app menu:
            // neither is a decision anyone makes standing on the opening screen.
            ThemeButton(
                title: "Scan My Mac",
                systemImage: "magnifyingglass",
                isPrimary: true,
                help: appState.deepSweep
                    ? "Measure the storage locations Housekeeping knows about, and also sweep the folders where undeclared data collects. The result is a list you can read and sort — nothing is ticked, moved, or changed by a scan, and you can stop it partway."
                    : "Measure the storage locations Housekeeping knows about. The result is a list you can read and sort — nothing is ticked, moved, or changed by a scan, and you can stop it partway."
            ) {
                appState.startScan()
            }
            .keyboardShortcut(.defaultAction)

            Divider()

            Toggle(isOn: Binding(
                get: { appState.deepSweep },
                set: { appState.setDeepSweep($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Also measure folders Housekeeping has no rule for")
                        .font(style.bodyFont)
                        .foregroundStyle(style.text)
                    Text("This is usually where the big wins hide, because nothing else reports them. It adds up to a minute to the scan. Those findings are shown for information and can only be cleaned after an extra typed confirmation.")
                        .font(style.smallFont)
                        .foregroundStyle(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
        }
    }

    private var scope: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT HOUSEKEEPING WILL LOOK AT")
                .font(style.labelFont)
                .foregroundStyle(style.secondaryText)

            ForEach(scannedAreas, id: \.self) { area in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").font(style.bodyFont).foregroundStyle(style.secondaryText)
                    Text(area)
                        .font(style.bodyFont)
                        .foregroundStyle(style.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Scanning only measures. Nothing is moved, changed, or deleted until you tick it and confirm.")
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
                .padding(.top, 2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(alignment: .center) {
            // Read from the bundle rather than written here: this line, the one
            // in Settings, and Info.plist all used to carry their own copy of the
            // version, so a release could ship with the app naming the wrong one.
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")")
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
            Spacer()
        }
    }
}

// MARK: - Scanning

private struct ScanningScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    private var currentPath: String? {
        if case .pathProgress(let path, _, _) = appState.scanProgress { return path }
        return nil
    }

    private var progress: Float { appState.scanProgress.progressValue }

    var body: some View {
        ScreenChrome(title: "Housekeeping", subtitle: "Scanning") {
            VStack(alignment: .leading, spacing: 16) {
                Text("Measuring your Mac")
                    .font(style.titleFont)
                    .foregroundStyle(style.text)
                Text("Housekeeping is only reading sizes and dates. Nothing is being changed.")
                    .font(style.bodyFont)
                    .foregroundStyle(style.secondaryText)

                if style.isRetro {
                    RetroProgressView(progress: progress, label: appState.scanProgress.title)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: Double(progress))
                        Text(appState.scanProgress.title)
                            .font(style.smallFont)
                            .foregroundStyle(style.secondaryText)
                    }
                }

                if let currentPath {
                    Text(currentPath)
                        .font(style.pathFont)
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(2)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                }

                Spacer()

                HStack {
                    ThemeButton(title: "Cancel", isEnabled: true, help: "Stop the scan. Nothing has been changed, so there is nothing to undo.") {
                        appState.cancelScan()
                    }
                    Spacer()
                }
            }
            .padding(24)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Results

private struct FindingGroup: Identifiable {
    let kind: FindingKind
    let items: [FoundItem]
    var id: FindingKind { kind }
}

private struct ResultsScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    @State private var query = ""
    @State private var showReadingGuide = false
    @State private var showAllNotes = false

    /// Three notes fit beside the findings without crowding them. Anything past
    /// that folds away, so a scan that produces a dozen of them can never push the
    /// list, the detail pane, and the action bar off the bottom of the window.
    private static let inlineNoteLimit = 3

    private var allItems: [FoundItem] { appState.scanResults?.foundItems ?? [] }

    private var visibleItems: [FoundItem] {
        guard !query.isEmpty else { return allItems }
        let needle = query.lowercased()
        return allItems.filter { item in
            item.path.path.lowercased().contains(needle)
                || (item.primaryApplication?.name.lowercased().contains(needle) ?? false)
        }
    }

    private var groups: [FindingGroup] {
        FindingKind.displayOrder.compactMap { kind in
            let matching = visibleItems
                .filter { $0.findingKind == kind }
                .sorted { $0.size > $1.size }
            return matching.isEmpty ? nil : FindingGroup(kind: kind, items: matching)
        }
    }

    private var totalSize: Int64 { allItems.reduce(0) { $0 + $1.size } }

    var body: some View {
        ScreenChrome(title: "Housekeeping", subtitle: "Findings") {
            VStack(spacing: 0) {
                header
                Rectangle().fill(style.border.opacity(0.5)).frame(height: 1)

                if allItems.isEmpty {
                    nothingFound
                } else {
                    HSplitView {
                        sidebar
                        DetailPane(item: appState.inspectedItem)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Rectangle().fill(style.border.opacity(0.5)).frame(height: 1)
                ActionBar()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(allItems.isEmpty
                     ? "Nothing to clean"
                     : "Found \(allItems.count) thing\(allItems.count == 1 ? "" : "s") worth reviewing")
                    .font(style.titleFont)
                    .foregroundStyle(style.text)

                Spacer()

                if !allItems.isEmpty {
                    Text("\(totalSize.sizeDescription) in total")
                        .font(style.bodyFont)
                        .foregroundStyle(style.secondaryText)
                }
            }

            Text(measuredLine)
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)

            notesBanner

            if let error = appState.lastErrorMessage, !error.isEmpty {
                Text(error)
                    .font(style.smallFont)
                    .foregroundStyle(style.negative)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            DisclosureGroup(isExpanded: $showReadingGuide) {
                readingGuide
                    .padding(.top, 6)
            } label: {
                Text("How to read this list")
                    .font(style.labelFont)
                    .foregroundStyle(style.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var measuredLine: String {
        guard let results = appState.scanResults else { return "" }
        let seconds = String(format: "%.1f", results.scanDuration)
        return "Measured \(results.scannedPaths.count) location\(results.scannedPaths.count == 1 ? "" : "s") in \(seconds) seconds."
    }

    @ViewBuilder
    private var notesBanner: some View {
        let notes = appState.scanResults?.scanNotes ?? []
        if !notes.isEmpty {
            let shown = Array(notes.prefix(Self.inlineNoteLimit))
            let hidden = Array(notes.dropFirst(Self.inlineNoteLimit))

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, note in
                    noteRow(note)
                }

                if !hidden.isEmpty {
                    DisclosureGroup(isExpanded: $showAllNotes) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(Array(hidden.enumerated()), id: \.offset) { _, note in
                                    noteRow(note)
                                }
                            }
                            .padding(.top, 4)
                        }
                        // Same reason as the review sheet: with the modifiers the
                        // other way round the block is always 120 points tall, so
                        // one short note left a blank space under the disclosure.
                        .frame(maxHeight: 120)
                        .fixedSize(horizontal: false, vertical: true)
                    } label: {
                        Text(showAllNotes
                             ? "Hide these details"
                             : "Show \(hidden.count) more detail\(hidden.count == 1 ? "" : "s")")
                            .font(style.labelFont)
                            .foregroundStyle(style.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.rowSelection.opacity(0.45))
        }
    }

    private func noteRow(_ note: ScanResults.ScanNote) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(note.phase)
            Text(note.message)
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var readingGuide: some View {
        VStack(alignment: .leading, spacing: 8) {
            guideRow(
                icon: "checkmark.seal.fill",
                colour: style.positive,
                title: "Ready to clean",
                text: "Housekeeping is confident this is replaceable — a cache, a log, or residue from something no longer installed. Tick it and it moves to Quarantine."
            )
            guideRow(
                icon: "exclamationmark.triangle.fill",
                colour: style.caution,
                title: "Inspect only",
                text: "This might be disposable, but Housekeeping cannot prove it. Tick it and you will be asked to type a confirmation before anything moves."
            )
            guideRow(
                icon: "lock.fill",
                colour: style.secondaryText,
                title: "Leave it alone",
                text: "This is your data, a credential, or something a program still needs. Housekeeping has made it impossible to tick, on purpose."
            )
            guideRow(
                icon: "checkmark.square",
                colour: style.text,
                title: "The tick box",
                text: "Nothing is ever pre-ticked. Every item in the list starts unticked and stays that way unless you tick it."
            )
        }
    }

    private func guideRow(icon: String, colour: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colour)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(style.labelFont).foregroundStyle(style.text)
                Text(text).font(style.smallFont).foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(style.secondaryText)
                TextField("Filter by name or path", text: $query)
                    .textFieldStyle(.plain)
                    .font(style.bodyFont)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(style.secondaryText)
                    }
                    .buttonStyle(.plain)
                    .helpIfPresent("Clear the filter")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Rectangle().fill(style.border.opacity(0.5)).frame(height: 1)

            if groups.isEmpty {
                VStack {
                    Spacer()
                    Text("Nothing matches “\(query)”.")
                        .font(style.bodyFont)
                        .foregroundStyle(style.secondaryText)
                    ThemeButton(
                        title: "Clear the filter",
                        help: "Show every result again. The filter only hides rows — it never changes what was found, what it is, or what is ticked."
                    ) { query = "" }
                        .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.items) { item in
                                    FindingRow(item: item)
                                }
                            } header: {
                                GroupHeader(kind: group.kind, items: group.items)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 440, idealWidth: 500)
        .background(style.isRetro ? style.rowBackground : Color.clear)
    }

    private var nothingFound: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(style.positive)
            Text("There is nothing here Housekeeping can offer to clean.")
                .font(style.titleFont)
                .foregroundStyle(style.text)
            Text(appState.deepSweep
                 ? "Every rule Housekeeping has came back empty, and the deep sweep found nothing outside them either. Your Mac is already tidy — or the remaining clutter is somewhere Housekeeping has no rule for."
                 : "Every rule Housekeeping has came back empty. Turning on the deep sweep would also measure folders no rule describes, which is often where the real leftovers are.")
                .font(style.bodyFont)
                .foregroundStyle(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: 620, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct GroupHeader: View {
    @Environment(\.uiStyle) private var style
    let kind: FindingKind
    let items: [FoundItem]

    private var total: Int64 { items.reduce(0) { $0 + $1.size } }

    /// How many in this group have sat untouched long enough to look abandoned.
    /// The single most useful number for spotting a phantom from a bygone year.
    private var staleCount: Int { items.filter { $0.lastUsedIsStale }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: kind.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(style.text)
                Text(kind.rawValue)
                    .font(style.labelFont)
                    .foregroundStyle(style.text)
                Text("\(items.count)")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
                if staleCount > 0 {
                    Text("· \(staleCount) not used in over \(FoundItem.staleAfterDays / 30) months")
                        .font(style.smallFont)
                        .foregroundStyle(style.caution)
                        .lineLimit(1)
                }
                Spacer()
                Text(total.sizeDescription)
                    .font(style.labelFont)
                    .foregroundStyle(style.text)
            }
            Text(kind.tagline)
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.groupingBackground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(style.border.opacity(0.45)).frame(height: 1)
        }
    }
}

private struct FindingRow: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style
    let item: FoundItem

    private var assessment: CleanupSafetyPolicy.Assessment {
        appState.cleanupAssessment(for: item)
    }

    private var isInspected: Bool { appState.inspectedItemID == item.id }

    /// Says when this was last used, or says plainly that macOS kept no dates for
    /// it, which is itself useful: an item nobody has touched in years is what the
    /// reader is looking for.
    private var ageLabel: String {
        item.lastUsedDate == nil ? "no dates recorded" : "used \(item.lastUsedDescription)"
    }

    var body: some View {
        HStack(spacing: 10) {
            if assessment.canBeSelected || item.isSelected {
                ThemeCheckbox(isChecked: item.isSelected) {
                    appState.toggleSelection(for: item.id)
                }
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(style.secondaryText)
                    .frame(width: 22, height: 22)
                    .helpIfPresent("Housekeeping will not clean this. \(assessment.reason)")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.path.lastPathComponent)
                    .font(style.bodyFont)
                    .foregroundStyle(style.text)
                    .lineLimit(1)
                // The path is the part that can be cut short; the age is not, so
                // it keeps its whole width and the path truncates around it.
                HStack(spacing: 6) {
                    Text(item.path.deletingLastPathComponent().homeAbbreviatedPath)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Text(ageLabel)
                        .fixedSize()
                        .foregroundStyle(item.lastUsedIsStale ? style.caution : style.secondaryText)
                }
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.size.sizeDescription)
                    .font(style.bodyFont)
                    .foregroundStyle(style.text)
                Text(Verdict.of(assessment.decision).shortLabel)
                    .font(style.smallFont)
                    .foregroundStyle(Verdict.of(assessment.decision).colour(in: style))
            }
            .frame(width: 104, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isInspected ? style.rowSelection : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { appState.inspectItem(item.id) }
        .helpIfPresent(item.path.path)
    }
}

// MARK: - Verdict

/// The three things Housekeeping can say about an item, in the reader's words
/// rather than its own. Every place a verdict appears goes through here, so the
/// wording cannot drift apart between the list and the details.
private enum Verdict {
    case ready, inspect, leave

    static func of(_ decision: CleanupSafetyPolicy.Decision) -> Verdict {
        switch decision {
        case .eligibleForQuarantine: return .ready
        case .reviewOnly: return .inspect
        case .blocked: return .leave
        }
    }

    var shortLabel: String {
        switch self {
        case .ready: return "Ready to clean"
        case .inspect: return "Inspect only"
        case .leave: return "Leave it alone"
        }
    }

    var icon: String {
        switch self {
        case .ready: return "checkmark.seal.fill"
        case .inspect: return "exclamationmark.triangle.fill"
        case .leave: return "lock.fill"
        }
    }

    func colour(in style: UIStyle) -> Color {
        switch self {
        case .ready: return style.positive
        case .inspect: return style.caution
        case .leave: return style.secondaryText
        }
    }
}

// MARK: - Details

private struct DetailPane: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style
    let item: FoundItem?

    var body: some View {
        Group {
            if let item {
                content(for: item)
            } else {
                VStack {
                    Spacer()
                    Text("Pick something from the list to see what it is.")
                        .font(style.bodyFont)
                        .foregroundStyle(style.secondaryText)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 400, idealWidth: 460)
    }

    private func content(for item: FoundItem) -> some View {
        let assessment = appState.cleanupAssessment(for: item)
        let verdict = Verdict.of(assessment.decision)
        let guide = item.readerGuide

        return VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.path.lastPathComponent)
                            .font(style.titleFont)
                            .foregroundStyle(style.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(item.path.deletingLastPathComponent().homeAbbreviatedPath)
                            .font(style.pathFont)
                            .foregroundStyle(style.secondaryText)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: verdict.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(verdict.colour(in: style))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verdict.shortLabel)
                                .font(style.labelFont)
                                .foregroundStyle(verdict.colour(in: style))
                            Text(assessment.reason)
                                .font(style.bodyFont)
                                .foregroundStyle(style.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(style.rowSelection.opacity(0.4))

                    section("What this is") {
                        Text(guide.whatItIs)
                        Text("Housekeeping grouped it as “\(item.findingKind.rawValue)” — \(item.findingKind.tagline.lowercased()).")
                            .foregroundStyle(style.secondaryText)
                        if item.isUndeclared {
                            Text("Housekeeping has no rule that describes this path. It measured it because it lives where undeclared data collects. That is a statement about its rule database, not about whether the contents matter.")
                                .foregroundStyle(style.caution)
                        }
                    }

                    section("Why it is here") {
                        Text(guide.whyItExists)
                        Text(item.findingKind.explanation)
                            .foregroundStyle(style.secondaryText)
                    }

                    section("Your data in it") {
                        Text(guide.necessity)
                    }

                    section("If it is cleaned") {
                        Text("\(guide.risk.rawValue). \(guide.riskExplanation)")
                    }

                    section("The facts") {
                        facts(item)
                    }
                }
                .padding(18)
            }

            Rectangle().fill(style.border.opacity(0.5)).frame(height: 1)

            HStack(spacing: 10) {
                ThemeButton(title: "Reveal in Finder", help: "Show this in a Finder window so you can look at it yourself before deciding.") {
                    NSWorkspace.shared.activateFileViewerSelecting([item.path])
                }

                // Sits on the left, beside Reveal rather than next to the cleanup
                // button, because it is the opposite of the cleanup button: it is
                // how you tell Housekeeping to stop asking. Labels stay short because
                // this footer already carries three buttons in a narrow pane; the
                // help text is where the rules are spelled out.
                if appState.isProtected(item.path.path) {
                    ThemeButton(
                        title: "Offer It Again",
                        help: "This is on your left-alone list. Pressing this takes it off, which does not clean anything — it just lets Housekeeping judge this path by its rules again."
                    ) {
                        appState.releaseProtection(path: ProtectionList.normalize(item.path).path)
                    }
                } else {
                    ThemeButton(
                        title: "Leave It Alone",
                        help: "Adds this path to a list Housekeeping will not offer again, on this or any later scan, until you take it off. It moves and deletes nothing. Protecting a folder protects everything inside it."
                    ) {
                        appState.protect(item)
                    }
                }

                Spacer()

                if assessment.canBeSelected {
                    ThemeButton(
                        title: item.isSelected ? "Untick" : "Tick for cleanup",
                        isPrimary: item.isSelected,
                        help: assessment.requiresProtectedConfirmation
                            ? "This moves to Quarantine only after you type an extra confirmation."
                            : "This moves to Housekeeping's Quarantine, where you can put it back."
                    ) {
                        appState.toggleSelection(for: item.id)
                    }
                } else {
                    ThemeButton(
                        title: "Housekeeping will not touch this",
                        isEnabled: false,
                        help: assessment.reason
                    ) {}
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func facts(_ item: FoundItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            fact("Size", sizeValue(item))
            fact("Kind of data", item.category.displayName)
            fact("Belongs to", item.primaryApplication.map { app in
                app.isInstalled ? app.name : "\(app.name) — no longer installed"
            } ?? "Nothing Housekeeping can name")
            fact("How sure", item.association.rawValue)
            fact("Housekeeping's rating", item.safetyLevel.rawValue)
            fact(
                "Last used",
                lastUsedValue(item),
                colour: item.lastUsedIsStale ? style.caution : nil
            )
            if let modified = item.modified {
                fact("Last changed", modified.formatted(date: .abbreviated, time: .shortened))
            }
            fact("Full path", item.path.path, isPath: true)
        }
    }

    /// The measured size, or a straight admission that there is no measurement
    /// to show. A scanner that could not read a size leaves a zero behind, and a
    /// zero shown as "0 B" reads as a very small thing rather than an unknown one.
    private func sizeValue(_ item: FoundItem) -> String {
        item.size == 0
            ? "Not measured. Housekeeping could not read a size for this path, so treat it as unknown rather than empty."
            : item.size.humanReadable
    }

    /// "Last used" in words, with the honest caveat attached when the figure had
    /// to come from the change date instead of a recorded access date.
    private func lastUsedValue(_ item: FoundItem) -> String {
        guard item.lastUsedDate != nil else {
            return "Not recorded. macOS keeps no dates for this one, so there is no way to tell how long it has been sitting there."
        }
        if item.lastUsedIsRecorded {
            return item.lastUsedDescription
        }
        return "\(item.lastUsedDescription) — worked out from when it last changed, because macOS did not record a separate last-used date."
    }

    /// One "label: value" line. The label column is sized to the longest label
    /// ("Housekeeping's rating") so it always stays on one line — a label that wraps
    /// drops its second word next to the value and reads as part of it.
    private func fact(
        _ label: String,
        _ value: String,
        isPath: Bool = false,
        colour: Color? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(isPath ? style.pathFont : style.smallFont)
                .foregroundStyle(colour ?? style.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(style.labelFont)
                .foregroundStyle(style.secondaryText)
            VStack(alignment: .leading, spacing: 5) {
                content()
            }
            .font(style.bodyFont)
            .foregroundStyle(style.text)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Step 3: the one question that asks for an answer

/// The last question. It names exactly what would move, says plainly what
/// happens to it, and puts the safe answer first — "Not yet" is a complete
/// answer here, not a cancel button.
private struct ConfirmScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    private var ticked: [FoundItem] { appState.activeCleanupItems }
    private var recommended: [FoundItem] { appState.recommendedCleanupItems }

    /// Ticks the reader made themselves always win. The recommendation is only
    /// ever the answer for someone who has not expressed a preference.
    private var aboutToMove: [FoundItem] {
        ticked.isEmpty ? recommended : ticked
    }

    private var size: Int64 { aboutToMove.reduce(0) { $0 + $1.size } }
    private var wasChosenByHand: Bool { !ticked.isEmpty }

    var body: some View {
        ScreenChrome(title: "Housekeeping", subtitle: "Before anything moves") {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(headline)
                            .font(style.titleFont)
                            .foregroundStyle(style.text)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(detail)
                            .font(style.bodyFont)
                            .foregroundStyle(style.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        if !aboutToMove.isEmpty {
                            ThemePanel(padding: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ledgerLine("Moves into Quarantine", "\(size.sizeDescription), \(aboutToMove.count) item\(aboutToMove.count == 1 ? "" : "s")")
                                    ledgerLine("Deleted", "Nothing. Quarantine is an ordinary folder")
                                    ledgerLine("Putting it back", "Any item, at any time, by hand or in the app")
                                }
                            }

                            Button {
                                appState.showCleanupPreview = true
                            } label: {
                                Label("Show me what that will do first", systemImage: "doc.text.magnifyingglass")
                                    .font(style.smallFont)
                                    .foregroundStyle(style.accent)
                            }
                            .buttonStyle(.plain)
                            .help("Read the rehearsal before anything moves: which items would move, which ones would be refused because their application is open right now, and what would be left alone. Nothing moves and nothing is ticked — it is there to be read.")
                        }
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(32)
                }

                Rectangle().fill(style.border.opacity(0.5)).frame(height: 1)

                HStack(spacing: 12) {
                    FlowDots(step: .confirm)
                    Spacer()

                    ThemeButton(
                        title: "Not yet",
                        help: "Back to the list to change your mind. Nothing has moved, and nothing will until you say so."
                    ) { appState.advanceFlow(.review) }

                    ThemeButton(
                        title: "Yes, tidy up",
                        systemImage: "checkmark",
                        isPrimary: true,
                        isEnabled: !aboutToMove.isEmpty,
                        help: aboutToMove.isEmpty
                            ? "There is nothing here Housekeeping would clear on its own. Tick anything you recognise in the list and this becomes available."
                            : "Move the \(aboutToMove.count) items into Quarantine. You will see the full list once more, and nothing moves until you confirm it there."
                    ) {
                        appState.confirmRecommendedCleanup()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
            }
        }
    }

    private var headline: String {
        if aboutToMove.isEmpty { return "Nothing here I would clear without asking." }
        if wasChosenByHand {
            return "You picked \(aboutToMove.count) thing\(aboutToMove.count == 1 ? "" : "s")."
        }
        return "\(aboutToMove.count) of these are safe to clear."
    }

    private var detail: String {
        if aboutToMove.isEmpty {
            return "Nothing came up that is a clear-cut yes, and I would rather say so than talk you into something. Open the list and tick anything you recognise — or leave all of it, which is a perfectly good answer. The space is not going anywhere."
        }
        if wasChosenByHand {
            return "You chose these yourself, so I will take you at your word on which ones — you will see the full list once more before anything moves."
        }
        return "These are the ones I am confident about. Everything else in the list stays exactly where it is."
    }

    private func ledgerLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(style.labelFont)
                .foregroundStyle(style.secondaryText)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(style.bodyFont)
                .foregroundStyle(style.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Actions

/// The review step's whole navigation: back, forward, or start over. The screens
/// that used to sit here as buttons — Quarantine, Left Alone, the rehearsal, the
/// one-at-a-time walk — are all still in the app menu, which is where a thing you
/// need once a month belongs.
private struct ActionBar: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    private var ticked: [FoundItem] { appState.activeCleanupItems }
    private var recommended: [FoundItem] { appState.recommendedCleanupItems }

    var body: some View {
        HStack(spacing: 12) {
            FlowDots(step: .review)

            ThemeButton(
                title: "Start Over",
                help: "Read the disk again from the start. Nothing has moved, so there is nothing to undo."
            ) { appState.startScan() }

            Spacer()

            Text(tickedSummary)
                .font(style.smallFont)
                .foregroundStyle(ticked.isEmpty ? style.secondaryText : style.text)

            ThemeButton(
                title: "Back",
                help: "Back to the summary. Nothing has moved."
            ) { appState.advanceFlow(.summary) }

            ThemeButton(
                title: "Continue",
                systemImage: "arrow.right",
                isPrimary: true,
                isEnabled: !ticked.isEmpty || !recommended.isEmpty,
                help: ticked.isEmpty
                    ? "Go on to the last question. Nothing is ticked, so you will be asked about the \(recommended.count) item\(recommended.count == 1 ? "" : "s") Housekeeping recommends — and nothing else."
                    : "Go on to the last question with the \(ticked.count) item\(ticked.count == 1 ? "" : "s") you ticked."
            ) { appState.advanceFlow(.confirm) }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var tickedSummary: String {
        if !ticked.isEmpty {
            return "Ticked: \(ticked.count) · \(appState.totalReclaimable.sizeDescription)"
        }
        if recommended.isEmpty {
            return "Nothing here clears itself — tick anything you recognise"
        }
        return "Nothing ticked — I would suggest \(recommended.count)"
    }
}

// MARK: - Error

private struct ErrorScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    var body: some View {
        ScreenChrome(title: "Housekeeping", subtitle: "Problem") {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(style.caution)
                Text("The scan could not finish")
                    .font(style.titleFont)
                    .foregroundStyle(style.text)
                Text(appState.lastErrorMessage ?? "Housekeeping could not read part of your home folder. Nothing has been changed.")
                    .font(style.bodyFont)
                    .foregroundStyle(style.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This is usually a permissions problem: Housekeeping needs access to the folders it is measuring. Nothing was moved, so there is nothing to undo.")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                HStack {
                    ThemeButton(
                        title: "Try Again",
                        isPrimary: true,
                        help: "Run the same scan once more. If macOS is refusing a folder rather than the folder being broken, granting access in System Settings → Privacy & Security → Files and Folders and then trying again is usually what fixes it."
                    ) { appState.startScan() }
                    ThemeButton(
                        title: "Back to the Start",
                        help: "Put the app back on its opening screen without scanning again. Nothing was moved, so there is nothing to undo."
                    ) { appState.cancelScan() }
                    Spacer()
                }
            }
            .padding(24)
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}
