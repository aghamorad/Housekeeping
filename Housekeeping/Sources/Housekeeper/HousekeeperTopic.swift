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

extension HousekeeperTopic {

    /// The Routes screen's subject.
    ///
    /// Routes is the one screen here that changes the state of the machine while
    /// it is open: it connects and disconnects a VPN client over and over to see
    /// which of its routes actually carries traffic. So the facts lead with what
    /// it does to the connection rather than with what it measures — a reader who
    /// watches their connection drop and come back needs to be told that this is
    /// the test working, not something going wrong. The last fact is about what
    /// is left behind, because on this screen the answer is that almost nothing
    /// is: a file, and only when asked.
    ///
    /// The counts are handed in rather than read from a model, so this file stays
    /// data and the screen stays the one that knows how far along it is.
    static func routes(
        provider: String,
        running: Bool,
        tested: Int,
        total: Int,
        reachable: Int
    ) -> HousekeeperTopic {
        var facts: [String] = [
            "This screen tries the servers, protocols and ports a VPN client offers, one route at a time, and measures how well each one carries traffic.",
            "The interesting choice is usually the protocol and the port, which most clients make silently and never show. This screen tries the combinations instead of trusting the default.",
            "Trying one route at a time means the connection drops and comes back repeatedly while it runs. That is the test working, not a fault, and the client is left disconnected when it ends.",
            "It changes nothing else on the machine. It connects and disconnects the client and takes measurements. The one thing it can leave behind is a markdown log, and only if the reader turned that on.",
        ]

        if running {
            facts.append("A run is in progress against \(provider): \(tested) of \(total) routes tried so far, and \(reachable) of them carried traffic.")
        } else if tested > 0 {
            facts.append("The last run against \(provider) tried \(tested) routes, and \(reachable) of them carried traffic.")
        } else {
            facts.append("Nothing has been tried yet this visit. The client in use is \(provider).")
        }

        return HousekeeperTopic(
            id: running ? "routes-running" : "routes",
            title: running ? "The route test, running" : "Trying routes",
            label: running ? "\(tested) of \(total)" : nil,
            tone: .plain,
            facts: facts,
            opener: running
                ? "What is it doing to my connection right now, and will it leave the VPN on a server I did not pick?"
                : "What does this screen do, and what does it change on my Mac?"
        )
    }
}

// MARK: - The rooms in the menu bar panel

extension HousekeeperTopic {

    /// The readings are handed in as a snapshot rather than read from
    /// `SystemVitals` here, for the same reason the routes screen hands in its
    /// counts: the panel knows what it was showing when the reader pressed, and
    /// the topic has to be about that, not about a later tick that has already
    /// moved on. Everything else on this page is the teaching the panel itself is
    /// too small to carry.
    static func processor(_ snapshot: VitalsSnapshot) -> HousekeeperTopic {
        var facts: [String] = [
            "This is the share of the whole processor that was busy in the last second, added up across all \(snapshot.coreCount) cores. A reading of 30% on eight cores is about two and a half cores' worth of work.",
            "Short spikes are the machine doing something and then stopping. A figure that stays high while nothing visible is running is the case worth looking at.",
            "Each process's own figure is out of one core, so 100% is one core fully used and 200% is two.",
        ]

        if snapshot.processes.isEmpty {
            facts.append("At the last reading no process was using measurable processor time.")
        } else {
            let hands = snapshot.processes.prefix(4)
                .map { "\($0.name) at \(VitalsFormat.share($0.cpu))" }
                .joined(separator: ", ")
            facts.append("At the last reading the busiest hands were \(hands).")
        }

        facts.append("Housekeeping does not know what a process is or who installed it; the name comes from the process itself. That is why the panel offers to stop one only after showing you what it is doing.")

        return HousekeeperTopic(
            id: "room-processor",
            title: "The processor",
            label: VitalsFormat.percent(snapshot.cpu),
            tone: snapshot.cpu > 0.85 ? .caution : .plain,
            facts: facts,
            opener: "My processor reads \(VitalsFormat.percent(snapshot.cpu)) — what is using it, is that a lot, and should I do anything?"
        )
    }

