import SwiftUI

/// The update sheet. It is organised by channel rather than by name, because the
/// channel is what decides everything a reader needs to know — whether Housekeeping
/// can finish the job, whether it has to ask someone else, and whether it should
/// be involved at all. A plain alphabetical list of applications would put a
/// system app, a store app, and a cask in one column and say nothing about any of
/// them.
///
/// Every row states what it found and, when it will not act, why. The "why" is
/// never a tooltip: a reason hidden behind a hover is a reason a reader will not
/// read, and the rows that cannot be updated are exactly the ones that need the
/// sentence.
struct UpdateView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    /// Which rows have their evidence unfolded. Kept here rather than on the row
    /// so it survives a rebuild of the list after an update finishes.
    @State private var expandedEvidence: Set<String> = []

    private var groups: [(channel: UpdateChannel, rows: [UpdateRow])] {
        UpdateChannel.allCases
            .sorted { $0.order < $1.order }
            .compactMap { channel in
                let rows = appState.updateRows.filter { $0.channel == channel }
                return rows.isEmpty ? nil : (channel, rows)
            }
    }

    private var selectedCount: Int {
        appState.updateRows.filter { $0.isSelected && $0.canUpdate && $0.channel.canInstall }.count
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            ThemePanel(padding: 10) { explanationPanel }

            if appState.updateIsReading {
                readingState
            } else if appState.updateRows.isEmpty {
                emptyState
            } else {
                list
            }

            if !appState.updateOutcomes.isEmpty {
                outcomesPanel
            }

            footer
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 560)
        .preferredColorScheme(style.isRetro ? .light : nil)
        // Opening the sheet is what starts the reading, because the answer is
        // only wanted when the screen is up — and the reading runs `brew` and
        // fetches feeds, which is not a thing to do in the background on launch.
        .task { appState.startUpdateInventory() }
        // Closing it mid-read stops the read, since nothing is on screen to show
        // the answer to. An update in progress is left alone: it changes the Mac,
        // and abandoning one half-way is the only way this screen could do harm.
        .onDisappear {
            if appState.updateIsReading { appState.cancelUpdateWork() }
        }
    }

    // MARK: - Header and footer

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Update Apps")
                    .font(style.titleFont)
                Text("Everything on this Mac that could be updated, sorted by where its updates come from.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }
            Spacer()
            ThemeButton(
                title: "Recheck",
                systemImage: "arrow.clockwise",
                isEnabled: !appState.updateIsReading && !appState.updateIsWorking,
                help: "Ask every source again. This only reads — Homebrew's list, the store, and the release feeds. Nothing is downloaded or changed by a check."
            ) { appState.startUpdateInventory() }
        }
    }

    private var explanationPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Why this is grouped this way")
                .font(style.labelFont)
            Text("Software does not arrive by one route. A Homebrew cask is a command and an answer; an App Store app belongs to the store and can only be asked; an app that came as a file has to be fetched and swapped. Each group below says in one line what Housekeeping does for it, and a row says in plain words why it will not act when it will not. Nothing here is updated until you tick it and press Update.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(appState.updateNotes, id: \.self) { note in
                Text(note)
                    .font(style.smallFont)
                    .foregroundColor(style.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var readingState: some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView()
            Text("Reading what is installed and asking each source for its newest version.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
            Text("This reads only. It runs Homebrew's own list command, reads each bundle's signature, and asks the release feeds — nothing is downloaded and nothing is changed.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            ThemeButton(
                title: "Stop",
                help: "Stop reading. Nothing has been changed, and the list simply stays as it is."
            ) { appState.cancelUpdateWork() }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("Nothing came back to list.")
                .font(style.bodyFont)
            Text("Either every source was quiet, or the reading did not finish. Press Recheck to try again.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(groups, id: \.channel) { group in
                    channelGroup(group.channel, group.rows)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var outcomesPanel: some View {
        ThemePanel(padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(appState.updateSummaryLine ?? "What happened")
                    .font(style.labelFont)
                ForEach(appState.updateOutcomes) { outcome in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(outcome.succeeded ? style.positive : style.caution)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(outcome.name)
                                .font(style.smallFont)
                                .foregroundColor(style.text)
                            Text(outcome.message)
                                .font(style.smallFont)
                                .foregroundColor(style.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(selectedCount == 0
                 ? "Nothing ticked. Tick a row in a group Housekeeping can finish, or press Done."
                 : "\(selectedCount) ticked, in groups Housekeeping can finish on its own.")
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
            Spacer()
            if appState.updateIsWorking {
                ThemeButton(
                    title: "Stop",
                    help: "Stop after the update in progress finishes. Anything already updated stays updated; nothing is rolled back by a Stop."
                ) { appState.cancelUpdateWork() }
            }
            ThemeButton(
                title: "Update All",
                systemImage: "arrow.down.circle",
                isPrimary: true,
                isEnabled: selectedCount > 0 && !appState.updateIsWorking && !appState.updateIsReading,
                help: selectedCount == 0
                    ? "Rows in the App Store, macOS, and unidentified groups cannot be updated here, so they are never included. Tick something in a group Housekeeping can finish."
                    : "Update the \(selectedCount) ticked row\(selectedCount == 1 ? "" : "s"). The App Store, macOS, and unidentified groups are never touched by this button."
            ) { appState.runUpdateAll() }
            ThemeButton(title: "Done", isPrimary: false) { appState.showUpdateList = false }
        }
    }

    // MARK: - One group

    private func channelGroup(_ channel: UpdateChannel, _ rows: [UpdateRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(channel.title)
                        .font(style.labelFont)
                        .foregroundColor(style.text)
                    Text("\(rows.count)")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                }
                // The method sentence is the group's contract, so it is written
                // out above the rows rather than hidden in a button's help text.
                Text(channel.method)
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(style.groupingBackground)

            ForEach(rows) { row in
                rowView(row)
                Rectangle().fill(style.border.opacity(0.3)).frame(height: 1)
            }
        }
        .overlay(
            Rectangle().stroke(style.border.opacity(0.5), lineWidth: 1)
        )
    }

    // MARK: - One row

    private func rowView(_ row: UpdateRow) -> some View {
        let actionLabel = rowActionLabel(row)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if row.canUpdate && row.channel.canInstall {
                    ThemeCheckbox(
                        isChecked: row.isSelected,
                        help: row.isSelected
                            ? "Untick this row. Nothing is updated for it."
                            : "Tick this row so Update All includes it."
                    ) { appState.toggleUpdateSelection(id: row.id) }
                } else {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 12))
                        .foregroundColor(style.secondaryText)
                        .frame(width: 22, height: 22)
                        // A tick box that Update All would then skip is worse than
                        // no tick box at all, so the ones it cannot finish say why
                        // here rather than leaving the reader to find out.
                        .help(row.channel.canInstall
                              ? "Housekeeping will not update this row. The reason is written under it."
                              : "\(row.channel.title) is a group Update All cannot finish on its own, so there is nothing to tick. Use this row's own button.")
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name)
                        .font(style.bodyFont)
                        .foregroundColor(style.text)
                        .lineLimit(1)
                    Text(row.detail)
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(row.installedVersion.isEmpty ? "version unknown" : row.installedVersion)
                        .font(style.bodyFont)
                        .foregroundColor(style.text)
                    Text(row.check.shortLabel)
                        .font(style.smallFont)
                        .foregroundColor(checkColour(row.check))
                }
                .frame(width: 150, alignment: .trailing)
            }

            HStack(alignment: .top, spacing: 10) {
                Text(explanation(row))
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.leading, 32)

            HStack(spacing: 8) {
                if !row.evidence.isEmpty {
                    Button {
                        toggleEvidence(row.id)
                    } label: {
                        Text(expandedEvidence.contains(row.id) ? "Hide how this was worked out" : "How this was worked out")
                            .font(style.smallFont)
                            .foregroundColor(style.accent)
                    }
                    .buttonStyle(.plain)
                }
                if let path = row.path {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting(
                            [row.action.flatMap { _ in URL(fileURLWithPath: path) } ?? URL(fileURLWithPath: path)]
                        )
                    } label: {
                        Text("Show in Finder")
                            .font(style.smallFont)
                            .foregroundColor(style.accent)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                if let actionLabel, row.canUpdate {
                    ThemeButton(
                        title: actionLabel.title,
                        isEnabled: !appState.updateIsWorking && !appState.updateIsReading,
                        help: actionLabel.help
                    ) { appState.runUpdate(row) }
                }
                if !row.isExcepted {
                    ThemeButton(
                        title: "Ignore from now on",
                        help: "Add this to the list Housekeeping stops offering. It updates nothing and deletes nothing — it only means this row stops being offered, on this and every later reading. You can take it off again in Settings."
                    ) { appState.ignoreUpdate(row) }
                } else {
                    Text("Ignored")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                }
            }
            .padding(.leading, 32)

            if expandedEvidence.contains(row.id), !row.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(row.evidence.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.finding)
                                .font(style.smallFont)
                                .foregroundColor(style.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.source)
                                .font(style.pathFont)
                                .foregroundColor(style.secondaryText)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(style.rowSelection.opacity(0.35))
                .padding(.leading, 32)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: - Words

    private func toggleEvidence(_ id: String) {
        if expandedEvidence.contains(id) {
            expandedEvidence.remove(id)
        } else {
            expandedEvidence.insert(id)
        }
    }

    private func checkColour(_ check: UpdateCheck) -> Color {
        switch check {
        case .checking: return style.secondaryText
        case .current: return style.positive
        case .available: return style.accent
        case .unknown: return style.caution
        case .refused: return style.secondaryText
        }
    }

    /// Why Housekeeping will or will not act on this row, in one plain sentence.
    /// This is the part that has to be right even when it is unwelcome news, so it
    /// never falls back on a cheerful default.
    private func explanation(_ row: UpdateRow) -> String {
        if row.isExcepted {
            return "You have told Housekeeping to stop offering this one."
        }
        if row.action != nil {
            switch row.check {
            case .available(let version, _):
                return "A newer version, \(version), is available."
            case .current:
                return "This is the newest version Housekeeping can see."
            default:
                break
            }
        }
        switch row.check {
        case .checking:
            return "Still being checked."
        case .current:
            return "This is the newest version Housekeeping can see."
        case .available(let version, let download):
            // Only a feed that names a version without offering anything
            // Housekeeping can install gets this far: Homebrew and the App Store
            // both answer without a download and are dealt with above, and a
            // pinned package comes back refused rather than available.
            if download == nil {
                return "\(version) is available, but the release offers no disk image or archive Housekeeping can verify, so it will not replace anything."
            }
            return "\(version) is available."
        case .unknown(let reason):
            return "Housekeeping could not find out: \(reason)"
        case .refused(let reason):
            return reason
        }
    }

    /// The per-row button, named for what it will actually do. A row whose only
    /// action is to open the store says so rather than saying "Update".
    private func rowActionLabel(_ row: UpdateRow) -> (title: String, help: String)? {
        guard let action = row.action else { return nil }
        switch action {
        case .brewPackage:
            return ("Update", "Run Homebrew's own upgrade for this package. Homebrew checks the checksum, so this is the safest kind of update in the list.")
        case .replaceBundle(let download):
            return ("Update", "Download \(download.url.lastPathComponent), check its signature against the copy you have, and swap it in. The copy you have now is kept until the new one is in place, and put back if anything fails.")
        case .appStoreUpgrade:
            return ("Update", "Ask the App Store's own tool to update this application.")
        case .openAppStoreUpdates:
            return ("Open App Store", "Open the App Store's Updates page. There is no command-line tool installed here to update this app directly, and only the store can honour its receipt.")
        }
    }
}
