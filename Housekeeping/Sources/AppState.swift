// Housekeeping — AppState

import Foundation
import SwiftUI
import Combine

/// The three readings a sweep runs, in the order it runs them.
///
/// It is a type rather than three booleans because the working screen has to say
/// what the octopus is at, and "the disk, then the setup, then updates" said as
/// one value cannot drift out of step with the order the readings actually
/// happen in.
enum SweepStage: Int, CaseIterable, Equatable {
    case disk
    case setup
    case updates

    var title: String {
        switch self {
        case .disk: return "Reading the disk"
        case .setup: return "Checking the setup"
        case .updates: return "Asking about updates"
        }
    }

    /// One line under the title, saying what the octopus is doing right now.
    /// Each is a plain description of the reading behind it, not a promise about
    /// what will be found — nothing is known until the reading comes back.
    var detail: String {
        switch self {
        case .disk:
            return "Walking your home folder and measuring what each application has left behind."
        case .setup:
            return "Working out which command actually runs when you type a name, and whether the link that reaches it leads anywhere."
        case .updates:
            return "Listing what is installed, where each thing came from, and which of it is behind."
        }
    }

    /// The name it goes by in the list of three on the working screen.
    var shortTitle: String {
        switch self {
        case .disk: return "The disk"
        case .setup: return "The setup"
        case .updates: return "Updates"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    /// The one sheet the window may show at a time.
    ///
    /// AppKit attaches a single sheet to a window, so fourteen independent
    /// `showX` flags did not give fourteen screens. They gave one screen and a
    /// queue nobody could see: asking for Update Apps while Check My Setup was
    /// open put it behind Setup, and closing Setup then opened Update Apps as if
    /// the click had only just happened. One optional screen makes the flags
    /// exclusive by construction, and every `appState.showX = true` call site
    /// still reads the way it did.
    enum Screen: String, Identifiable, Hashable {
        case cleanupConfirmation, guidedCleanup, cleanupPreview, quarantine
        case protectionList, diskBrowser, reconcile, updateList, setupCheck
        case housekeeper, routes, phone, mediaDock, bookbind, selfUpdate
        case clean, localModels

        var id: String { rawValue }

        var isWorkspace: Bool {
            switch self {
            case .clean, .diskBrowser, .reconcile, .updateList, .setupCheck, .routes,
                 .phone, .mediaDock, .bookbind, .quarantine, .protectionList,
                 .localModels: return true
            default: return false
            }
        }
    }

    @Published var showOverview = true
    @Published var workspace: Screen?
    @Published var presentedScreen: Screen?
    // Tool navigation changes the workspace; contextual help and confirmations
    // present above it. Closing a modal returns to the same tool.
    var screen: Screen? {
        get { presentedScreen ?? workspace }
        set {
            if let newValue {
                if newValue.isWorkspace {
                    workspace = newValue
                    presentedScreen = nil
                } else {
                    presentedScreen = newValue
                }
            } else if presentedScreen != nil {
                presentedScreen = nil
            } else {
                workspace = nil
            }
        }
    }

    let diskBrowser = DiskBrowserModel()
    /// What is installed locally and what is in memory right now. A model's own
    /// inventory, so that reading it cannot disturb the scan or the disk browser.
    let localModels = LocalModelInventory()
    lazy var reconciler = ReconcileModel()
    lazy var routeTester = RoutesModel()
    lazy var phoneController = PhoneModel()

    private func show(_ which: Screen, _ on: Bool) {
        if on {
            screen = which
        } else if screen == which {
            screen = nil
        }
    }

    @Published var scanState: ScanState = .idle
    @Published var flowStep: FlowStep = .summary
    @Published var scanProgress: ScanProgress = .idle  // Changed from .none to .idle
    @Published var scanResults: ScanResults?
    var showCleanupConfirmation: Bool {
        get { screen == .cleanupConfirmation }
        set { show(.cleanupConfirmation, newValue) }
    }
    @Published var cleanupHistory: [CleanupRecord] = []
    @Published var currentTheme: Theme
    @Published var lastErrorMessage: String?
    @Published var inspectedItemID: UUID?
    /// Set at the end of `init`, after any quarantine left in the old hidden
    /// folder has been walked out into the visible one. A property initializer
    /// here would run before that move and report the wrong answer.
    @Published var hasQuarantineItems = false
    var showQuarantineManagement: Bool {
        get { screen == .quarantine }
        set { show(.quarantine, newValue) }
    }
    /// The Clean Up shelf: everyday junk, developer leftovers, installers,
    /// large files, apps, and the Trash. Everything it moves goes into
    /// Quarantine, except emptying the Trash, which asks first and says so.
    var showClean: Bool {
        get { screen == .clean }
        set { show(.clean, newValue) }
    }
    var showGuidedCleanup: Bool {
        get { screen == .guidedCleanup }
        set { show(.guidedCleanup, newValue) }
    }
    /// The rehearsal sheet: what a cleanup would do, said before anything does it.
    var showCleanupPreview: Bool {
        get { screen == .cleanupPreview }
        set { show(.cleanupPreview, newValue) }
    }
    @Published var guidedCleanupItems: [FoundItem] = []
    /// When on, the scan also measures folders no rule describes. It is the
    /// difference between "nothing else to clean" and "4 GB in places I have no
    /// rule for", so it defaults to on and the cost is disclosed before the scan.
    @Published var deepSweep: Bool
    /// The paths the reader has asked Housekeeping to stop offering, loaded once at
    /// launch. Published so the lists, counts, and veredicts that depend on it
    /// redraw the moment it changes.
    @Published private(set) var protectionEntries: [ProtectionList.Entry] = []
    var showProtectionList: Bool {
        get { screen == .protectionList }
        set { show(.protectionList, newValue) }
    }
    /// Whether the disk browser is open. Only the flag lives here — which folder
    /// is on screen and what the measurement found belong to `DiskBrowserModel`,
    /// so that walking around the disk cannot disturb the scan or the quarantine.
    var showDiskBrowser: Bool {
        get { screen == .diskBrowser }
        set { show(.diskBrowser, newValue) }
    }
    /// Whether the local-model list is open. Only the flag lives here: what is
    /// installed and what is loaded belong to `LocalModelInventory`, which re-reads
    /// the runtimes itself.
    var showLocalModels: Bool {
        get { screen == .localModels }
        set { show(.localModels, newValue) }
    }
    /// Whether the two-folder comparison is open. Only the flag lives here, for
    /// the same reason as the disk browser: which pair is on screen and what the
    /// comparison found belong to `ReconcileModel`, so that reading two libraries
    /// cannot disturb the scan, the disk measurements, or the quarantine.
    var showReconcile: Bool {
        get { screen == .reconcile }
        set { show(.reconcile, newValue) }
    }
    /// Whether the Routes screen is open. Only the flag lives here, for the same
    /// reason again: the run, its settings and its results belong to
    /// `RoutesModel`, so that testing routes cannot disturb the scan, the disk
    /// measurements, or the quarantine. This is the one screen here that touches
    /// the network rather than the filesystem — it connects and disconnects a VPN
    /// client over and over while it runs — which is why it is deliberately built
    /// to leave the machine on nothing when it stops.
    var showRoutes: Bool {
        get { screen == .routes }
        set { show(.routes, newValue) }
    }
    /// Whether the Spoof Location sheet is open. Only the flag lives here, for the
    /// same reason again: the phone readings and the run belong to `PhoneModel`,
    /// so a location change cannot disturb the scan or the quarantine. It is the
    /// one screen that acts on another device rather than on this Mac.
    var showPhone: Bool {
        get { screen == .phone }
        set { show(.phone, newValue) }
    }
    /// Whether MediaDock 9 is open. The flag lives here like every other door's;
    /// the settings, the queue and a command in flight belong to `mediaDock`, so
    /// closing the sheet does not drop them.
    var showMediaDock: Bool {
        get { screen == .mediaDock }
        set { show(.mediaDock, newValue) }
    }
    /// Whether Bookbind is open. Its model holds the engine and the page, for the
    /// same reason: the file list a reader has built up and a merge in progress
    /// outlive the sheet that shows them.
    var showBookbind: Bool {
        get { screen == .bookbind }
        set { show(.bookbind, newValue) }
    }

    /// Clean Up's reading and selection. Owned here for the same reason: a
    /// second look at the shelf keeps what the first one found and ticked.
    let cleaner = CleanerModel()
    /// MediaDock 9, folded into this app. Owned here rather than by its screen so
    /// that reopening the sheet finds the same settings and the same queue.
    let mediaDock = AppModel()
    /// Bookbind, folded into this app. Owned here so its server and its page live
    /// as long as the app does rather than as long as one sheet is on screen.
    let bookbind = BookbindEngine()
    /// Whether the housekeeper sheet is open. Only the flag lives here; the
    /// conversation belongs to `Housekeeper` and is shared rather than owned by
    /// the sheet, so opening it from the menu bar the second time does not lose
    /// what was said the first.
    var showHousekeeper: Bool {
        get { screen == .housekeeper }
        set { show(.housekeeper, newValue) }
    }
    /// What the housekeeper's window should be about, when the screen opening it
    /// is not about a scanned path. A screen that wants the housekeeper sets this
    /// and flips `showHousekeeper` in the same turn; the sheet takes it as it
    /// appears and clears the slot, so a topic cannot outlive the visit that
    /// created it.
    @Published var housekeeperTopic: HousekeeperTopic?
    // MARK: - Is a newer Housekeeping out

    /// Whether the sheet that checks this copy's own age is open.
    var showSelfUpdate: Bool {
        get { screen == .selfUpdate }
        set { show(.selfUpdate, newValue) }
    }
    /// What the last check found. Starts `.idle` rather than `.checking`: nothing
    /// has been asked yet, and a screen that showed a spinner before the question
    /// was put would be animating a lie.
    @Published private(set) var selfUpdateState: SelfUpdateState = .idle
    /// The folder this copy was built from, once one has been found or chosen.
    /// `nil` is a real answer — the app may have been built on another machine —
    /// and the sheet says so rather than offering a button that would fail.
    @Published var selfUpdateSource: SelfUpdateSource?
    /// One entry per step while an update runs, so a failure can say exactly how
    /// far it got rather than only that it stopped.
    @Published private(set) var selfUpdateSteps: [SelfUpdateStep: SelfUpdateStepState] = [:]
    @Published private(set) var selfUpdateIsRunning = false
    /// Set once the new copy is built, signed, and the swap has been handed to a
    /// helper. The app still has to quit for that helper to run, which is the
    /// only thing left and belongs to the screen.
    @Published private(set) var selfUpdateIsHandedOff = false
    @Published private(set) var selfUpdateFailure: SelfUpdateFailure?

    // MARK: - Updating the applications

    /// Whether the update sheet is open.
    var showUpdateList: Bool {
        get { screen == .updateList }
        set { show(.updateList, newValue) }
    }
    /// What the last reading found. Kept as one flat list: `UpdateView` groups it
    /// by channel itself, because the grouping is a presentation choice and the
    /// list should stay usable without it.
    @Published var updateRows: [UpdateRow] = []
    /// True while the disk and the sources are being read, which is the only part
    /// of this feature that can take a while before anything is decided.
    @Published var updateIsReading = false
    /// True while updates are actually being applied.
    @Published var updateIsWorking = false
    /// How much of the run is done, and which row is being worked on. Counted in
    /// rows rather than in bytes because a Homebrew cask gives no byte total, and a
    /// bar that invents one would sit at 90% for the minute that matters.
    @Published var updateRunDone = 0
    @Published var updateRunTotal = 0
    @Published var updateRunCurrent: String?
    /// The same for the reading pass: how many applications and packages have been
    /// asked so far. The inventory is counted first, so the length is known before
    /// the slow part starts.
    @Published var updateReadDone = 0
    @Published var updateReadTotal = 0
    /// The one line above the outcomes, e.g. "3 of 5 updated".
    @Published var updateSummaryLine: String?
    /// Things the reading noticed — Homebrew missing, `mas` missing, an answer
    /// that could not be read. Shown in the sheet rather than logged.
    @Published var updateNotes: [String] = []
    @Published var updateOutcomes: [UpdateOutcome] = []
    /// The reader's "ignore from now on" list, published so the Settings screen
    /// redraws the moment it changes.
    @Published var updateExceptionEntries: [UpdateExceptions.Entry] = []
    /// Set when a list existed and could not be read. A list that came back empty
    /// for a reason is not the same as one that was empty.
    @Published var updateExceptionNote: String?

    /// These three are stored here rather than in the bridge's extension because
    /// Swift does not allow stored properties in an extension. They are internal
    /// rather than private for the same reason — the extension lives in its own
    /// file — and read as belonging to the update feature by their names.
    let updateExceptions: UpdateExceptions
    var updateTask: Task<Void, Never>?
    var updateRunner: ProcessRunner?
    /// The last reading's bundles, kept so a row's update can name the bundle it
    /// is about to replace. Keyed by the row id, which for an application is its
    /// bundle identifier.
    var updateApplications: [InstalledApplication] = []
    /// Set by a Stop press while updates are running. The loop between items reads
    /// it; the program already running is left to finish, because stopping `brew`
    /// or a bundle swap halfway is the one way this could leave a Mac worse off.
    var updateStopRequested = false

    // MARK: - Checking the setup

    /// Whether the setup sheet is open.
    var showSetupCheck: Bool {
        get { screen == .setupCheck }
        set { show(.setupCheck, newValue) }
    }
    /// What the last reading found, in the order the sheet draws it. Rebuilt
    /// whole by each reading rather than merged into, so the list can never hold
    /// a row whose subject has since been fixed by hand.
    @Published var environmentFindings: [EnvironmentFinding] = []
    /// Things the reading noticed but did not turn into a finding: where the
    /// search path was assembled from, a command that was missing, a file that
    /// could not be read.
    @Published var environmentNotes: [String] = []
    @Published var environmentIsReading = false
    @Published var environmentIsWorking = false
    /// The one line above the outcomes, e.g. "3 done, 1 not — each row says why".
    @Published var environmentSummaryLine: String?
    @Published var environmentOutcomes: [EnvironmentOutcome] = []
    /// Whether a reading has finished at least once. The sheet opens on the list
    /// from the last reading rather than reading again — see
    /// `beginSetupCheckIfNeeded` — so this is the flag that tells a list nobody
    /// has asked for yet from one that came back empty.
    @Published var environmentHasRead = false
    /// What earlier readings and repairs found, newest first.
    @Published var environmentHistoryEntries: [EnvironmentHistoryEntry] = []
    /// Whether the sheet is showing the history rather than the current list.
    @Published var environmentShowHistory = false

    /// The record on disk. Its entries are mirrored into the published list
    /// above, so views observe one array rather than a reference type. Lazy so
    /// the file is read after the one-time folder migration in `init`.
    lazy var environmentHistory = EnvironmentHistory()

    /// Stored here for the same reason the update feature's are: an extension
    /// cannot hold storage, and the bridge that uses these lives in its own file.
    var environmentTask: Task<Void, Never>?
    var environmentRunner: ProcessRunner?
    /// Held while a run is going so the sheet's Stop can reach the process in
    /// flight. Nil the rest of the time, which is also how the run knows it is
    /// the only one.
    var environmentFixer: EnvironmentFixer?

    // MARK: - The sweep

    /// True from the moment the housekeeper is set to work until the last of the
    /// three readings is back. While it is on, the window shows the working
    /// screen; afterwards, the same screen shows what came of it.
    @Published var isSweeping = false
    /// Which reading is in flight. Nil between them and when no sweep is running,
    /// which is what the working screen reads to say what the octopus is at.
    @Published var sweepStage: SweepStage?
    /// Set when a sweep finishes. Kept apart from `isSweeping` so the results
    /// stay on screen after the work has stopped, and can be dismissed by the
    /// reader rather than blinking away on their own.
    @Published var showSweepResults = false
    /// When the sweep began, so the working screen can say how long it has been
    /// going without owning a timer of its own.
    @Published var sweepStartedAt: Date?
    private var sweepTask: Task<Void, Never>?

    let protectionList: ProtectionList
    /// Rebuilt only when the list changes, and only ever read. Caching it here
    /// keeps a per-row assessment from re-deriving the whole list on every redraw.
    private var cleanupSafetyPolicy = CleanupSafetyPolicy()
    private var scanTask: Task<Void, Never>?
    private var scanWorkerTask: Task<ScanResults, Error>?
    /// The update question is asked once per launch however many views are on
    /// screen, so every surface that shows the answer shows the same one.
    private var updateCheckStarted = false

    init() {
        let storedTheme = UserDefaults.standard.string(forKey: "housekeeping.theme")
        // Default to the clean appearance. Classic 9 is still there for anyone
        // who asks for it by name, but the app should not open as a period piece
        // the first time someone runs it.
        currentTheme = Theme(rawValue: storedTheme ?? "") ?? .liquidGlass

        let storedSweep = UserDefaults.standard.object(forKey: "housekeeping.deepSweep") as? Bool
        deepSweep = storedSweep ?? true

        // The app used to be called something else, and its support folder was
        // named after it. That move has to happen before anything reads the
        // folder, so it goes first — ahead of even the left-alone list, which
        // lives inside it.
        CleanupEngine.migrateLegacySupportDirectoryIfNeeded()

        protectionList = ProtectionList()
        protectionEntries = protectionList.entries

        // The update feature's own left-alone list. Read once here so the Settings
        // section that offers things again shows the real list from the start.
        let exceptions = UpdateExceptions()
        updateExceptions = exceptions
        updateExceptionEntries = exceptions.entries
        updateExceptionNote = exceptions.loadFailureNote

        cleanupSafetyPolicy = CleanupSafetyPolicy(protectedPaths: protectionEntries.map(\.path))

        // Anything quarantined by an older build sits in a hidden folder. Move
        // it somewhere visible before anything reads the quarantine folder, so
        // the first screen the user sees already reflects the real contents.
        let engine = CleanupEngine()
        engine.adoptLegacyQuarantineIfNeeded()
        hasQuarantineItems = engine.hasQuarantineItems

        // Read once here so the history panel has something to show before this
        // launch's first check.
        environmentHistoryEntries = environmentHistory.entries
    }

    // MARK: - Leaving things alone

    /// Whether this path is one the reader has taken off the table, either itself
    /// or by protecting a folder above it. Answered by the same policy that makes
    /// the cleanup decision, so the button and the refusal cannot disagree.
    func isProtected(_ path: String) -> Bool {
        cleanupSafetyPolicy.isProtected(ProtectionList.normalize(URL(fileURLWithPath: path)))
    }

    /// Puts an item on the left-alone list and takes it out of the current
    /// selection, so a ticked row cannot be protected and cleaned in the same
    /// breath.
    func protect(_ item: FoundItem) {
        guard protectionList.protect(path: item.path.path, kind: item.findingKind.rawValue) else { return }
        applyProtectionChange()
        guard var results = scanResults,
              let index = results.foundItems.firstIndex(where: { $0.id == item.id }) else { return }
        results.foundItems[index].isSelected = false
        scanResults = results
    }

    /// Puts a path on the left-alone list without a `FoundItem` to hand — the
    /// Clean Up screen knows a path and a shelf name, not a sweep result.
    @discardableResult
    func protect(path: String, kind: String) -> Bool {
        guard protectionList.protect(path: path, kind: kind) else { return false }
        applyProtectionChange()
        return true
    }

    /// Takes one entry off the list. Keyed on the entry's own stored path rather
    /// than a live scan result, so a path that nothing was found at this time can
    /// still be released.
    func releaseProtection(path: String) {
        guard protectionList.release(path: path) else { return }
        applyProtectionChange()
    }

    func releaseAllProtection() {
        guard !protectionList.isEmpty else { return }
        protectionList.releaseAll()
        applyProtectionChange()
    }

    /// The one place the list and the policy are brought back into step. Every
    /// mutation goes through here, so there is no path that changes one and
    /// leaves the other describing the previous answer.
    private func applyProtectionChange() {
        protectionEntries = protectionList.entries
        cleanupSafetyPolicy = CleanupSafetyPolicy(protectedPaths: protectionEntries.map(\.path))
    }

    func setTheme(_ theme: Theme) {
        guard currentTheme != theme else { return }
        currentTheme = theme
        bookbind.applyTheme(theme)
        UserDefaults.standard.set(theme.rawValue, forKey: "housekeeping.theme")
    }

    func setDeepSweep(_ enabled: Bool) {
        guard deepSweep != enabled else { return }
        deepSweep = enabled
        UserDefaults.standard.set(enabled, forKey: "housekeeping.deepSweep")
    }

    // MARK: - Is a newer Housekeeping out?

    /// Where a reader of a copy that cannot update itself is sent: the repository
    /// itself. Not the release page, which is the address this used to hand out
    /// and which lags far enough behind `main` to be misleading.
    static let repositoryURL = SelfUpdateChecker.repositoryURL

    /// The version this copy was built from. Read from the bundle rather than
    /// written here, because this number, the one in Settings, and Info.plist all
    /// used to carry their own copy and a release could ship naming the wrong one.
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Which commit this copy was built from, read once at launch. Absent on a
    /// copy built by Xcode rather than by the release script, and the sheet says
    /// so instead of guessing a version-to-commit mapping that does not exist.
    let selfUpdateProvenance = BuildProvenance.current()

    /// Asks GitHub once, in the background, after the window is already drawn.
    /// Nothing is downloaded and nothing is installed here — the answer only
    /// decides whether the footer mentions that a newer commit exists. Safe to
    /// call from more than one place; only the first call reaches the network.
    func startSelfUpdateCheck() async {
        guard !updateCheckStarted else { return }
        updateCheckStarted = true
        await refreshSelfUpdate()
    }

    /// Asks again on purpose, which is what the sheet's own Check button does.
    /// Unlike the launch check this one always reaches the network, because a
    /// person who pressed a button is asking a question and deserves a live
    /// answer rather than the one from this morning.
    func refreshSelfUpdate() async {
        if selfUpdateSource == nil {
            selfUpdateSource = SourceTreeLocator.locate()
        }
        selfUpdateFailure = nil
        selfUpdateState = .checking
        selfUpdateState = await SelfUpdateChecker().check(provenance: selfUpdateProvenance)
    }

    /// Records a folder the reader chose by hand, so the next launch does not
    /// have to ask and the next check does not have to guess.
    func adoptSelfUpdateSource(_ tree: URL) {
        SourceTreeLocator.remember(tree)
        selfUpdateSource = SelfUpdateSource(
            tree: tree,
            remoteMatches: SourceTreeLocator.remoteMatches(tree),
            destination: Bundle.main.bundleURL
        )
        Task { await refreshSelfUpdate() }
    }

    /// Runs the update the sheet has just described, step by step.
    ///
    /// The plan shown to the reader and the plan executed here are the same
    /// values, deliberately: a screen that described one thing and ran another
    /// would be worse than no screen at all on the one action that replaces the
    /// app you are looking at.
    func runSelfUpdate() async {
        guard !selfUpdateIsRunning,
              let source = selfUpdateSource,
              case .available(let report) = selfUpdateState else { return }

        let plan = SelfUpdateEngine.Plan(
            source: source,
            behindBy: report.behindBy,
            remoteCommit: report.remoteCommit,
            version: selfUpdateProvenance.version
        )

        selfUpdateIsRunning = true
        selfUpdateIsHandedOff = false
        selfUpdateFailure = nil
        selfUpdateSteps = Dictionary(uniqueKeysWithValues: SelfUpdateStep.allCases.map { ($0, .pending) })

        do {
            _ = try await SelfUpdateEngine().perform(plan: plan) { [weak self] step, state in
                self?.selfUpdateSteps[step] = state
            }
            // The swap is written and the helper is running. All that is left is
            // for this process to end, which the screen does after saying so.
            selfUpdateIsHandedOff = true
        } catch let failure as SelfUpdateFailure {
            selfUpdateFailure = failure
            selfUpdateIsRunning = false
        } catch {
            selfUpdateFailure = .cancelled
            selfUpdateIsRunning = false
        }
    }

    /// "v1.2.10" -> "1.2.10". A tag may carry the v; the version does not.
    /// `nonisolated` because the update engine compares versions on its own
    /// threads, and none of these three touch any state that belongs to the main
    /// actor — they are pure functions on strings that happen to live here.
    nonisolated static func normalize(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("v") || trimmed.hasPrefix("V") else { return trimmed }
        return String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    /// "1.2.10" -> [1, 2, 10]. Anything unparseable counts as zero, so a tag that
    /// is not a version number reads as older than every real one instead of
    /// derailing the comparison.
    nonisolated static func versionParts(_ version: String) -> [Int] {
        version.split(separator: ".", omittingEmptySubsequences: false).map { piece in
            let digits = piece.filter(\.isNumber)
            return digits.isEmpty ? 0 : (Int(digits) ?? 0)
        }
    }

    /// Numeric, part by part, missing parts counting as zero — so 1.2 equals
    /// 1.2.0, and 1.10 is newer than 1.9 rather than older the way strings say.
    nonisolated static func isNewer(_ candidate: String, than mine: String) -> Bool {
        let theirs = versionParts(candidate)
        let ours = versionParts(mine)
        for index in 0..<max(theirs.count, ours.count) {
            let x = index < theirs.count ? theirs[index] : 0
            let y = index < ours.count ? ours[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    enum ScanState: String, Codable {
        case idle, scanning, complete, error
    }

    /// Where the reader is in the three-question pass that follows a scan. The
    /// scan state says whether there is anything to look at; this says which of
    /// the three questions is on screen, so that every screen can end in exactly
    /// one answer instead of a wall of buttons.
    enum FlowStep {
        case summary, review, confirm
    }

    var activeCleanupItems: [FoundItem] {
        scanResults?.foundItems.filter { $0.isSelected } ?? []
    }

    var totalReclaimable: Int64 {
        activeCleanupItems.reduce(0) { $0 + $1.size }
    }

    var recommendedCleanupItems: [FoundItem] {
        (scanResults?.foundItems ?? [])
            .filter { cleanupSafetyPolicy.isRecommendedForGuidedCleanup($0) }
            .sorted { $0.size > $1.size }
    }

    var inspectedItem: FoundItem? {
        guard let inspectedItemID else { return nil }
        return scanResults?.foundItems.first { $0.id == inspectedItemID }
    }

    func updateScanState(_ state: ScanState) { scanState = state }
    func updateScanProgress(_ progress: ScanProgress) { scanProgress = progress }
    func saveCleanupHistory(_ record: CleanupRecord) { cleanupHistory.insert(record, at: 0) }

    func recordCleanupResult(_ result: CleanupResult) {
        guard result.successCount > 0 else { return }
        let record = CleanupRecord(
            id: UUID(),
            date: result.date,
            itemCount: result.successCount,
            totalSize: result.totalSize,
            items: result.movedItems.map { MovedItemRecord(item: $0) },
            usedTrash: result.usedTrash
        )
        saveCleanupHistory(record)
        removeSuccessfullyMovedItems(result.movedItems)
    }

    /// Starts a scan and hands back the task doing it, so the one caller that has
    /// to wait for it — the sweep — can, without the others having to care.
    @discardableResult
    func startScan() -> Task<Void, Never>? {
        showOverview = false
        workspace = nil
        presentedScreen = nil
        scanTask?.cancel()
        lastErrorMessage = nil
        // A scan is the moment the disk is read again, so anything the policy
        // worked out about what lives where has to be worked out again too.
        cleanupSafetyPolicy.invalidateWorkingCopyMemo()
        scanResults = nil
        scanProgress = .phase("Preparing scan...")
        scanState = .scanning

        if RuleEngine.shared.applications.isEmpty {
            RuleEngine.shared.loadRules()
        }
        let applications = RuleEngine.shared.applications
        let sweep = deepSweep

        let worker = Task.detached(priority: .userInitiated) { [weak self] in
            let scanner = Scanner(applications: applications, deepSweep: sweep)
            return try await scanner.scan { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard self?.scanState == .scanning else { return }
                    self?.scanProgress = progress
                }
            }
        }
        scanWorkerTask = worker

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let results = try await worker.value

                try Task.checkCancellation()
                let classifier = Classifier()
                var classifiedResults = results
                classifiedResults.foundItems = classifier.classify(items: results.foundItems)
                self.scanResults = classifiedResults
                self.inspectedItemID = classifiedResults.foundItems.first?.id
                self.scanProgress = .complete(classifiedResults)
                self.flowStep = .summary
                self.scanState = .complete
            } catch is CancellationError {
                self.scanProgress = .idle
                self.scanState = .idle
            } catch {
                self.lastErrorMessage = error.localizedDescription
                self.scanState = .error
            }
            self.scanTask = nil
            self.scanWorkerTask = nil
        }
        return scanTask
    }

    func cancelScan() {
        scanWorkerTask?.cancel()
        scanWorkerTask = nil
        scanTask?.cancel()
        scanTask = nil
        scanProgress = .idle
        scanState = .idle
    }

    // MARK: - The sweep

    /// Every reading the app has, run in one go, and then one screen saying what
    /// came of it.
    ///
    /// This is the app's automated version, and it is automated exactly as far as
    /// reading. It measures the disk, checks the setup, and asks about updates,
    /// then hands back a single account of all three. It ticks nothing, moves
    /// nothing, installs nothing, and fixes nothing. That is not caution bolted
    /// on afterwards — a sweep that also acted would be the cleaner this app
    /// exists not to be, and each of the three readings already ends at a screen
    /// that asks per item before it changes anything.
    ///
    /// The three run in sequence rather than at once. Two of them drive Homebrew,
    /// which takes a lock, and the disk reading is the one whose screen the other
    /// two are reached from, so it goes first and the reader has a result to look
    /// at while the rest is still being read.
    func startSweep() {
        showOverview = false
        workspace = nil
        presentedScreen = nil
        sweepTask?.cancel()
        lastErrorMessage = nil
        showSweepResults = false
        sweepStartedAt = Date()
        sweepStage = .disk
        isSweeping = true

        sweepTask = Task { [weak self] in
            guard let self else { return }

            await self.startScan()?.value
            guard !Task.isCancelled else { return }

            self.sweepStage = .setup
            await self.beginSetupReading()?.value
            guard !Task.isCancelled else { return }

            self.sweepStage = .updates
            await self.beginUpdateReading()?.value
            guard !Task.isCancelled else { return }

            self.sweepStage = nil
            self.sweepStartedAt = nil
            self.isSweeping = false
            self.sweepTask = nil
            self.showSweepResults = true
        }
    }

    /// Stops the sweep where it stands, and the reading in flight with it.
    ///
    /// Nothing survives the stop. The scan is cancelled like any other — which
    /// takes the window back to the opening screen rather than leaving a partial
    /// list behind — and the setup and update readings are dropped the same way.
    /// That is safe because nothing was ever changed: a sweep only reads, so a
    /// stopped sweep has nothing to undo, and the reader can simply start it
    /// again. The Stop button's wording says exactly this.
    func cancelSweep() {
        sweepTask?.cancel()
        sweepTask = nil
        cancelScan()
        cancelEnvironmentWork()
        if updateIsReading {
            updateTask?.cancel()
            updateRunner?.cancel()
            updateRunner = nil
            updateIsReading = false
        }
        sweepStage = nil
        sweepStartedAt = nil
        isSweeping = false
    }

    /// Leaves the sweep's results screen without running anything, which is the
    /// only way off it that is not one of the three job buttons. The scan is
    /// still complete underneath, so the window falls back to the summary the
    /// disk reading produced.
    func dismissSweepResults() {
        showSweepResults = false
        sweepStage = nil
        sweepStartedAt = nil
    }

    func inspectItem(_ id: UUID) {
        inspectedItemID = id
    }

    func beginGuidedCleanup() {
        guidedCleanupItems = recommendedCleanupItems
        showGuidedCleanup = !guidedCleanupItems.isEmpty
    }

    func advanceFlow(_ step: FlowStep) {
        flowStep = step
    }

    /// The confirm step is the reader agreeing to these particular items, so the
    /// agreement is recorded as a selection before the review sheet opens. That
    /// way the sheet shows exactly what was agreed to, and nothing else.
    ///
    /// Ticks the reader made themselves always win: this only fills in the
    /// recommended items when they have ticked nothing, which is the path that
    /// took them here through "Yes, tidy up" rather than through the list.
    func confirmRecommendedCleanup() {
        if activeCleanupItems.isEmpty,
           var results = scanResults {
            let recommendedIDs = Set(recommendedCleanupItems.map(\.id))
            for index in results.foundItems.indices
            where recommendedIDs.contains(results.foundItems[index].id) {
                results.foundItems[index].isSelected = true
            }
            scanResults = results
        }
        guard !activeCleanupItems.isEmpty else { return }
        showCleanupConfirmation = true
    }

    func cleanupAssessment(for item: FoundItem) -> CleanupSafetyPolicy.Assessment {
        cleanupSafetyPolicy.assess(item)
    }

    func toggleSelection(for id: UUID) {
        guard var results = scanResults,
              let index = results.foundItems.firstIndex(where: { $0.id == id }) else { return }

        if results.foundItems[index].isSelected {
            results.foundItems[index].isSelected = false
        } else if cleanupAssessment(for: results.foundItems[index]).canBeSelected {
            results.foundItems[index].isSelected = true
        }
        scanResults = results
    }

    func removeSuccessfullyMovedItems(_ movedItems: [MovedItem]) {
        let movedIDs = Set(movedItems.filter(\.success).map { $0.item.id })
        guard !movedIDs.isEmpty, var results = scanResults else { return }
        results.foundItems.removeAll { movedIDs.contains($0.id) }
        scanResults = results
        if let inspectedItemID, movedIDs.contains(inspectedItemID) {
            self.inspectedItemID = results.foundItems.first?.id
        }
        refreshQuarantineAvailability()
    }

    func refreshQuarantineAvailability() {
        hasQuarantineItems = CleanupEngine().hasQuarantineItems
    }

    func quarantineEntries() -> [QuarantineEntry] {
        CleanupEngine().quarantineEntries()
    }

    func transactionHistory() -> [CleanupTransaction] {
        CleanupEngine().transactionHistory()
    }

    /// Puts back one recorded batch. It deliberately does not start a scan: the
    /// history screen sits over the main window, and a scan firing behind it
    /// would be more disruptive than the staleness it fixes. The items that come
    /// back simply reappear on the next scan.
    func restoreTransaction(_ transaction: CleanupTransaction) async {
        do {
            lastErrorMessage = nil
            _ = try await CleanupEngine().restoreTransaction(transaction)
            refreshQuarantineAvailability()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func restoreQuarantineEntry(_ entry: QuarantineEntry) {
        do {
            try CleanupEngine().restore(entry)
            lastErrorMessage = nil
            refreshQuarantineAvailability()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func permanentlyDeleteQuarantineEntries(_ entries: [QuarantineEntry]) {
        do {
            let result = try CleanupEngine().permanentlyDelete(entries)
            lastErrorMessage = result.failed.isEmpty
                ? nil
                : result.failed.map { "\($0.0.originalPath): \($0.1)" }.joined(separator: "\n")
            refreshQuarantineAvailability()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func undoLastQuarantine() async {
        do {
            lastErrorMessage = nil
            _ = try await CleanupEngine().undoLastCleanup()
            refreshQuarantineAvailability()
            startScan()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}

extension AppState {
    enum Theme: String, CaseIterable, Identifiable {
        case classic9 = "Mac OS 9"
        case liquidGlass = "Liquid Glass"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .classic9: return "Mac OS 9 / Platinum"
            case .liquidGlass: return "Modern"
            }
        }

        var shortName: String {
            switch self {
            case .classic9: return "Classic 9"
            case .liquidGlass: return "Modern"
            }
        }
    }
}
