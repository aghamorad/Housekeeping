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


    /// The view a sheet shows, one screen per case. Each is given the
    /// appearance explicitly — a sheet is presented in its own window, and one
    /// attached here outside the `.environment(\.uiStyle, …)` call above would
    /// not inherit it: the content falls back to `UIStyleKey.defaultValue`,
    /// which is Classic 9, so a Liquid Glass window opened a retro sheet.
    private func sheetBody(_ screen: AppState.Screen) -> some View {
        let style = UIStyle.resolve(appState.currentTheme)
        return Group {
            switch screen {
            case .cleanupConfirmation: CleanupView()
            case .guidedCleanup: GuidedCleanupView(items: appState.guidedCleanupItems)
            case .cleanupPreview: CleanupPreviewView(items: appState.recommendedCleanupItems)
            case .quarantine: QuarantineView()
            case .protectionList: ProtectionView()
            case .diskBrowser: DiskBrowserView(model: appState.diskBrowser)
            case .reconcile: ReconcileView(model: appState.reconciler)
            case .updateList: UpdateView()
            case .setupCheck: EnvironmentView()
            case .housekeeper: HousekeeperView()
            case .routes: RoutesView(model: appState.routeTester)
            case .phone: PhoneView(model: appState.phoneController)
            case .mediaDock: mediaDockBody
            case .bookbind: BookbindView(engine: appState.bookbind)
            case .selfUpdate: SelfUpdateView()
            case .clean: CleanerView(model: appState.cleaner)
            }
        }
        .environment(\.uiStyle, style)
        .environment(\.mediaDockSkin, MediaDockSkin.resolve(style))
        .environmentObject(appState)
        .housekeepingSurface(style)
    }

    /// MediaDock 9's own window, laid into a sheet. It wears the house's
    /// appearance like every other sheet — Liquid Glass by default, its Classic 9
    /// front end when that is what Housekeeping is wearing — and takes its size
    /// from the room the window has.
    private var mediaDockBody: some View {
        RootView(onBack: { appState.showMediaDock = false })
            .environmentObject(appState.mediaDock)
            .frame(minWidth: 1040, idealWidth: 1200, maxWidth: 1360,
                   minHeight: 640, idealHeight: 800, maxHeight: 980)
    }

    var body: some View {
        let style = UIStyle.resolve(appState.currentTheme)

        Group {
            if let workspace = appState.workspace {
                ScreenChrome(title: "Housekeeping") {
                    sheetBody(workspace)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Screen()
            }
        }
            .environment(\.uiStyle, style)
            .housekeepingSurface(style)
            // The tools share one navigable window; the rail scrolls when needed.
            .frame(minWidth: 1180, minHeight: 720)
            // Contextual help and confirmations stay above the active workspace.
            .sheet(item: $appState.presentedScreen) { screen in
                sheetBody(screen)
            }
            // Asked after the first screen is already drawn, not before it: the
            // answer is a line in a footer, and a launch should never wait on the
            // network to show itself.
            .task { await appState.startSelfUpdateCheck() }
            // The weekly terminal check. On most launches this is one
            // UserDefaults read; when it is due it reads the setup in the
            // background, changes nothing, uses no network, and stays silent
            // unless something is broken or running the wrong copy.
            .task { appState.runWeeklyTerminalHealthCheckIfNeeded() }
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
            // A room or a hand in the menu bar panel asked for the housekeeper by
            // name. The topic rides on the notification because the reading that
            // prompted it is the whole reason for opening the sheet.
            .onReceive(NotificationCenter.default.publisher(for: .housekeepingAskAbout)) { note in
                guard let topic = note.object as? HousekeeperTopic else { return }
                appState.housekeeperTopic = topic
                appState.showHousekeeper = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .housekeepingOpenDisk)) { _ in
                appState.showDiskBrowser = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .housekeepingScanNow)) { _ in
                appState.startScan()
            }
            .onReceive(NotificationCenter.default.publisher(for: .housekeepingOpenPhone)) { _ in
                appState.showPhone = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .housekeepingOpenMediaDock)) { _ in
                appState.showMediaDock = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .housekeepingOpenBookbind)) { _ in
                appState.showBookbind = true
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
    @AppStorage("housekeeping.appearance") private var appearance = "system"

    private var colorScheme: ColorScheme? {
        if style.isRetro { return .light }
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    func body(content: Content) -> some View {
        content
            .background { HousekeepingBackdrop(style: style) }
            .preferredColorScheme(colorScheme)
            .tint(style.accentShaded)
    }
}

extension View {
    func housekeepingSurface(_ style: UIStyle) -> some View {
        modifier(HousekeepingSurface(style: style))
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
        if appState.showOverview && appState.scanState != .scanning {
            WelcomeScreen()
        } else {
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
        Group {
            if style.isRetro {
                VStack(spacing: 0) {
                    TitleBarView(title: title, subtitle: subtitle)
                        .frame(height: 28)
                    JobBar()
                    screen
                    credit
                }
            } else {
                // Liquid Glass stands the bar on its end and moves it to the
                // side. The readings these screens show are wide and short — a
                // path, a size, a list of rows — so the edge is where a run of
                // destinations costs nothing, and the top of the window is worth
                // more to the content than it was to the buttons. The credit
                // strip stays inside the right-hand column so it spans the
                // content it signs rather than the rail beside it.
                HStack(spacing: 0) {
                    JobBar()
                    VStack(spacing: 0) {
                        screen
                    }
                }
            }
        }
    }

    private var screen: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Every screen signs the app, so no screen can be the one that forgot.
    ///
    /// It is a strip rather than a word tucked in a corner, because the corners of
    /// these screens are where the readings already are — a count, a path, a
    /// percentage — and a signature competing with those is one nobody reads. Here
    /// it has its own line, on every screen, in both appearances.
    private var credit: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("Made by Morad")
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(style.rowBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(style.border.opacity(0.55))
                .frame(height: 1)
        }
    }
}

/// One door into one job, described once for both appearances.
///
/// The bar and the rail carry the same twelve doors, and the help text is not
/// decoration on either one — a button says what it does, and the tooltip is the
/// only place that says what it costs. Test Routes warns there that the
/// connection will drop; Look Everywhere says there that it changes nothing. Two
/// lists of jobs would be two places for a warning to quietly go missing, so
/// there is one list and both appearances draw it.
private struct Job: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let zone: Zone
    var isEnabled: Bool = true
    let help: String
    let action: () -> Void

    /// How long each door waits behind the one above it. Twelve doors arriving at
    /// once is a rail switching on; twelve arriving in a run is a rail being built,
    /// which is the half-second that tells a reader there are twelve of them and in
    /// what order. Short enough to be over before anyone has finished reading the
    /// first label.
    static let stagger: Double = 0.035

    /// What kind of place this is. It decides the colour of the disc on the
    /// rail, which is how a reader knows a button tests the network rather than
    /// reading the disk without first finding which group it is standing in.
    enum Zone {
        case reading
        case route
        case device
        case holding
        case app
        case extra

        /// The reading zone borrows the theme's own accent, so the rail always
        /// agrees with everything else on the screen. The other four need to be
        /// told apart from it and from each other, so they are hues of their own
        /// — dark enough to carry a white glyph, light enough to read as a disc
        /// rather than a hole.
        func tint(_ style: UIStyle) -> Color {
            switch self {
            case .reading: return style.accent
            case .route: return Color(red: 0.36, green: 0.63, blue: 0.94)
            case .device: return Color(red: 0.66, green: 0.50, blue: 0.24)
            case .holding: return Color(red: 0.40, green: 0.76, blue: 0.58)
            case .app: return Color(red: 0.64, green: 0.55, blue: 0.94)
            case .extra: return Color(red: 0.91, green: 0.60, blue: 0.36)
            }
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
/// The row is five zones, and the zones are the point — a flat run of buttons
/// with no shape to it is a list to be read, while each of these is the same kind
/// of thing. On the left, what looks at the Mac and changes nothing: the sweep
/// first, because it is every reading at once, then the same readings one at a
/// time. Behind the first rule, the one job that is about the network rather than
/// the disk, and the only button here that changes the machine while it works.
/// Behind the second rule, the one job that acts on another device rather than on
/// this Mac. Behind the third, the two drawers holding what Housekeeping has
/// already done. On the right, apart from all of it, the two things that are
/// about the app itself rather than the Mac: its settings, and the housekeeper
/// you can ask.
///
/// The two appearances then disagree about the one thing they are allowed to:
/// the shape. Classic 9 draws the row it always drew. Liquid Glass stands the
/// same five zones on their end as a rail of coloured discs down the left edge,
/// because a run of buttons read left to right is a sequence to be walked, and
/// these were never steps — see `rail`.
///
/// Quiet by construction: secondary buttons, never the default action, so
/// nothing here can be hit by pressing Return on a screen that was asking
/// something else entirely. The rail keeps that: a disc is a destination, not an
/// answer to whatever question the screen behind it is asking.
private struct JobBar: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    var body: some View {
        if style.isRetro {
            bar
        } else {
            modernSidebar
                .frame(width: 224)
        }
    }

    // MARK: - Classic 9: the bar across the top

    private var bar: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 7)], spacing: 7) {
            ThemeButton(title: "Overview", systemImage: "square.grid.2x2", isPrimary: appState.workspace == nil && appState.showOverview) {
                appState.workspace = nil
                appState.showOverview = true
            }
            ThemeButton(title: "Scan My Mac", systemImage: "magnifyingglass", isPrimary: appState.workspace == nil && !appState.showOverview) {
                if appState.scanState == .scanning || appState.scanState == .complete {
                    appState.workspace = nil
                    appState.showOverview = false
                } else { appState.startScan() }
            }
            themeButtons(readingJobs)
            themeButtons(holdingJobs)
            themeButtons(routeJobs)
            themeButtons(deviceJobs)
            themeButtons(appJobs)
            AskHousekeeperButton(topic: housekeeperTopic, title: "Housekeeper")
        }
        .padding(10)
        .background(style.rowBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(style.border).frame(height: 1) }
    }

    private func themeButtons(_ jobs: [Job]) -> some View {
        ForEach(jobs) { job in
            if job.id == "settings", #available(macOS 14.0, *) {
                SettingsLink { Text(job.title) }
                    .buttonStyle(RetroButtonStyle())
                    .help(job.help)
            } else {
                ThemeButton(
                    title: job.title,
                    systemImage: job.systemImage,
                    isPrimary: selectedJobID == job.id,
                    isEnabled: job.isEnabled,
                    help: job.help,
                    action: job.action
                )
            }
        }
    }

    // MARK: - Liquid Glass: the rail down the side

    /// The same doors, stood on their end.
    ///
    /// A row across the top is read left to right, and reading left to right is
    /// how one reads a sequence — as though Look Everywhere came before Browse
    /// the Disk, and that before Two Folders. Nothing on this bar is a step
    /// after anything: they are eleven separate places, of five kinds, and the
    /// column is the shape that says so. It also gives the width back. Every
    /// screen behind it is wide and short, so the edge costs nothing and the top
    /// of the window was being spent on buttons rather than on the reading.
    ///
    /// The rules between the groups are a quiet way to say which kind of place
    /// something is, and a reader who never notices them has still been told:
    /// the colour of the disc says the same thing, in the half-second before the
    /// label is read.
    private var modernSidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Housekeeping").font(.system(size: 14, weight: .bold))
                    Text("Your Mac, at a glance").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 24)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 3) {
                        SidebarNavigationRow(title: "Overview", icon: "square.grid.2x2",
                                             selected: appState.workspace == nil && appState.showOverview) {
                            appState.workspace = nil
                            appState.showOverview = true
                            appState.showSweepResults = false
                        }
                        SidebarNavigationRow(title: appState.scanState == .complete ? "Scan Results" : "Scan My Mac", icon: "magnifyingglass",
                                             selected: appState.workspace == nil && !appState.showOverview) {
                            if appState.scanState == .scanning || appState.scanState == .complete {
                                appState.workspace = nil
                                appState.showOverview = false
                            } else { appState.startScan() }
                        }
                    }
                    sidebarSection("Storage", ids: ["clean", "browse-the-disk", "quarantine", "left-alone"])
                    sidebarSection("Maintenance", ids: ["look-everywhere", "update-apps", "check-my-setup", "two-folders"])
                    sidebarSection("Utilities", ids: ["mediadock", "bookbind", "test-routes", "spoof-location"])
                }.padding(.horizontal, 12)
            }
            Divider().padding(.horizontal, 16).padding(.top, 12)
            VStack(spacing: 3) {
                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Label("Settings", systemImage: "gearshape")
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverHighlight(cornerRadius: 7, hovered: Color.primary.opacity(0.045))
                } else if let job = allJobs.first(where: { $0.id == "settings" }) { sidebarJob(job) }
                SidebarNavigationRow(title: "Housekeeper", icon: "bubble.left.and.text.bubble.right", selected: false) {
                    appState.housekeeperTopic = housekeeperTopic
                    appState.showHousekeeper = true
                }
            }.padding(12)
            HStack {
                Text("Made by Morad")
                Spacer()
                Text(AppState.currentVersion)
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
                .padding(.horizontal, 20).padding(.bottom, 14)
        }
        .background { HousekeepingBackdrop(style: style, sidebar: true) }
        .overlay(alignment: .trailing) { Divider() }
    }

    private var allJobs: [Job] { readingJobs + holdingJobs + appJobs + routeJobs + deviceJobs }

    private func sidebarSection(_ title: String, ids: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.bottom, 2)
            ForEach(ids, id: \.self) { id in
                if let job = allJobs.first(where: { $0.id == id }) { sidebarJob(job) }
            }
        }
    }

    private func sidebarJob(_ job: Job) -> some View {
        SidebarNavigationRow(title: job.title, icon: job.systemImage,
                             selected: selectedJobID == job.id, enabled: job.isEnabled, action: job.action)
            .help(job.help)
    }

    private var selectedJobID: String? {
        guard let workspace = appState.workspace else { return nil }
        switch workspace {
        case .clean: return "clean"
        case .diskBrowser: return "browse-the-disk"
        case .quarantine: return "quarantine"
        case .protectionList: return "left-alone"
        case .reconcile: return "two-folders"
        case .updateList: return "update-apps"
        case .setupCheck: return "check-my-setup"
        case .mediaDock: return "mediadock"
        case .bookbind: return "bookbind"
        case .routes: return "test-routes"
        case .phone: return "spoof-location"
        default: return nil
        }
    }

    /// What reads the Mac, and only reads.
    ///
    /// The sweep stands first and alone in its weight — one press for all three
    /// readings — and the three behind it are the same work done singly, for a
    /// reader who wants one answer rather than the whole account. Check My Setup
    /// was the one job with no button anywhere in the window; it had a menu item
    /// and nothing else.
    private var readingJobs: [Job] {
        [
            Job(
                id: "look-everywhere",
                title: "Look Everywhere",
                systemImage: "sparkle.magnifyingglass",
                zone: .reading,
                isEnabled: !appState.isSweeping,
                help: appState.isSweeping
                    ? "This is the sweep that is running now. It is stopped from its own screen, where Stop sits."
                    : "Read everything Housekeeping can read — the disk, the setup, and which of your apps and packages have updates — and come back with one list of what it found. It only reads: nothing is ticked, moved, installed or changed, and every screen it hands you still asks before anything happens.",
                action: { appState.startSweep() }
            ),

            Job(
                id: "browse-the-disk",
                title: "Browse the Disk",
                systemImage: "internaldrive",
                zone: .reading,
                help: "Measure the whole disk and walk around it yourself. This only reads — it changes nothing, offers nothing, and removes nothing.",
                action: { appState.showDiskBrowser = true }
            ),

            Job(
                id: "two-folders",
                title: "Two Folders",
                systemImage: "arrow.left.arrow.right",
                zone: .reading,
                help: "Compare two folders that are meant to hold the same things — a library and its backup — and see what is on one side and not the other. Reading changes nothing; a copy happens only when you tick the row and press the button.",
                action: { appState.showReconcile = true }
            ),

            Job(
                id: "check-my-setup",
                title: "Terminal Health",
                systemImage: "wrench.and.screwdriver",
                zone: .reading,
                help: "Audit the tools and commands on this Mac: which copy of each one really runs, whether a link leads anywhere, what Homebrew reports about itself, and which updates are waiting. Every finding says what it would change before you can agree to it.",
                action: { appState.showSetupCheck = true }
            ),

            Job(
                id: "update-apps",
                title: "Update Apps",
                systemImage: "arrow.triangle.2.circlepath",
                zone: .reading,
                help: "What is installed, where each thing came from, and whether any of it is out of date — grouped by where its updates actually come from.",
                action: { appState.showUpdateList = true }
            )
        ]
    }

    /// The one job on the bar that is about the network rather than the disk.
    ///
    /// It sits in its own zone because it belongs to neither of the other two:
    /// it is not a reading, since it changes the state of the machine, and it is
    /// not a drawer of things already done, since nothing is kept. What it does
    /// leave behind is a decision — which route to use from now on — and that is
    /// the reason the warning in its help text is not a formality.
    private var routeJobs: [Job] {
        [
            Job(
                id: "test-routes",
                title: "Test Routes",
                systemImage: "network",
                zone: .route,
                help: "Try each server, protocol and port your VPN client offers, one at a time, and see which of them actually carry traffic. The client's own window lists the servers but says nothing about which of their settings this line will carry. Your connection will drop and come back over and over while it runs — that is the test working, not a fault — and it leaves the VPN disconnected when it finishes, never on a server you did not choose.",
                action: { appState.showRoutes = true }
            )
        ]
    }

    /// The one job that acts on something other than this Mac.
    ///
    /// It is not a reading — it changes where a phone says it is — and it is not
    /// a drawer of things Housekeeping has done, because nothing is kept. It
    /// stands apart from the route test for the same reason that one stands apart
    /// from the readings: it changes a device, and the help text has to say what
    /// has to be true before that can happen.
    private var deviceJobs: [Job] {
        [
            Job(
                id: "spoof-location",
                title: "Spoof Location",
                systemImage: "location.slash",
                zone: .device,
                help: "Tell a plugged-in iPhone that it is standing somewhere else. Plug it in with a USB cable, unlock it, and tap Trust if the Mac asks. Nothing is installed on the phone and nothing on it is changed; Real GPS puts it back, and the fake location also ends when the phone is unplugged or restarted.",
                action: { appState.showPhone = true }
            )
        ]
    }

    /// What Housekeeping has already done, and where the doing can be taken back.
    private var holdingJobs: [Job] {
        [
            Job(
                id: "quarantine",
                title: "Quarantine",
                systemImage: "archivebox",
                zone: .holding,
                help: "Everything Housekeeping has moved aside, where it went, and how to put any of it back.",
                action: { appState.showQuarantineManagement = true }
            ),

            Job(
                id: "left-alone",
                title: "Left Alone",
                systemImage: "hand.raised",
                zone: .holding,
                help: "Folders and apps you have told Housekeeping never to offer again, and the way to undo that.",
                action: { appState.showProtectionList = true }
            )
        ]
    }

    /// The theme, the deep sweep, and the list of updates told to stay put all
    /// live one window away, behind the standard macOS Settings item — which is
    /// a place a reader only looks if they already know what is in there. The
    /// gear puts the same window on the bar, so the appearance of the app is
    /// reachable from the app.
    private var appJobs: [Job] {
        [
            // The two other things built here, as screens rather than as apps
            // carried alongside: they open in this window, keep this window's
            // look, and are backed by the same install.
            Job(
                id: "mediadock",
                title: "MediaDock 9",
                systemImage: "play.rectangle.fill",
                zone: .extra,
                help: "A retro front end for yt-dlp, spotdl and gamdl. Paste a link and pick where it goes; the downloaders still do the downloading, and every command is shown before it runs.",
                action: { appState.showMediaDock = true }
            ),

            Job(
                id: "bookbind",
                title: "Bookbind",
                systemImage: "book.closed.fill",
                zone: .extra,
                help: "Give it a folder of loose audio and it merges it into one .m4b with chapters, looks the book up for its cover and metadata, and checks the result. It runs on this Mac.",
                action: { appState.showBookbind = true }
            ),

            Job(
                id: "clean",
                title: "Clean Up",
                systemImage: "sparkles",
                zone: .app,
                help: "Caches, logs, build folders, installers, large files and apps you no longer need — each on its own shelf, with a sentence saying what it is. Everything moved goes to Quarantine and can come back; emptying the Trash is the one exception, and it says so.",
                action: { appState.showClean = true }
            ),

            Job(
                id: "settings",
                title: "Settings",
                systemImage: "gearshape",
                zone: .app,
                help: "Appearance, how far a scan reaches, and the updates you have told Housekeeping to leave alone.",
                action: { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
            )
        ]
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
                         ? "It is also looking in the folders that belong to no app, which is usually where the space is. That is why this scan is taking longer."
                         : "It is only looking in the folders it knows an app owns. Space inside other folders is not measured, so it will not appear in the results.")
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
                         ? "This run also looks in the folders that belong to no app, so it takes longer than usual and finds more."
                         : "This run only looks in the folders it knows an app owns. Nothing else is being measured.")
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
                Group {
                    if style.isRetro {
                        Circle()
                            .fill(position <= index ? style.accent : style.border)
                            .frame(width: 7, height: 7)
                    } else {
                        // The step the reader is standing on stretches into a
                        // capsule. Three identical dots say "three of something";
                        // one longer dot says "you are here", which is the whole
                        // job of this control — and the stretching is what makes
                        // moving between steps visible.
                        Capsule()
                            .fill(position <= index ? style.accent : style.border)
                            .frame(width: position == index ? 20 : 7, height: 7)
                            .animation(HousekeepingMotion.settle, value: index)
                    }
                }
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
            if style.isRetro {
                retroBody
            } else {
                modernBody
            }
        }
    }

    /// The good-news screen, and the only one that can lead with a picture.
    ///
    /// The amount is the hero rather than the sentence about it, because the
    /// amount is the thing the reader came for and a number set at 32 points is
    /// read before any line of prose is. The ring around it is full and glowing:
    /// nothing about a finished reading is part-way through.
    private var modernBody: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    HeroMeter(
                        progress: 1,
                        symbol: items.isEmpty ? "checkmark.seal" : "sparkles",
                        caption: items.isEmpty ? "Nothing to clean up" : "found across \(items.count) item\(items.count == 1 ? "" : "s")",
                        size: 196,
                        centerText: items.isEmpty ? "Tidy" : totalSize.sizeDescription
                    )
                    .entrance()

                    VStack(spacing: 8) {
                        Text(headline)
                            .font(style.titleFont)
                            .foregroundStyle(style.text)
                        Text(detail)
                            .font(style.bodyFont)
                            .foregroundStyle(style.secondaryText)
                    }
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520)
                    .entrance(delay: 0.08)

                    if let biggestGroup, !items.isEmpty {
                        biggestPanel(biggestGroup)
                            .entrance(delay: 0.14)
                    }

                    Text("I have not touched anything. Reading the list changes nothing — it is a list, and you can walk away from it.")
                        .font(style.smallFont)
                        .foregroundStyle(style.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 460)
                        .entrance(delay: 0.20)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
            }

            Rectangle().fill(style.border.opacity(0.5)).frame(height: 1)

            footline
        }
    }

    /// Classic 9 keeps the original layout exactly. The hero ring is a modern
    /// object — a glowing gradient circle would read as decoration dropped into a
    /// Platinum window, and the point of the retro appearance is that nothing in
    /// it looks like it arrived later than 1999.
    private var retroBody: some View {
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
                        biggestPanel(biggestGroup)
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

            footline
        }
    }

    /// The one fact under the headline that makes the total mean something, so
    /// whoever is reading it does not have to work out where the mess actually is.
    private func biggestPanel(_ group: (kind: FindingKind, size: Int64, count: Int)) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: group.kind.iconName)
                .font(.system(size: 15))
                .foregroundStyle(style.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Most of it is \(group.kind.plainName) — \(group.size.sizeDescription) across \(group.count) item\(group.count == 1 ? "" : "s").")
                    .font(style.bodyFont)
                    .foregroundStyle(style.text)
                Text(group.kind.tagline)
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(style.rowSelection, in: RoundedRectangle(cornerRadius: 10))
    }

    private var footline: some View {
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

    /// The first screen, and the one that has to answer "what is this" before it
    /// asks for anything. In the modern appearance the answer is centred and the
    /// three panels arrive one after another, so the eye is walked down the page
    /// in the order the reader will actually need them: what it does, how to
    /// start it, what it will look at. Classic 9 keeps the left-aligned column it
    /// has always had, because a Platinum window does not centre its type.
    var body: some View {
        ScreenChrome(title: "Housekeeping", subtitle: "Overview") { OverviewView() }
    }

    private var legacyBody: some View {
        ScreenChrome(title: "Housekeeping", subtitle: "Safety-first cleanup") {
            ScrollView {
                VStack(alignment: style.isRetro ? .leading : .center, spacing: 16) {
                    masthead
                        .entrance()
                    WelcomeRing()
                        .entrance(delay: 0.08)
                    ThemePanel { scanOptions }
                        .entrance(delay: 0.16)
                    ThemePanel { scope }
                        .entrance(delay: 0.20)
                    footer
                        .entrance(delay: 0.24)
                }
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
        }
    }

    private var masthead: some View {
        VStack(alignment: style.isRetro ? .leading : .center, spacing: 6) {
            // Her, not a stand-in glyph. This screen is the first thing anyone
            // sees and the one place the app gets to say what it is, so it says it
            // with the mark rather than with a sparkle that every other cleaner
            // also has. `working: false` keeps her to the slow breath: she is
            // waiting to be asked for something, and a figure mid-task on an
            // untouched screen would claim work that has not started.
            WorkingOctopus(size: style.isRetro ? 60 : 68, working: false)
                .padding(.bottom, 2)
            Text("Housekeeping")
                .font(style.titleFont)
                .foregroundStyle(style.text)
            Text("Finds the storage your Mac is holding on to, explains what each thing actually is, and moves nothing until you say so.")
                .font(style.bodyFont)
                .foregroundStyle(style.secondaryText)
                .multilineTextAlignment(style.isRetro ? .leading : .center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: style.isRetro ? .leading : .center)
    }

    /// The one switch the ring does not carry. Both ways into a scan — Look
    /// Everywhere and Scan My Mac — are doors on the ring now, so what is left
    /// here is the choice about how far a scan reaches, which is a setting rather
    /// than an action and belongs in a panel of its own.
    private var scanOptions: some View {
        Toggle(isOn: Binding(
            get: { appState.deepSweep },
            set: { appState.setDeepSweep($0) }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Also look in folders that belong to no app")
                    .font(style.bodyFont)
                    .foregroundStyle(style.text)
                // Said in the reader's terms rather than the app's. The first
                // draft of this line talked about "folders Housekeeping can't
                // name" and "undeclared data", which is the vocabulary the
                // code uses and no vocabulary a reader has — it described the
                // mechanism to someone who wanted to know what the switch
                // would do to their Mac. So: what Housekeeping knows, what
                // this adds, what it costs, and the one thing that makes it
                // safe. The count is read rather than written down, because
                // it is also shown on the Settings screen and a number typed
                // into two places is a number that will disagree with itself.
                Text("Housekeeping knows where \(RuleEngine.shared.applications.count) apps and tools keep their files, and normally looks only there. Turning this on also opens the folders that belong to no app — usually where the missing space is, because nothing else reports it. It adds about a minute to a scan, and anything found that way is only listed: you tick it, then type a word to confirm.")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
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

            // The one place the app mentions its own age, and only when there is
            // something the reader can act on. A copy that is current and a copy
            // that could not ask both stay silent: "could not check" is true on
            // any launch without a network, and a footer that said it every time
            // would be talking about the connection rather than the app.
            //
            // It is a line, not a dialog. Housekeeping is fully usable either way,
            // a window that interrupts a cleanup to talk about its own packaging
            // has its priorities wrong, and nothing updates without being asked —
            // the button opens the screen, it does not start the work.
            if case .available(let report) = appState.selfUpdateState {
                Text("·")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)

                Button {
                    appState.showSelfUpdate = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(SelfUpdateView.footerLabel(for: report))
                    }
                    .font(style.smallFont)
                    .foregroundStyle(style.accent)
                }
                .buttonStyle(.plain)
                .help("Housekeeping builds itself from its own source folder. Nothing has been downloaded and nothing has changed — this opens the screen that says what updating would involve and offers to do it.")
            }

            // The credit lives on the chrome now, on its own line under every
            // screen. It used to be here, which meant the first screen signed the
            // app and the other six did not.
            Spacer()
        }
    }
}

/// The doors, arranged in a ring.
///
/// The bar above carries every job the app has, which is the right shape for a
/// reader who already knows what they are looking for and the wrong shape for
/// someone opening this for the first time: a list of twelve names tells you what
/// the app is called, not what it does. So the first screen says it the other
/// way — seven discs around the mark, each one an action with its name under it,
/// the same arrangement the Jeopardy board uses to say "these are the categories"
/// before any of them is opened.
///
/// The seven are the things a reader comes here to do. The rest (Two Folders,
/// Update Apps, Check My Setup, Quarantine, Left Alone, Settings) stay on the bar,
/// where they are a glance away rather than a second ring.
private struct WelcomeRing: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style
    @State private var hovered: String?

    private struct Door: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        let zone: Job.Zone
        let help: String
        let action: () -> Void
    }

    private var doors: [Door] {
        [
            Door(
                id: "sweep",
                title: "Look Everywhere",
                systemImage: "sparkle.magnifyingglass",
                zone: .reading,
                help: "Read the disk, the setup, and which of your apps and packages have updates — then come back with one list of what it found. It only reads: nothing is ticked, moved, installed or changed.",
                action: { appState.startSweep() }
            ),
            Door(
                id: "scan",
                title: "Scan My Mac",
                systemImage: "magnifyingglass",
                zone: .reading,
                help: "Measure the apps and tools Housekeeping knows. The result is a list you can read and sort — nothing is ticked, moved, or changed by a scan, and you can stop it partway.",
                action: { appState.startScan() }
            ),
            Door(
                id: "clean",
                title: "Clean Up",
                systemImage: "sparkles",
                zone: .reading,
                help: "Caches, logs, build folders, installers, large files and apps you no longer need, each on its own shelf. Everything moved goes to Quarantine and can come back — except emptying the Trash, which asks in words first.",
                action: { appState.showClean = true }
            ),
            Door(
                id: "phone",
                title: "Spoof Location",
                systemImage: "location.slash",
                zone: .device,
                help: "Tell a plugged-in iPhone it is standing somewhere else. It walks you through the cable, the Trust prompt and the way back to real GPS, and changes nothing on the phone itself.",
                action: { appState.showPhone = true }
            ),
            Door(
                id: "mediadock",
                title: "MediaDock 9",
                systemImage: "play.rectangle.fill",
                zone: .extra,
                help: "Paste a link and pick where it goes: yt-dlp, spotdl and gamdl do the downloading, and every command is shown before it runs.",
                action: { appState.showMediaDock = true }
            ),
            Door(
                id: "bookbind",
                title: "Bookbind",
                systemImage: "book.closed.fill",
                zone: .extra,
                help: "Give it a folder of loose audio and it merges it into one chaptered audiobook, looks up the cover and tags, and checks the result. Everything runs on this Mac.",
                action: { appState.showBookbind = true }
            ),
            Door(
                id: "routes",
                title: "Test Routes",
                systemImage: "network",
                zone: .route,
                help: "Check whether the network paths this Mac can take actually work — which services answer, and which do not. It reads and reports; nothing is reconfigured.",
                action: { appState.showRoutes = true }
            ),
            Door(
                id: "disk",
                title: "Browse the Disk",
                systemImage: "internaldrive",
                zone: .reading,
                help: "Look through the folders Housekeeping measured, by size, and open any of them in Finder. Browsing changes nothing.",
                action: { appState.showDiskBrowser = true }
            )
        ]
    }

    private var diameter: CGFloat { style.isRetro ? 448 : 482 }
    private var discSize: CGFloat { style.isRetro ? 72 : 78 }
    private var orbitRadius: CGFloat { diameter / 2 - discSize / 2 - 30 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    style.border.opacity(style.isRetro ? 0.45 : 0.30),
                    style: StrokeStyle(lineWidth: 1, dash: [3, 7])
                )
                .frame(width: orbitRadius * 2, height: orbitRadius * 2)

            centre

            ForEach(Array(doors.enumerated()), id: \.element.id) { index, door in
                // Starting at the top and running clockwise. The first door is the
                // one a reader should try, so it gets the position the eye lands on
                // first and the only halo on the screen.
                let angle = -CGFloat.pi / 2 + CGFloat(index) * (2 * .pi / CGFloat(doors.count))
                doorView(door, isPrimary: index == 0)
                    .position(
                        x: diameter / 2 + cos(angle) * orbitRadius,
                        // Lifted by half the label so the disc — not the disc and
                        // its caption together — sits on the orbit.
                        y: diameter / 2 + sin(angle) * orbitRadius + 15
                    )
            }
        }
        .frame(width: diameter, height: diameter + 34)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("What Housekeeping can do")
    }

    private var centre: some View {
        ZStack {
            Circle()
                .fill(style.accent.opacity(style.isRetro ? 0.10 : 0.13))
            Circle()
                .stroke(style.accent.opacity(0.30), lineWidth: 1)
            WorkingOctopus(size: discSize * 0.86, working: false)
        }
        .frame(width: discSize * 1.74, height: discSize * 1.74)
    }

    private func doorView(_ door: Door, isPrimary: Bool) -> some View {
        let tint = door.zone.tint(style)
        let isHot = hovered == door.id

        return VStack(spacing: 6) {
            Button {
                door.action()
            } label: {
                Image(systemName: door.systemImage)
                    .font(.system(size: discSize * 0.34, weight: .medium))
                    .foregroundColor(style.isRetro ? .white : tint)
                    .frame(width: discSize, height: discSize)
                    .background(
                        Circle().fill(
                            style.isRetro
                                ? tint.opacity(isHot ? 1.0 : 0.88)
                                : tint.opacity(isHot ? 0.30 : 0.15)
                        )
                    )
                    .overlay(
                        Circle().stroke(
                            style.isRetro ? tint : tint.opacity(isHot ? 0.85 : 0.40),
                            lineWidth: style.isRetro ? 1 : 1.5
                        )
                    )
                    .shadow(color: tint.opacity(isHot ? 0.50 : 0.0), radius: 14)
                    .scaleEffect(isHot ? 1.06 : 1.0)
                    .animation(.easeOut(duration: 0.14), value: isHot)
            }
            .buttonStyle(.plain)
            .modifier(ReturnKey(enabled: isPrimary))
            .breathingHalo(tint, radius: 12, active: isPrimary && !style.isRetro)
            .onHover { hovered = $0 ? door.id : nil }
            .help(door.help)
            .accessibilityLabel(door.title)

            Text(door.title)
                .font(style.smallFont.weight(isHot ? .semibold : .regular))
                .foregroundColor(isHot ? style.text : style.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 106)
                .animation(.easeOut(duration: 0.14), value: isHot)
        }
        .frame(width: 112)
        .contentShape(Rectangle())
    }
}

