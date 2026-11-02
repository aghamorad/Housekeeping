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
    @Published var pendingUninstallPlan: [InstalledApp]? = nil

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
        if query.isEmpty { return apps }
        return apps.filter {
            $0.name.lowercased().contains(query) ||
            ($0.bundleIdentifier?.lowercased().contains(query) ?? false)
        }
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
                    Image(systemName: "app.badge.minus")
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
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search installed applications…", text: $model.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(style.border, lineWidth: 1))
            .frame(maxWidth: 340)

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
    }

    // MARK: - Apps List

    private var appsList: some View {
        VStack(spacing: 10) {
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
                    Text(app.url.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteCountFormatter.string(fromByteCount: app.totalSize, countStyle: .file))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    if !app.leftovers.isEmpty {
                        Text("\(app.leftovers.count) leftover items")
                            .font(.system(size: 11))
                            .foregroundStyle(style.accent)
                    } else {
                        Text("Clean bundle")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    model.toggleExpand(app)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Components & Associated Leftovers")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            VStack(spacing: 6) {
                // Main Application Bundle
                HStack {
                    Image(systemName: "app.fill")
                        .foregroundStyle(style.accent)
                        .frame(width: 18)
                    Text("Application Binary")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: app.size, countStyle: .file))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)

                // Leftovers
                ForEach(app.leftovers) { leftover in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(.orange)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(leftover.name)
                                .font(.system(size: 12, weight: .medium))
                            Text(leftover.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: leftover.size, countStyle: .file))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 12)
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
                ThemeButton(title: "Cancel") {
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
