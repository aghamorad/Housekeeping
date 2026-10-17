// Housekeeping — The screen for comparing two folders
//
// Two trees, one comparison, and the four answers it can give. The screen exists
// to make one thing hard to do by accident: writing over a library. Nothing here
// is ticked by itself except a copy, every row that takes something out of a
// tree starts unticked, and the button that does the work says what it will do
// before it does it.

import AppKit
import SwiftUI

struct ReconcileView: View {
    @Environment(\.uiStyle) private var style
    @Environment(\.dismiss) private var dismiss

    @StateObject private var model = ReconcileModel()
    @State private var bucket: ReconcileVerdict = .missingFromB
    @State private var showLibrariesWithoutASecondCopy = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            pairBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(minWidth: 940, maxWidth: 940, minHeight: 660)
        .background(style.windowBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Two Folders")
                    .font(style.titleFont)
                Text("Compares two folders that are meant to hold the same things, says what is missing from which side, and puts the missing piece where it belongs. It reads size and date first and only reads a file when those disagree.")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if model.isComparing {
                ThemeButton(title: "Stop", systemImage: "stop.circle", help: "Stops reading. What has been found so far is kept.") {
                    model.stop()
                }
            } else {
                ThemeButton(
                    title: "Compare",
                    systemImage: "arrow.left.arrow.right",
                    isPrimary: model.selectedPair != nil,
                    isEnabled: model.selectedPair != nil,
                    help: model.selectedPair.map { "Reads \($0.sideAName) and \($0.sideBName) and reports the difference. It changes nothing." } ?? "Choose a pair first."
                ) { model.compare() }
            }
        }
        .padding(14)
    }

    // MARK: - Which pair

    private var pairBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("", selection: $model.selectedPairID) {
                    ForEach(model.pairs) { pair in
                        Text(pair.label).tag(pair.id as String?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)

                ThemeButton(title: "Two More Folders…", systemImage: "plus", help: "Adds a pair that is not on the list. It starts out only reporting — nothing is copied until you set a direction.") {
                    model.addPair()
                }
                ThemeButton(title: "What Has No Second Copy", systemImage: "exclamationmark.shield", help: "The libraries the record says live in one place only. Nothing on this Mac can tell you that — it is a list to read and correct.") {
                    showLibrariesWithoutASecondCopy.toggle()
                }
                Spacer()
                Text("\(model.pairs.count) pair\(model.pairs.count == 1 ? "" : "s")")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
            }

            if showLibrariesWithoutASecondCopy { singleCopyPanel }

            if let binding = pairBinding {
                pairPanel(binding)
            }

            if let failure = model.loadFailureNote {
                Text(failure)
                    .font(style.smallFont)
                    .foregroundStyle(style.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// The pair being shown, as something the pickers below can write back to.
    private var pairBinding: Binding<FolderPair>? {
        guard let pair = model.selectedPair else { return nil }
        return Binding(
            get: { model.selectedPair ?? pair },
            set: { model.update($0) }
        )
    }

    private func pairPanel(_ binding: Binding<FolderPair>) -> some View {
        ThemePanel(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text(binding.wrappedValue.summary)
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                sideRow(name: binding.wrappedValue.sideAName, path: binding.wrappedValue.sideAPath, side: .a)
                sideRow(name: binding.wrappedValue.sideBName, path: binding.wrappedValue.sideBPath, side: .b)

                HStack(spacing: 14) {
                    Picker("Writing", selection: binding.direction) {
                        ForEach(ReconcileDirection.allCases, id: \.self) { direction in
                            Text(direction.title).tag(direction)
                        }
                    }
                    .frame(maxWidth: 360)

                    Picker("Closed", selection: Binding(
                        get: { binding.wrappedValue.frozenSide },
                        set: { binding.wrappedValue.frozenSide = $0 }
                    )) {
                        Text("Neither side is closed").tag(ReconcileSide?.none)
                        Text("\(binding.wrappedValue.sideAName) is closed").tag(ReconcileSide?.some(.a))
                        Text("\(binding.wrappedValue.sideBName) is closed").tag(ReconcileSide?.some(.b))
                    }
                    .frame(maxWidth: 280)

                    if !binding.wrappedValue.isBuiltIn {
                        ThemeButton(title: "Remove This Pair", help: "Takes the pair off the list. It reads and moves nothing.") {
                            model.removeSelectedPair()
                        }
                    }
                    Spacer()
                }

                if let frozen = binding.wrappedValue.frozenSide {
                    Text("\(binding.wrappedValue.name(of: frozen)) is closed, so nothing will be written to it. It is still worth comparing — knowing what is in a closed archive is not the same as adding to it. Set it back to open to let copies through.")
                        .font(style.smallFont)
                        .foregroundStyle(style.caution)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !binding.wrappedValue.exclusions.isEmpty {
                    Text("Present on one side on purpose, so its absence is not counted: \(binding.wrappedValue.exclusions.joined(separator: ", ")).")
                        .font(style.smallFont)
                        .foregroundStyle(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sideRow(name: String, path: String, side: ReconcileSide) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(style.labelFont)
                .frame(width: 90, alignment: .leading)
            Text(path.isEmpty ? "Not set" : path)
                .font(style.pathFont)
                .foregroundStyle(path.isEmpty ? style.caution : style.secondaryText)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            ThemeButton(title: "Change…", help: "Pick a different folder for this side.") {
                model.choosePath(for: side)
            }
        }
    }

    private var singleCopyPanel: some View {
        ThemePanel(padding: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Libraries with no second copy")
                    .font(style.labelFont)
                Text("This is the part a comparison cannot tell you. It can only say whether two folders agree; it cannot know that a folder has no twin at all. These are the ones the record says live in exactly one place, which is the real exposure — a pair that agrees is no help to a library with nothing to compare it against.")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(model.singleCopyLibraries) { library in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(library.name)
                            .font(style.bodyFont)
                        if !library.path.isEmpty {
                            Text(library.path)
                                .font(style.pathFont)
                                .foregroundStyle(style.secondaryText)
                                .textSelection(.enabled)
                        }
                        Text(library.note)
                            .font(style.smallFont)
                            .foregroundStyle(style.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - What was found

    @ViewBuilder
    private var content: some View {
        if model.isComparing {
            working
        } else if let report = model.report {
            if report.unreachableSide != nil {
                notThere(report)
            } else {
                results(report)
            }
        } else {
            firstRun
        }
    }

    private var working: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(model.progress?.phase ?? "Reading")
                .font(style.bodyFont)
            if let detail = model.progress?.detail {
                Text(detail)
                    .font(style.pathFont)
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: 560)
            }
            if let fraction = model.progress?.fraction {
                ProgressView(value: fraction)
                    .frame(maxWidth: 360)
            } else {
                ProgressView()
                    .frame(maxWidth: 200)
            }
            if let note = model.note {
                Text(note)
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var firstRun: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("Nothing has been compared yet.")
                .font(style.bodyFont)
            Text("Press Compare. Both folders are read and nothing else happens — no file is opened for its contents unless a size and a date disagree, and nothing is written until you tick a row and press the button at the bottom.")
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 480)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func notThere(_ report: ReconcileReport) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 34))
                .foregroundStyle(style.caution)
            Text(report.headline)
                .font(style.bodyFont)
            if let note = report.notes.first {
                Text(note)
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520)
            }
            Text("Comparing against a folder that is not there would call every file in the library missing, so the comparison stops instead. Plug the drive in and press Compare again.")
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func results(_ report: ReconcileReport) -> some View {
        VStack(spacing: 0) {
            headlineBar(report)
            Divider()
            Picker("", selection: $bucket) {
                Text("On \(report.sideAName) only — \(report.missingFromB.count)").tag(ReconcileVerdict.missingFromB)
                Text("On \(report.sideBName) only — \(report.missingFromA.count)").tag(ReconcileVerdict.missingFromA)
                Text("Differ — \(report.collisions.count)").tag(ReconcileVerdict.sameNameDifferentBytes)
                Text("Moved — \(report.moves.count)").tag(ReconcileVerdict.movedOrRenamed)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            Divider()
            findingsList(report)
        }
    }

    private func headlineBar(_ report: ReconcileReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: report.gapCount == 0 ? "checkmark.seal" : "exclamationmark.triangle")
                    .foregroundStyle(report.gapCount == 0 ? style.positive : style.caution)
                Text(report.headline)
                    .font(style.bodyFont)
                Spacer()
                Text("\(report.sideAName) \(report.sideACount) files · \(report.sideABytes.sizeDescription)   |   \(report.sideBName) \(report.sideBCount) files · \(report.sideBBytes.sizeDescription)")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
            }
            Text("\(report.identicalCount) files match on both sides\(report.moves.isEmpty ? "" : ", and \(report.moves.count) turned up again under a different name or folder — those are moves, not gaps")\(report.isComplete ? "." : ". This comparison did not finish, so it is a partial answer.")")
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(report.notes, id: \.self) { note in
                Text(note)
                    .font(style.smallFont)
                    .foregroundStyle(style.caution)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }

    private func findings(_ report: ReconcileReport) -> [ReconcileFinding] {
        switch bucket {
        case .missingFromB: return report.missingFromB
        case .missingFromA: return report.missingFromA
        case .sameNameDifferentBytes: return report.collisions
        case .movedOrRenamed: return report.moves
        case .identical: return []
        }
    }

    private func findingsList(_ report: ReconcileReport) -> some View {
        let rows = findings(report)
        return Group {
            if rows.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Text(emptyBucketMessage(report))
                        .font(style.bodyFont)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { finding in
                            findingRow(finding, report: report)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func emptyBucketMessage(_ report: ReconcileReport) -> String {
        switch bucket {
        case .missingFromB: return "Nothing is on \(report.sideAName) that \(report.sideBName) does not have."
        case .missingFromA: return "Nothing is on \(report.sideBName) that \(report.sideAName) does not have."
        case .sameNameDifferentBytes: return "No file has the same name and different contents on the two sides."
        case .movedOrRenamed: return "Nothing was found under a different name or in a different folder."
        case .identical: return ""
        }
    }

    private func findingRow(_ finding: ReconcileFinding, report: ReconcileReport) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: finding.verdict.iconName)
                .foregroundStyle(colour(for: finding.verdict))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.displayName)
                    .font(style.bodyFont)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(finding.folder)
                    .font(style.pathFont)
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let other = finding.otherRelativePath {
                    Text("Same contents as \(other)")
                        .font(style.smallFont)
                        .foregroundStyle(style.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if finding.verdict == .sameNameDifferentBytes {
                    Text("\(report.sideAName): \(finding.size.sizeDescription)\(dateSuffix(finding.modified))   ·   \(report.sideBName): \((finding.otherSize ?? 0).sizeDescription)\(dateSuffix(finding.otherModified))")
                        .font(style.smallFont)
                        .foregroundStyle(style.caution)
                }
            }
            Spacer()
            if finding.verdict != .sameNameDifferentBytes && finding.verdict != .movedOrRenamed {
                Text(finding.size.sizeDescription)
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
            }
            ThemeButton(title: "Show", help: "Reveals this on the side it is on, in Finder.") {
                model.reveal(absolutePath(for: finding, in: report))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    /// A finding records only where a file sits inside its side, so the side's
    /// own path has to be put back in front of it before Finder can be pointed
    /// at anything. A move is anchored to the side the walk started from, which
    /// is the same side every other gap is anchored to, so only a file that is
    /// on B alone needs B's path.
    private func absolutePath(for finding: ReconcileFinding, in report: ReconcileReport) -> String {
        let root = finding.verdict == .missingFromA ? report.sideBPath : report.sideAPath
        guard !root.isEmpty else { return "" }
        return (root as NSString).appendingPathComponent(finding.relativePath)
    }

    private func dateSuffix(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return ", \(formatter.string(from: date))"
    }

    private func colour(for verdict: ReconcileVerdict) -> Color {
        switch verdict {
        case .identical: return style.positive
        case .missingFromB, .missingFromA: return style.caution
        case .sameNameDifferentBytes: return style.negative
        case .movedOrRenamed: return style.accent
        }
    }

    // MARK: - The plan

    @ViewBuilder
    private var footer: some View {
        if let result = model.applyResult {
            appliedBar(result)
        } else if model.report != nil && !model.proposals.isEmpty {
            planBar
        } else {
            HStack {
                Text(model.note ?? "Nothing has been changed. Comparing only reads.")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
                    .lineLimit(2)
                Spacer()
                ThemeButton(title: "Done", isPrimary: true) { dismiss() }
            }
            .padding(12)
        }
    }

    private var planBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("What could be done")
                    .font(style.labelFont)
                Spacer()
                Text("\(model.selectedCount) of \(model.proposals.count) ticked")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
                ThemeButton(title: "Tick Only the Copies", help: "Copies are what the pair was set up for. Nothing that takes a file out of a tree gets ticked by this.") {
                    model.clearSelection()
                    model.selectAllCopies()
                }
                ThemeButton(title: "Tick Everything", help: "Includes the moves aside. Read those rows first — each one takes a file out of a folder and puts it in Quarantine.") {
                    model.selectEverythingActionable()
                }
                ThemeButton(
                    title: model.isApplying ? "Working…" : "Do the Ticked Ones",
                    systemImage: "arrow.right.circle",
                    isPrimary: true,
                    isEnabled: model.hasSomethingToDo && !model.isApplying,
                    help: "Copies the files that are missing, and moves the spare ones you ticked into Quarantine. Every copy is a real copy, never a link. Nothing is deleted."
                ) { model.apply() }
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.proposals) { proposal in
                        proposalRow(proposal)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding(12)
    }

    private func proposalRow(_ proposal: ReconcileProposal) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if proposal.action == .decide {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(style.caution)
                    .frame(width: 18)
            } else {
                ThemeCheckbox(
                    isChecked: proposal.isSelected,
                    help: proposal.action == .copy
                        ? "Copying this across closes the gap."
                        : "Ticking this takes the spare copy out of the folder and puts it in Quarantine, where it can be put back."
                ) { model.toggle(proposal) }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(proposal.action.title)
                        .font(style.labelFont)
                        .foregroundStyle(proposal.action == .decide ? style.caution : style.accent)
                    if !proposal.relativePath.isEmpty {
                        Text(proposal.displayName)
                            .font(style.bodyFont)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Text(proposal.reason)
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if proposal.size > 0 {
                Text(proposal.size.sizeDescription)
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
            }
        }
        .padding(.vertical, 6)
    }

    private func appliedBar(_ result: ReconcileApplyResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: result.failures.isEmpty ? "checkmark.seal" : "exclamationmark.triangle")
                    .foregroundStyle(result.failures.isEmpty ? style.positive : style.caution)
                Text(result.summaryLine)
                    .font(style.bodyFont)
                Spacer()
                ThemeButton(title: "Done", isPrimary: true) { dismiss() }
            }
            Text("Everything that changed is written down in a record, before it happened, so the run can be read back and undone without Housekeeping.")
                .font(style.smallFont)
                .foregroundStyle(style.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if !result.failures.isEmpty {
                ForEach(Array(result.failures.prefix(4).enumerated()), id: \.offset) { entry in
                    Text("\(entry.element.path) — \(entry.element.message)")
                        .font(style.smallFont)
                        .foregroundStyle(style.caution)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                if result.journalURL != nil {
                    ThemeButton(title: "Show the Record", systemImage: "doc.text", help: "Opens Finder at the file recording this run.") {
                        model.revealRunRecord()
                    }
                }
                ThemeButton(title: "Show All Past Runs") { model.revealRunsFolder() }
                Spacer()
                Text("Anything moved aside is in Quarantine, and can be put back from there.")
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText)
            }
        }
        .padding(12)
    }
}