/// Return opens the first door. `keyboardShortcut` has no "sometimes" form, so
/// this applies it to one disc and leaves the other five alone — a return key
/// that fired whichever disc happened to be last would be worse than none.
private struct ReturnKey: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.keyboardShortcut(.defaultAction)
        } else {
            content
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
            if style.isRetro {
                retroBody
            } else {
                modernBody
            }
        }
    }

    /// One number, as big as the window will carry it.
    ///
    /// A scan is the only thing this app does that takes real time, and it is the
    /// only screen where the reader has nothing to do but watch. So the reading
    /// gets the whole middle of the window rather than a thin bar at the top of a
    /// list of text: the ring is the answer to "how much longer", and the line
    /// under it is the answer to "what is it doing", which is the question a bar
    /// alone never answers.
    private var modernBody: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            HeroMeter(
                progress: Double(progress),
                symbol: "sparkle.magnifyingglass",
                caption: appState.scanProgress.title,
                size: 200
            )
            .frame(maxWidth: .infinity)
            .entrance()

            VStack(spacing: 5) {
                Text("Reading sizes and dates. Nothing is being changed.")
                    .font(style.bodyFont)
                    .foregroundStyle(style.secondaryText)

                if let currentPath {
                    Text(currentPath)
                        .font(style.pathFont)
                        .foregroundStyle(style.secondaryText.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                        .frame(maxWidth: 520)
                }
            }
            .padding(.top, 10)
            .entrance(delay: 0.08)

            Spacer(minLength: 8)

            ThemeButton(
                title: "Stop the Reading",
                systemImage: "stop.circle",
                help: "Stop the scan. Nothing has been changed, so there is nothing to undo."
            ) {
                appState.cancelScan()
            }
            .entrance(delay: 0.16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Classic 9 gets the same screen in its own vocabulary: a barber-pole strip
    /// and a written line, which is what a system of that vintage actually did.
    /// The hero ring is a modern object and would read as decoration here.
    private var retroBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Measuring your Mac")
                .font(style.titleFont)
                .foregroundStyle(style.text)
            Text("Housekeeping is only reading sizes and dates. Nothing is being changed.")
                .font(style.bodyFont)
                .foregroundStyle(style.secondaryText)

            RetroProgressView(progress: progress, label: appState.scanProgress.title)

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

// MARK: - Results

private struct FindingGroup: Identifiable {
    /// Nil is the flat size list: everything found, biggest first, with no
    /// grouping at all.
    let kind: FindingKind?
    let items: [FoundItem]
    var id: String { kind?.displayName ?? "size" }
}

/// How the list is organised. Grouping by kind is how a scan is normally read —
/// one heading per kind of residue. Organising by size drops the headings and
/// puts the whole list in one descending order, which is what you want when the
/// figure in the header is the thing you are trying to move.
private enum ResultsOrder: String, CaseIterable, Identifiable {
    case kind = "Kind"
    case size = "Largest"
    case smallest = "Smallest"
    case name = "Name"

    var id: String { rawValue }

    var label: String { self == .kind ? "Kind" : "Size" }
    var help: String {
        switch self {
        case .kind: return "Group the list by what each item is."
        case .size: return "Put everything in one list, biggest first."
        case .smallest: return "Put everything in one list, smallest first."
        case .name: return "Sort the list by filename."
        }
    }
}

private struct ResultsScreen: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    @State private var query = ""
    @State private var order: ResultsOrder = .size
    @State private var showReadingGuide = false
    @State private var showScanNotes = false

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
        switch order {
        case .kind:
            return FindingKind.displayOrder.compactMap { kind in
                let matching = visibleItems
                    .filter { $0.findingKind == kind }
                    .sorted { $0.size > $1.size }
                return matching.isEmpty ? nil : FindingGroup(kind: kind, items: matching)
            }
        case .size:
            guard !visibleItems.isEmpty else { return [] }
            return [FindingGroup(kind: nil, items: visibleItems.sorted { $0.size == $1.size ? $0.path.path < $1.path.path : $0.size > $1.size })]
        case .smallest:
            return visibleItems.isEmpty ? [] : [FindingGroup(kind: nil, items: visibleItems.sorted { $0.size == $1.size ? $0.path.path < $1.path.path : $0.size < $1.size })]
        case .name:
            return visibleItems.isEmpty ? [] : [FindingGroup(kind: nil, items: visibleItems.sorted { $0.path.lastPathComponent.localizedStandardCompare($1.path.lastPathComponent) == .orderedAscending })]
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

            disclosureRow(
                showReadingGuide ? "Hide how to read this list" : "How to read this list",
                isExpanded: showReadingGuide
            ) {
                showReadingGuide.toggle()
            }
            if showReadingGuide {
                readingGuide
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var measuredLine: String {
        guard let results = appState.scanResults else { return "" }
        let seconds = String(format: "%.1f", results.scanDuration)
        return "Measured \(results.scannedPaths.count) location\(results.scannedPaths.count == 1 ? "" : "s") in \(seconds) seconds."
    }

    /// The notes above the list used to be printed in full, three paragraphs deep,
    /// before a single finding was visible. They are still one click away, but the
    /// header now reads as a title, a line, and two small links — so the list is
    /// what the screen is about again.
    @ViewBuilder
    private var notesBanner: some View {
        let notes = appState.scanResults?.scanNotes ?? []
        if !notes.isEmpty {
            disclosureRow(
                showScanNotes ? "Hide scan details" : "Scan details · \(notes.count)",
                isExpanded: showScanNotes
            ) {
                showScanNotes.toggle()
            }
            if showScanNotes {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                            noteRow(note)
                        }
                    }
                    .padding(.top, 6)
                }
                .frame(maxHeight: 140)
            }
        }
    }

    /// A one-line disclosure. `DisclosureGroup` was used here first, but its header
    /// stops taking clicks the moment it is given a plain button style — it drew the
    /// chevron and did nothing when pressed. This is the same look without that trap.
    private func disclosureRow(
        _ title: String,
        isExpanded: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(style.accent)
                Text(title)
                    .font(style.labelFont)
                    .foregroundStyle(style.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func noteRow(_ note: ScanResults.ScanNote) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(note.phase)
                .font(style.labelFont)
                .foregroundStyle(style.text)
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

                Rectangle().fill(style.border.opacity(0.5)).frame(width: 1, height: 16)

                HStack(spacing: 2) {
                    ForEach(ResultsOrder.allCases) { choice in
                        Button {
                            order = choice
                        } label: {
                            Text(choice.rawValue)
                                .font(style.smallFont)
                                .padding(.horizontal, 8)
                                .frame(height: 20)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(order == choice ? style.accent.opacity(0.28) : Color.clear)
                                )
                                .foregroundStyle(order == choice ? style.text : style.secondaryText)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(choice.help)
                        .accessibilityAddTraits(order == choice ? .isSelected : [])
                    }
                }
                .padding(2)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(style.rowBackground.opacity(0.5))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(style.border.opacity(0.6), lineWidth: 1)
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Organise the list, currently \(order.label)")
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
                                if let kind = group.kind {
                                    GroupHeader(kind: kind, items: group.items)
                                } else {
                                    SizeHeader(items: group.items)
                                }
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
                 ? "Every folder it knows about came back empty, and it found nothing in the folders belonging to no app either. Your Mac is already tidy — or the clutter is somewhere it cannot see."
                 : "Every folder it knows about came back empty. Turning on “Also look in folders that belong to no app”, in Settings, would check those too — that is often where the real leftovers are.")
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

/// The heading for the flat size list. There is no kind to name, so it names the
/// order instead and keeps the count and the total in the same place the grouped
/// headings put theirs.
private struct SizeHeader: View {
    @Environment(\.uiStyle) private var style
    let items: [FoundItem]

    private var total: Int64 { items.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(style.text)
                Text("Biggest first")
                    .font(style.labelFont)
                    .foregroundStyle(style.text)
                Text("\(items.count)")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
                Spacer()
                Text(total.sizeDescription)
                    .font(style.labelFont)
                    .foregroundStyle(style.text)
            }
            Text("Everything found, in one list. Each row still says what it is and whether it can be cleaned.")
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

    /// Two ways of wearing the same row.
    ///
    /// Classic 9 rows run edge to edge and go flat maroon when inspected, which
    /// is how a Platinum list behaves. The modern list floats each row on an
    /// inset rounded shape instead — the pointer lights the row it is over, and
    /// the row that is open stays lit, so the two states are the same gesture and
    /// the eye does not have to learn two colours.
    var body: some View {
        if style.isRetro {
            row
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isInspected ? style.rowSelection : Color.clear)
                .contentShape(Rectangle())
                .onTapGesture { appState.inspectItem(item.id) }
                .helpIfPresent(item.path.path)
        } else {
            row
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .hoverHighlight(
                    cornerRadius: 7,
                    normal: isInspected ? style.rowSelection : Color.clear,
                    hovered: style.rowSelection.opacity(isInspected ? 1 : 0.55)
                )
                .contentShape(Rectangle())
                .onTapGesture { appState.inspectItem(item.id) }
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .helpIfPresent(item.path.path)
        }
    }

    private var row: some View {
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
                        // The last screen before anything moves, so the amount moves
                        // up and gets a ring around it. It is the one number the
                        // reader is being asked to agree to, and at this size it
                        // cannot be skimmed past on the way to the buttons.
                        if !style.isRetro {
                            HeroMeter(
                                progress: 1,
                                symbol: aboutToMove.isEmpty ? "hand.raised" : "arrow.down.circle",
                                caption: aboutToMove.isEmpty ? "Nothing to clear without asking" : "moving into Quarantine, nothing deleted",
                                size: 168,
                                centerText: aboutToMove.isEmpty ? "None" : size.sizeDescription
                            )
                            .frame(maxWidth: .infinity)
                            .entrance()
                        }

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
