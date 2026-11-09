// Housekeeping — Dedicated App Uninstaller
//
// CleanMyMac-style application uninstaller.
// Discovers installed applications and all related leftovers (Application Support,
// Caches, Preferences, Saved State, Containers) with granular selection and safe Quarantine removal.

import SwiftUI
import AppKit

@MainActor
final class UninstallerModel: ObservableObject {
    static let shared = UninstallerModel()

    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var isScanning: Bool = false
    @Published private(set) var scanProgress: String = ""
    @Published private(set) var scanNotice: String?
    /// Set when a search or filter change cleared apps the reader can no longer
    /// see, so a selection never disappears without a word.
    @Published private(set) var selectionNotice: String?
    private var scanWorker: Task<[InstalledApp], Never>?
    private var scanToken = UUID()
    @Published var selectedAppURLs: Set<URL> = []
    @Published var expandedAppURLs: Set<URL> = []
    @Published var searchQuery: String = "" {
        didSet {
            // A notice about the last clearing stays until the reader empties the
            // search or makes a new explicit choice; clearing it on every
            // keystroke would erase the message the first character produced.
            if searchQuery.isEmpty { selectionNotice = nil }
            retainOnlyVisibleSelections()
        }
    }
    @Published var sortOption: AppSortOption = .sizeDescending
    @Published var filterOption: AppFilterOption = .all {
        didSet {
            retainOnlyVisibleSelections()
        }
    }
    @Published private(set) var isWorking = false
    @Published private(set) var outcome: String?
    @Published private(set) var failures: [String] = []
    @Published private(set) var includedRelatedPaths: Set<String> = []
    @Published var pendingUninstallPlan: [InstalledApp]? = nil
    @Published private(set) var session: UninstallSession?

    public enum AppFilterOption: String, CaseIterable, Identifiable, Sendable {
        case all = "All Apps"
        case withLeftovers = "With Leftovers"
        case cleanOnly = "Clean Bundles"

        public var id: String { rawValue }
    }

    var appsWithLeftoversCount: Int {
        apps.filter { !$0.leftovers.isEmpty }.count
    }

    var cleanAppsCount: Int {
        apps.filter { $0.leftovers.isEmpty }.count
    }

    var allExpanded: Bool {
        let targets = filteredApps.filter { !$0.leftovers.isEmpty }
        guard !targets.isEmpty else { return false }
        return targets.allSatisfy { expandedAppURLs.contains($0.url) }
    }

    func expandAll() {
        for app in filteredApps where !app.leftovers.isEmpty {
            expandedAppURLs.insert(app.url)
        }
    }

    func collapseAll() {
        expandedAppURLs.removeAll()
    }

    init() {
        startScan()
    }

    func startScan() {
        guard !isScanning, !isWorking else { return }
        isScanning = true
        scanNotice = nil
        scanProgress = "Discovering applications…"
        let token = UUID()
        scanToken = token

        let progress: @Sendable (String) -> Void = { [weak self] line in
            Task { @MainActor in
                guard let self, self.scanToken == token, self.isScanning else { return }
                self.scanProgress = line
            }
        }
        let worker = Task.detached(priority: .userInitiated) {
            Uninstaller.installed(progress: progress)
        }
        scanWorker = worker
        Task { @MainActor [weak self] in
            let results = await worker.value
            guard let self, self.scanToken == token, !worker.isCancelled else { return }
            self.apps = results
            self.selectedAppURLs.formIntersection(Set(results.map(\.url)))
            self.expandedAppURLs.formIntersection(Set(results.map(\.url)))
            // New related files remain excluded until deliberately selected.
            self.includedRelatedPaths.formIntersection(Set(results.flatMap(\.leftovers).map(\.id)))
            self.isScanning = false
            self.scanWorker = nil
            self.scanProgress = ""
        }
    }

    func stopScan() {
        guard isScanning else { return }
        scanToken = UUID()
        scanWorker?.cancel()
        scanWorker = nil
        isScanning = false
        scanProgress = ""
        scanNotice = "Scan stopped. Existing complete results are still shown; click Refresh to start again."
    }

