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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let style = UIStyle.resolve(appState.currentTheme)

        Screen()
            .environment(\.uiStyle, style)
            .housekeepingSurface(style)
            // 1100 rather than the 1040 this window used to open at: the job bar
            // is the width of the window at its narrowest, and eight labelled
            // buttons crowded into 1040 would either wrap or start truncating
            // their own names — which is the opposite of the point of putting
            // them there.
            .frame(minWidth: 1100, minHeight: 680)
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
                    .housekeepingSurface(style)
            }
            .sheet(isPresented: $appState.showGuidedCleanup) {
                GuidedCleanupView(items: appState.guidedCleanupItems)
                    .environment(\.uiStyle, style)
                    .environmentObject(appState)
                    .housekeepingSurface(style)
            }
            .sheet(isPresented: $appState.showCleanupPreview) {
                CleanupPreviewView(items: appState.recommendedCleanupItems)
                    .environment(\.uiStyle, style)
                    .environmentObject(appState)
                    .housekeepingSurface(style)
            }
            .sheet(isPresented: $appState.showQuarantineManagement) {
                QuarantineView()
                    .environment(\.uiStyle, style)
                    .environmentObject(appState)
                    .housekeepingSurface(style)
            }
            .sheet(isPresented: $appState.showProtectionList) {
                ProtectionView()
                    .environment(\.uiStyle, style)
                    .environmentObject(appState)
                    .housekeepingSurface(style)
            }
            // The disk browser measures and navigates, and it never acts on what it
            // finds, so it holds none of the cleanup state. It is handed `appState`
            // for one thing only: the housekeeper's subject slot, because the
            // housekeeper is a sheet on this window and this screen is a sheet too,
            // so it is the one that has to step aside and ask.
            .sheet(isPresented: $appState.showDiskBrowser) {
                DiskBrowserView()
                    .environment(\.uiStyle, style)
                    .environmentObject(appState)
                    .housekeepingSurface(style)
            }
            // Like the disk browser this is its own job, but unlike it this one
            // acts: it runs Homebrew, the store's tool, and swaps bundles. So it
            // gets the state, and it starts its own reading rather than showing
            // rows from a scan that was about something else entirely.
            .sheet(isPresented: $appState.showUpdateList) {
                UpdateView()
                    .environment(\.uiStyle, style)
                    .environmentObject(appState)
                    .housekeepingSurface(style)
            }
            // The setup check gets the state for the update feature's reason: it
            // reads the machine and then acts on it, so the ticks and the list
            // they are ticks on have to outlive the sheet being redrawn.
            .sheet(isPresented: $appState.showSetupCheck) {
                EnvironmentView()
                    .environment(\.uiStyle, style)
                    .environmentObject(appState)
                    .housekeepingSurface(style)
            }
            // The housekeeper gets the state because it has to know which finding
            // is on screen and what Housekeeping decided about it — that pairing is
            // the whole of what it explains.
            .sheet(isPresented: $appState.showHousekeeper) {
                HousekeeperView()
                    .environment(\.uiStyle, style)
                    .environmentObject(appState)
                    .housekeepingSurface(style)
            }
            // Asked after the first screen is already drawn, not before it: the
            // answer is a line in a footer, and a launch should never wait on the
            // network to show itself.
            .task { await appState.startUpdateCheck() }
            // The menu bar holds no reference to this view, so it asks by
            // notification. Both are only posted once a window is up, because it
            // is the one that delivers them — see `WindowOpener`. What that means
            // here is that closing the window does not close the door: the octopus
            // can still be clicked, and it will build this view again to talk to.
            .onAppear {
                WindowOpener.shared.register { openWindow(id: "main") }
            }
            .onReceive(NotificationCenter.default.publisher(for: .housekeepingOpenHousekeeper)) { _ in
                appState.showHousekeeper = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .housekeepingScanNow)) { _ in
                appState.startScan()
            }
    }
}

/// Every surface Housekeeping opens — the window and each sheet alike.
///
/// A sheet is its own window, so it inherits neither the window's background nor
/// its appearance: left alone, a red app opens grey panels, and in a light-mode
/// system they would come up light with the app's own pale text on them. Both are
/// fixed here, at each point a window is opened, rather than left to the system.
///
/// The colour is the icon's, so it does not follow the system either way. `tint`
/// is what reaches the controls SwiftUI draws itself — toggles, progress bars,
/// focus rings — which otherwise stay system blue inside a red app.
struct HousekeepingSurface: ViewModifier {
    let style: UIStyle