    static func memory(_ snapshot: VitalsSnapshot) -> HousekeeperTopic {
        var facts: [String] = [
            "This figure counts memory apps are actively using, memory the system is holding and cannot page out, and memory it has compressed in RAM. It does not count files kept in memory as cache, which macOS drops when an app needs the room.",
            "A Mac keeps memory busy on purpose — free memory is memory doing nothing — so a high number is not by itself a problem. The reading that describes actual trouble is memory pressure, which this panel does not measure yet. Housekeeping can tell you what is holding memory, not whether the Mac is short of it.",
        ]

        if snapshot.memoryHogs.isEmpty {
            facts.append("At the last reading no process was holding more than about 8 MB on its own.")
        } else {
            let holders = snapshot.memoryHogs.prefix(5)
                .map { "\($0.name) holding \(VitalsFormat.megabytes($0.memory))" }
                .joined(separator: ", ")
            facts.append("At the last reading the biggest holders were \(holders).")
        }

        facts.append("Quitting an app frees what it was holding, but the overall figure can stay high afterwards, because macOS fills the freed room with cache. On Apple silicon the processor and the graphics share this one pool of memory.")

        return HousekeeperTopic(
            id: "room-memory",
            title: "Memory",
            label: "\(String(format: "%.1f", Double(snapshot.memoryUsed) / 1_000_000_000)) of \(VitalsFormat.gigabytes(snapshot.memoryTotal))",
            tone: snapshot.memoryFraction > 0.92 ? .caution : .plain,
            facts: facts,
            opener: "My memory reads \(String(format: "%.1f", Double(snapshot.memoryUsed) / 1_000_000_000)) of \(VitalsFormat.gigabytes(snapshot.memoryTotal)). What does that mean, what is holding it, and should I do something about it?"
        )
    }

    static func disk(_ snapshot: VitalsSnapshot) -> HousekeeperTopic {
        let facts: [String] = [
            "This is the volume macOS started from, not every disk attached to the Mac.",
            "macOS wants roughly a tenth of a volume free. Below about 5%, caches, updates and the sleep image start failing, and the machine slows down.",
            "At the last reading \(VitalsFormat.gigabytes(snapshot.diskUsed)) of \(VitalsFormat.gigabytes(snapshot.diskTotal)) was in use, leaving \(VitalsFormat.gigabytes(snapshot.diskFree)) free.",
            "This panel can say how full the volume is. It does not know which folders are taking the room — the disk browser on the main window measures them when you ask it to.",
        ]

        return HousekeeperTopic(
            id: "room-disk",
            title: "The disk",
            label: VitalsFormat.percent(snapshot.diskFraction),
            tone: snapshot.diskFraction > 0.92 ? .broken : (snapshot.diskFraction > 0.85 ? .caution : .plain),
            facts: facts,
            opener: "My disk is \(VitalsFormat.percent(snapshot.diskFraction)) full with \(VitalsFormat.gigabytes(snapshot.diskFree)) free. What is taking the space, and what is safe to do about it?"
        )
    }

    static func network(_ snapshot: VitalsSnapshot) -> HousekeeperTopic {
        let facts: [String] = [
            "The two numbers are every app's traffic added together, measured between two readings a second apart. They are not one app's share.",
            "Traffic is counted on every network interface except the loopback, so while a VPN tunnel is up the same bytes can be counted twice: once on the tunnel and once on the interface carrying it.",
            "At the last reading the Mac was receiving \(VitalsFormat.rate(snapshot.downPerSecond)) and sending \(VitalsFormat.rate(snapshot.upPerSecond)).",
            "Housekeeping does not break this figure down by app. It can tell you how much is moving, not who is moving it.",
        ]

        return HousekeeperTopic(
            id: "room-network",
            title: "The network",
            label: nil,
            tone: .plain,
            facts: facts,
            opener: "The panel says \(VitalsFormat.rate(snapshot.downPerSecond)) down and \(VitalsFormat.rate(snapshot.upPerSecond)) up. What does that include, and is it a lot?"
        )
    }

