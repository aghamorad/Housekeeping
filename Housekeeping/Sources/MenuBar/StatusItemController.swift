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
import Combine
import SwiftUI

extension Notification.Name {
    /// Asks the main window to open the housekeeper. Posted rather than called, so the
    /// menu bar does not need a reference to any window or to `AppState`.
    static let housekeepingOpenHousekeeper = Notification.Name("HousekeepingOpenHousekeeper")
    static let housekeepingScanNow = Notification.Name("HousekeepingScanNow")
    static let housekeepingOpenPhone = Notification.Name("HousekeepingOpenPhone")
    static let housekeepingOpenMediaDock = Notification.Name("HousekeepingOpenMediaDock")
    static let housekeepingOpenBookbind = Notification.Name("HousekeepingOpenBookbind")
    /// Opens the housekeeper already holding a topic. The topic itself travels as
    /// the notification's object, because a reading is the reason it was opened.
    static let housekeepingAskAbout = Notification.Name("HousekeepingAskAbout")
    static let housekeepingOpenDisk = Notification.Name("HousekeepingOpenDisk")
    /// The panel was dismissed, so the next opening starts at the overview rather
    /// than on whichever page was left behind.
    static let housekeepingPanelClosed = Notification.Name("HousekeepingPanelClosed")
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
        bringForward()

        if let window = liveWindow() {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            // An accessory app can be refused the activation it just asked for, and
            // a window ordered front by an app that is not active stays exactly
            // where it was. This is the one case where the window is put in front
            // regardless of who is active, and it is a person's click that asks.
            if !NSApp.isActive { window.orderFrontRegardless() }
            // It is already in the hierarchy, so the view can be told on the next
            // turn of the run loop rather than whenever a new one is built.
            DispatchQueue.main.async(execute: then)
            return
        }

