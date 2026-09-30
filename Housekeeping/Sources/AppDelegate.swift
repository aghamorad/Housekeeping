// Housekeeping — AppDelegate
// Handles app lifecycle and permissions

import Foundation
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up the retro cursor
        setupAppearance()

        // A sheet must not be able to hold the app open.
        allowQuittingThroughSheets()

        // Load rules
        RuleEngine.shared.loadRules()

        // The octopus belongs to the app, not to the window: it goes up here, at
        // launch, so it is in the menu bar whether or not a window is open — which
        // is the point of having it there at all.
        StatusItemController.shared.install()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The housekeeper's runtime is a child process holding most of a gigabyte
        // while it is up, and it is nobody else's to shut down. Left alone it outlives
        // the app that started it, still resident and still listening, with nothing
        // left running that knows it is there.
        Housekeeper.shared.server.stopAndWait()
    }

    /// Lets the app be quit while one of its own sheets is open.
    ///
    /// A sheet is a modal window, and a modal window refuses application
    /// termination unless it is told otherwise — `NSWindow`'s
    /// `preventsApplicationTerminationWhenModal` is `true` by default. That default
    /// is there to protect a dialog that would throw away a half-finished answer.
    /// Nothing here is that: every sheet in this app is a place the reader can
    /// simply leave, so leaving is what quitting should mean. Without this, ⌘Q and
    /// Quit in both menus do nothing whatsoever until the sheet is dismissed, and
    /// the app looks hung at exactly the moment someone is trying to shut it down.
    private func allowQuittingThroughSheets() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            (notification.object as? NSWindow)?.preventsApplicationTerminationWhenModal = false
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let window = sender.windows.first(where: { !$0.isMiniaturized }) ?? sender.windows.first {
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    private func setupAppearance() {
        // A regular app: a window, a Dock tile, and the octopus in the menu bar.
        NSApp.setActivationPolicy(.regular)

        // The standard application menu is SwiftUI's, not this file's. Housekeeping
        // contributes through Scene commands rather than replacing Settings, Window,
        // Help, keyboard navigation, and the other native menus.
    }
}
