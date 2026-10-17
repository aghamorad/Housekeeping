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
    @State private var filter: Filter = .needsAttention
    /// Nil is every family. A selection narrows the same list rather than
    /// replacing it, so the picker above and the search on the right keep working.
    @State private var family: UpdateFamily?
    @State private var query: String = ""

    /// What the list is showing. "Needs updating" is where it opens, because that
    /// is the only reason anyone opens a screen called Update Apps — and the count
    /// in the other label is what says the rest of the Mac has not gone missing.
    private enum Filter: String, CaseIterable, Identifiable {
        case needsAttention
        case everything

        var id: String { rawValue }

        var title: String {
            switch self {
            case .needsAttention: return "Needs updating"
            case .everything: return "Everything"
            }
        }
    }

    /// Whether a row is worth someone's attention: there is a newer version to be
    /// had, or Housekeeping has found something wrong with the copy. Nothing else
    /// qualifies. In particular "could not check" is not an update waiting to
    /// happen — it is a question Housekeeping failed to answer, and two hundred of
    /// those in the opening view would bury the fifty that are real.
    private func isNoteworthy(_ row: UpdateRow) -> Bool {
        guard !row.isExcepted else { return false }
        if case .available = row.check { return true }
        // An unidentified copy that Housekeeping refused is the altered-signature
        // case: not an update, but the one thing on this screen a reader should
        // not be able to miss.
        if case .refused = row.check, row.channel == .unidentified { return true }
        return false
    }

    private func matches(_ row: UpdateRow) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        return [row.name, row.summary ?? "", row.detail]
            .contains { $0.localizedCaseInsensitiveContains(needle) }
    }

    /// The rows the picker, the search and the family strip leave on screen.
    private var shownRows: [UpdateRow] {
        appState.updateRows.filter { matches($0) && (filter == .everything || isNoteworthy($0)) }
    }

    private func rows(of family: UpdateFamily) -> [UpdateRow] {
        shownRows
            .filter { UpdateFamily.of($0.channel) == family }
            .sorted { a, b in
                if a.channel.order != b.channel.order { return a.channel.order < b.channel.order }
                // Within a family, the rows with something to do come first —
                // that is the only reason this screen was opened.
                if isNoteworthy(a) != isNoteworthy(b) { return isNoteworthy(a) }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
    }

    /// Every family worth a chip: the ones with rows under the current filter and
    /// search, plus the one selected even when it has none, so pressing a chip can
    /// never make that chip vanish under the pointer.
    private var familiesOnScreen: [(family: UpdateFamily, rows: [UpdateRow])] {
        UpdateFamily.allCases.compactMap { candidate in
            let rows = rows(of: candidate)
            guard !rows.isEmpty || family == candidate else { return nil }
            return (candidate, rows)
        }
    }

    private var groups: [(family: UpdateFamily, rows: [UpdateRow])] {
        familiesOnScreen.filter { family == nil || $0.family == family }
    }

    private var noteworthyCount: Int {
        appState.updateRows.filter { matches($0) && isNoteworthy($0) }.count
    }

    private var totalCount: Int {
        appState.updateRows.filter { matches($0) }.count
    }

    private static func wasNotChecked(_ row: UpdateRow) -> Bool {
        if case .unknown = row.check { return true }
        return false
    }

    /// The one fact the picker beside it cannot supply: how much of the list
    /// Housekeeping never reached an answer about. The picker already carries the
    /// other two counts, so repeating them here would put two different numbers
    /// for "needs attention" a centimetre apart.
    private var summaryLine: String {
        let unchecked = appState.updateRows
            .filter { matches($0) && !$0.isExcepted }
            .filter(Self.wasNotChecked).count

        let installed = "\(totalCount) installed"
        guard unchecked > 0 else { return "\(installed) · every one checked" }
        return "\(installed) · \(unchecked) it could not check"
    }

    private var selectedCount: Int {
        appState.updateRows.filter { $0.isSelected && $0.canUpdate && $0.channel.canInstall }.count
    }

    /// The rows a group heading's tick box stands for: the ones Housekeeping can
    /// finish, in the list as it is filtered on screen.
    private func selectableRows(_ rows: [UpdateRow]) -> [UpdateRow] {
        rows.filter { $0.canUpdate && $0.channel.canInstall }
    }

    /// Everything Select all and Select none act on — the rows the list is showing
    /// right now, after the search and the filter, rather than the whole Mac. A
    /// button that ticked things the reader cannot see would be doing more than
    /// the screen says it does.
    private var visibleSelectableIDs: [String] {
        groups.flatMap { selectableRows($0.rows).map(\.id) }
    }

    private var visibleCount: Int {
        groups.reduce(0) { $0 + $1.rows.count }
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            ThemePanel(padding: 10) { toolbar }

            if appState.updateIsReading {
                readingState
            } else if visibleCount == 0 {
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
                Text("Every application and Homebrew package on this Mac, what each one actually is, and whether it is out of date.")
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

    /// What the list is showing, and how to look through it. The explanation of
    /// the grouping lives in each group's own heading, one line at a time, rather
    /// than in a paragraph pinned above everything: a reader who has to scroll past
    /// the same six lines on every visit stops reading them, and the line that
    /// mattered was one of the six.
    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("Show", selection: $filter) {
                    Text("\(Filter.needsAttention.title) (\(noteworthyCount))")
                        .tag(Filter.needsAttention)
                    Text("\(Filter.everything.title) (\(totalCount))")
                        .tag(Filter.everything)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)

                TextField("Search by name", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)

                Spacer()

                if !appState.updateIsReading {
                    Text(summaryLine)
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                }
            }
            let families = familiesOnScreen
            if families.count > 1 || family != nil {
                HStack(spacing: 6) {
                    familyChip(
                        "All",
                        symbol: "square.grid.2x2.fill",
                        count: shownRows.count,
                        isOn: family == nil
                    ) { family = nil }
                    ForEach(families, id: \.family) { pair in
                        familyChip(
                            pair.family.title,
                            symbol: pair.family.symbol,
                            count: pair.rows.count,
                            isOn: family == pair.family
                        ) {
                            family = family == pair.family ? nil : pair.family
                        }
                    }
                    Spacer()
                }
            }
            ForEach(appState.updateNotes, id: \.self) { note in
                Text(note)
                    .font(style.smallFont)
                    .foregroundColor(style.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A text button for the two bulk selections. Plain rather than a full
    /// `ThemeButton` because they sit in a toolbar line whose subject is the list,
    /// not them — and because the group headings already carry the same control.
    private func selectionButton(
        _ title: String,
        help: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(style.smallFont)
                .underline()
                .foregroundColor(enabled ? style.accentLifted : style.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(title)
    }

    /// One family, as a chip. Not a segmented control: there can be five families
    /// and the counts change with every check, and a capsule reads as a thing to
    /// press rather than as a row of exclusive tabs.
    private func familyChip(
        _ title: String,
        symbol: String,
        count: Int,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(style.smallFont)
                Text("\(count)")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
            }
            .foregroundColor(isOn ? style.text : style.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(isOn ? style.rowSelection : style.rowBackground))
            .overlay(
                Capsule().stroke(style.border.opacity(isOn ? 0.7 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(isOn ? "Showing only \(title). Press again to show every family." : "Show only \(title).")
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

    /// Shown when the list has nothing to draw. The message has to name the real
    /// reason: an empty pane under a search that *did* match something, with the
    /// picker beside it counting those matches, would otherwise send the reader off
    /// to clear a search that was working.
    private var emptyState: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return VStack(spacing: 6) {
            Spacer()
            if appState.updateRows.isEmpty {
                Text("Nothing came back to list.")
                    .font(style.bodyFont)
                Text("Either every source was quiet, or the reading did not finish. Press Recheck to try again.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            } else if totalCount == 0 {
                Text("Nothing matches “\(trimmed)”.")
                    .font(style.bodyFont)
                Text("Clear the search to see the rest of the list.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            } else if trimmed.isEmpty {
                Text("Nothing needs updating.")
                    .font(style.bodyFont)
                Text("None of the \(totalCount) things installed here has a newer version that Housekeeping can see.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            } else {
                Text("Nothing matching “\(trimmed)” needs updating.")
                    .font(style.bodyFont)
                Text("The \(totalCount) that match are up to date, or could not be checked.")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            // The pane is otherwise a dead end: the thing to look at is one
            // filter away, and the reader should not have to work out that the
            // picker above is the way to it.
            if filter == .needsAttention, totalCount > 0 {
                ThemeButton(
                    title: "Show all \(totalCount)",
                    help: "List everything that matches, including the things Housekeeping could not check."
                ) { filter = .everything }
                .padding(.top, 4)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(groups, id: \.family) { group in
                    familyGroup(group.family, group.rows)
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
            if !appState.updateIsReading {
                selectionButton(
                    "Select all",
                    help: "Tick every row the list is showing that Housekeeping can update. Groups it cannot finish are left alone.",
                    enabled: !visibleSelectableIDs.isEmpty && !appState.updateIsWorking
                ) { appState.setUpdateSelection(ids: visibleSelectableIDs, selected: true) }
                selectionButton(
                    "Select none",
                    help: "Untick every row in the list. Nothing is changed on the Mac — this only clears the ticks.",
                    enabled: visibleSelectableIDs.contains { id in
                        appState.updateRows.first { $0.id == id }?.isSelected == true
                    } && !appState.updateIsWorking
                ) { appState.setUpdateSelection(ids: visibleSelectableIDs, selected: false) }
            }
            Spacer()
            AskHousekeeperButton(
                topic: overviewTopic,
                closing: { appState.showUpdateList = false },
                title: "Ask About This List"
            )
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

    private func familyGroup(_ family: UpdateFamily, _ rows: [UpdateRow]) -> some View {
        let selectable = selectableRows(rows)
        let selected = selectable.filter(\.isSelected)
        let allSelected = !selectable.isEmpty && selected.count == selectable.count
        let partlySelected = !selected.isEmpty && !allSelected
        let needing = rows.filter(isNoteworthy).count
        // An altered copy in the unclear group is not "to update" — Housekeeping
        // will not touch it, and saying update there would promise the one thing
        // this group exists to refuse.
        let needingWording = family.channels.contains { $0.canInstall } ? "to update" : "to look at"

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                // The heading's tick box stands for every row below it. It is
                // drawn only where there is something Housekeeping can finish;
                // the App Store, macOS and unclear groups get the same dash they
                // get on their own rows.
                if selectable.isEmpty {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 12))
                        .foregroundColor(style.secondaryText)
                        .frame(width: 22, height: 22)
                        .help("Nothing in this group is updated by Housekeeping, so there is nothing to select.")
                } else {
                    ThemeCheckbox(
                        isChecked: allSelected,
                        isMixed: partlySelected,
                        help: allSelected
                            ? "Untick every row in this group."
                            : "Tick every row in this group that Housekeeping can update."
                    ) {
                        appState.setUpdateSelection(ids: selectable.map(\.id), selected: !allSelected)
                    }
                }
                Image(systemName: family.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(family.tint ?? style.secondaryText)
                Text(family.title)
                    .font(style.labelFont)
                    .foregroundColor(style.text)
                if needing == rows.count {
                    Text("\(needing) \(needingWording)")
                        .font(style.smallFont)
                        .foregroundColor(style.accent)
                } else {
                    Text("\(rows.count)")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                    if needing > 0 {
                        Text("· \(needing) \(needingWording)")
                            .font(style.smallFont)
                            .foregroundColor(style.accent)
                    }
                }
                // The method sentence is the group's contract. It lives on the ⓘ
                // rather than above the rows: five paragraphs of contract is what
                // turned this screen into something to be got past, and the reader
                // who wants the reason now has one place to ask instead of five
                // lines to skip.
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundColor(style.secondaryText)
                    .help(family.method)
                Spacer()
                // The same action for the whole group, without having to reach
                // the footer's Update All and hope it covers what was meant.
                if !selectable.isEmpty {
                    selectionButton(
                        selected.isEmpty ? "Update group" : "Update \(selected.count)",
                        help: selected.isEmpty
                            ? "Tick at least one row in this group first."
                            : "Update only the ticked rows in this group — \(selected.count) of \(selectable.count) it can finish.",
                        enabled: !selected.isEmpty && !appState.updateIsWorking && !appState.updateIsReading
                    ) { appState.runUpdateAll(in: Set(family.channels)) }
                }
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
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 9) {
                Group {
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
                }
                .padding(.top, 1)

                rowIcon(row)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .font(style.bodyFont)
                            .foregroundColor(style.text)
                            .lineLimit(1)
                        if !row.installedVersion.isEmpty {
                            Text(row.installedVersion)
                                .font(style.smallFont)
                                .foregroundColor(style.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    // What this is, before anything about its version. A reader who
                    // does not know what `dav1d` is cannot decide anything about it,
                    // and its version number is no help at all. When nothing on disk
                    // could describe it, the channel's own label stands in.
                    if let line = row.summary ?? (row.detail.isEmpty ? nil : row.detail) {
                        Text(line)
                            .font(style.smallFont)
                            .foregroundColor(style.secondaryText)
                            .lineLimit(1)
                    }
                    if let said = explanation(row) {
                        Text(said)
                            .font(style.smallFont)
                            .foregroundColor(row.check.isUnknown ? style.caution : style.secondaryText)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(row.check.shortLabel)
                        .font(style.smallFont)
                        .foregroundColor(checkColour(row.check))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let actionLabel, row.canUpdate {
                            ThemeButton(
                                title: actionLabel.title,
                                isEnabled: !appState.updateIsWorking && !appState.updateIsReading,
                                help: actionLabel.help
                            ) { appState.runUpdate(row) }
                        }
                        // One small control instead of a button per row. "Leave this
                        // alone for good" is a rare decision about a single row, and
                        // printing it on all fifty-five of them is most of what made
                        // this list feel like something to be got past.
                        Menu {
                            rowMenuItems(row)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 13))
                                .foregroundColor(style.secondaryText)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Everything else you can do with this row — ask the housekeeper, see where it came from, or leave it alone from now on.")
                        .accessibilityLabel("More options for \(row.name)")
                    }
                }
            }

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
                .padding(.leading, 41)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        // The same list again on a right-click, because that is where a reader
        // looks for the thing that is not a button, and the ellipsis above is what
        // tells them there is one.
        .contextMenu { rowMenuItems(row) }
    }

    /// What the housekeeper is handed when it is opened from this screen. Every
    /// fact here is a sentence this screen already says, so the model cannot be
    /// told something the reader cannot see above it.
    private var overviewTopic: HousekeeperTopic {
        var facts: [String] = []

        if appState.updateIsReading {
            facts.append("Housekeeping is still reading the list. It walks the applications on this Mac, asks Homebrew what it knows, and reads the update feeds — so the counts are not final yet.")
        } else if totalCount == 0 {
            facts.append("Housekeeping found nothing to list. That will be either a filter hiding everything or a reading that did not return anything.")
        } else {
            facts.append("The list is showing \(totalCount) installed thing\(totalCount == 1 ? "" : "s"), of which \(noteworthyCount) need\(noteworthyCount == 1 ? "s" : "") attention — a newer version to be had, or a copy Housekeeping found something wrong with.")
            facts.append(summaryLine)
            for group in groups {
                facts.append("- \(group.family.title): \(group.rows.count). \(group.family.method)")
            }
            // A family with nothing in it is still a question the reader can ask —
            // "what about the App Store ones?" arrived in testing and the model,
            // given no line for it, invented a reason. Its method is the answer,
            // and it is one sentence, so it is handed over even when empty.
            for family in UpdateFamily.allCases where !groups.contains(where: { $0.family == family }) {
                facts.append("- \(family.title): nothing in this list. \(family.method)")
            }
            if selectedCount > 0 {
                facts.append("\(selectedCount) row\(selectedCount == 1 ? " is" : "s are") ticked, meaning Update All would act on them.")
            } else {
                facts.append("Nothing is ticked, so Update All would do nothing.")
            }
            facts.append("Update All never touches the Mac App Store, macOS itself, or anything whose origin Housekeeping could not establish — those groups say so instead.")
            facts.append("Each group heading has its own tick box for the whole group and a button that updates just that group; Select all and Select none sit beside the ticked count at the bottom and act on what the list is showing.")
        }

        if let line = appState.updateSummaryLine {
            facts.append(line)
        }
        for outcome in appState.updateOutcomes {
            facts.append("- \(outcome.succeeded ? "Succeeded" : "Failed"): \(outcome.name) — \(outcome.message)")
        }

        return HousekeeperTopic(
            id: "update-overview",
            title: "Update Apps",
            label: appState.updateIsReading ? "Still reading" : "\(noteworthyCount) need\(noteworthyCount == 1 ? "s" : "") attention",
            tone: appState.updateIsReading ? .plain : (noteworthyCount > 0 ? .caution : .good),
            facts: facts,
            opener: appState.updateIsReading
                ? "What is this screen doing while it reads?"
                : "Go through this list with me — what actually needs updating, and what will you not touch?"
        )
    }

    /// One row, as the housekeeper is handed it.
    private func topic(for row: UpdateRow) -> HousekeeperTopic {
        var facts: [String] = []
        facts.append("Installed: \(row.installedVersion.isEmpty ? "version unknown" : row.installedVersion). The check says: \(row.check.shortLabel).")
        if let summary = row.summary { facts.append("What it is: \(summary)") }
        facts.append(row.detail)
        if case .available(let version, _) = row.check {
            facts.append("A newer version exists: \(version).")
        }
        if case .unknown(let reason) = row.check {
            facts.append("Housekeeping could not reach an answer: \(reason)")
        }
        if case .refused(let reason) = row.check {
            facts.append("Housekeeping will not update this copy: \(reason)")
        }
        facts.append("It came from: \(row.channel.title). \(row.channel.method)")
        if let said = explanation(row) { facts.append(said) }
        if let actionLabel = rowActionLabel(row), row.canUpdate {
            facts.append("What Housekeeping would run for this row: \(actionLabel.title). \(actionLabel.help)")
        } else if row.isExcepted {
            facts.append("This row is on the left-alone list, so Housekeeping does not offer it at all any more.")
        } else {
            facts.append("Housekeeping will not act on this row itself.")
        }
        if !row.evidence.isEmpty {
            facts.append("What the check was worked out from:")
            for item in row.evidence {
                facts.append("  \(item.finding) — \(item.source)")
            }
        }
        if let path = row.path { facts.append("On disk at: \(path)") }

        return HousekeeperTopic(
            id: "update-\(row.id)",
            title: row.name,
            label: row.check.shortLabel,
            tone: {
                if case .refused = row.check { return .broken }
                if case .available = row.check { return .caution }
                if case .unknown = row.check { return .caution }
                return .plain
            }(),
            facts: facts,
            opener: row.canUpdate
                ? "What is this, why does it need updating, and what would you actually run?"
                : "Why are you not updating this one?"
        )
    }

    /// Everything a row can be asked to do that is not "update it". Written once
    /// and used by both the ellipsis and the right-click, so the two can never
    /// drift into offering different things.
    @ViewBuilder
    private func rowMenuItems(_ row: UpdateRow) -> some View {
        // The same door the row used to print as a red link on every line, now in
        // the one menu the row has room for.
        Button("Ask the Housekeeper about this") {
            appState.housekeeperTopic = topic(for: row)
            appState.showUpdateList = false
            Task { @MainActor in appState.showHousekeeper = true }
        }
        if let path = row.path {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
        if !row.evidence.isEmpty {
            Button(expandedEvidence.contains(row.id) ? "Hide how this was worked out" : "How this was worked out") {
                toggleEvidence(row.id)
            }
        }
        Divider()
        if row.isExcepted {
            Button("Offer this again") { appState.offerUpdateAgain(row) }
        } else {
            Button("Ignore from now on") { appState.ignoreUpdate(row) }
        }
    }

    /// The row's own face: the application's real icon when the row has a bundle,
    /// and the family's glyph otherwise. A list of fifty-five identical rows reads
    /// as a block of text; a column of recognizable icons is read one at a time,
    /// which is the whole difference between a list a reader scans and a wall they
    /// scroll past.
    @ViewBuilder
    private func rowIcon(_ row: UpdateRow) -> some View {
        let family = UpdateFamily.of(row.channel)
        if let path = row.path, path.hasSuffix(".app") {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: family.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(family.tint ?? style.secondaryText)
                .frame(width: 20, height: 20)
        }
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

    /// Why Housekeeping will or will not act on this row — and nothing at all when
    /// the row already says it. "Up to date" in the right-hand column does not need
    /// a sentence under it repeating the same fact, and fifty-five of those
    /// sentences is what made this list a wall to be got past rather than a list to
    /// be read.
    ///
    /// What is left is the part that has to be right even when it is unwelcome
    /// news: a reason for standing still that a reader could not have worked out
    /// from the row alone. It never falls back on a cheerful default.
    private func explanation(_ row: UpdateRow) -> String? {
        if row.isExcepted {
            return "You have told Housekeeping to leave this one alone, so it is not offered. Right-click the row to put it back on offer."
        }
        switch row.check {
        case .checking:
            return "Still being checked."
        case .current:
            return nil
        case .available(let version, let download):
            // With an action, the status column already reads "\(version)
            // available" and the row carries its own Update button. Saying it a
            // third time in a sentence is noise.
            guard row.action == nil else { return nil }
            // Reached by a feed that named a version without offering anything
            // Housekeeping can verify and install.
            guard download != nil else {
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
