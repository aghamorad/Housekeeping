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
    @Published var selectedAppURLs: Set<URL> = []
    @Published var expandedAppURLs: Set<URL> = []
    @Published var searchQuery: String = ""
    @Published var sortOption: AppSortOption = .sizeDescending
    @Published var filterOption: AppFilterOption = .all
    @Published var pendingUninstallPlan: [InstalledApp]? = nil

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
        guard !isScanning else { return }
        isScanning = true
        scanProgress = "Discovering applications…"

        Task.detached(priority: .userInitiated) { [weak self] in
            let results = Uninstaller.installed { _ in }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.apps = results
                self.isScanning = false
                self.scanProgress = ""
            }
        }
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

    func selectAllFiltered() {
        for app in filteredApps {
            selectedAppURLs.insert(app.url)
        }
    }

    func deselectAll() {
        selectedAppURLs.removeAll()
    }

    var selectedTotalSize: Int64 {
        apps.filter { selectedAppURLs.contains($0.url) }.reduce(0) { $0 + $1.totalSize }
    }

    func toggleSelection(_ app: InstalledApp) {
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
        let targets = apps.filter { selectedAppURLs.contains($0.url) }
        guard !targets.isEmpty else { return }
        pendingUninstallPlan = targets
    }

    func executeUninstall() {
        guard let targets = pendingUninstallPlan else { return }
        let paths = targets.flatMap { [$0.url.path] + $0.leftovers.map(\.url.path) }
        let engine = CleanupEngine()

        Task { @MainActor [weak self] in
            _ = try? await engine.quarantineRepairs(
                paths: paths,
                category: "App Uninstaller",
                reason: "Uninstalled \(targets.count) application(s)"
            )
            self?.selectedAppURLs.removeAll()
            self?.expandedAppURLs.removeAll()
            self?.pendingUninstallPlan = nil
            self?.startScan()
        }
    }
}

struct UninstallerModernView: View {
    @ObservedObject var model: UninstallerModel = .shared
    @Environment(\.uiStyle) private var style

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                searchAndActionBar

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
        .sheet(item: Binding(
            get: { model.pendingUninstallPlan.map { UninstallPlanWrapper(items: $0) } },
            set: { model.pendingUninstallPlan = $0?.items }
        )) { wrapper in
            uninstallConfirmationSheet(wrapper.items)
                .housekeepingSurface(style)
        }
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
                Text("Completely remove applications along with their hidden caches, containers, and leftovers.")
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

                // Row action buttons: See Leftovers + Direct Uninstall
                if !app.leftovers.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            model.toggleExpand(app)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isExpanded ? "chevron.up" : "folder.badge.gearshape")
                            Text(isExpanded ? "Hide" : "See Leftovers")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(style.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(style.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(style.accent.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Hide leftover components" : "Inspect and reveal the \(app.leftovers.count) leftover items in Finder")
                }

                // Direct 1-click uninstall
                Button {
                    model.selectedAppURLs = [app.url]
                    model.prepareUninstall()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Uninstall")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Uninstall \(app.name) and its leftovers")

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
    }

    private func leftoversDetail(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header summary bar
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.gearshape")
                        .foregroundStyle(style.accent)
                    Text("Associated Components & Leftovers (\(app.leftovers.count))")
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
        HStack(spacing: 14) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.scanProgress)
                    .font(.system(size: 13, weight: .medium))
                Text("Indexing application support files and container directories…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
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
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Confirm Complete App Removal")
                        .font(.system(size: 18, weight: .bold))
                    Text("The selected applications and all their components will be moved safely to Quarantine.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(targets) { app in
                        HStack {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                                .resizable()
                                .frame(width: 24, height: 24)
                            Text(app.name)
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: app.totalSize, countStyle: .file))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)

            Divider()

            HStack {
                ThemeButton(title: "Cancel", systemImage: "xmark") {
                    model.pendingUninstallPlan = nil
                }
                Spacer()
                ThemeButton(
                    title: "Uninstall & Move to Quarantine",
                    systemImage: "trash.fill",
                    isPrimary: true
                ) {
                    model.executeUninstall()
                }
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 380)
    }
}

private struct UninstallPlanWrapper: Identifiable {
    var id: String { items.map(\.id).joined(separator: ",") }
    let items: [InstalledApp]
}
