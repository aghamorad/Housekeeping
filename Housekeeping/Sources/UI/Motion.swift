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
