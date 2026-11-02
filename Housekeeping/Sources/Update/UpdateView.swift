// Housekeeping — Modern Application & Package Updater
//
// CleanMyMac-inspired updater. Spacious, fast, and intuitive.
// Handles Homebrew formulae & casks (with automated sudo escalation when needed),
// Mac App Store packages, and direct downloads. Includes Full Disk Access verification.

import SwiftUI
import AppKit

struct UpdateView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    @State private var filter: Filter = .needsAttention
    @State private var query: String = ""
    @State private var selectedFamily: UpdateFamily? = nil

    private enum Filter: String, CaseIterable, Identifiable {
        case needsAttention = "Updates Available"
        case everything = "All Installed"
        case homebrew = "Homebrew"
        case appStore = "App Store"

        var id: String { rawValue }
    }

    private func isNoteworthy(_ row: UpdateRow) -> Bool {
        guard !row.isExcepted else { return false }
        if case .available = row.check { return true }
        return false
    }

    private func matches(_ row: UpdateRow) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return [row.name, row.summary ?? "", row.detail]
            .contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    private var shownRows: [UpdateRow] {
        appState.updateRows.filter { row in
            guard matches(row) else { return false }
            switch filter {
            case .needsAttention:
                return isNoteworthy(row)
            case .everything:
                return true
            case .homebrew:
                return row.channel == .homebrewFormula || row.channel == .homebrewCask
            case .appStore:
                return row.channel == .macAppStore
            }
        }
    }

    private var noteworthyCount: Int {
        appState.updateRows.filter { isNoteworthy($0) }.count
    }

    private var totalCount: Int {
        appState.updateRows.count
    }

    private var selectedCount: Int {
        appState.updateRows.filter { $0.isSelected && $0.canUpdate && $0.channel.canInstall }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                fullDiskAccessBannerIfNeeded
                heroUpdateBanner
                filterAndSearchBar

                if appState.updateIsWorking {
                    runProgressBar
                }

                if appState.updateIsReading {
                    readingState
                } else if shownRows.isEmpty {
                    emptyState
                } else {
                    cardsList
                }

                if !appState.updateOutcomes.isEmpty {
                    outcomesPanel
                }

                footer
            }
            .padding(32)
            .frame(maxWidth: 1080, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { HousekeepingBackdrop(style: style) }
        .task {
            if appState.updateRows.isEmpty && !appState.updateIsReading && !appState.updateIsWorking {
                appState.startUpdateInventory()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 24))
                        .foregroundStyle(style.accent)
                    Text("App & Package Updates")
                        .font(style.isRetro ? style.titleFont : .system(size: 28, weight: .bold))
                }
                Text("Manage updates across Homebrew packages, Mac App Store apps, and system binaries.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ThemeButton(
                title: "Recheck Updates",
                systemImage: "arrow.clockwise",
                isEnabled: !appState.updateIsReading && !appState.updateIsWorking,
                help: "Re-query Homebrew and remote release feeds"
            ) {
                appState.startUpdateInventory()
            }
        }
    }

    // MARK: - Full Disk Access Banner

    @ViewBuilder
    private var fullDiskAccessBannerIfNeeded: some View {
        if !AppUpdateEngine.hasFullDiskAccess {
            HStack(spacing: 14) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Full Disk Access Recommended")
                        .font(.system(size: 13, weight: .bold))
                    Text("Granting Full Disk Access allows Housekeeping to update protected tools, run privileged casks, and inspect caches smoothly.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ThemeButton(
                    title: "Open Privacy Settings",
                    systemImage: "arrow.up.forward.app"
                ) {
                    AppUpdateEngine.openPrivacySettings()
                }
            }
            .padding(14)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.25), lineWidth: 1))
        }
    }

    // MARK: - Hero Update Banner

    private var heroUpdateBanner: some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(noteworthyCount > 0 ? style.accent.opacity(0.12) : Color.green.opacity(0.12))
                    .frame(width: 58, height: 58)
                Image(systemName: noteworthyCount > 0 ? "arrow.down.circle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(noteworthyCount > 0 ? style.accent : Color.green)
            }

            VStack(alignment: .leading, spacing: 4) {
                if noteworthyCount > 0 {
                    Text("\(noteworthyCount) Update\(noteworthyCount == 1 ? "" : "s") Ready to Install")
                        .font(.system(size: 18, weight: .bold))
                    Text("All packages are scanned, verified, and ready for immediate update.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    Text("All Applications & Packages Are Up to Date")
                        .font(.system(size: 18, weight: .bold))
                    Text("Every installed application and Homebrew bottle matches the newest available version.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if noteworthyCount > 0 {
                ThemeButton(
                    title: "Update All (\(noteworthyCount))",
                    systemImage: "sparkles",
                    isPrimary: true,
                    isEnabled: !appState.updateIsWorking && !appState.updateIsReading
                ) {
                    // Select all available updates and run
                    let availableIDs = appState.updateRows.filter { isNoteworthy($0) && $0.canUpdate && $0.channel.canInstall }.map(\.id)
                    appState.setUpdateSelection(ids: availableIDs, selected: true)
                    appState.runUpdateAll()
                }
            }
        }
        .padding(20)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(style.border, lineWidth: 1))
    }

    // MARK: - Filter and Search Bar

    private var filterAndSearchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(Filter.allCases, id: \.self) { f in
                    let isSelected = filter == f
                    let countLabel: String = {
                        switch f {
                        case .needsAttention: return " (\(noteworthyCount))"
                        case .everything: return " (\(totalCount))"
                        case .homebrew: return " (\(appState.updateRows.filter { $0.channel == .homebrewFormula || $0.channel == .homebrewCask }.count))"
                        case .appStore: return " (\(appState.updateRows.filter { $0.channel == .macAppStore }.count))"
                        }
                    }()

                    Button {
                        filter = f
                    } label: {
                        Text("\(f.rawValue)\(countLabel)")
                            .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(isSelected ? style.accent.opacity(0.12) : Color.clear, in: Capsule())
                            .foregroundStyle(isSelected ? style.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search apps…", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(style.border, lineWidth: 1))
            .frame(maxWidth: 240)
        }
    }

    // MARK: - Cards List

    private var cardsList: some View {
        VStack(spacing: 10) {
            ForEach(shownRows) { row in
                updateCard(row)
            }
        }
    }

    private func updateCard(_ row: UpdateRow) -> some View {
        HStack(spacing: 14) {
            if row.canUpdate && row.channel.canInstall {
                Toggle("", isOn: Binding(
                    get: { row.isSelected },
                    set: { _ in appState.toggleUpdateSelection(id: row.id) }
                ))
                .labelsHidden()
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.green)
                    .frame(width: 20)
            }

            Image(systemName: channelIcon(row.channel))
                .font(.system(size: 18))
                .foregroundStyle(style.accent)
                .frame(width: 32, height: 32)
                .background(style.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(row.name)
                        .font(.system(size: 14, weight: .bold))
                    Text(row.channel.title)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(channelBadgeColor(row.channel).opacity(0.12), in: Capsule())
                        .foregroundStyle(channelBadgeColor(row.channel))
                }

                HStack(spacing: 8) {
                    if !row.installedVersion.isEmpty {
                        Text("Current: v\(row.installedVersion)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if case .available(let newVer, _) = row.check {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(style.accent)
                        Text("New: v\(newVer)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            if row.canUpdate && row.channel.canInstall {
                ThemeButton(
                    title: "Update",
                    systemImage: "arrow.down.circle",
                    isPrimary: true,
                    isEnabled: !appState.updateIsWorking && !appState.updateIsReading
                ) {
                    appState.setUpdateSelection(ids: [row.id], selected: true)
                    appState.runUpdateAll()
                }
            } else if case .available = row.check {
                ThemeButton(
                    title: "Open Store",
                    systemImage: "arrow.up.forward.app"
                ) {
                    if let url = URL(string: "macappstore://showUpdatesPage") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .padding(14)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(row.isSelected ? style.accent : style.border, lineWidth: row.isSelected ? 1.5 : 1)
        )
    }

    private func channelIcon(_ channel: UpdateChannel) -> String {
        switch channel {
        case .homebrewFormula, .homebrewCask: return "shippingbox.fill"
        case .macAppStore: return "apple.logo"
        case .githubRelease: return "chevron.left.forwardslash.chevron.right"
        case .sparkleFeed: return "sparkle"
        default: return "app.fill"
        }
    }

    private func channelBadgeColor(_ channel: UpdateChannel) -> Color {
        switch channel {
        case .homebrewFormula, .homebrewCask: return .orange
        case .macAppStore: return .blue
        case .githubRelease: return .purple
        case .sparkleFeed: return .pink
        default: return .secondary
        }
    }

    // MARK: - Progress & Outcomes

    private var runProgressBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressBar(
                fraction: Double(appState.updateRunDone) / Double(max(appState.updateRunTotal, 1)),
                caption: "\(appState.updateRunDone) of \(appState.updateRunTotal) Updated",
                detail: appState.updateRunCurrent.map { "Installing \($0)… Privileged commands prompt automatically via macOS authorization." },
                height: 8
            )
        }
        .padding(16)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var readingState: some View {
        HStack(spacing: 14) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.updateReadTotal > 0
                     ? "Checking \(appState.updateReadDone) of \(appState.updateReadTotal) packages…"
                     : "Querying installed package feeds…")
                    .font(.system(size: 13, weight: .medium))
                Text("Reading Homebrew and application version tags asynchronously.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var outcomesPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Update Results")
                .font(.system(size: 13, weight: .bold))
            ForEach(appState.updateOutcomes) { outcome in
                HStack(spacing: 8) {
                    Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(outcome.succeeded ? .green : .orange)
                    Text(outcome.name)
                        .font(.system(size: 12, weight: .bold))
                    Text(outcome.message)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .background(style.rowBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 32))
                .foregroundStyle(.green)
            Text(filter == .needsAttention ? "All packages are up to date." : "No applications found.")
                .font(.system(size: 14, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if selectedCount > 0 {
                Text("\(selectedCount) item\(selectedCount == 1 ? "" : "s") selected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selectedCount > 0 {
                ThemeButton(
                    title: "Update Selected (\(selectedCount))",
                    systemImage: "arrow.down.circle",
                    isPrimary: true,
                    isEnabled: !appState.updateIsWorking && !appState.updateIsReading
                ) {
                    appState.runUpdateAll()
                }
            }
            ThemeButton(title: "Done") {
                appState.showUpdateList = false
            }
        }
        .padding(.top, 8)
    }
}
