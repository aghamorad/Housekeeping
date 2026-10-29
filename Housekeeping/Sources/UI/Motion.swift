import SwiftUI

/// Every duration the modern appearance uses, in one place.
///
/// The point of collecting them is that a screen full of controls only reads as
/// *animated* — rather than as several unrelated things twitching — when the
/// timings agree. Classic 9 draws its own controls and never reads any of this.
enum HousekeepingMotion {
    /// Pointer entering or leaving a control. Fast enough to feel like the
    /// control is tracking the cursor rather than reacting to it.
    static let hover = Animation.easeOut(duration: 0.13)
    /// Mouse-down. A spring, so releasing settles instead of snapping.
    static let press = Animation.spring(response: 0.24, dampingFraction: 0.6)
    /// A value arriving: a meter filling, a row appearing in place.
    static let settle = Animation.spring(response: 0.44, dampingFraction: 0.84)
    /// A whole screen or panel arriving.
    static let entrance = Animation.spring(response: 0.5, dampingFraction: 0.88)
    /// Something travelling a distance — the selection capsule, a sheet.
    static let travel = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// Numbers ticking.
    static let count = Animation.easeInOut(duration: 0.32)
    /// The halo on the one action a screen is asking for. Never resolves; that
    /// is what makes it read as "waiting on you" rather than "just finished".
    static let breathe = Animation.easeInOut(duration: 2.2).repeatForever(autoreverses: true)
    /// A ring that has no progress to report, turning so the screen is visibly
    /// still doing something.
    static let orbit = Animation.linear(duration: 1.5).repeatForever(autoreverses: false)
}

// MARK: - The motion budget

/// Decides whether the app's decorative motion is allowed to run.
///
/// The housekeeper breathes. Drawn inside a `TimelineView` that means her body is
/// evaluated and laid out every frame, and in the menu bar it means a status item
/// swapping template images twelve times a second — charming while someone is
/// looking, expensive while nobody is. Measured on this Mac on 2026-10-30: a copy
/// sitting in the menu bar with no window open held one core at roughly a quarter,
/// all day, because a window SwiftUI has closed but not torn down keeps its
/// timelines firing and the status item keeps its timer. That is a laptop's battery
/// spent on an animation behind a closed door.
///
/// So motion is a budget, and the budget is spent only where it can be seen: while
/// the app is active, while the menu bar panel is open, and for a moment at launch
/// so the mark reads as alive rather than stuck. Everywhere else she stands still —
/// one frame, no timer, no layout work.
///
/// A view asks one question, `isTicking`, and falls back to a still frame when the
/// answer is no:
///
///     if MotionBudget.shared.isTicking {
///         TimelineView(.periodic(from: .now, by: 1.0 / 20)) { context in
///             OctopusMark(time: context.date.timeIntervalSinceReferenceDate)
///         }
///     } else {
///         OctopusMark(time: 0)
///     }
///
/// Nothing is lost by this: a still octopus at rest is a still octopus. What is
/// gone is the version of her that animated for a reader who was not there.
final class MotionBudget: NSObject, ObservableObject {
    static let shared = MotionBudget()

    /// Whether decorative motion may run right now.
    @Published private(set) var isTicking = true

    private var appIsActive = false
    private var displayIsAsleep = false
    private var holds: Set<String> = ["greeting"]
    private var greetingEnd: Timer?

    private override init() {
        super.init()

        let app = NotificationCenter.default
        app.addObserver(
            self,
            selector: #selector(appBecameActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        app.addObserver(
            self,
            selector: #selector(appResignedActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )

        // A sleeping display is the one moment nothing can be seen at all, and it
        // is also the moment the machine is most likely to be on battery. Whatever
        // else is held open, nothing ticks through it.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self,
            selector: #selector(displaySlept),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        workspace.addObserver(
            self,
            selector: #selector(displayWoke),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )

        // The greeting: one turn of the animation at launch, then still. Long
        // enough to show she is a drawing and not a glyph, short enough to cost
        // nothing. `common` mode, so a launch that lands while a menu is open
        // still clears it.
        let timer = Timer(timeInterval: 2.6, repeats: false) { [weak self] _ in
            self?.release("greeting")
        }
        RunLoop.main.add(timer, forMode: .common)
        greetingEnd = timer
    }

    // MARK: - What is asking for motion

    /// Something wants motion for as long as it says so. Tokens rather than a
    /// boolean, because two of these overlap all the time — the panel is open on
    /// an active app — and the last one out should not switch off the lights.
    func hold(_ token: String) {
        holds.insert(token)
        refresh()
    }

    func release(_ token: String) {
        holds.remove(token)
        refresh()
    }

    // MARK: - The answer

    private func refresh() {
        let ticking = !displayIsAsleep && (appIsActive || !holds.isEmpty)
        guard ticking != isTicking else { return }
        isTicking = ticking
    }

    @objc private func appBecameActive() {
        appIsActive = true
        refresh()
    }

    @objc private func appResignedActive() {
        appIsActive = false
        // Nothing that can be seen survives the app losing the foreground, so
        // anything still holding motion open has outlived its reason. Dropping the
        // holds here is the belt to the release's braces: a token whose owner was
        // never told it had gone away — a panel dismissed by a key press, a sheet
        // that closed itself — would otherwise keep the menu bar's timer running
        // for the rest of the session.
        holds.removeAll()
        refresh()
    }

    @objc private func displaySlept() {
        displayIsAsleep = true
        refresh()
    }

    @objc private func displayWoke() {
        displayIsAsleep = false
        refresh()
    }
}

// MARK: - Whether this view is on screen

/// Answers the other half of the question.
///
/// `MotionBudget` says whether the app has any reason to animate at all. This says
/// whether *this* drawing is somewhere a person can see it. Both are needed: opening
/// the menu bar panel makes the app active, and the main window — closed, forgotten,
/// but still hosted by SwiftUI — would take that as its cue to lay itself out twenty
/// times a second behind a shut door. Measured while the panel was open: the app went
/// from nothing to a fifth of a core, none of it on screen.
///
/// A window answers for itself. AppKit tracks whether a window is actually visible and
/// how much of it is covered, and posts a notification when that changes; a zero-sized
/// `NSView` inside the view tree is enough to listen. SwiftUI has no per-window
/// visibility of its own, which is the whole reason this exists.
private final class OnScreenProbe: NSView {
    var report: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var last: Bool?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()

