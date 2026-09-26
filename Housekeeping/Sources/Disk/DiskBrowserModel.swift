// Housekeeping — What the disk browser is currently showing
//
// The browser's own state, deliberately not folded into `AppState`. Everything
// here is about one screen — which folder is open, how the reader got there, and
// whether a measurement is running — and `AppState` is about the scan, the
// safety policy, and the quarantine. Keeping them apart means browsing the disk
// cannot disturb what the cleanup side of the app believes.

import Foundation
import SwiftUI

@MainActor
final class DiskBrowserModel: ObservableObject {
    /// Where a measurement started from. Offered as three named places rather
    /// than a path field, because the question being asked is almost always one
    /// of these three, and a typed path is a way to measure the wrong thing.
    enum RootChoice: String, CaseIterable, Identifiable {
        case home, applications, wholeDisk

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: return "Home"
            case .applications: return "Applications"
            case .wholeDisk: return "This Mac"
            }
        }

        var url: URL {
            switch self {
            case .home: return FileManager.default.homeDirectoryForCurrentUser
            case .applications: return URL(fileURLWithPath: "/Applications")
            case .wholeDisk: return URL(fileURLWithPath: "/")
            }
        }
    }

    /// The folder the current snapshot describes, once there is one.
    @Published private(set) var snapshot: DiskSnapshot?
    /// The folder open on screen. Always a path inside the snapshot's root.
    @Published private(set) var currentPath = ""
    /// Where Back goes, newest last. A history rather than a single parent link,
    /// because the reader who has walked down through four folders wants to come
    /// back out the way they came, not by retracing the tree by hand.
    @Published private(set) var history: [String] = []
    @Published private(set) var isScanning = false
    @Published private(set) var progress: DiskScanProgress?
    /// A sentence about the last thing that happened — a measurement that was
    /// stopped, or a folder that has since been deleted. Shown in the footer
    /// rather than as an alert, because none of it needs an answer.
    @Published var note: String?

    private var worker: Task<DiskSnapshot, Never>?
    private var reporter: Task<Void, Never>?
    private var cancelFlag = CancelFlag()
    private let scanner = DiskScanner()
    private let snapshotURL: URL

    /// A scan switched from the clock to a flag the moment the Stop button was
    /// added: cancelling a `Task` does not reach a synchronous walk that never
    /// suspends, so the walk has to be told in a way it can actually observe.
    private final class CancelFlag {
        var isCancelled = false
    }

    init(snapshotURL: URL = DiskSnapshot.defaultFileURL()) {
        self.snapshotURL = snapshotURL
        if let stored = DiskSnapshot.load(from: snapshotURL) {
            snapshot = stored
            currentPath = stored.root
        }
    }

    // MARK: - Measuring

    /// Starts a measurement of `root`, replacing whatever is on screen.
    ///
    /// The measurement runs off the main thread and reports its progress back
    /// here; nothing about it touches the reader's other work in the app.
    func scan(root: URL) {
        worker?.cancel()
        reporter?.cancel()
        cancelFlag = CancelFlag()
        let flag = cancelFlag

        isScanning = true
        progress = nil
        snapshot = nil
        currentPath = root.path
        history = []
        note = nil

        let options = DiskScanner.Options(root: root)
        let scanner = self.scanner
        let worker = Task.detached(priority: .userInitiated) { [weak self] in
            scanner.scan(
                options: options,
                progress: { report in
                    Task { @MainActor [weak self] in self?.progress = report }
                },
                isCancelled: { flag.isCancelled }
            )
        }
        self.worker = worker

        reporter = Task { [weak self] in
            let measured = await worker.value
            guard let self, !Task.isCancelled else { return }
            self.finish(measured)
        }
    }

    /// Stops a measurement and keeps what it had got to. Anything else would
    /// throw away several minutes of reading the disk to honour a press that was
    /// about wanting the answer sooner, not about wanting no answer.
    func stopScan() {
        guard isScanning else { return }
        cancelFlag.isCancelled = true
        note = "Stopped early. What is shown was measured before you stopped it; folders it never reached say so."
    }

    private func finish(_ measured: DiskSnapshot) {
        isScanning = false
        progress = nil
        snapshot = measured
        currentPath = measured.root
        history = []
        measured.save(to: snapshotURL)

        if !measured.isComplete {
            note = "This measurement stopped before it finished, so some folders are marked as not measured."
        }
    }

    /// Throws away the stored measurement. It is only ever a reading of a machine
    /// that can be read again, so there is nothing here to keep.
    func forgetSnapshot() {
        snapshot = nil
        currentPath = ""
        history = []
        note = nil
        try? FileManager.default.removeItem(at: snapshotURL)
    }

    // MARK: - Moving around

    var rootNode: DiskNode? { snapshot?.rootNode }

    var currentNode: DiskNode? {
        snapshot?.node(at: currentPath)
    }

    var visibleChildren: [DiskNode] {
        snapshot?.childNodes(of: currentPath) ?? []
    }

    var breadcrumb: [(name: String, path: String)] {
        snapshot?.breadcrumb(to: currentPath) ?? []
    }

    var canGoBack: Bool { !history.isEmpty }

    var canGoUp: Bool {
        guard let snapshot else { return false }
        return snapshot.parent(of: currentPath) != nil
    }

    func open(_ path: String) {
        guard path != currentPath, snapshot?.node(at: path) != nil else { return }
        history.append(currentPath)
        currentPath = path
    }

    /// Back, along the path the reader actually took. Not the same as Up: coming
    /// back from a folder reached by clicking through three others should land
    /// where the third click happened, not one level up from here.
    func goBack() {
        guard let previous = history.popLast() else { return }
        currentPath = previous
    }

    func goUp() {
        guard let parent = snapshot?.parent(of: currentPath) else { return }
        history.append(currentPath)
        currentPath = parent
    }

    /// Where this folder sits inside the folder that contains it, as a fraction,
    /// for the bar beside the row. Zero when the parent is the same size as the
    /// child or the parent has nothing in it, so the bar never divides by nothing.
    func shareOfParent(_ node: DiskNode) -> Double {
        guard let snapshot, let parentPath = snapshot.parent(of: node.path),
              let parent = snapshot.node(at: parentPath), parent.size > 0 else { return 0 }
        return min(1, Double(node.size) / Double(parent.size))
    }

    /// The folder's own words about what it was: how many files and folders are
    /// under it, and whether anything was left unread. Separate from the size so
    /// the size can stay a number and this can carry the caveats.
    func summary(for node: DiskNode) -> String {
        var parts: [String] = []
        if node.isUnmeasured {
            parts.append("not measured")
        } else {
            parts.append("\(node.fileCount.formatted()) files")
            parts.append("\(node.directoryCount.formatted()) folders")
        }
        if node.isPartial {
            parts.append("at least, some of it could not be read")
        }
        return parts.joined(separator: " · ")
    }

    /// The biggest folders anywhere below the measurement's root. The answer to
    /// "where did it all go" without having to click into anything to find it.
    func biggestFolders(limit: Int = 25) -> [DiskNode] {
        snapshot?.largestDescendants(limit: limit) ?? []
    }

    var limits: [String] {
        snapshot?.notes ?? []
    }

    var measurementDescription: String? {
        guard let snapshot else { return nil }
        let when = snapshot.measuredAt.formatted(date: .abbreviated, time: .shortened)
        let seconds = Int(snapshot.duration.rounded())
        return "Measured \(when), in \(seconds)s"
    }
}
