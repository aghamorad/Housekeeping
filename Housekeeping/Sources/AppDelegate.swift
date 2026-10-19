// Housekeeping — AppDelegate
// Handles app lifecycle and permissions

import Foundation
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // One window, and only one. Left on, macOS adds window tabbing, which
        // puts "Show Tab Bar" and "Show All Tabs" in the View menu as disabled
        // items — a menu of things this app does not do.
        NSWindow.allowsAutomaticWindowTabbing = false

        // A sheet must not be able to hold the app open.
        allowQuittingThroughSheets()

        // Load rules
        RuleEngine.shared.loadRules()

        // The octopus belongs to the app, not to the window: it goes up here, at
        // launch, so it is in the menu bar whether or not a window is open — which
        // is the point of having it there at all.
        StatusItemController.shared.install()
        DockVisibility.applySavedPreference()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The housekeeper's runtime is a child process holding most of a gigabyte
        // while it is up, and it is nobody else's to shut down. Left alone it outlives
        // the app that started it, still resident and still listening, with nothing
        // left running that knows it is there.
        Housekeeper.shared.server.stopAndWait()

        // The fake-location session is the same shape of thing: a child process
        // holding a phone somewhere it is not. It ends with the app.
        PhoneTool.endSession()

        // Bookbind's engine, too. It watches this process and would quit on its
        // own, but saying so here is quicker and does not depend on it noticing.
        BookbindEngine.current?.stop()
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
        // Three states, and the old two-line version only covered two of them.
        // Minimised and hidden windows come back with `deminiaturize` and
        // `makeKeyAndOrderFront`; a window that was closed outright is gone, and
        // there is nothing left to order front — clicking the Dock tile did
        // nothing, which reads as the app being broken. `WindowOpener` knows how
        // to ask SwiftUI for a new one, so the reopen goes through it either way.
        WindowOpener.shared.withWindow {}
        sender.activate(ignoringOtherApps: true)
        return true
    }

}

/// The menu-bar item is installed before the Dock can be hidden. Accessory mode
/// keeps windows usable while removing the Dock and Command-Tab entry.
@MainActor
enum DockVisibility {
    static let defaultsKey = "housekeeping.showInDock"

    static func applySavedPreference() {
        let defaults = UserDefaults.standard
        apply(showInDock: defaults.object(forKey: defaultsKey) == nil || defaults.bool(forKey: defaultsKey))
    }

    static func apply(showInDock: Bool) {
        let policy: NSApplication.ActivationPolicy = showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        let windows = NSApp.windows.filter { $0.isVisible && $0.level == .normal }
        let keyWindow = NSApp.keyWindow
        NSApp.setActivationPolicy(policy)
        // Changing activation policy can reorder windows. Preserve the current
        // workspace and Settings window without opening a closed window.
        DispatchQueue.main.async {
            for window in windows { window.orderFront(nil) }
            if let keyWindow, windows.contains(keyWindow) {
                keyWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
