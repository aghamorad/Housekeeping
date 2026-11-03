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
    static let housekeepingOpenVPNTunnels = Notification.Name("HousekeepingOpenVPNTunnels")
    static let housekeepingOpenDNSSwitcher = Notification.Name("HousekeepingOpenDNSSwitcher")
    /// Opens the housekeeper already holding a topic. The topic itself travels as
    /// the notification's object, because a reading is the reason it was opened.
    static let housekeepingAskAbout = Notification.Name("HousekeepingAskAbout")
    static let housekeepingOpenDisk = Notification.Name("HousekeepingOpenDisk")
    static let housekeepingOpenFanControl = Notification.Name("HousekeepingOpenFanControl")
    static let housekeepingOpenBatteryHealth = Notification.Name("HousekeepingOpenBatteryHealth")
    static let housekeepingOpenUninstaller = Notification.Name("HousekeepingOpenUninstaller")
    static let housekeepingOpenUpdates = Notification.Name("HousekeepingOpenUpdates")
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

    /// A true macOS template mask derived directly from the supplied Housekeeping maid logo.
    /// Dark artwork becomes the tintable foreground; white details become transparent
    /// cut-outs, preserving the original silhouette and expression.
    private static let menuBarTemplate: NSImage? = {
        let encoded = [
            "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"
        ].joined()
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return NSImage(data: data)
    }()

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
        if let source = Self.menuBarTemplate {
            source.size = NSSize(width: Self.markSize, height: Self.markSize)

            return (0..<Self.frameCount).map { index in
                let time = Double(index) * Self.frameInterval
                let breath = 1 + 0.022 * sin(time * 1.25)
                let renderer = ImageRenderer(
                    content: Image(nsImage: source)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: Self.markSize, height: Self.markSize)
                        .scaleEffect(breath)
                )
                renderer.scale = 2

                let size = NSSize(width: Self.markSize, height: Self.markSize)
                let image = renderer.nsImage ?? NSImage(size: size)
                image.size = size
                image.isTemplate = true
                return image
            }
        }

        // Keep the original vector mark as a fallback if the embedded artwork
        // cannot be decoded, so the status item still appears and remains usable.
        return buildVectorFrames()
    }

    private func buildVectorFrames() -> [NSImage] {
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
            onFans: { [weak self] in self?.openFans() },
            onUpdates: { [weak self] in self?.openUpdates() },
            onAsk: { [weak self] in self?.askTheHousekeeper() },
            onMediaDock: { [weak self] in self?.openMediaDock() },
            onBookbind: { [weak self] in self?.openBookbind() },
            onQuit: { NSApp.terminate(nil) },
            onClose: { [weak self] in self?.popover?.performClose(nil) },
            onDisk: { [weak self] in self?.openDisk() },
            onBatteryHealth: { [weak self] in self?.openBatteryHealth() },
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

    private func openFans() {
        WindowOpener.shared.withWindow {
            NotificationCenter.default.post(name: .housekeepingOpenFanControl, object: nil)
        }
    }

    private func openBatteryHealth() {
        WindowOpener.shared.withWindow {
            NotificationCenter.default.post(name: .housekeepingOpenBatteryHealth, object: nil)
        }
    }

    private func openUpdates() {
        WindowOpener.shared.withWindow {
            NotificationCenter.default.post(name: .housekeepingOpenUpdates, object: nil)
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
        menu.addItem(entry("App Uninstaller…", #selector(openUninstaller)))
        menu.addItem(entry("Battery Health…", #selector(openBatteryHealthMenu)))
        menu.addItem(entry("Spoof Location…", #selector(spoofLocation)))
        menu.addItem(entry("MediaDock 9…", #selector(openMediaDock)))
        menu.addItem(entry("Bookbind…", #selector(openBookbind)))
        menu.addItem(entry("VPN Tunnels…", #selector(openVPNTunnels)))
        menu.addItem(entry("DNS Easy Switcher…", #selector(openDNSSwitcher)))
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

    @objc private func openUninstaller() {
        WindowOpener.shared.withWindow {
            NotificationCenter.default.post(name: .housekeepingOpenUninstaller, object: nil)
        }
    }

    @objc private func openBatteryHealthMenu() {
        openBatteryHealth()
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

    @objc private func openVPNTunnels() {
        WindowOpener.shared.withWindow {
            NotificationCenter.default.post(name: .housekeepingOpenVPNTunnels, object: nil)
        }
    }

    @objc private func openDNSSwitcher() {
        WindowOpener.shared.withWindow {
            NotificationCenter.default.post(name: .housekeepingOpenDNSSwitcher, object: nil)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
