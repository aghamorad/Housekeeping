// Housekeeping — what the housekeeper is talking about
//
// The housekeeper's window opens from a dozen places, and most of them are about
// something that is not a scanned folder: a Homebrew package whose name belongs
// to another copy of it, an app that is a version behind, a folder the disk
// browser has walked into, a transaction sitting in Quarantine. The model is only
// ever as good as the briefing underneath it, and a small model with no briefing
// invents one convincingly — the first build of this sheet described a folder
// that was not there.
//
// `FoundItem` and its verdict were the original answer to that, and they are
// still the right answer for the screens that are about a scanned path. This is
// the general shape beside it: a title, Housekeeping's own facts, and the
// question to open with. A screen that is not about a scanned path builds one of
// these and hands it over, and both the reader and the model get the same
// sentences — the strip above the model's prose is drawn from `facts`, and
// `facts` is what the model is given.
//
// Nothing here carries a verdict, because the verdict is Housekeeping's and
// these screens do not have one to give. `label` is a description — "Not
// working", "Out of date", "Nothing to fix" — and the model is told, as it
// always is, that it explains and does not decide.

import SwiftUI

struct HousekeeperTopic: Identifiable, Equatable {

    /// How serious the thing is, which decides the colour of the strip and
    /// nothing else. There is deliberately no "delete this" tone: a topic can
    /// describe a problem, and only Housekeeping's own policy can call something
    /// safe to remove.
    enum Tone: Equatable {
        case plain
        case caution
        case broken
        case good

        func colour(in style: UIStyle) -> Color {
            switch self {
            case .plain: return style.secondaryText
            case .caution: return style.caution
            case .broken: return style.negative
            case .good: return style.positive
            }
        }

        var icon: String {
            switch self {
            case .plain: return "info.circle"
            case .caution: return "exclamationmark.triangle"
            case .broken: return "xmark.octagon"
            case .good: return "checkmark.circle"
            }
        }
    }

    /// The same job `FoundItem.id` does: how the housekeeper tells that it has
    /// been handed a different subject and has to start again rather than carry
    /// on about the last one.
    let id: String

    /// The heading of the strip above the model's prose.
    let title: String

    /// The one word for it, shown beside the title. Nil when there is no word.
    let label: String?

    let tone: Tone

    /// Housekeeping's own account of this, one fact per line. These are the strip
    /// and they are the briefing, so the reader and the model are looking at the
    /// same sentences and neither can be told something the other was not.
    let facts: [String]

    /// What the model is asked first. A window that opens on an empty room makes
    /// the reader do the work of thinking of a question; a window that opens by
    /// explaining the thing on screen does not.
    let opener: String

    /// The briefing, assembled here rather than at the call sites so that every
    /// screen's topic is framed for the model the same way — the facts, then the
    /// instruction, and never the instruction mixed in among the facts.
    var briefing: String {
        var lines: [String] = []
        lines.append("The reader has opened you from a screen inside Housekeeping, and this is what that screen is about. This briefing was written by Housekeeping, and it is the only information you have about it.")
        lines.append("")
        lines.append("Subject: \(title)")
        if let label { lines.append("Housekeeping describes it as: \(label)") }
        lines.append("")
        lines.append(contentsOf: facts)
        lines.append("")
        lines.append("Explain this to the reader in plain English. Housekeeping decides what happens; you explain.")
        return lines.joined(separator: "\n")
    }

    /// The line the conversation opens with, in the housekeeper's own voice, so
    /// the window is never blank while the model is waking up.
    var openingLine: String {
        "\(title) — let me take a look at that one for you."
    }
}

/// The one button every screen in Housekeeping uses to reach the housekeeper.
///
/// It exists rather than each screen setting the two properties itself because
/// the two must not come apart: a sheet opened without a topic is a model with
/// nothing in front of it, and a small model with nothing invents something.
/// Setting them in the same turn, in one place, is what keeps that from
/// depending on every call site remembering.
///
/// The housekeeper's own window is a sheet on the main window, and a window
/// carries one sheet at a time. So the two kinds of caller are handled here
/// rather than at a dozen call sites:
///
/// - A screen that is itself a sheet passes `closing`. It steps aside first, and
///   the housekeeper is asked for on the next turn of the run loop, once the
///   closing sheet has actually gone. Without that the press does nothing at
///   all, silently, because the window already has a sheet on it.
/// - A screen in a window of its own — Settings is one — passes nothing. The
///   main window is brought forward first, since a sheet attached to a window
///   nobody can see has not been opened in any sense the reader would accept.
struct AskHousekeeperButton: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.uiStyle) private var style

    let topic: HousekeeperTopic

    /// How this screen steps out of the way so the housekeeper's sheet can be
    /// drawn. Nil from a screen that is not a sheet on the main window.
    var closing: (() -> Void)?

    var title: String = "Ask the Housekeeper"
    var isPrimary: Bool = false
    var help: String = "Opens the housekeeper on what is on this screen. It explains; Housekeeping is the one that decides."

    /// For the row a finding is on, where a drawn button next to the row's other
    /// controls would be louder than the thing it is about. The same action, said
    /// in the same voice as the row's other quiet links.
    var compact: Bool = false

    var body: some View {
        if compact {
            Button(action: open) {
                Text(title)
                    .font(style.smallFont)
                    .foregroundColor(style.accent)
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
        } else {
            ThemeButton(
                title: title,
                systemImage: "bubble.left.and.text.bubble.right",
                isPrimary: isPrimary,
                help: help,
                action: open
            )
        }
    }

    private func open() {
        appState.housekeeperTopic = topic

        if let closing {
            // The sheet that carried this button has to go before the next one is
            // asked for: a window carries one sheet at a time, and a second
            // request made in the same turn is one AppKit quietly drops.
            closing()
            Task { @MainActor in
                appState.showHousekeeper = true
            }
        } else {
            // Settings lives in a window of its own. The housekeeper's sheet is
            // attached to the main window, so that window has to be there first —
            // which may mean reopening it, if it was closed.
            WindowOpener.shared.withWindow {
                appState.showHousekeeper = true
            }
        }
    }
}