        // Nothing is left to bring back. SwiftUI is the only thing that can build
        // a window, and only when it is asked from inside the scene. The job is
        // kept even when there is no scene to ask yet, so a window that arrives
        // later — from the menu, from the Dock, from a launch — still runs it.
        waiting = then
        open?()
    }

    /// The window that can actually be shown, which is not the same thing as the
    /// window that can become main.
    ///
    /// A window SwiftUI has finished with stays in `NSApp.windows` with its style
    /// mask intact, so it still answers `canBecomeMain` — it is only no longer
    /// visible. Ordering that one front is why every door in the panel did nothing:
    /// the app activated, a window that draws nothing was brought forward over the
    /// desktop, and the reader was left looking at the screen they started on. The
    /// live window was there the whole time, one entry further down the list — and
    /// when it had been minimized there was no live window to find at all, because
    /// a miniaturized window is not allowed to become main either.
    private func liveWindow() -> NSWindow? {
        let ordinary = NSApp.windows.filter {
            $0.level == .normal && $0.styleMask.contains(.titled)
        }
        if let key = NSApp.keyWindow, ordinary.contains(key), key.isVisible {
            return key
        }
        // A window waiting in the Dock is still the reader's window, and bringing
        // it back is a restore rather than a second window beside it.
        if let asleep = ordinary.first(where: { $0.isMiniaturized }) { return asleep }
        return ordinary.first { $0.isVisible }
    }

    /// A panel click is a person asking for the app, so the activation is allowed
    /// — but `NSApp.activate` alone is not enough for an accessory app on current
    /// macOS, where an unbundled activation request can be ignored silently.
    private func bringForward() {
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
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
final class StatusItemController: NSObject, NSPopoverDelegate {
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
    private var budgetObserver: AnyCancellable?
    private var pendingResize: DispatchWorkItem?
    private var frames: [NSImage] = []
    private var tick = 0
    private var popover: NSPopover?
    private var lastClose = Date.distantPast

    private override init() { super.init() }

    func install() {
        guard item == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.imagePosition = .imageOnly
        item.button?.toolTip = "Housekeeping"
        // The octopus opens a panel now, not a menu. The old menu is still there,
        // one right-click away, for anyone who knows where things live.
        item.button?.target = self
        item.button?.action = #selector(handleClick)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        self.item = item

        frames = buildFrames()
        item.button?.image = frames.first

        // The animation follows the motion budget, not the clock. Before 0.20.1 this
        // timer was installed at launch and never stopped: twelve status-bar image
        // swaps a second from login to logout, each one a menu bar redraw, for a
        // reader who was not there. On an otherwise idle Mac that was the single
        // biggest reason Housekeeping sat at a quarter of a core all day. Now the
        // budget says when she moves — while the app is active, while the panel is
        // open, for a moment at launch — and she stands still the rest of the time.
        budgetObserver = MotionBudget.shared.$isTicking
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] ticking in self?.setAnimating(ticking) }
    }

    /// Starts or stops the two-second loop. Stopping parks the mark on its rest
    /// frame rather than leaving whatever frame it happened to be on, so the
    /// still image is always the same still image.
    private func setAnimating(_ animating: Bool) {
        if animating {
            guard timer == nil, !frames.isEmpty else { return }
            let timer = Timer(
                timeInterval: Self.frameInterval,
                target: self,
                selector: #selector(advance),
                userInfo: nil,
                repeats: true
            )
            // Common mode, so the octopus keeps moving while a menu is open or the
            // window is being dragged — the two moments a reader is most likely to
            // be looking at her.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else {
            timer?.invalidate()
            timer = nil
            tick = 0
            item?.button?.image = frames.first
        }
    }

    // MARK: - Drawing

    private func buildFrames() -> [NSImage] {
        (0..<Self.frameCount).map { index in
            let renderer = ImageRenderer(
                content: OctopusMark(
                    time: Double(index) * Self.frameInterval,
                    color: .black,
                    // The menu bar gets a template image — one tint, decided by
                    // whether the bar is light or dark. Anything drawn in a second
                    // colour would come out as the first, so she is handed over as
                    // a cut-paper silhouette instead.
                    rendering: .singleColour
                )
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

    // MARK: - The panel

    @objc private func handleClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }

        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }

        // A transient popover closes on the same click that lands on the button.
        // Without this guard the click that dismisses the panel would also be the
        // click that opens it again, and the octopus could never be clicked shut.
        guard Date().timeIntervalSince(lastClose) > 0.18 else { return }
        // A turn later, so the mouse-up that got us here is finished before the
        // popover exists. Shown from inside the action it is shown *during* that
        // click, and a transient popover reads the rest of the click as a click
        // outside itself and shuts again immediately.
        DispatchQueue.main.async { [weak self] in self?.showPanel() }
    }

    /// Opens the panel from somewhere other than the octopus itself.
    ///
    /// The panel is the app's smallest screen and the only one with no route to it
    /// but a mouse: the status item is the sole way in, and a menu bar a reader
    /// cannot see or reach leaves every reading behind it out of reach. With this,
    /// the panel is a job like everything else — in the Jobs menu, and on a key.
    func presentPanel() {
        guard popover?.isShown != true else {
            popover?.performClose(nil)
            return
        }
        // A transient popover closes on the click that opens it, so the opening
        // waits for this click to finish — the same reason the octopus does.
        DispatchQueue.main.async { [weak self] in self?.showPanel() }
    }

    private func showPanel() {
        guard let button = item?.button, popover?.isShown != true else { return }

        // The reader may have turned the login item off in System Settings since
        // the panel was last seen; the switch should say what is true now.
        LoginItem.shared.refresh()
        SystemVitals.shared.start()

        let popover = panel()
        popover.contentViewController?.view.layoutSubtreeIfNeeded()
        let fitting = popover.contentViewController?.view.fittingSize ?? .zero
        if fitting.height > 0 {
            popover.contentSize = NSSize(width: max(352, fitting.width), height: fitting.height)
        }

        // Active first: a popover shown into an inactive app is dismissed by the
        // activation that follows it.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
    }

    private func panel() -> NSPopover {
        if let popover { return popover }

        let root = MenuBarPanel(
            vitals: SystemVitals.shared,
            loginItem: LoginItem.shared,
            onOpen: { [weak self] in self?.openMainWindow() },
            onScan: { [weak self] in self?.scanNow() },
            onAsk: { [weak self] in self?.askTheHousekeeper() },
            onMediaDock: { [weak self] in self?.openMediaDock() },
            onBookbind: { [weak self] in self?.openBookbind() },
            onQuit: { NSApp.terminate(nil) },
            onClose: { [weak self] in self?.popover?.performClose(nil) },
            onDisk: { [weak self] in self?.openDisk() },
            onExplain: { [weak self] topic in self?.explain(topic) },
            onResize: { [weak self] height in self?.resize(to: height) }
        )

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        // The panel is always the dark house, whatever the Mac is wearing. Without
        // this the popover draws its own light chrome around it — a white arrow and
        // a pale edge, framing a dark panel.
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.delegate = self
        self.popover = popover
        return popover
    }

    /// A page inside the panel is taller than the overview, and the popover is only
    /// measured once, when it is built. So the page reports its own height and the
    /// popover is resized here. It anchors at the arrow, so growth goes downward.
    ///
    /// Debounced, because resizing a popover makes its hosting view lay out again,
    /// and laying out again reports a height, which asks for another resize. The
    /// old version chased that round trip as fast as the run loop would carry it:
    /// with the panel open, Housekeeping sat at about a fifth of a core, all of it
    /// spent asking a 352-point panel how tall it was. Waiting for the reports to
    /// stop before acting on the last one ends it — the popover is resized once,
    /// to the height the page actually settled at.
    private func resize(to height: CGFloat) {
        guard let popover, popover.isShown, height > 0 else { return }
        let target = NSSize(width: 352, height: ceil(height))
        guard abs(popover.contentSize.height - target.height) > 1 else { return }

        pendingResize?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let popover = self.popover, popover.isShown else { return }
            guard abs(popover.contentSize.height - target.height) > 1 else { return }
            popover.contentSize = target
        }
        pendingResize = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func explain(_ topic: HousekeeperTopic) {
        // The sheet belongs to the window, so the window has to be there first —
        // and the topic has to survive that wait, which is why it rides along.
        WindowOpener.shared.withWindow {
            NotificationCenter.default.post(name: .housekeepingAskAbout, object: topic)
        }
    }

    private func openDisk() {
        WindowOpener.shared.withWindow {
            NotificationCenter.default.post(name: .housekeepingOpenDisk, object: nil)
        }
    }

    /// Right-click keeps the old menu. `popUp` draws it at the button without
    /// leaving it attached to the status item, which would take the left click back.
    private func showMenu() {
        guard let button = item?.button else { return }
        let menu = buildMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    func popoverDidClose(_ notification: Notification) {
        // Nothing measures the machine while the panel is shut.
        SystemVitals.shared.stop()
        // The panel keeps its state between openings, which is what lets a detail
        // page survive the popover resizing underneath it. Without this, reopening
        // the panel would land on whatever page was last looked at.
        NotificationCenter.default.post(name: .housekeepingPanelClosed, object: nil)
        item?.button?.highlight(false)
        lastClose = Date()
    }

    // MARK: - The menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(entry("Open Housekeeping", #selector(openMainWindow)))
        menu.addItem(entry("Talk to the Housekeeper", #selector(askTheHousekeeper)))
        menu.addItem(.separator())
        menu.addItem(entry("Scan My Mac", #selector(scanNow)))
        menu.addItem(entry("Spoof Location…", #selector(spoofLocation)))
        menu.addItem(entry("MediaDock 9…", #selector(openMediaDock)))
        menu.addItem(entry("Bookbind…", #selector(openBookbind)))
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

    @objc private func spoofLocation() {
        WindowOpener.shared.withWindow {
            NotificationCenter.default.post(name: .housekeepingOpenPhone, object: nil)
        }
    }

    @objc private func openMediaDock() {
        WindowOpener.shared.withWindow {
            NotificationCenter.default.post(name: .housekeepingOpenMediaDock, object: nil)
        }
    }

    @objc private func openBookbind() {
        WindowOpener.shared.withWindow {
            NotificationCenter.default.post(name: .housekeepingOpenBookbind, object: nil)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
