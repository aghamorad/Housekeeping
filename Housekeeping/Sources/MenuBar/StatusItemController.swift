// Housekeeping — the octopus in the menu bar
//
// The mark is rendered once into a small set of template images and then played back
// on a timer, rather than being redrawn from SwiftUI on every tick. `ImageRenderer`
// builds a fresh rendering context each call, and the menu bar draws on the same
// thread that draws the windows — twelve of those a second, forever, is a cost that
// buys nothing when the animation is a two-second loop.
//
// The frames are template images, so macOS tints them for the current menu bar and
// the mark works in both appearances without knowing which one is on.

import AppKit
import SwiftUI

extension Notification.Name {
    /// Asks the main window to open the housekeeper. Posted rather than called, so the
    /// menu bar does not need a reference to any window or to `AppState`.
    static let housekeepingOpenHousekeeper = Notification.Name("HousekeepingOpenHousekeeper")
    static let housekeepingScanNow = Notification.Name("HousekeepingScanNow")
}

/// The menu bar's way back into the main window.
///
/// SwiftUI owns that window, and it will only build another one when it is asked
/// from inside the scene — but the octopus is AppKit and deliberately outlives the
/// window, so the two ends never meet on their own. This is where they do: the
/// window leaves its own `openWindow` action here as it appears, and the menu bar
/// calls it later, long after the view that registered it has gone.
///
/// Work that was asked for while there was no window waits here as well. A
/// notification posted at a scene that does not exist is simply dropped, so the
/// octopus cannot open a window and then shout into it; it hands over the job
/// instead, and the incoming window runs it on the way up.
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()

    private var open: (@MainActor @Sendable () -> Void)?
    private var waiting: (@MainActor @Sendable () -> Void)?

    private init() {}

    /// Called by the main window as it appears. Kept rather than used, because its
    /// value is entirely in still being here once the window has closed.
    func register(_ open: @escaping @MainActor @Sendable () -> Void) {
        self.open = open
        deliver()
    }

    /// Brings the window back, running `then` once it is there — immediately if it
    /// was only closed or hidden, or when it comes up if it has to be built again.
    func withWindow(_ then: @escaping @MainActor @Sendable () -> Void) {
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            // It is already in the hierarchy, so the view can be told on the next
            // turn of the run loop rather than whenever a new one is built.
            DispatchQueue.main.async(execute: then)
            return
        }

        // Nothing is left to bring back. SwiftUI is the only thing that can build
        // a window, and only when it is asked from inside the scene.
        guard let open else { return }
        waiting = then
        open()
    }

    /// Called by the window as it appears, after it has registered.
    private func deliver() {
        guard let waiting else { return }
        self.waiting = nil
        // A turn later, so the window is finished being a window before a sheet is
        // asked of it. Presenting from inside `onAppear` asks too early.
        DispatchQueue.main.async(execute: waiting)
    }
}

@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    /// Twenty-four frames at twelve a second is a two-second loop. The mark's breath
    /// and the arms' drift do not divide evenly into two seconds, so the loop has a
    /// seam — it is under half a point at this size, which is below what a menu bar can
    /// show, and the alternative is a frame count in the thousands.
    private static let frameCount = 24
    private static let frameInterval = 1.0 / 12
    private static let markSize: CGFloat = 18

    private var item: NSStatusItem?
    private var timer: Timer?
    private var frames: [NSImage] = []
    private var tick = 0

    private override init() { super.init() }

    func install() {
        guard item == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "Housekeeping"
        item.menu = buildMenu()
        self.item = item

        frames = buildFrames()
        item.button?.image = frames.first

        let timer = Timer(
            timeInterval: Self.frameInterval,
            target: self,
            selector: #selector(advance),
            userInfo: nil,
            repeats: true
        )
        // Common mode, so the octopus keeps moving while a menu is open or the window
        // is being dragged — the two moments the reader is most likely to be looking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Drawing

    private func buildFrames() -> [NSImage] {
        (0..<Self.frameCount).map { index in
            let renderer = ImageRenderer(
                content: OctopusMark(time: Double(index) * Self.frameInterval, color: .black)
                    .frame(width: Self.markSize, height: Self.markSize)
            )
            // Two, so the mark is sharp on every Mac this app runs on. The renderer
            // carries the scale; the status item picks the right representation.
            renderer.scale = 2

            let size = NSSize(width: Self.markSize, height: Self.markSize)
            let image = renderer.nsImage ?? NSImage(size: size)
            image.size = size
            image.isTemplate = true
            return image
        }
    }

    @objc private func advance() {
        guard !frames.isEmpty else { return }
        tick = (tick + 1) % frames.count
        item?.button?.image = frames[tick]
    }

    // MARK: - The menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(entry("Open Housekeeping", #selector(openMainWindow)))
        menu.addItem(entry("Ask the Housekeeper", #selector(askTheHousekeeper)))
        menu.addItem(.separator())
        menu.addItem(entry("Scan My Mac", #selector(scanNow)))
        menu.addItem(.separator())
        menu.addItem(entry("Quit Housekeeping", #selector(quit)))

        return menu
    }

    private func entry(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openMainWindow() {
        WindowOpener.shared.withWindow {}
    }

    @objc private func askTheHousekeeper() {
        // The sheet belongs to the window, so the window has to be there first.
        // The notification is posted once it is — which may be a launch away if the
        // last window was closed, and posting it any earlier would be posting it
        // into nothing.
        WindowOpener.shared.withWindow {
            NotificationCenter.default.post(name: .housekeepingOpenHousekeeper, object: nil)
        }
    }

    @objc private func scanNow() {
        WindowOpener.shared.withWindow {
            NotificationCenter.default.post(name: .housekeepingScanNow, object: nil)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
