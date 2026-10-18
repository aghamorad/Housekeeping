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

    @Published var category: CleanCategory = .everydayJunk

    @Published private(set) var pendingAction: PendingAction?
    @Published var confirmationText = ""
    @Published private(set) var pendingTitle = ""
    @Published private(set) var pendingDetail = ""
    @Published private(set) var pendingPaths: [String] = []
    @Published private(set) var pendingSize: Int64 = 0
    @Published private(set) var pendingAppName: String?
    @Published private(set) var confirmationHint: String?

    // MARK: - Reading

    func scanIfNeeded() {
        guard phase == .idle else { return }
        scan()
    }

    func scan() {
        guard phase != .scanning, phase != .working else { return }
        phase = .scanning
        outcome = nil
        failures = []
        progressLine = "Getting ready…"

        let progress: @Sendable (String) -> Void = { [weak self] line in
            Task { @MainActor in
                self?.progressLine = line
            }
        }

        Task { @MainActor [weak self] in
            let snapshot = await Task.detached(priority: .userInitiated) {
                CleanerScanner.scanAll(progress: progress)
            }.value
            self?.apply(snapshot)
        }
    }

    private func apply(_ snapshot: CleanerSnapshot) {
        candidates = snapshot.candidates
        apps = snapshot.apps
        trash = snapshot.trash
        notes = snapshot.notes
        lastScan = Date()
        progressLine = ""
        phase = .ready
    }

    // MARK: - Looking at what was found

    func candidates(in category: CleanCategory) -> [CleanCandidate] {
        candidates.filter { $0.category == category }
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
        let chosen = selectedCandidates
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
        if app.isRunning {
            outcome = nil
            failures = ["\(app.name) is open. Quit it first — macOS will not let an application be moved while it is running."]
            return
        }
        let paths = [app.url.path] + app.leftovers.map(\.url.path)

        pendingAction = .uninstall
        pendingTitle = "Move \(app.name) to Quarantine?"
        var detail = "The application and \(app.leftovers.count) file\(app.leftovers.count == 1 ? "" : "s") it left behind, \(app.totalSize.sizeDescription) together."
        if let version = app.version {
            detail += " Version \(version)."
        }
        pendingDetail = detail
        pendingPaths = paths
        pendingSize = app.totalSize
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

        var sentence = "\(title): \(result.succeededCount) \(noun)\(result.succeededCount == 1 ? "" : "s"), \(pendingSize.sizeDescription), moved to Quarantine."
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
