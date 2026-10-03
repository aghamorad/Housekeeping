// Housekeeping — The screen's side of comparing two folders
//
// The long work happens off the main thread and reports back through a closure
// that hops to the main queue, the same way browsing the disk does. The flag is
// a class rather than a `Task` cancellation because a filesystem walk is
// synchronous and never looks at `Task.isCancelled` — the walk has to be asked.

import Foundation
import Combine
import AppKit

@MainActor
final class ReconcileModel: ObservableObject {

    private final class CancelFlag { var isCancelled = false }

    @Published private(set) var pairs: [FolderPair] = []
    @Published var selectedPairID: String?
    @Published private(set) var report: ReconcileReport?
    @Published private(set) var proposals: [ReconcileProposal] = []
    @Published private(set) var isComparing = false
    @Published private(set) var isApplying = false
    @Published private(set) var progress: ReconcileProgress?
    @Published private(set) var applyResult: ReconcileApplyResult?
    @Published var note: String?
    @Published private(set) var loadFailureNote: String?

    let singleCopyLibraries = ReconcileConventions.knownSingleCopyLibraries

    private let store: FolderPairStore
    private let engine: ReconcileEngine
    private var worker: Task<ReconcileReport, Never>?
    private var reporter: Task<Void, Never>?
    private var cancelFlag = CancelFlag()

    init(store: FolderPairStore = FolderPairStore(), engine: ReconcileEngine = ReconcileEngine()) {
        self.store = store
        self.engine = engine
        self.pairs = store.pairs
        self.loadFailureNote = store.loadFailureNote
        self.selectedPairID = store.pairs.first?.id
    }

    var selectedPair: FolderPair? {
        guard let selectedPairID else { return nil }
        return pairs.first { $0.id == selectedPairID }
    }

    var selectedCount: Int { proposals.filter(\.isSelected).count }
    var hasSomethingToDo: Bool { proposals.contains { $0.isSelected && $0.action != .decide } }

    // MARK: - Comparing

    func compare() {
        guard let pair = selectedPair, !isComparing else { return }
        worker?.cancel()
        reporter?.cancel()

        cancelFlag = CancelFlag()
        let flag = cancelFlag
        isComparing = true
        progress = nil
        report = nil
        proposals = []
        applyResult = nil
        note = nil

        let engine = self.engine
        let worker = Task.detached(priority: .userInitiated) { [weak self] in
            engine.compare(
                pair: pair,
                progress: { update in Task { @MainActor [weak self] in self?.progress = update } },
                isCancelled: { flag.isCancelled }
            )
        }
        self.worker = worker

        reporter = Task { [weak self] in
            let measured = await worker.value
            guard let self, !Task.isCancelled else { return }
            self.finish(measured, pair: pair)
        }
    }

    func stop() {
        cancelFlag.isCancelled = true
        note = "Stopping. Whatever has been read so far is kept."
    }

    private func finish(_ measured: ReconcileReport, pair: FolderPair) {
        isComparing = false
        progress = nil
        report = measured
        proposals = engine.plan(for: measured, pair: pair)
    }

    // MARK: - Choosing

    func toggle(_ proposal: ReconcileProposal) {
        guard let index = proposals.firstIndex(where: { $0.id == proposal.id }) else { return }
        guard proposals[index].action != .decide else { return }
        proposals[index].isSelected.toggle()
    }

    func selectAllCopies() {
        for index in proposals.indices where proposals[index].action == .copy {
            proposals[index].isSelected = true
        }
    }

    func clearSelection() {
        for index in proposals.indices { proposals[index].isSelected = false }
    }

    /// Everything, including the moves aside. Kept as a separate deliberate
    /// action because ticking a row that takes a file out of a library should
    /// never be something that happens by pressing the obvious button.
    func selectEverythingActionable() {
        for index in proposals.indices where proposals[index].action != .decide {
            proposals[index].isSelected = true
        }
    }

    // MARK: - Doing it

    func apply() {
        guard let pair = selectedPair, !isApplying, hasSomethingToDo else { return }
        let chosen = proposals
        isApplying = true
        note = nil
        applyResult = nil

        let engine = self.engine
        Task { [weak self] in
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try await engine.apply(chosen, pair: pair, progress: { update in
                        Task { @MainActor [weak self] in self?.progress = update }
                    })
                }.value
                guard let self else { return }
                self.isApplying = false
                self.progress = nil
                self.applyResult = result
                if !result.failures.isEmpty {
                    self.note = result.failures.prefix(3)
                        .map { "\($0.path) — \($0.message)" }
                        .joined(separator: "  ·  ")
                }
                // The comparison that produced the plan is now out of date, so
                // it is dropped rather than left on screen looking current.
                self.report = nil
                self.proposals = []
            } catch {
                guard let self else { return }
                self.isApplying = false
                self.progress = nil
                self.note = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func revealRunRecord() {
        guard let url = applyResult?.journalURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealRunsFolder() {
        let url = engine.runRecordDirectoryURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    func reveal(_ path: String) {
        // A finding carries a path relative to its side, and revealing one of
        // those as if it were absolute would quietly point Finder at whatever
        // directory the app happened to be launched from. Only an absolute path
        // is revealed; the caller is the one that has the side's root.
        guard path.hasPrefix("/") else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - Editing the pairs

    func addPair() {
        guard let a = chooseFolder(prompt: "Choose the first folder") else { return }
        guard let b = chooseFolder(prompt: "Choose the second folder") else { return }

        let pair = FolderPair(
            id: "pair-\(UUID().uuidString.prefix(8))",
            label: "\(a.lastPathComponent) ↔ \(b.lastPathComponent)",
            summary: "Added by hand. Nothing is ever written unless a direction is set and a row is ticked.",
            sideAPath: a.path,
            sideBPath: b.path,
            sideAName: "A",
            sideBName: "B",
            direction: .reportOnly,
            exclusions: [],
            ignoredExtensions: [],
            includedExtensions: [],
            frozenSide: nil,
            isBuiltIn: false
        )
        store.add(pair)
        pairs = store.pairs
        selectedPairID = pair.id
        report = nil
        proposals = []
        applyResult = nil
    }

    func update(_ pair: FolderPair) {
        store.update(pair)
        pairs = store.pairs
        report = nil
        proposals = []
    }

    func choosePath(for side: ReconcileSide) {
        guard let pair = selectedPair else { return }
        guard let url = chooseFolder(prompt: "Choose the folder for \(pair.name(of: side))") else { return }
        var updated = pair
        if side == .a { updated.sideAPath = url.path } else { updated.sideBPath = url.path }
        update(updated)
    }

    func removeSelectedPair() {
        guard let pair = selectedPair, !pair.isBuiltIn else { return }
        store.remove(pair)
        pairs = store.pairs
        selectedPairID = pairs.first?.id
        report = nil
        proposals = []
        applyResult = nil
    }

    private func chooseFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose"
        panel.message = prompt
        // A drive that is not mounted cannot be chosen, which is the right
        // moment to find that out.
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        return panel.runModal() == .OK ? panel.url : nil
    }
}