    func body(content: Content) -> some View {
        content
            .background(WindowBackground(isRetro: style.isRetro, color: style.windowBackground))
            .preferredColorScheme(style.isRetro ? .light : .dark)
            .tint(style.accent)
    }
}

extension View {
    func housekeepingSurface(_ style: UIStyle) -> some View {
        modifier(HousekeepingSurface(style: style))
    }
}

private struct WindowBackground: View {
    let isRetro: Bool
    let color: Color

    var body: some View {
        if isRetro {
            color
        } else {
            // The wash is the icon's red rather than the system accent: it is the
            // one place the surface is allowed to be more than flat, and it should
            // be the same red the app is wearing, not a second colour arriving
            // from System Settings.
            LinearGradient(
                colors: [color, HousekeepingInk.red.opacity(0.16), color],
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
        // The sweep sits above the scan's own six screens rather than beside
        // them: while it runs it owns the window, and the results it leaves
        // behind are its own screen, not the scan summary. Checking it first
        // means no scan state has to be taught about the sweep.
        if appState.isSweeping || appState.showSweepResults {
            SweepScreen()
        } else {
            scanScreen
        }
    }

    @ViewBuilder
    private var scanScreen: some View {
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
///
/// Not private to this file: the sweep screen is its own file, and it hangs off
/// this for the same reason every screen here does. Two chromes would be two
/// places for the appearances to drift apart.
struct ScreenChrome<Content: View>: View {
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
            JobBar()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Every door the app has, on every screen, in the order a reader needs them.
///
/// These jobs were reachable from the app menu alone, which meant a reader who
/// never opened that menu would never learn Housekeeping does anything besides
/// clean — and the screen they were removed from even said so in a comment, as
/// though the menu were an interface. It is not: it is where a thing goes to be
/// hidden. The bar hangs off `ScreenChrome`, so every screen carries it in both
/// appearances, and no appearance can quietly lose a button the other has.
///
/// The row is three zones, and the zones are the point — a run of seven buttons
/// with no shape to it is a list to be read, while two of these are the same kind
/// of thing. On the left, what looks at the Mac and changes nothing: the sweep
/// first, because it is every reading at once, then the same readings one at a
/// time. In the middle, behind the rule, the two drawers holding what
/// Housekeeping has already done to the Mac. On the right, apart from both,
/// the two things that are about the app itself rather than the Mac: its
/// settings, and the housekeeper you can ask.
///
/// Quiet by construction: secondary buttons, never the default action, so
/// nothing here can be hit by pressing Return on a screen that was asking
/// something else entirely.
private struct JobBar: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    var body: some View {
        HStack(spacing: 8) {
            readingJobs

            rule

            holdingJobs

            Spacer(minLength: 16)

            settingsButton

            // The scan itself had no way to reach the housekeeper from here: the
            // findings carry one each, but the screen that is about to produce
            // them did not. This sits on the bar every screen already carries, so
            // whatever is behind it — an empty first screen, a running scan, the
            // summary, the list, the last confirmation — is what it opens on.
            AskHousekeeperButton(
                topic: housekeeperTopic,
                title: "Ask About This"
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(style.rowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(style.border)
                .frame(height: 1)
        }
    }

    /// What reads the Mac, and only reads.
    ///
    /// The sweep stands first and alone in its weight — one press for all three
    /// readings — and the three behind it are the same work done singly, for a
    /// reader who wants one answer rather than the whole account. Check My Setup
    /// was the one job with no button anywhere in the window; it had a menu item
    /// and nothing else.
    private var readingJobs: some View {
        HStack(spacing: 8) {
            ThemeButton(
                title: "Look Everywhere",
                systemImage: "sparkle.magnifyingglass",
                isEnabled: !appState.isSweeping,
                help: appState.isSweeping
                    ? "This is the sweep that is running now. It is stopped from its own screen, where Stop sits."
                    : "Read everything Housekeeping can read — the disk, the setup, and which of your apps and packages have updates — and come back with one list of what it found. It only reads: nothing is ticked, moved, installed or changed, and every screen it hands you still asks before anything happens."
            ) {
                appState.startSweep()
            }

            ThemeButton(
                title: "Browse the Disk",
                systemImage: "internaldrive",
                help: "Measure the whole disk and walk around it yourself. This only reads — it changes nothing, offers nothing, and removes nothing."
            ) {
                appState.showDiskBrowser = true
            }

            ThemeButton(
                title: "Check My Setup",
                systemImage: "wrench.and.screwdriver",
                help: "Look at the tools and commands Housekeeping itself depends on: which one a command really runs, whether a link leads anywhere, whether something installed is properly in reach. Every finding says what it would change before you can agree to it."
            ) {
                appState.showSetupCheck = true
            }

            ThemeButton(
                title: "Update Apps",
                systemImage: "arrow.triangle.2.circlepath",
                help: "What is installed, where each thing came from, and whether any of it is out of date — grouped by where its updates actually come from."
            ) {
                appState.showUpdateList = true
            }
        }
    }

    /// What Housekeeping has already done, and where the doing can be taken back.
    private var holdingJobs: some View {
        HStack(spacing: 8) {
            ThemeButton(
                title: "Quarantine",
                systemImage: "archivebox",
                help: "Everything Housekeeping has moved aside, where it went, and how to put any of it back."
            ) {
                appState.showQuarantineManagement = true
            }

            ThemeButton(
                title: "Left Alone",
                systemImage: "hand.raised",
                help: "Folders and apps you have told Housekeeping never to offer again, and the way to undo that."
            ) {
                appState.showProtectionList = true
            }
        }
    }

    /// The theme, the deep sweep, and the list of updates told to stay put all
    /// live one window away, behind the standard macOS Settings item — which is
    /// a place a reader only looks if they already know what is in there. The
    /// gear puts the same window on the bar, so the appearance of the app is
    /// reachable from the app.
    private var settingsButton: some View {
        ThemeButton(
            title: "Settings",
            systemImage: "gearshape",
            help: "Appearance, how far a scan reaches, and the updates you have told Housekeeping to leave alone."
        ) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(style.border)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 3)
    }

    // MARK: - What the housekeeper is handed from the bar

    /// The scan has six screens and one bar, so the bar cannot have one subject.
    /// This follows the screen behind it: before a scan there is nothing to
    /// describe but what a scan is about to read, during one there is the folder
    /// being audited, and after one there is the total that screen is showing.
    /// The facts are the sentences those screens already print.
    private var housekeeperTopic: HousekeeperTopic {
        // A sweep says nothing about `scanState`: its disk reading has finished,
        // so the scan switch below would describe a summary that is not on the
        // screen. Asked first, for the same reason the window asks first.
        if appState.isSweeping || appState.showSweepResults {
            return appState.sweepHousekeeperTopic
        }

        switch appState.scanState {
        case .idle:
            var facts: [String] = []
            facts.append("Nothing has been read yet. This is the screen Housekeeping opens on, and no scan has been run in this sitting.")
            facts.append("What a scan reads: ~/Library — application data, caches, logs, preferences and containers; tool caches and hidden folders in the home folder, such as cache, .npm, .ollama and similar; housekeeping files left behind on the Desktop by Office and similar apps; and your Applications folders, to work out which apps are still installed.")
            facts.append("Measuring is all it does. Nothing is moved, changed or deleted until an item is ticked and the move is confirmed, and once moved everything can be put back.")
            facts.append(appState.deepSweep
                         ? "The deep sweep is on, so it also measures the folders it cannot name, where the larger wins usually hide, at the cost of up to a minute more reading."
                         : "The deep sweep is off, so it only reports what its list of \(RuleEngine.shared.applications.count) known applications and tools covers, and anything not on that list goes unmeasured.")
            return HousekeeperTopic(
                id: "scan-idle",
                title: "Housekeeping, before a scan",
                label: "Nothing read yet",
                tone: .plain,
                facts: facts,
                opener: "What is a scan about to look at, and what does it do with what it finds?"
            )

        case .scanning:
            var facts: [String] = []
            facts.append("A scan is running now. It is reading the disk; it has not changed anything, and it cannot — measuring and moving are separate steps.")
            facts.append("Right now it is: \(appState.scanProgress.title)")
            facts.append(appState.deepSweep
                         ? "The deep sweep is on for this run, so the folders Housekeeping cannot name are being measured too, and up to a minute of extra reading is normal."
                         : "The deep sweep is off for this run, so it is reading only what its list of \(RuleEngine.shared.applications.count) known applications and tools covers.")
            facts.append("A scan can be stopped at any point. Stopping keeps whatever was measured so far; it throws nothing away and it changes nothing.")
            return HousekeeperTopic(
                id: "scan-running",
                title: "A scan is running",
                label: appState.scanProgress.title,
                tone: .plain,
                facts: facts,
                opener: "What is it doing right now, and what will it do when it finishes?"
            )

        case .complete:
            switch appState.flowStep {
            case .summary:
                var facts: [String] = []
                if let results = appState.scanResults {
                    let items = results.foundItems
                    facts.append("The scan is finished. It read the disk and stopped there — nothing has been moved, and nothing will be until a move is confirmed.")
                    facts.append("It found \(items.count) item\(items.count == 1 ? "" : "s") worth \(items.reduce(0) { $0 + $1.size }.sizeDescription).")
                    if let biggest = items.max(by: { $0.size < $1.size }) {
                        facts.append("The largest single thing is \(biggest.path.lastPathComponent) at \(biggest.size.sizeDescription)\(biggest.primaryApplication.map { ", belonging to \($0.name)" } ?? "").")
                    }
                    if results.summary.remnantsFound > 0 || results.summary.sharedResourcesFound > 0 {
                        facts.append("Of those, \(results.summary.remnantsFound) look like leftovers from apps that are gone, and \(results.summary.sharedResourcesFound) are shared resources, which are the ones to be most careful about because more than one thing may rely on them.")
                    }
                } else {
                    facts.append("The scan finished, but its results are not being held, so this screen has nothing to show. Running it again is the answer, and running it again changes nothing.")
                }
                facts.append("This screen only reports. Reading the list changes nothing — it is a list, and it can be walked away from.")
                return HousekeeperTopic(
                    id: "scan-summary",
                    title: "The scan's summary",
                    label: appState.scanResults.map { $0.foundItems.reduce(0) { $0 + $1.size }.sizeDescription },
                    tone: .plain,
                    facts: facts,
                    opener: "What did the scan find, and where is the space actually going?"
                )

            case .review:
                let selected = appState.activeCleanupItems
                var facts: [String] = []
                facts.append("This is the list of what the scan found, one row at a time. Reading it changes nothing; every tick on it is a tick a person made, because Housekeeping never ticks anything itself.")
                if let results = appState.scanResults {
                    facts.append("There are \(results.foundItems.count) items in total, worth \(results.foundItems.reduce(0) { $0 + $1.size }.sizeDescription).")
                }
                facts.append("\(selected.count) \(selected.count == 1 ? "is" : "are") ticked, worth \(appState.totalReclaimable.sizeDescription). Ticking decides what gets offered to be moved; it moves nothing by itself.")
                facts.append("The recommended ones are recommended on Housekeeping's own rules and its reading of each file. A recommendation is not proof that nothing needs it.")
                return HousekeeperTopic(
                    id: "scan-review",
                    title: "The list of findings",
                    label: "\(selected.count) ticked · \(appState.totalReclaimable.sizeDescription)",
                    tone: .plain,
                    facts: facts,
                    opener: "How should I read this list, and what do the ticks mean?"
                )

            case .confirm:
                let moving = appState.activeCleanupItems
                var facts: [String] = []
                facts.append("This is the last question before anything moves: the ticked items, named one by one, and one button that moves them.")
                facts.append("\(moving.count) item\(moving.count == 1 ? "" : "s") will move, worth \(appState.totalReclaimable.sizeDescription).")
                for item in moving.prefix(10) {
                    facts.append("- \(item.path.homeAbbreviatedPath) — \(item.size.sizeDescription)")
                }
                if moving.count > 10 { facts.append("- and \(moving.count - 10) more.") }
                facts.append("Moving means the items go into Quarantine — a normal folder at the top of the home folder, in plain sight. Nothing is deleted, and everything moved can be put back.")
                facts.append("Backing out here costs nothing. Nothing has moved yet, and the ticks are still there afterwards.")
                return HousekeeperTopic(
                    id: "scan-confirm",
                    title: "About to move \(moving.count) item\(moving.count == 1 ? "" : "s")",
                    label: appState.totalReclaimable.sizeDescription,
                    tone: moving.isEmpty ? .plain : .caution,
                    facts: facts,
                    opener: "What exactly is about to happen, and can it be undone?"
                )
            }

        case .error:
            var facts: [String] = []
            facts.append("The last scan did not finish. This is what it said: \(appState.lastErrorMessage ?? "no reason was recorded").")
            facts.append("A failed scan is a failed read. Nothing was moved, changed or deleted by it — a scan that cannot read something simply stops, and the disk is as it was.")
            facts.append("Running it again is safe and is usually the answer. If it fails the same way twice, the reason above is what to look at.")
            return HousekeeperTopic(
                id: "scan-error",
                title: "The scan did not finish",
                label: "Stopped",
                tone: .broken,
                facts: facts,
                opener: "Why did the scan stop, and does anything need putting right?"
            )
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
            // Two ways in, and they differ only in how much is read. The sweep is
            // the default because it is the one that answers the question a
            // reader arrives with — what is on this Mac — and it is safe to make
            // the default precisely because it decides nothing: it reads the
            // disk, the setup and the update list and hands back one account of
            // what it found.
            ThemeButton(
                title: "Look Everywhere",
                systemImage: "sparkle.magnifyingglass",
                isPrimary: true,
                help: "Read everything Housekeeping can read — the disk, the setup, and which of your apps and packages have updates — and come back with one list of what it found. It only reads: nothing is ticked, moved, installed or changed, and every screen it hands you still asks before anything happens."
            ) {
                appState.startSweep()
            }
            .keyboardShortcut(.defaultAction)

            ThemeButton(
                title: "Scan My Mac",
                systemImage: "magnifyingglass",
                isPrimary: false,
                help: appState.deepSweep
                    ? "Measure only the storage locations Housekeeping knows about, and also sweep the folders where undeclared data collects. The result is a list you can read and sort — nothing is ticked, moved, or changed by a scan, and you can stop it partway."
                    : "Measure only the storage locations Housekeeping knows about. The result is a list you can read and sort — nothing is ticked, moved, or changed by a scan, and you can stop it partway."
            ) {
                appState.startScan()
            }

            Divider()

            Toggle(isOn: Binding(
                get: { appState.deepSweep },
                set: { appState.setDeepSweep($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Also measure folders Housekeeping can't name")
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
        HStack(alignment: .center, spacing: 6) {
            // Read from the bundle rather than written here: this line, the one
            // in Settings, and Info.plist all used to carry their own copy of the
            // version, so a release could ship with the app naming the wrong one.
            Text("Version \(AppState.currentVersion.isEmpty ? "Unknown" : AppState.currentVersion)")
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)

            // The one place the app mentions its own age, and only once a newer
            // release has been confirmed. A copy that is current and a copy that
            // could not ask both stay silent, because neither has anything to say.
            // It is a line, not a dialog: Housekeeping is fully usable either way,
            // and a window that interrupts a cleanup to talk about packaging has
            // its priorities wrong.
            if case .newer(let available) = appState.updateStatus {
                Text("·")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
                Link(destination: AppState.releasesURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Version \(available) is out")
                    }
                    .font(style.smallFont)
                    .foregroundStyle(style.accent)
                }
                .buttonStyle(.plain)
                .help("Open the release page on GitHub. Housekeeping does not update itself and has downloaded nothing — this is only the address of the newer copy.")
            }

            Spacer()

            Text("Made by Morad")
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
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
                 ? "Every folder Housekeeping knows about came back empty, and the deep sweep found nothing outside them either. Your Mac is already tidy — or the remaining clutter is somewhere Housekeeping cannot name."
                 : "Everything Housekeeping knows about came back empty. Turning on the deep sweep would also measure folders it has nothing on file for, which is often where the real leftovers are.")
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
                Text(kind.displayName)
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
/// Not private: the housekeeper prints the same verdict above the model's prose,
/// and there has to be exactly one wording of it.
enum Verdict {
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

                    // Sits directly under the verdict because the question it
                    // answers is "why", which is the question the verdict has just
                    // raised. It belongs here rather than in the footer below,
                    // which is already carrying three buttons in a narrow pane.
                    ThemeButton(
                        title: "Ask the Housekeeper About This",
                        systemImage: "bubble.left.and.text.bubble.right",
                        help: "Opens the housekeeper on this item. It explains the verdict above in plain English; it does not make one, and it cannot clean anything."
                    ) {
                        appState.showHousekeeper = true
                    }

                    section("What this is") {
                        Text(guide.whatItIs)
                        Text("Housekeeping grouped it as: \(item.findingKind.tagline.lowercased()).")
                            .foregroundStyle(style.secondaryText)
                        if item.isUndeclared {
                            Text("Housekeeping has no entry that says what this path is. It measured it because it lives where unclaimed data collects. That says something about what Housekeeping knows, not about whether the contents matter.")
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
                        help: "This is on your left-alone list. Pressing this takes it off, which does not clean anything — it just lets Housekeeping judge this path the same way as everything else again."
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