    static func graphics(_ snapshot: VitalsSnapshot) -> HousekeeperTopic {
        var facts: [String] = [
            "This is how much of the graphics processor the driver reports busy.",
            "Video, games, and image or video processing move it. A figure that stays high with nothing open is the case worth looking at.",
            "Housekeeping has no per-app breakdown of the graphics processor; that is not something this panel can read.",
        ]
        if let value = snapshot.gpu {
            facts.insert("At the last reading it was \(VitalsFormat.percent(value)) busy.", at: 0)
        } else {
            facts.insert("This Mac did not report a graphics reading when the panel last asked.", at: 0)
        }

        return HousekeeperTopic(
            id: "room-graphics",
            title: "The graphics processor",
            label: snapshot.gpu.map(VitalsFormat.percent),
            tone: .plain,
            facts: facts,
            opener: snapshot.gpu == nil
                ? "The panel cannot read my graphics processor — is that expected?"
                : "Graphics reads \(VitalsFormat.percent(snapshot.gpu ?? 0)). Is that normal for what I am doing?"
        )
    }

    static func battery(_ battery: BatteryState) -> HousekeeperTopic {
        let state: String
        if battery.charging {
            state = "The Mac is plugged in and charging."
        } else if battery.onAC {
            state = "The Mac is on power and the battery is not charging."
        } else if let left = VitalsFormat.minutes(battery.minutesLeft) {
            state = "The Mac is running on the battery, with about \(left) left at the current draw."
        } else {
            state = "The Mac is running on the battery, and macOS has not offered an estimate of the time left."
        }

        let facts: [String] = [
            "Percent is the charge in the battery, not a statement about its health.",
            "macOS estimates the time left from recent draw, so the estimate moves as apps load the machine.",
            state,
        ]

        return HousekeeperTopic(
            id: "room-battery",
            title: "The battery",
            label: "\(battery.percent)%",
            tone: battery.percent < 10 ? .broken : (battery.percent < 20 ? .caution : .plain),
            facts: facts,
            opener: "My battery reads \(battery.percent)%. What should I know about that right now?"
        )
    }

    /// One process, as the panel saw it when the reader pressed its row.
    static func process(_ load: ProcessLoad, totalMemory: UInt64) -> HousekeeperTopic {
        let cpu = load.cpu > 0.001
            ? "\(VitalsFormat.share(load.cpu)) of one core"
            : "no measurable processor time"
        let share = totalMemory > 0 ? Double(load.memory) / Double(totalMemory) : 0

        let facts: [String] = [
            "\(load.name) (process \(load.id)) was using \(cpu) and holding \(VitalsFormat.megabytes(load.memory)), about \(VitalsFormat.percent(share)) of the Mac's memory.",
            "A quit is a request: the process can save, close and exit on its own terms. A force quit takes the memory away where it stands, and anything unsaved in it is lost.",
            "The name comes from the process itself. Housekeeping does not know what installed it, when it started, or what it is partway through.",
            "Housekeeping will not stop the system's own processes or itself, and macOS refuses for anything owned by another user.",
        ]

        return HousekeeperTopic(
            id: "process-\(load.id)",
            title: load.name,
            label: "process \(load.id)",
            tone: load.cpu > 1 ? .caution : .plain,
            facts: facts,
            opener: "What is \(load.name), and is it safe to quit it?"
        )
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

    var title: String = "Talk to the Housekeeper"
    var isPrimary: Bool = false
    var help: String = "Opens the housekeeper on what is on this screen. It explains; Housekeeping is the one that decides."

    /// For the row a finding is on, where a drawn button next to the row's other
    /// controls would be louder than the thing it is about. The same action, said
    /// in the same voice as the row's other quiet links.
    var compact: Bool = false

    /// For the navigation rail, where every other door is a coloured disc and a
    /// drawn pill would be the one thing on the edge that is not. It is still
    /// this button that opens the housekeeper, rather than the rail setting the
    /// two properties itself, because the invariant above is exactly the one
    /// that must not be re-implemented somewhere else.
    var railTint: Color? = nil

    /// Where this door falls in the rail's arrival, so the housekeeper queues up
    /// behind the ten jobs rather than appearing underneath them while they are
    /// still flying in.
    var railDelay: Double = 0

    var body: some View {
        if let railTint {
            RailButton(
                title: title,
                systemImage: "bubble.left.and.text.bubble.right",
                tint: railTint,
                help: help,
                delay: railDelay,
                // The rail draws the character rather than the glyph. The symbol
                // above is still passed because every other door has one and the
                // button takes it unconditionally — the rail simply chooses not to
                // draw it. The door keeps the label as its accessibility label, so
                // nothing is lost by the disc being a drawing.
                showsOctopus: true,
                action: open
            )
        } else if compact {
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