        guard let window else {
            send(false)
            return
        }

        // AppKit does not have an ordering notification to hang this on: a window
        // being hidden, shown, minimized or covered all arrive as an occlusion
        // change or as the app activating. `NSWindow` has only these two names for
        // it, so these two are what is watched.
        for name in [
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.willCloseNotification,
            NSApplication.didBecomeActiveNotification,
            NSApplication.didResignActiveNotification
        ] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                    [weak self] _ in self?.send(self?.isOnScreen ?? false)
                }
            )
        }

        send(isOnScreen)
    }

    private var isOnScreen: Bool {
        guard let window, window.isVisible, !window.isMiniaturized else { return false }
        // `occlusionState` is the only thing that knows the window is entirely
        // covered by another one — `isVisible` happily says yes to a window hidden
        // behind a full-screen video.
        return window.occlusionState.contains(.visible)
    }

    private func send(_ value: Bool) {
        guard value != last else { return }
        last = value
        // A turn later: the answer usually arrives during layout, and SwiftUI
        // treats state written from inside a layout pass as a mistake.
        DispatchQueue.main.async { [weak self] in
            self?.report?(value)
        }
    }
}

extension View {
    /// Reports whether this view's window is on screen and not fully covered, so a
    /// drawing can stop moving while it is behind a closed window.
    func tracksOnScreen(_ onScreen: Binding<Bool>) -> some View {
        background(OnScreenReader(onScreen: onScreen).frame(width: 0, height: 0))
    }
}

private struct OnScreenReader: NSViewRepresentable {
    @Binding var onScreen: Bool

    func makeNSView(context: Context) -> OnScreenProbe {
        let probe = OnScreenProbe()
        probe.report = { value in
            DispatchQueue.main.async { onScreen = value }
        }
        return probe
    }

    func updateNSView(_ nsView: OnScreenProbe, context: Context) {
        nsView.report = { value in
            DispatchQueue.main.async { onScreen = value }
        }
    }
}

// MARK: - Entrance

private struct EntranceModifier: ViewModifier {
    @State private var arrived = false
    let delay: Double

    func body(content: Content) -> some View {
        content
            .opacity(arrived ? 1 : 0)
            .offset(y: arrived ? 0 : 12)
            .onAppear {
                withAnimation(HousekeepingMotion.entrance.delay(delay)) { arrived = true }
            }
    }
}

// MARK: - Hover

private struct HoverHighlightModifier: ViewModifier {
    let shape: RoundedRectangle
    let normal: Color
    let hovered: Color
    let stroke: Color?

    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(isHovering ? hovered : normal, in: shape)
            .overlay {
                if let stroke {
                    shape.strokeBorder(stroke.opacity(isHovering ? 0.55 : 0.22), lineWidth: 1)
                }
            }
            .animation(HousekeepingMotion.hover, value: isHovering)
            .onHover { isHovering = $0 }
    }
}

extension View {
    /// Fades and lifts a view into place on appear. `delay` staggers siblings so
    /// a stack of panels arrives as a sequence rather than a single flash.
    func entrance(delay: Double = 0) -> some View {
        modifier(EntranceModifier(delay: delay))
    }

    /// A soft hover treatment for rows and trays. Not a button — it reports the
    /// pointer, it does not invite a click.
    func hoverHighlight(
        cornerRadius: CGFloat = 8,
        normal: Color = .clear,
        hovered: Color,
        stroke: Color? = nil
    ) -> some View {
        modifier(
            HoverHighlightModifier(
                shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                normal: normal,
                hovered: hovered,
                stroke: stroke
            )
        )
    }

    /// A halo that slowly breathes, for the one control a screen is asking for.
    /// `active` off means the halo is simply absent, so a screen that is not
    /// asking anything stays still.
    func breathingHalo(_ color: Color, radius: CGFloat, active: Bool) -> some View {
        modifier(BreathingHaloModifier(color: color, radius: radius, active: active))
    }
}

private struct BreathingHaloModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let active: Bool

    @State private var wide = false

    func body(content: Content) -> some View {
        content
            .shadow(color: active ? color.opacity(wide ? 0.42 : 0.20) : .clear, radius: wide ? radius : radius * 0.6)
            .onAppear {
                guard active else { return }
                withAnimation(HousekeepingMotion.breathe) { wide = true }
            }
            // A control can stop being the one a screen is asking for and then
            // start again — the sweep button is exactly that, going quiet for as
            // long as a sweep is running. Started only in `onAppear`, its halo
            // would breathe once and never come back.
            .onChange(of: active) { now in
                if now {
                    withAnimation(HousekeepingMotion.breathe) { wide = true }
                } else {
                    wide = false
                }
            }
    }
}
