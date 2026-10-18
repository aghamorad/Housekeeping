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

    private func apply(_ snapshot: CleanerSnapshot) {
        candidates = snapshot.candidates
        apps = snapshot.apps
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
            order.precedes(name: $0.name, size: $0.totalSize, modified: nil, path: $0.id,
                           name: $1.name, size: $1.totalSize, modified: nil, path: $1.id)
        }
    }

    func setVisible(selected: Bool) {
        guard phase != .working, phase != .scanning else { return }
        let ids = Set(visibleCandidates(in: category).map(\.id))
        for index in candidates.indices where ids.contains(candidates[index].id) {
            candidates[index].isSelected = selected
        }
    }

    func toggleRelated(_ candidate: CleanCandidate) {
        guard phase != .working, !ProtectionList().isProtected(candidate.url) else { return }
        if !includedRelatedPaths.insert(candidate.id).inserted { includedRelatedPaths.remove(candidate.id) }
    }

    func clearSelection() {
        guard phase != .working else { return }
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
        pendingDetail = "\(size.sizeDescription) from \(categories.joined(separator: ", ")). Everything moved can be put back from Quarantine."
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
        var detail = "The application and \(related.count) explicitly chosen related items, \(size.sizeDescription) together. Unchosen support files stay in place."
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
            perform(paths: pendingPaths, title: "Cleaned up", noun: "item")
        case .uninstall:
            perform(paths: pendingPaths, title: pendingAppName.map { "Uninstalled \($0)" } ?? "Uninstalled", noun: "item")
        case .emptyTrash:
            emptyTrash()
        }
    }

    // MARK: - Doing

    private func perform(paths: [String], title: String, noun: String) {
        let engine = CleanupEngine()
        Task { @MainActor [weak self] in
            do {
                let result = try await engine.quarantineRepairs(
                    paths: paths,
                    category: "Clean Up",
                    reason: title
                )
                self?.absorb(result, title: title, noun: noun)
            } catch {
                self?.finishWith(error: error)
            }
        }
    }

    private func absorb(_ result: RepairMoveResult, title: String, noun: String) {
        let moved = Set(result.movedPaths)
        let movedBytes = candidates.filter { moved.contains($0.id) }.reduce(0) { $0 + $1.size }
            + apps.reduce(Int64(0)) { total, app in
                total + (moved.contains(app.id) ? app.size : 0)
                    + app.leftovers.filter { moved.contains($0.id) }.reduce(0) { $0 + $1.size }
            }
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
        outcome = "Nothing was moved."
        phase = .ready
    }
}