    var filteredApps: [InstalledApp] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var matching = query.isEmpty ? apps : apps.filter {
            $0.name.lowercased().contains(query) ||
            ($0.bundleIdentifier?.lowercased().contains(query) ?? false)
        }
        switch filterOption {
        case .all:
            break
        case .withLeftovers:
            matching = matching.filter { !$0.leftovers.isEmpty }
        case .cleanOnly:
            matching = matching.filter { $0.leftovers.isEmpty }
        }
        return matching.sorted { lhs, rhs in
            switch sortOption {
            case .sizeDescending:
                if lhs.totalSize != rhs.totalSize { return lhs.totalSize > rhs.totalSize }
            case .sizeAscending:
                if lhs.totalSize != rhs.totalSize { return lhs.totalSize < rhs.totalSize }
            case .nameAscending:
                let comp = lhs.name.localizedStandardCompare(rhs.name)
                if comp != .orderedSame { return comp == .orderedAscending }
            case .nameDescending:
                let comp = lhs.name.localizedStandardCompare(rhs.name)
                if comp != .orderedSame { return comp == .orderedDescending }
            case .modifiedNewest:
                if let l = lhs.modifiedDate, let r = rhs.modifiedDate, l != r { return l > r }
                if (lhs.modifiedDate != nil) != (rhs.modifiedDate != nil) { return lhs.modifiedDate != nil }
            case .modifiedOldest:
                if let l = lhs.modifiedDate, let r = rhs.modifiedDate, l != r { return l < r }
                if (lhs.modifiedDate != nil) != (rhs.modifiedDate != nil) { return lhs.modifiedDate != nil }
            case .installedNewest:
                if let l = lhs.createdDate, let r = rhs.createdDate, l != r { return l > r }
                if (lhs.createdDate != nil) != (rhs.createdDate != nil) { return lhs.createdDate != nil }
            case .installedOldest:
                if let l = lhs.createdDate, let r = rhs.createdDate, l != r { return l < r }
                if (lhs.createdDate != nil) != (rhs.createdDate != nil) { return lhs.createdDate != nil }
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func retainOnlyVisibleSelections() {
        guard !isWorking else { return }
        // A hidden app must never be removed when someone presses Uninstall
        // Selected after changing a search or category filter — and it must not
        // disappear from the count without telling the reader either.
        let visible = Set(filteredApps.map(\.url))
        let hidden = selectedAppURLs.subtracting(visible)
        guard !hidden.isEmpty else { return }
        selectedAppURLs.formIntersection(visible)
        selectionNotice = "\(hidden.count) selected app\(hidden.count == 1 ? "" : "s") \(hidden.count == 1 ? "is" : "are") hidden by the current search or filter and \(hidden.count == 1 ? "was" : "were") cleared. Clear the search to choose across searches."
    }

    func selectAllFiltered() {
        guard !isWorking && !isScanning else { return }
        selectionNotice = nil
        for app in filteredApps {
            selectedAppURLs.insert(app.url)
        }
    }

    func deselectAll() {
        selectionNotice = nil
        selectedAppURLs.removeAll()
    }

    var selectedTotalSize: Int64 {
        apps.filter { selectedAppURLs.contains($0.url) }.reduce(0) { total, app in
            total + app.size + includedLeftovers(app).reduce(0) { $0 + $1.size }
        }
    }

    func toggleSelection(_ app: InstalledApp) {
        guard !isWorking && !isScanning else { return }
        selectionNotice = nil
        if selectedAppURLs.contains(app.url) {
            selectedAppURLs.remove(app.url)
        } else {
            selectedAppURLs.insert(app.url)
        }
    }

    func toggleExpand(_ app: InstalledApp) {
        if expandedAppURLs.contains(app.url) {
            expandedAppURLs.remove(app.url)
        } else {
            expandedAppURLs.insert(app.url)
        }
    }

    func prepareUninstall() {
        guard !isWorking, !isScanning else { return }
        retainOnlyVisibleSelections()
        outcome = nil
        let selected = apps.filter { selectedAppURLs.contains($0.url) }
        let targets = selected.filter { !$0.isRunning && !ProtectionList().isProtected($0.url) }
        failures = selected.filter { $0.isRunning || ProtectionList().isProtected($0.url) }.map {
            $0.isRunning ? "\($0.name) is open. Quit it, then try again." : "\($0.name) is on the Leave Alone list."
        }
        guard !targets.isEmpty else { return }
        pendingUninstallPlan = targets
    }

    func requestQuit(_ app: InstalledApp) {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.standardizedFileURL == app.url.standardizedFileURL
                || (app.bundleIdentifier != nil && $0.bundleIdentifier == app.bundleIdentifier)
        }
        let accepted = running.map { $0.terminate() }.allSatisfy { $0 }
        outcome = accepted
            ? "Quit requested for \(app.name). Save any open work, then click Uninstall when it has closed."
            : "\(app.name) could not be closed. Quit it from its own menu, then try Uninstall again."
        failures = []
    }

    func includedLeftovers(_ app: InstalledApp) -> [CleanCandidate] {
        app.leftovers.filter { includedRelatedPaths.contains($0.id) && !ProtectionList().isProtected($0.url) }
    }

    func setRelatedFiles(_ app: InstalledApp, included: Bool) {
        let paths = app.leftovers.filter { !ProtectionList().isProtected($0.url) }.map(\.id)
        if included { includedRelatedPaths.formUnion(paths) }
        else { includedRelatedPaths.subtract(paths) }
    }

    func setRelatedFile(_ item: CleanCandidate, included: Bool) {
        guard !ProtectionList().isProtected(item.url) else { return }
        if included { includedRelatedPaths.insert(item.id) }
        else { includedRelatedPaths.remove(item.id) }
    }

    func executeUninstall() {
        guard !isWorking, let planned = pendingUninstallPlan else { return }
        let targets = Uninstaller.unambiguousLeftovers(in: planned.map { app in
            var copy = app
            copy.leftovers = includedLeftovers(app)
            return copy
        })
        pendingUninstallPlan = nil
        isWorking = true
        outcome = nil
        session = UninstallSession(apps: targets)
        let skipped = failures
        Task { @MainActor [weak self] in
            do {
                let result = try await CleanupEngine().uninstall(targets) { [weak self] event in
                    await self?.receiveProgress(event)
                }
                let moved = Set(result.movedPaths)
                let count = targets.filter { moved.contains($0.id) }.count
                let relatedCount = targets.flatMap(\.leftovers).filter { moved.contains($0.id) }.count
                self?.outcome = "\(count) app\(count == 1 ? "" : "s") and \(relatedCount) related item\(relatedCount == 1 ? "" : "s") moved to Quarantine. You can put them back there. Space is freed when you delete them permanently."
                self?.failures = skipped + result.moves.filter { !$0.succeeded }.map {
                    "\($0.path) — \($0.message ?? "Could not be moved. Try again.")"
                }
                self?.selectedAppURLs.subtract(targets.filter { moved.contains($0.id) }.map(\.url))
                self?.apps.removeAll { moved.contains($0.id) }
                self?.session?.finish(result: result)
            } catch {
                self?.failures = skipped + [error.localizedDescription]
                self?.session?.finish(error: error.localizedDescription)
            }
            self?.isWorking = false
            self?.startScan()
        }
    }

    private func receiveProgress(_ event: UninstallProgress) {
        session?.receive(event)
    }

    func dismissSession() {
        guard !isWorking else { return }
        session = nil
    }

}

struct UninstallerModernView: View {
    @ObservedObject var model: UninstallerModel = .shared
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    var body: some View {
        Group {
            if let session = model.session {
                UninstallActivityView(session: session, done: model.dismissSession) {
                    appState.refreshQuarantineAvailability()
                    appState.showQuarantineManagement = true
                }
            } else {
                browser
            }
        }
        .background { HousekeepingBackdrop(style: style) }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            model.objectWillChange.send()
        }
        .sheet(item: Binding(
            get: { model.pendingUninstallPlan.map { UninstallPlanWrapper(items: $0) } },
            set: { model.pendingUninstallPlan = $0?.items }
        )) { wrapper in
            uninstallConfirmationSheet(wrapper.items)
                .housekeepingSurface(style)
        }
    }

