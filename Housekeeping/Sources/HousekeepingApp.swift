// Housekeeping - App Entry Point
//
// Not `@main`. The program starts in `main.swift`, which decides between the
// window and the command line before either has begun — a decision that has to
// be made before AppKit is up, and so cannot be made from inside the app itself.
// `main.swift` calls `HousekeepingApp.main()` when there was nothing to do but
// show a window, which is every launch but one.

import SwiftUI
import AppKit

struct HousekeepingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        // Named, because a `WindowGroup` can only be opened again from the code
        // side when it has an id — and "again" is the whole point: see
        // `WindowOpener`.
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}

            // Left to itself the View menu is the stock single-window one and
            // every item in it is greyed out: tab bar, tabs, full screen — none
            // of which this window has. A menu of disabled items reads as a
            // broken app; one item that closes whatever screen is open is the
            // only thing here a reader would actually use. The tab items are
            // removed at the source, in `AppDelegate`.
            CommandGroup(replacing: .toolbar) {
                Button("Close This Screen") {
                    appState.screen = nil
                }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(appState.screen == nil)
            }

            // "Housekeeping Help" is the stock item, and with no help book behind
            // it it is a menu entry that does nothing. These three do something.
            CommandGroup(replacing: .help) {
                Button("How Housekeeping Works") {
                    if let url = URL(string: "https://github.com/aghamorad/Housekeeping#readme") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Button("Report a Problem or Ask a Question") {
                    if let url = URL(string: "https://github.com/aghamorad/Housekeeping/issues/new") {
                        NSWorkspace.shared.open(url)
                    }
                }

                Divider()

                Button("Show the Quarantine Folder in Finder") {
                    CleanupEngine().revealQuarantine()
                }
            }

            // Named "Jobs", not "Housekeeping": SwiftUI puts the app's own menu
            // first under the app name, so a command menu of the same name puts
            // "Housekeeping" in the menu bar twice and neither reading tells you
            // which one is which. Everything in here is a job you go and ask for,
            // which is what the name says.
            CommandMenu("Jobs") {
                Button("Scan My Mac") {
                    appState.startScan()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Cancel Scan") {
                    appState.cancelScan()
                }
                .keyboardShortcut(".", modifiers: .command)

                Divider()

                // The read-only rehearsal sits above the acting menu item on
                // purpose: the cheapest way to be sure about Housekeeping is to
                // watch it decide first, and that has to be reachable without
                // pressing anything that moves a file.
                Button("What Would Happen… (Rehearsal)") {
                    if appState.recommendedCleanupItems.isEmpty {
                        appState.lastErrorMessage = "Housekeeping has no recommendations to rehearse yet. Scan first."
                    } else {
                        appState.showCleanupPreview = true
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Review Selected for Quarantine") {
                    if appState.activeCleanupItems.isEmpty {
                        appState.lastErrorMessage = "Select at least one reviewable item first."
                    } else {
                        appState.showCleanupConfirmation = true
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])

                // The one-at-a-time walk. It is not on a screen any more — the
                // three-step pass replaced it as the main road — but it is still
                // the right tool for someone who would rather decide item by item
                // than answer a single question about the whole set.
                Button("Walk Me Through Them, One at a Time") {
                    if appState.recommendedCleanupItems.isEmpty {
                        appState.lastErrorMessage = "Housekeeping has nothing it would walk you through yet. Scan first."
                    } else {
                        appState.beginGuidedCleanup()
                    }
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                // Always opens, empty or not. Refusing to open a window and
                // printing "the quarantine is empty" made the one screen that
                // explains where your files go the one screen you could not look
                // at — and it is the screen that says where the folder even is.
                Button("Manage Quarantine") {
                    appState.showQuarantineManagement = true
                }

                Button("Undo Last Quarantine") {
                    Task { await appState.undoLastQuarantine() }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])

                Button("Show Quarantine Folder in Finder") {
                    CleanupEngine().revealQuarantine()
                }

                // Same rule as Manage Quarantine: always openable, even when the
                // list is empty. The empty list is the one that most needs saying
                // out loud, because the screen is where the whole idea of leaving
                // something alone is explained.
                Button("Left Alone") {
                    appState.showProtectionList = true
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                // Reading the disk, which is not the same job as cleaning it. The
                // scan above decides what Housekeeping would offer to remove; this
                // only measures, and it is here rather than on a screen because
                // "where did it all go" is a question that arrives on its own.
                Button("Browse the Disk…") {
                    appState.showDiskBrowser = true
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                // The question a backup raises and a disk measurement cannot
                // answer: are these two folders actually the same? It belongs
                // beside browsing because it is the same kind of thing — a
                // reading you go and ask for — with one difference, that it can
                // copy a missing file across once you have said so.
                Button("Compare Two Folders…") {
                    appState.showReconcile = true
                }
                .keyboardShortcut("y", modifiers: [.command, .shift])

                // The other half of looking after a Mac: what is installed and
                // whether any of it is out of date. Kept off the cleanup screens
                // because it changes things rather than removing them.
                Button("Update Apps…") {
                    appState.showUpdateList = true
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                // The other half of the same question. Updating asks whether what
                // is installed is current; this asks whether what is installed is
                // the thing that runs when you type its name — which is a
                // different bug with the same symptom, and the one that made a
                // stale yt-dlp run for months without anything announcing it.
                Button("Terminal Health…") {
                    appState.showSetupCheck = true
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                // The one job here that is about the network rather than the
                // disk. It belongs in this menu because it is the same kind of
                // thing as the rest — something you go and ask for — and because
                // it has nowhere else to be: the VPN client's own window shows
                // the servers but not which of their protocols this line will
                // actually carry. It is set slightly apart from the readings
                // above it, since it is the only one that changes the state of
                // the machine while it works.
                Button("Test Routes…") {
                    appState.showRoutes = true
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                // The one job that acts on something other than this Mac. It
                // belongs in the same menu because it is the same kind of thing —
                // a job you go and ask for — and because it changes a device, so
                // it lives beside the route test rather than among the readings.
                Button("Spoof Location…") {
                    appState.showPhone = true
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                // MediaDock 9 and Bookbind. Not jobs this app performs, so they
                // are set apart from the readings and the two that touch a
                // device — what they have in common with the rest is only where
                // they are found.
                Button("Extras…") {
                    appState.showExtras = true
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])

                Divider()

                // Opens on whatever is picked out in the list, and introduces
                // itself when nothing is. It is deliberately not gated on a scan
                // having run: "what is this app" is a fair question at any moment.
                Button("Talk to the Housekeeper") {
                    appState.showHousekeeper = true
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Picker("Theme", selection: Binding(
                    get: { appState.currentTheme },
                    set: { appState.setTheme($0) }
                )) {
                    ForEach(AppState.Theme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
            }
        }

        Settings {
            // Settings is a window of its own, opened by the system, so it is given
            // the same two things every other window here is given by hand: the
            // appearance, and the surface it is painted on.
            let style = UIStyle.resolve(appState.currentTheme)
            SettingsView()
                .environmentObject(appState)
                .environment(\.uiStyle, style)
                .housekeepingSurface(style)
        }
    }
}
