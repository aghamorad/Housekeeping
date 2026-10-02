import AppKit
import SwiftUI

struct QuarantineView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style
    @State private var entries: [QuarantineEntry] = []
    @State private var transactions: [CleanupTransaction] = []
    @State private var pendingPermanentDeletion: QuarantineEntry?
    /// Which half of the same question the sheet is answering: where is my stuff
    /// now, or what has Housekeeping already done to this Mac.
    @State private var showingHistory = false

    private let engine = CleanupEngine()

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(showingHistory ? "What Housekeeping Has Done" : "Quarantine")
                        .font(style.titleFont)
                    Text(showingHistory
                         ? "Every cleanup it has run on this Mac, including the ones already finished with."
                         : "Nothing Housekeeping takes is deleted. It waits here until you say otherwise.")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                }
                Spacer()
                ThemeButton(
                    title: "Show Me the Folder",
                    systemImage: "folder",
                    help: "Opens the quarantine folder in Finder, so you can see it is a real folder you own."
                ) { engine.revealQuarantine() }
            }

            ThemePanel(padding: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("This is a normal folder, not a hidden one")
                        .font(style.labelFont)
                    Text(engine.quarantineURL.homeAbbreviatedPath)
                        .font(style.pathFont)
                        .textSelection(.enabled)
                    Text(engine.quarantineExists
                         ? "Open it in Finder any time. You can drag things back out by hand, exactly where they came from, even without Housekeeping."
                         : "You have not cleaned anything yet, so the folder does not exist. It appears the moment something first goes into quarantine. Show Me the Folder opens your home folder, one step away, and the folder will be right there once it exists.")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            switcher

            if showingHistory {
                historyList
            } else if entries.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Text("Nothing is in quarantine right now.")
                        .font(style.bodyFont)
                    Text("That means either you have not cleaned anything yet, or you already restored or deleted what was in here.")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(entries) { entry in
                            quarantineRow(entry)
                        }
                    }
                }
            }

            if let error = appState.lastErrorMessage {
                Text(error)
                    .font(style.smallFont)
                    .foregroundColor(style.negative)
                    .textSelection(.enabled)
            }

            HStack {
                Text(footerSummary)
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                Spacer()
                ThemeButton(title: "Done", isPrimary: true) { appState.showQuarantineManagement = false }
            }
        }
        .padding(16)
        .frame(minWidth: 760, minHeight: 540)
        .preferredColorScheme(style.isRetro ? .light : nil)
        .onAppear { reload() }
        .alert("Delete permanently?", isPresented: Binding(
            get: { pendingPermanentDeletion != nil },
            set: { if !$0 { pendingPermanentDeletion = nil } }
        )) {
            Button("Delete Permanently", role: .destructive) {
                guard let entry = pendingPermanentDeletion else { return }
                appState.permanentlyDeleteQuarantineEntries([entry])
                pendingPermanentDeletion = nil
                reload()
            }
            Button("Cancel", role: .cancel) { pendingPermanentDeletion = nil }
        } message: {
            if let entry = pendingPermanentDeletion {
                Text("Until now this was reversible. This is the one action that is not.\n\nIt deletes \(entry.size.humanReadable), originally from:\n\(entry.originalPath)\n\nAfter this there is no copy left for Housekeeping to put back.")
            }
        }
    }

    // MARK: - The two halves

    /// Two buttons rather than a segmented control: the same pair has to look
    /// right in Mac OS 9 as well as in Liquid Glass, and this is the one piece of
    /// chrome the app already has for both.
    private var switcher: some View {
        HStack(spacing: 8) {
            ThemeButton(
                title: "Waiting to Decide (\(entries.count))",
                isPrimary: !showingHistory,
                help: "Everything Housekeeping has moved out of the way and that you have not decided about yet. None of it is deleted."
            ) { showingHistory = false }

            ThemeButton(
                title: "Past Cleanups (\(transactions.count))",
                isPrimary: showingHistory,
                help: "Every cleanup Housekeeping has run on this Mac, including the ones you have already put back or deleted. It is read from the records kept next to the items, so it still knows about cleanups run before the app was last quit."
            ) { showingHistory = true }

            Spacer()

            AskHousekeeperButton(
                topic: screenTopic,
                closing: { appState.showQuarantineManagement = false },
                title: showingHistory ? "Ask About This History" : "Ask About Quarantine"
            )
        }
    }

    // MARK: - What the housekeeper is handed

    /// The half that is on screen, rather than both halves at once. The switcher
    /// decides what the reader is looking at, and the housekeeper is told the same
    /// thing — a question asked over the history should not be answered with a
    /// list of what is still waiting.
    private var screenTopic: HousekeeperTopic {
        showingHistory ? historyTopic : waitingTopic
    }

    private var waitingTopic: HousekeeperTopic {
        var facts: [String] = []
        facts.append("This is the Quarantine folder: \(engine.quarantineURL.homeAbbreviatedPath)")
        facts.append("Nothing Housekeeping takes is deleted. It is moved here and stays until the reader decides.")

        if entries.isEmpty {
            facts.append("Nothing is waiting here right now. Either nothing has been cleaned yet, or everything that was here has already been put back or deleted.")
        } else {
            facts.append("\(entries.count) item\(entries.count == 1 ? "" : "s") are waiting here, \(entries.reduce(0) { $0 + $1.size }.sizeDescription) in total, none of it deleted.")
            let shown = entries.prefix(20)
            for entry in shown {
                facts.append("- \(entry.originalPath) — \(entry.category), \(entry.size.humanReadable), moved on \(entry.date.formatted(date: .abbreviated, time: .omitted))")
            }
            if entries.count > shown.count {
                facts.append("- and \(entries.count - shown.count) more, which are not listed here.")
            }
            facts.append("Every one of these can be put back to the exact path it came from, or deleted permanently — and deleting permanently is the one action here that cannot be undone.")
        }

        return HousekeeperTopic(
            id: "quarantine-waiting",
            title: "Quarantine",
            label: entries.isEmpty ? "Empty" : "\(entries.count) waiting",
            tone: entries.isEmpty ? .good : .plain,
            facts: facts,
            opener: entries.isEmpty
                ? "How does Quarantine work, and what happens to things I clean?"
                : "Walk me through what is sitting in Quarantine and what my choices are for it."
        )
    }

    private var historyTopic: HousekeeperTopic {
        var facts: [String] = []
        facts.append("This is Housekeeping's own record of every cleanup it has run on this Mac, including ones already put back or deleted.")
        facts.append("The record is written next to the items in the Quarantine folder before a single file moves, so quitting or reinstalling Housekeeping does not lose it.")

        if transactions.isEmpty {
            facts.append("There are no cleanups recorded yet, so Housekeeping has not moved anything on this Mac.")
        } else {
            let moved = transactions.reduce(0) { $0 + $1.totalSize }
            let waiting = transactions.reduce(0) { $0 + $1.waitingSize }
            facts.append("\(transactions.count) cleanup\(transactions.count == 1 ? "" : "s") recorded, \(moved.sizeDescription) moved in total\(waiting > 0 ? ", of which \(waiting.sizeDescription) is still waiting in Quarantine" : ", none of it still waiting").")
            for transaction in transactions.prefix(15) {
                facts.append("- \(transaction.date.formatted(date: .abbreviated, time: .shortened)): \(transaction.items.count) item\(transaction.items.count == 1 ? "" : "s"), \(transaction.totalSize.humanReadable)")
            }
            if transactions.count > 15 {
                facts.append("- and \(transactions.count - 15) more, which are not listed here.")
            }
            facts.append("An item's state is one of: waiting in Quarantine, put back, deleted permanently, gone from the folder by hand, or never moved because the cleanup stopped first.")
        }

        return HousekeeperTopic(
            id: "quarantine-history",
            title: "What Housekeeping has done",
            label: transactions.isEmpty ? "Nothing yet" : "\(transactions.count) cleanup\(transactions.count == 1 ? "" : "s")",
            tone: .plain,
            facts: facts,
            opener: "Go through what Housekeeping has cleaned on my Mac, and tell me how I read this."
        )
    }

    /// One item still waiting, as the housekeeper is handed it.
    private func topic(for entry: QuarantineEntry) -> HousekeeperTopic {
        var facts: [String] = []
        facts.append("This item is waiting in Quarantine, so it has been moved but not deleted.")
        facts.append("It came from: \(entry.originalPath)")
        facts.append("It is stored now at: \(entry.quarantinePath)")
        facts.append("Size: \(entry.size.humanReadable). Kind: \(entry.category). From: \(entry.appName ?? "an application Housekeeping cannot name"). Moved on \(entry.date.formatted(date: .abbreviated, time: .shortened)).")
        facts.append("Putting it back returns it to the exact path it came from. Deleting it permanently is the one action in Quarantine that cannot be undone.")

        return HousekeeperTopic(
            id: "quarantine-entry-\(entry.quarantinePath)",
            title: entry.originalPath,
            label: "Waiting in Quarantine",
            tone: .plain,
            facts: facts,
            opener: "What is this, and what happens if I put it back or delete it?"
        )
    }

    /// One batch from the history.
    private func topic(for transaction: CleanupTransaction) -> HousekeeperTopic {
        var facts: [String] = []
        facts.append("This is one cleanup batch, run on \(transaction.date.formatted(date: .abbreviated, time: .shortened)).")
        facts.append("It moved \(transaction.items.count) item\(transaction.items.count == 1 ? "" : "s"), \(transaction.totalSize.humanReadable) in total.")
        if transaction.waitingCount > 0 {
            facts.append("\(transaction.waitingCount) of them are still waiting in Quarantine, \(transaction.waitingSize.sizeDescription), and can be put back.")
        } else {
            facts.append("None of them are still waiting: each has been put back, deleted permanently, or is no longer in the folder.")
        }
        for item in transaction.items.prefix(15) {
            facts.append("- \(item.name) — \(stateLabel(item.state)), \(item.size.humanReadable). \(stateExplanation(item.state))")
        }
        if transaction.items.count > 15 {
            facts.append("- and \(transaction.items.count - 15) more, which are not listed here.")
        }

        return HousekeeperTopic(
            id: "quarantine-batch-\(transaction.id)",
            title: "Cleanup of \(transaction.date.formatted(date: .abbreviated, time: .omitted))",
            label: "\(transaction.items.count) item\(transaction.items.count == 1 ? "" : "s")",
            tone: transaction.canBePutBack ? .caution : .plain,
            facts: facts,
            opener: "What did this cleanup do, and can I get any of it back?"
        )
    }

    private var footerSummary: String {
        if showingHistory {
            guard !transactions.isEmpty else { return "No cleanups recorded yet." }
            let recorded = "\(transactions.count) cleanup\(transactions.count == 1 ? "" : "s") recorded"
            let waiting = transactions.reduce(0) { $0 + $1.waitingSize }
            let moved = transactions.reduce(0) { $0 + $1.totalSize }
            if waiting > 0 {
                return "\(recorded) · \(waiting.sizeDescription) still waiting out of \(moved.sizeDescription) moved in total"
            }
            if moved > 0 {
                return "\(recorded) · \(moved.sizeDescription) moved in total, none of it still waiting"
            }
            return "\(recorded), and none of them moved anything"
        }
        return entries.isEmpty
            ? "Nothing waiting here."
            : "\(entries.count) item\(entries.count == 1 ? "" : "s") waiting · \(entries.reduce(0) { $0 + $1.size }.sizeDescription), none of it deleted"
    }

    // MARK: - History

    private var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                legend
                if transactions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Housekeeping has not cleaned anything yet.")
                            .font(style.bodyFont)
                        Text("When it does, every batch is written down here before a single file moves — which files, what they were, how big, and where they went. Because that record lives next to the items in the Quarantine folder rather than inside the app, quitting Housekeeping or reinstalling it does not lose the history.")
                            .font(style.smallFont)
                            .foregroundColor(style.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
                ForEach(transactions) { transaction in
                    transactionCard(transaction)
                }
            }
        }
    }

    /// The five outcomes explained once, in one place, instead of repeating a
    /// sentence on every row. Each line is also what the matching row's tooltip
    /// says, so the two can never disagree.
    private var legend: some View {
        ThemePanel(padding: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("How to read this")
                    .font(style.labelFont)
                ForEach(CleanupTransaction.ItemState.allCases, id: \.self) { state in
                    HStack(alignment: .top, spacing: 8) {
                        Text(stateLabel(state))
                            .font(style.smallFont)
                            .foregroundColor(stateColor(state))
                            .frame(width: 118, alignment: .leading)
                        Text(stateExplanation(state))
                            .font(style.smallFont)
                            .foregroundColor(style.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func transactionCard(_ transaction: CleanupTransaction) -> some View {
        ThemePanel(padding: 10) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(transaction.date.formatted(date: .abbreviated, time: .shortened))
                        .font(style.labelFont)
                    Spacer()
                    Text("\(transaction.items.count) item\(transaction.items.count == 1 ? "" : "s") · \(transaction.totalSize.humanReadable)")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                }

                Text(transactionSummary(transaction))
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(transaction.items.prefix(15)) { item in
                        historyRow(item)
                    }
                }

                if transaction.items.count > 15 {
                    Text("…and \(transaction.items.count - 15) more in this batch. “Show Me This Batch in Finder” opens the folder holding every one of them.")
                        .font(style.smallFont)
                        .foregroundColor(style.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    ThemeButton(
                        title: "Show Me This Batch in Finder",
                        systemImage: "folder",
                        help: "Opens the Quarantine folder at this batch, so you can see the items it moved and read the record for yourself."
                    ) { engine.revealTransaction(transaction) }

                    if transaction.canBePutBack {
                        ThemeButton(
                            title: "Put All of It Back",
                            systemImage: "arrow.uturn.backward",
                            isPrimary: true,
                            help: "Returns the \(transaction.waitingCount) item\(transaction.waitingCount == 1 ? "" : "s") from this batch that are still waiting, each to the exact path it came from. Anything already put back or deleted is left as it is."
                        ) { putBack(transaction) }
                    }
                    AskHousekeeperButton(
                        topic: topic(for: transaction),
                        closing: { appState.showQuarantineManagement = false },
                        title: "Ask about this cleanup",
                        help: "Opens the housekeeper on this one batch. It explains what this cleanup moved and what each item's state means; Housekeeping is the one that decides.",
                        compact: true
                    )
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func historyRow(_ item: CleanupTransaction.Item) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(item.name)
                .font(style.smallFont)
                .foregroundColor(style.text)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(stateLabel(item.state))
                .font(style.smallFont)
                .foregroundColor(stateColor(item.state))
                .fixedSize()
                .help(stateExplanation(item.state))
            Spacer()
            Text(item.size.humanReadable)
                .font(style.smallFont)
                .foregroundColor(style.secondaryText)
                .fixedSize()
        }
    }

    private func transactionSummary(_ transaction: CleanupTransaction) -> String {
        var parts: [String] = []
        if transaction.waitingCount > 0 {
            parts.append("\(transaction.waitingCount) still waiting (\(transaction.waitingSize.humanReadable))")
        }
        if transaction.putBackCount > 0 { parts.append("\(transaction.putBackCount) put back") }
        if transaction.deletedCount > 0 { parts.append("\(transaction.deletedCount) deleted for good") }
        if transaction.goneCount > 0 { parts.append("\(transaction.goneCount) no longer in the folder") }
        if transaction.neverMovedCount > 0 { parts.append("\(transaction.neverMovedCount) never moved") }
        guard !parts.isEmpty else { return "This batch is empty." }
        if transaction.waitingCount == 0 {
            return "Nothing from this batch is left in Quarantine: " + parts.joined(separator: " · ")
        }
        return parts.joined(separator: " · ")
    }

    private func putBack(_ transaction: CleanupTransaction) {
        Task {
            await appState.restoreTransaction(transaction)
            reload()
        }
    }

    private func stateLabel(_ state: CleanupTransaction.ItemState) -> String {
        switch state {
        case .waiting: return "Still waiting"
        case .putBack: return "Put back"
        case .deletedForever: return "Deleted for good"
        case .gone: return "Not in the folder"
        case .neverMoved: return "Never moved"
        }
    }

    private func stateColor(_ state: CleanupTransaction.ItemState) -> Color {
        switch state {
        case .waiting: return style.caution
        case .putBack: return style.positive
        case .deletedForever: return style.negative
        case .gone, .neverMoved: return style.secondaryText
        }
    }

    private func stateExplanation(_ state: CleanupTransaction.ItemState) -> String {
        switch state {
        case .waiting:
            return "It is sitting in the Quarantine folder right now. Putting it back returns it to the exact path it came from."
        case .putBack:
            return "You already returned it, so it is back where it was."
        case .deletedForever:
            return "You deleted it permanently. There is no copy left anywhere, and this one cannot be undone."
        case .gone:
            return "The record says this was moved into Quarantine, but the folder does not have it any more. That usually means it was deleted by hand in Finder."
        case .neverMoved:
            return "The cleanup stopped or failed before this one was touched, so it should be exactly where it was."
        }
    }

    private func quarantineRow(_ entry: QuarantineEntry) -> some View {
        ThemePanel(padding: 10) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.originalPath)
                        .font(style.labelFont)
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Spacer()
                    Text(entry.size.humanReadable)
                        .font(style.smallFont)
                }
                Text("Stored at: \(entry.quarantinePath)")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Text("\(entry.category) · \(entry.appName ?? "Unclassified") · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                HStack {
                    ThemeButton(
                        title: "Reveal in Finder",
                        systemImage: "magnifyingglass",
                        help: "Opens Finder with this item selected, so you can see the file itself."
                    ) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.quarantinePath)])
                    }
                    AskHousekeeperButton(
                        topic: topic(for: entry),
                        closing: { appState.showQuarantineManagement = false },
                        title: "Ask what this is",
                        help: "Opens the housekeeper on this one item. It explains where it came from and what putting it back or deleting it would do; Housekeeping is the one that decides, and deleting for good is still yours to press.",
                        compact: true
                    )
                    ThemeButton(
                        title: "Put It Back",
                        systemImage: "arrow.uturn.backward",
                        isPrimary: true,
                        help: "Moves this item back to \(entry.originalPath), where it came from."
                    ) {
                        appState.restoreQuarantineEntry(entry)
                        reload()
                    }
                    Spacer()
                    ThemeButton(
                        title: "Delete Permanently",
                        systemImage: "trash",
                        help: "The only action here that cannot be undone."
                    ) { pendingPermanentDeletion = entry }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func reload() {
        entries = appState.quarantineEntries()
        transactions = appState.transactionHistory()
    }
}
