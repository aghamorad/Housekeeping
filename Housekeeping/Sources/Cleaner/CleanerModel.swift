// Housekeeping — Clean Up: the screen's state

import Foundation
import SwiftUI

/// Holds one reading of the disk, one selection, and one action at a time. The
/// moving itself is not done here: every action is handed to
/// `quarantineRepairs`, which writes a manifest first and puts everything in
/// Quarantine, so this model never deletes anything except the Trash.
@MainActor
final class CleanerModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case scanning
        case ready
        case working
    }

    /// The one action waiting on a typed confirmation.
    enum PendingAction: Equatable {
        case clean
        case uninstall
        case emptyTrash

        var word: String {
            switch self {
            case .clean: return "clean"
            case .uninstall: return "uninstall"
            case .emptyTrash: return "delete"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var candidates: [CleanCandidate] = []
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var trash = TrashSummary()
    @Published private(set) var notes: [String] = []
    @Published private(set) var progressLine = ""
    @Published private(set) var lastScan: Date?
    @Published private(set) var outcome: String?
    @Published private(set) var failures: [String] = []
    @Published private(set) var uninstallSession: UninstallSession?

    @Published var query = ""
    @Published var order: FileOrder = .largest
    @Published private(set) var completedCategories: Set<CleanCategory> = []
    @Published private(set) var wasStopped = false
    @Published private(set) var scanStartedAt: Date?
    @Published private(set) var includedRelatedPaths: Set<String> = []
    private var scanWorker: Task<CleanerSnapshot, Never>?
    private var scanID = UUID()

    @Published var category: CleanCategory = .everydayJunk

    @Published private(set) var pendingAction: PendingAction?
    @Published var confirmationText = ""
    @Published private(set) var pendingTitle = ""
    @Published private(set) var pendingDetail = ""
    @Published private(set) var pendingPaths: [String] = []
    @Published private(set) var pendingSize: Int64 = 0
    @Published private(set) var pendingAppName: String?
    @Published private(set) var confirmationHint: String?

    init(snapshot: CleanerSnapshot? = nil) {
        if let snapshot { apply(snapshot) }
    }

    // MARK: - Reading

    func scanIfNeeded() {
        guard phase == .idle else { return }
        scan()
    }

    func scan() {
        guard phase != .scanning, phase != .working else { return }
        phase = .scanning
        wasStopped = false
        completedCategories = []
        candidates = []
        apps = []
        trash = TrashSummary()
        notes = []
        includedRelatedPaths = []
        outcome = nil
        failures = []
        progressLine = "Getting ready…"
        scanStartedAt = Date()
        scanID = UUID()
        let id = scanID

        let progress: @Sendable (String) -> Void = { [weak self] line in
            Task { @MainActor in
                guard self?.scanID == id, self?.phase == .scanning else { return }
                self?.progressLine = line
            }
        }

        let partial: @Sendable (CleanerSnapshot, Set<CleanCategory>) -> Void = { [weak self] snapshot, completed in
            Task { @MainActor in
                guard let self, self.scanID == id, self.phase == .scanning else { return }
                self.candidates = snapshot.candidates
                self.apps = snapshot.apps
                self.includedRelatedPaths = self.defaultRelatedPaths(snapshot.apps)
                self.completedCategories = completed
            }
        }
        let worker = Task.detached(priority: .userInitiated) {
            CleanerScanner.scanAll(progress: progress, partial: partial)
        }
        scanWorker = worker
        Task { @MainActor [weak self] in
            let snapshot = await worker.value
            guard !worker.isCancelled, self?.scanID == id else { return }
            self?.scanWorker = nil
            self?.apply(snapshot)
        }
    }

    func stopScan() {
        guard phase == .scanning else { return }
        scanWorker?.cancel()
        scanWorker = nil
        scanID = UUID()
        progressLine = ""
        phase = .ready
        wasStopped = true
        outcome = "Scan stopped. Showing completed categories only; unvisited categories have not been checked."
    }

    private func defaultRelatedPaths(_ apps: [InstalledApp]) -> Set<String> {
        let protection = ProtectionList()
        return Set(apps.flatMap(\.leftovers).filter { !protection.isProtected($0.url) }.map(\.id))
    }

    private func apply(_ snapshot: CleanerSnapshot) {
        candidates = snapshot.candidates
        apps = snapshot.apps
        includedRelatedPaths = defaultRelatedPaths(snapshot.apps)
        trash = snapshot.trash
        notes = snapshot.notes
        lastScan = Date()
        completedCategories = Set(CleanCategory.allCases)
        wasStopped = false
        progressLine = ""
        phase = .ready
    }

    // MARK: - Looking at what was found

    func candidates(in category: CleanCategory) -> [CleanCandidate] {
        candidates.filter { $0.category == category }
    }

    func matches(_ name: String, path: String, detail: String = "") -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty || [name, path, detail].contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    func visibleCandidates(in category: CleanCategory) -> [CleanCandidate] {
        candidates(in: category).filter { matches($0.name, path: $0.url.path, detail: $0.detail) }.sorted {
            order.precedes(name: $0.name, size: $0.size, modified: $0.modified, path: $0.id,
                           name: $1.name, size: $1.size, modified: $1.modified, path: $1.id)
        }
    }

    var visibleApps: [InstalledApp] {
        apps.filter { matches($0.name, path: $0.url.path, detail: $0.bundleIdentifier ?? "") }.sorted {
            order.precedes(name: $0.name, size: $0.totalSize, modified: $0.modifiedDate, path: $0.id,
                           name: $1.name, size: $1.totalSize, modified: $1.modifiedDate, path: $1.id)
        }
    }

    /// Bulk selections apply strictly to the CURRENT CATEGORY AND FILTER.
    /// A row hidden by search or placed on another shelf is never changed.
    func setVisible(selected: Bool) {
        guard phase == .ready else { return }
        let ids = Set(visibleCandidates(in: category).map(\.id))
        for index in candidates.indices where ids.contains(candidates[index].id) {
            candidates[index].isSelected = selected
        }
    }

    var selectedOutsideVisibleCount: Int {
        let visible = Set(visibleCandidates(in: category).map(\.id))
        return selectedCandidates.filter { !visible.contains($0.id) }.count
    }

    func clearVisibleSelection() {
        setVisible(selected: false)
    }

    func toggleRelated(_ candidate: CleanCandidate) {
        guard phase != .working, !ProtectionList().isProtected(candidate.url) else { return }
        if !includedRelatedPaths.insert(candidate.id).inserted { includedRelatedPaths.remove(candidate.id) }
    }

    func clearSelection() {
        guard phase == .ready else { return }
        for index in candidates.indices { candidates[index].isSelected = false }
    }

    func total(in category: CleanCategory) -> Int64 {
        candidates.reduce(0) { $0 + ($1.category == category ? $1.size : 0) }
    }

    func count(in category: CleanCategory) -> Int {
        candidates.reduce(0) { $0 + ($1.category == category ? 1 : 0) }
    }

    func selected(in category: CleanCategory) -> [CleanCandidate] {
        candidates.filter { $0.category == category && $0.isSelected }
    }

    /// The part of the current selection that would have to come back over the
    /// network. Kept separate so the confirmation sheet can say so before
    /// anything moves, which is the only moment the warning is any use.
    var selectedDownloadItems: [CleanCandidate] { selectedCandidates.filter { $0.rebuild.isDownload } }

    /// The same, for the exact paths on the confirmation sheet.
    var pendingDownloadItems: [CleanCandidate] {
        let moved = Set(pendingPaths)
        return candidates.filter { moved.contains($0.id) && $0.rebuild.isDownload }
    }

    var selectedCandidates: [CleanCandidate] { candidates.filter(\.isSelected) }
    var selectedApps: [InstalledApp] { apps.filter(\.isSelected) }
    var selectedSize: Int64 { selectedCandidates.reduce(0) { $0 + $1.size } }

    var cleanerTotal: Int64 {
        candidates.reduce(0) { $0 + $1.size }
    }

    // MARK: - Ticking

    func toggle(_ candidate: CleanCandidate) {
        guard phase != .working, phase != .scanning else { return }
        guard let index = candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
        candidates[index].isSelected.toggle()
    }

    func setAll(in category: CleanCategory, selected: Bool) {
        guard phase == .ready else { return }
        for index in candidates.indices where candidates[index].category == category {
            candidates[index].isSelected = selected
        }
    }

    /// Removes a row that has just been put on the left-alone list. It is not
    /// gone from the disk — only from this screen, because it is no longer
    /// something the cleaner is offering.
    func forget(path: String) {
        includedRelatedPaths.remove(path)
        candidates.removeAll { $0.url.path == path }
        apps = apps.map { app in
            var copy = app
            copy.leftovers.removeAll { $0.url.path == path }
            return copy
        }
    }

    func toggleApp(_ app: InstalledApp) {
        guard let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        apps[index].isSelected.toggle()
    }

    /// Tick or untick every app the current search shows, so a list of forty is
    /// one decision rather than forty. Nothing moves until the button at the
    /// bottom is pressed and the exact paths are confirmed.
    func setAllApps(selected: Bool) {
        guard phase != .working, phase != .scanning else { return }
        let ids = Set(visibleApps.map(\.id))
        for index in apps.indices where ids.contains(apps[index].id) {
            apps[index].isSelected = selected
        }
    }

    var allAppsSelected: Bool {
        let rows = visibleApps
        return !rows.isEmpty && rows.allSatisfy(\.isSelected)
    }

    var anyAppsSelected: Bool {
        let rows = visibleApps
        return rows.contains { $0.isSelected }
    }

    /// Uninstalls everything ticked in one transaction. Open applications are
    /// left out rather than refused, because one open app should not stop the
    /// other thirty-nine from going. Matched related files are included by
    /// default; the reader can uncheck anything they want to keep.
    func requestUninstallSelected() {
        guard phase == .ready else { return }
        let protection = ProtectionList()
        let chosen = selectedApps.filter { !protection.isProtected($0.url) }
        guard !chosen.isEmpty else { return }

        let running = chosen.filter(\.isRunning)
        let ready = chosen.filter { !$0.isRunning }
        guard !ready.isEmpty else {
            failures = ["Every application you ticked is open. Quit them first — macOS will not let an application be moved while it is running."]
            return
        }

        var paths: [String] = []
        for app in ready {
            paths.append(app.url.path)
            paths += app.leftovers
                .filter { includedRelatedPaths.contains($0.id) && !protection.isProtected($0.url) }
                .map(\.url.path)
        }

        pendingAction = .uninstall
        pendingTitle = "Move \(ready.count) application\(ready.count == 1 ? "" : "s") to Quarantine?"
        let related = CleanCandidate.nonOverlapping(ready.flatMap(\.leftovers).filter { includedRelatedPaths.contains($0.id) && !protection.isProtected($0.url) })
        pendingDetail = "The applications and \(related.count) included related items move together. Related files may contain settings and personal app data. Uncheck anything you want to keep before continuing. Everything moved can be put back from Quarantine. macOS may ask for an administrator password."
        pendingPaths = paths
        pendingSize = ready.reduce(Int64(0)) { $0 + $1.size } + related.reduce(0) { $0 + $1.size }
        pendingAppName = ready.count == 1 ? ready[0].name : nil
        confirmationText = ""
        confirmationHint = running.isEmpty
            ? nil
            : "\(running.count) open application\(running.count == 1 ? " is" : "s are") left out: \(running.map(\.name).joined(separator: ", "))."
        failures = []
    }

    var allInCategorySelected: Bool {
        let rows = candidates(in: category)
        return !rows.isEmpty && rows.allSatisfy(\.isSelected)
    }

    // MARK: - Asking

    func requestClean() {
        guard phase == .ready else { return }
        let protection = ProtectionList()
        let chosen = CleanCandidate.nonOverlapping(selectedCandidates.filter { !protection.isProtected($0.url) })
        guard !chosen.isEmpty else { return }
        let size = chosen.reduce(0) { $0 + $1.size }
        let categories = Set(chosen.map(\.category.title)).sorted()

        pendingAction = .clean
        pendingTitle = "Move \(chosen.count) item\(chosen.count == 1 ? "" : "s") to Quarantine?"
        pendingDetail = "\(size.sizeDescription) from \(categories.joined(separator: ", ")). These items are MOVED, not deleted. No disk space is recovered while they remain in Quarantine; you can restore them there or review permanent deletion separately."
        pendingPaths = chosen.map(\.url.path)
        pendingSize = size
        pendingAppName = nil
        confirmationText = ""
        confirmationHint = nil
    }

    func requestUninstall(_ app: InstalledApp) {
        guard phase == .ready else { return }
        guard !ProtectionList().isProtected(app.url) else {
            failures = ["This application is on the Leave Alone list."]
            return
        }
        if app.isRunning {
            outcome = nil
            failures = ["\(app.name) is open. Quit it first — macOS will not let an application be moved while it is running."]
            return
        }
        let related = app.leftovers.filter { includedRelatedPaths.contains($0.id) && !ProtectionList().isProtected($0.url) }
        let paths = [app.url.path] + related.map(\.url.path)
        let size = app.size + related.reduce(0) { $0 + $1.size }

        pendingAction = .uninstall
        pendingTitle = "Move \(app.name) to Quarantine?"
        var detail = "The application and \(related.count) included related items, \(size.sizeDescription) together. Related files may contain settings and personal app data. Everything moved can be put back from Quarantine. macOS may ask for an administrator password."
        if let version = app.version {
            detail += " Version \(version)."
        }
        pendingDetail = detail
        pendingPaths = paths
        pendingSize = size
        pendingAppName = app.name
        confirmationText = ""
        confirmationHint = nil
    }

    func requestEmptyTrash() {
        guard !trash.isEmpty else { return }
        pendingAction = .emptyTrash
        pendingTitle = "Permanently delete everything in the Trash?"
        pendingDetail = "\(trash.count) item\(trash.count == 1 ? "" : "s"), \(trash.size.sizeDescription). This is the one action in Housekeeping that cannot be undone — there is no Quarantine copy afterwards."
        pendingPaths = []
        pendingSize = trash.size
        pendingAppName = nil
        confirmationText = ""
        confirmationHint = nil
    }

    func cancelPending() {
        pendingAction = nil
        confirmationText = ""
        confirmationHint = nil
        pendingPaths = []
        pendingAppName = nil
    }

    func confirmPending() {
        guard let action = pendingAction else { return }
        let typed = confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard typed == action.word else {
            confirmationHint = "Type \(action.word) to continue."
            return
        }
        pendingAction = nil
        confirmationText = ""
        confirmationHint = nil
        phase = .working

        switch action {
        case .clean:
            perform(paths: pendingPaths, title: "Cleaned up", noun: "item", intent: .sweep)
        case .uninstall:
            // Uninstalling names an application, so its containers are fair
            // game — that is the one path where they are.
            perform(paths: pendingPaths, title: pendingAppName.map { "Uninstalled \($0)" } ?? "Uninstalled", noun: "item", intent: .explicitRemoval)
        case .emptyTrash:
            emptyTrash()
        }
    }

    // MARK: - Doing

    private func perform(paths: [String], title: String, noun: String, intent: CleanupIntent) {
        let engine = CleanupEngine()
        // The shelf each item came from, so the Quarantine record says "Cache"
        // or "Orphaned Leftovers" rather than calling every move a "Clean Up".
        let moved = Set(paths)
        var categories: [String: String] = [:]
        for candidate in candidates where moved.contains(candidate.id) {
            categories[candidate.id] = candidate.category.title
        }
        Task { @MainActor [weak self] in
            do {
                let result: RepairMoveResult
                if intent == .explicitRemoval {
                    let targets: [InstalledApp] = self?.apps.filter { moved.contains($0.id) }.map { app in
                        var copy = app
                        copy.leftovers = app.leftovers.filter { moved.contains($0.id) }
                        return copy
                    } ?? []
                    self?.uninstallSession = UninstallSession(apps: targets)
                    result = try await engine.uninstall(targets) { [weak self] event in
                        await self?.receiveUninstallProgress(event)
                    }
                    self?.uninstallSession?.finish(result: result)
                } else {
                    result = try await engine.quarantineRepairs(paths: paths, category: "Clean Up",
                        reason: title, categories: categories, intent: intent)
                }
                self?.absorb(result, title: title, noun: noun)
            } catch {
                self?.uninstallSession?.finish(error: error.localizedDescription)
                self?.finishWith(error: error)
            }
        }
    }

    private func receiveUninstallProgress(_ event: UninstallProgress) {
        uninstallSession?.receive(event)
    }

    func dismissUninstallSession() {
        guard phase != .working else { return }
        uninstallSession = nil
    }

    private func absorb(_ result: RepairMoveResult, title: String, noun: String) {
        let moved = Set(result.movedPaths)
        var sizes: [String: Int64] = [:]
        for candidate in candidates { sizes[candidate.id] = candidate.size }
        for app in apps {
            sizes[app.id] = app.size
            for item in app.leftovers { sizes[item.id] = item.size }
        }
        let movedBytes = moved.reduce(Int64(0)) { $0 + (sizes[$1] ?? 0) }
        includedRelatedPaths.subtract(moved)
        candidates.removeAll { moved.contains($0.url.path) }
        apps = apps.compactMap { app in
            if moved.contains(app.url.path) { return nil }
            var copy = app
            copy.leftovers.removeAll { moved.contains($0.url.path) }
            copy.isSelected = false
            return copy
        }

        let failed = result.moves.filter { !$0.succeeded }
        failures = failed.map { "\($0.path) — \($0.message ?? "could not be moved")" }

        var sentence = "\(title): \(result.succeededCount) \(noun)\(result.succeededCount == 1 ? "" : "s"), \(movedBytes.sizeDescription), moved to Quarantine."
        if !failed.isEmpty {
            sentence += " \(failed.count) could not be moved and are still where they were."
        } else {
            sentence += " They can be put back from Quarantine."
        }
        outcome = sentence
        phase = .ready
    }

    private func emptyTrash() {
        let service = TrashService()
        Task { @MainActor [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                service.empty()
            }.value
            self?.trash = TrashService().read()
            self?.failures = result.failures
            if result.failures.isEmpty {
                self?.outcome = "Trash emptied: \(result.removedCount) item\(result.removedCount == 1 ? "" : "s"), \(result.removedBytes.sizeDescription) freed. That cannot be undone."
            } else {
                self?.outcome = "Emptied what it could: \(result.removedCount) item\(result.removedCount == 1 ? "" : "s"), \(result.removedBytes.sizeDescription) freed. \(result.failures.count) could not be removed."
            }
            self?.phase = .ready
        }
    }

    private func finishWith(error: Error) {
        failures = [error.localizedDescription]
        outcome = "Removal stopped. Review Quarantine for any items already moved before trying again."
        phase = .ready
    }
}