    private var browser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if let notice = model.scanNotice {
                    Label(notice, systemImage: "info.circle")
                        .font(style.smallFont)
                        .foregroundStyle(style.secondaryText)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 9))
                }
                searchAndActionBar
                if let notice = model.selectionNotice {
                    Label(notice, systemImage: "exclamationmark.circle")
                        .font(style.smallFont)
                        .foregroundStyle(style.secondaryText)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 9))
                }
                if model.isScanning && !model.apps.isEmpty { scanningView }
                if model.outcome != nil || !model.failures.isEmpty {
                    ThemePanel {
                        VStack(alignment: .leading, spacing: 10) {
                            if let outcome = model.outcome { Text(outcome).font(style.bodyFont) }
                            ForEach(model.failures, id: \.self) { failure in
                                Text(failure).font(style.smallFont).foregroundColor(style.negative).textSelection(.enabled)
                            }
                            ThemeButton(title: "Review Quarantine", systemImage: "archivebox") {
                                appState.refreshQuarantineAvailability()
                                appState.showQuarantineManagement = true
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if model.isScanning && model.apps.isEmpty {
                    scanningView
                } else if model.filteredApps.isEmpty {
                    emptyView
                } else {
                    appsList
                }
            }
            .padding(32)
            .frame(maxWidth: 1080, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { HousekeepingBackdrop(style: style) }
        .disabled(model.isWorking)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "xmark.app.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(style.accent)
                    Text("App Uninstaller")
                        .font(style.isRetro ? style.titleFont : .system(size: 28, weight: .bold))
                }
                Text("Remove an app with a recoverable Quarantine move. Related settings and personal data stay put unless you choose them in the final review.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ThemeButton(
                title: "Refresh Apps",
                systemImage: "arrow.clockwise",
                isEnabled: !model.isScanning
            ) {
                model.startScan()
            }
        }
    }

    // MARK: - Search & Action Bar

    private var searchAndActionBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search installed applications…", text: $model.searchQuery)
                        .textFieldStyle(.plain)
                    if !model.searchQuery.isEmpty {
                        Button {
                            model.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(style.border, lineWidth: 1))
                .frame(maxWidth: 320)

                // Organize by picker
                Menu {
                    Picker("Organize by", selection: $model.sortOption) {
                        ForEach(AppSortOption.allCases) { opt in
                            Label(opt.rawValue, systemImage: opt.systemImage)
                                .tag(opt)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: model.sortOption.systemImage)
                            .foregroundStyle(style.accent)
                        Text(model.sortOption.rawValue)
                            .font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(style.border, lineWidth: 1))
                }
                .menuStyle(.borderlessButton)

                Spacer()

                if !model.selectedAppURLs.isEmpty {
                    Text("\(model.selectedAppURLs.count) selected (\(ByteCountFormatter.string(fromByteCount: model.selectedTotalSize, countStyle: .file)))")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(style.accent)

                    ThemeButton(
                        title: "Uninstall Selected",
                        systemImage: "trash.fill",
                        isPrimary: true
                    ) {
                        model.prepareUninstall()
                    }
                }
            }

            // Filter Tabs & Global Leftovers Expansion Toggle
            HStack(spacing: 8) {
                filterPill(.all, title: "All Apps (\(model.apps.count))", icon: "square.grid.2x2")
                filterPill(.withLeftovers, title: "With Leftovers (\(model.appsWithLeftoversCount))", icon: "folder.badge.gearshape")
                filterPill(.cleanOnly, title: "Clean Bundles (\(model.cleanAppsCount))", icon: "checkmark.shield")

                Spacer()

                if model.appsWithLeftoversCount > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if model.allExpanded {
                                model.collapseAll()
                            } else {
                                model.expandAll()
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: model.allExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                            Text(model.allExpanded ? "Collapse All Leftovers" : "Expand All Leftovers (\(model.appsWithLeftoversCount))")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(style.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(style.accent.opacity(0.3), lineWidth: 1))
                        .foregroundStyle(style.accent)
                    }
                    .buttonStyle(.plain)
                    .help(model.allExpanded ? "Collapse all open leftover inspectors" : "Open leftover drawers for all applications with leftovers")
                }
            }

            // Quick select all / deselect all
            HStack(spacing: 8) {
                Button {
                    model.selectAllFiltered()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                        Text("Select All in View")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(style.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(style.accent)
                }
                .buttonStyle(.plain)

                if !model.selectedAppURLs.isEmpty {
                    Button {
                        model.deselectAll()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "circle")
                            Text("Deselect All")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Text("\(model.filteredApps.count) applications")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func filterPill(_ option: UninstallerModel.AppFilterOption, title: String, icon: String) -> some View {
        let isSelected = model.filterOption == option
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                model.filterOption = option
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isSelected ? style.accent.opacity(0.2) : style.rowBackground, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSelected ? style.accent : style.border, lineWidth: 1))
            .foregroundStyle(isSelected ? style.accent : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Apps List

    private var appsList: some View {
        LazyVStack(spacing: 10) {
            ForEach(model.filteredApps) { app in
                appRow(app)
            }
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        let isSelected = model.selectedAppURLs.contains(app.url)
        let isExpanded = model.expandedAppURLs.contains(app.url)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Toggle("", isOn: Binding(
                    get: { isSelected },
                    set: { _ in model.toggleSelection(app) }
                ))
                .labelsHidden()

                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(app.name)
                            .font(.system(size: 14, weight: .bold))
                        if let v = app.version {
                            Text("v\(v)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 10) {
                        if let mod = app.modifiedDate {
                            Label(mod.formatted(date: .abbreviated, time: .omitted), systemImage: "clock")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        } else if let created = app.createdDate {
                            Label(created.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Text(app.url.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(ByteCountFormatter.string(fromByteCount: app.totalSize, countStyle: .file))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    if !app.leftovers.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                model.toggleExpand(app)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isExpanded ? "eye.slash.fill" : "eye.fill")
                                    .font(.system(size: 9))
                                Text(isExpanded ? "Hide leftovers" : "See \(app.leftovers.count) leftovers")
                                    .font(.system(size: 11, weight: .semibold))
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                isExpanded ? style.accent.opacity(0.22) : style.accent.opacity(0.12),
                                in: Capsule()
                            )
                            .overlay(Capsule().stroke(style.accent.opacity(0.35), lineWidth: 1))
                            .foregroundStyle(style.accent)
                        }
                        .buttonStyle(.plain)
                        .help(isExpanded ? "Hide leftover files" : "Click to inspect all \(app.leftovers.count) leftover items")
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary.opacity(0.7))
                            Text("Clean bundle")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                    }
                }

                Button {
                    if app.isRunning {
                        model.requestQuit(app)
                    } else {
                        model.selectedAppURLs = [app.url]
                        model.prepareUninstall()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: app.isRunning ? "stop.circle" : "trash")
                        Text(app.isRunning ? "Quit to Uninstall" : "Uninstall")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 9)
                    .frame(minHeight: 44)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(app.isRunning ? "Ask \(app.name) to quit normally; review removal after it closes" : "Review \(app.name) and its matched related files")
                .disabled(model.isScanning)

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.toggleExpand(app)
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            if isExpanded {
                Divider().padding(.horizontal, 14)
                leftoversDetail(app)
            }
        }
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? style.accent : style.border, lineWidth: isSelected ? 1.5 : 1)
        )
        .contextMenu {
            Button {
                HousekeeperTopic.ask(.installedApp(app))
            } label: {
                Label("Ask the Housekeeper About \(app.name)", systemImage: "sparkles")
            }

            Divider()

            Button {
                NSWorkspace.shared.selectFile(app.url.path, inFileViewerRootedAtPath: app.url.deletingLastPathComponent().path)
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }

            if !app.leftovers.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        model.toggleExpand(app)
                    }
                } label: {
                    Label(isExpanded ? "Hide Leftovers" : "Inspect Leftovers (\(app.leftovers.count))", systemImage: "folder.badge.gearshape")
                }
            }

            Divider()

            Button(role: .destructive) {
                model.selectedAppURLs = [app.url]
                model.prepareUninstall()
            } label: {
                Label("Uninstall \(app.name)", systemImage: "trash")
            }
        }
    }

    private func leftoversDetail(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header summary bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundStyle(style.accent)
                    Text("Found Related Files (\(app.leftovers.count))")
                        .font(.system(size: 12, weight: .bold))
                }

                Spacer()

                HStack(spacing: 12) {
                    Text("Bundle: \(ByteCountFormatter.string(fromByteCount: app.size, countStyle: .file))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text("Leftovers: \(ByteCountFormatter.string(fromByteCount: app.leftoverSize, countStyle: .file))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(style.accent)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            Text("These are shown for inspection, not automatically selected for removal.")
                .font(.system(size: 11))
                .foregroundStyle(style.secondaryText)
                .padding(.horizontal, 16)

            VStack(spacing: 6) {
                // Main Application Bundle
                HStack(spacing: 10) {
                    Image(systemName: "app.fill")
                        .foregroundStyle(style.accent)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Application Binary")
                                .font(.system(size: 12, weight: .semibold))
                            badgeTag(label: "Main App Bundle", icon: "app.badge", color: .blue)
                        }
                        Text(abbreviatedPath(app.url))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer()

                    Text(ByteCountFormatter.string(fromByteCount: app.size, countStyle: .file))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([app.url])
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.right.square")
                            Text("Reveal")
                        }
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .help("Reveal main app bundle in Finder")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))

                // Leftover items
                ForEach(app.leftovers) { leftover in
                    let badge = categoryBadge(for: leftover.url)
                    HStack(spacing: 10) {
                        Image(systemName: badge.icon)
                            .foregroundStyle(badge.color)
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(leftover.name)
                                    .font(.system(size: 12, weight: .medium))
                                badgeTag(label: badge.label, icon: badge.icon, color: badge.color)
                            }
                            Text(abbreviatedPath(leftover.url))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        Spacer()

                        Text(ByteCountFormatter.string(fromByteCount: leftover.size, countStyle: .file))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([leftover.url])
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.right.square")
                                Text("Reveal")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .help("Reveal this leftover in Finder")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
                    .contextMenu {
                        Button {
                            HousekeeperTopic.ask(.candidate(leftover))
                        } label: {
                            Label("Ask the Housekeeper About This Item", systemImage: "sparkles")
                        }

                        Divider()

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([leftover.url])
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .background(Color.primary.opacity(0.03))
    }

    private func badgeTag(label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(label)
                .font(.system(size: 9, weight: .medium))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
        .foregroundStyle(color)
    }

    private func abbreviatedPath(_ url: URL) -> String {
        let path = url.path
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func categoryBadge(for url: URL) -> (label: String, icon: String, color: Color) {
        let path = url.path
        if path.contains("/Library/Application Support/") {
            return ("App Support", "folder.fill", .blue)
        } else if path.contains("/Library/Caches/") {
            return ("Caches", "archivebox.fill", .orange)
        } else if path.contains("/Library/Containers/") || path.contains("/Library/Group Containers/") {
            return ("Sandbox", "shippingbox.fill", .purple)
        } else if path.contains("/Library/Preferences/") {
            return ("Preferences", "slider.horizontal.3", .green)
        } else if path.contains("/Library/Saved Application State/") {
            return ("Saved State", "clock.arrow.circlepath", .teal)
        } else if path.contains("/Library/WebKit/") {
            return ("WebKit", "safari.fill", .indigo)
        } else if path.contains("/Library/Logs/") {
            return ("Logs", "doc.text.fill", .gray)
        } else {
            return ("Leftover", "folder.fill", .orange)
        }
    }

    // MARK: - Scanning & Empty Views

    private var scanningView: some View {
        HStack(spacing: 12) {
            TaskProgressCue(
                title: "Finding installed apps",
                detail: model.scanProgress.isEmpty
                    ? "Reading apps and related folders. No files are changed."
                    : model.scanProgress,
                symbol: "app.badge.magnifyingglass"
            )
            ThemeButton(title: "Stop Scan", systemImage: "stop.circle",
                        help: "Cancel this read without changing apps or related files.") {
                model.stopScan()
            }
        }
        .padding(12)
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text("No applications found matching \"\(model.searchQuery)\"")
                .font(.system(size: 14, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .padding(48)
    }

    // MARK: - Confirmation Sheet

    private func uninstallConfirmationSheet(_ targets: [InstalledApp]) -> some View {
        let included = targets.flatMap { model.includedLeftovers($0) }
        let size = targets.reduce(Int64(0)) { $0 + $1.size } + included.reduce(0) { $0 + $1.size }
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.app")
                    .font(.system(size: 26))
                    .foregroundStyle(style.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review App Removal")
                        .font(.system(size: 18, weight: .bold))
                    Text("The selected apps will move to Quarantine. Related data starts excluded because it may hold settings, documents or saved games; tick an exact file only if you want to move it too. macOS may ask for an administrator password.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 18) {
                Label("\(targets.count) app\(targets.count == 1 ? "" : "s")", systemImage: "square.stack.3d.up")
                Label("\(included.count) related items included", systemImage: "folder")
                Spacer()
                Text(size.sizeDescription).monospacedDigit()
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(14).background(style.rowSelection, in: RoundedRectangle(cornerRadius: 10))

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(targets) { app in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                .resizable()
                                .frame(width: 36, height: 36)
                            Text(app.name)
                                .font(.system(size: 15, weight: .bold))
                            Spacer()
                            Text((app.size + model.includedLeftovers(app).reduce(0) { $0 + $1.size }).sizeDescription)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Text(app.url.homeAbbreviatedPath).font(style.pathFont).textSelection(.enabled)
                        if !app.leftovers.isEmpty {
                            HStack {
                                Text("\(model.includedLeftovers(app).count) of \(app.leftovers.count) related files included")
                                    .font(.system(size: 13)).foregroundStyle(style.secondaryText)
                                Spacer()
                                Button("Include All (review first)") { model.setRelatedFiles(app, included: true) }
                                    .frame(minHeight: 44)
                                Button("Keep All Related Files") { model.setRelatedFiles(app, included: false) }
                                    .frame(minHeight: 44)
                            }
                        }
                        ForEach(app.leftovers) { item in
                            Toggle(isOn: Binding(
                                get: { model.includedRelatedPaths.contains(item.id) && !ProtectionList().isProtected(item.url) },
                                set: { include in model.setRelatedFile(item, included: include) }
                            )) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(item.name) · \(item.size.sizeDescription)").font(style.bodyFont)
                                    Text(categoryBadge(for: item.url).label)
                                        .font(.system(size: 12, weight: .medium)).foregroundStyle(style.accent)
                                    Text(item.url.homeAbbreviatedPath).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                    if ProtectionList().isProtected(item.url) {
                                        Label("Kept: on the Leave Alone list", systemImage: "hand.raised")
                                            .font(.system(size: 12)).foregroundStyle(style.caution)
                                    }
                                }
                            }
                            .disabled(ProtectionList().isProtected(item.url))
                            .padding(.vertical, 6).frame(minHeight: 48)
                        }
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 340)

            Divider()

            HStack {
                ThemeButton(title: "Cancel", systemImage: "xmark") {
                    model.pendingUninstallPlan = nil
                }
                Spacer()
                ThemeButton(
                    title: "Uninstall \(targets.count) App\(targets.count == 1 ? "" : "s")",
                    systemImage: "trash.fill",
                    isPrimary: true
                ) {
                    model.executeUninstall()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 700, minHeight: 500)
    }
}

private struct UninstallPlanWrapper: Identifiable {
    var id: String { items.map(\.id).joined(separator: ",") }
    let items: [InstalledApp]
}
