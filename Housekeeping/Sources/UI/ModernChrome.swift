import SwiftUI

/// Static lighting gives the burgundy surfaces depth without an animation loop.
struct HousekeepingBackdrop: View {
    let style: UIStyle
    @Environment(\.colorScheme) private var scheme
    var sidebar = false

    var body: some View {
        let base = sidebar ? HousekeepingPalette.sidebar : style.windowBackground
        ZStack {
            base
            if !style.isRetro {
                LinearGradient(colors: [style.accent.opacity(sidebar ? 0.045 : 0.075), .clear, .black.opacity(scheme == .dark ? 0.12 : 0.025)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [style.accentShaded.opacity(sidebar ? 0.06 : 0.13), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 650)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HousekeepingCardChrome: ViewModifier {
    @Environment(\.uiStyle) private var style
    @Environment(\.colorScheme) private var scheme
    let radius: CGFloat
    let highlighted: Bool
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if style.isRetro {
            content
                .background(style.rowBackground)
                .overlay(Rectangle().strokeBorder(style.border, lineWidth: 1))
                .overlay(alignment: .top) { Rectangle().fill(.white).frame(height: 1).padding(.horizontal, 1).padding(.top, 1) }
                .overlay(alignment: .leading) { Rectangle().fill(.white).frame(width: 1).padding(.vertical, 1).padding(.leading, 1) }
        } else {
            modern(content)
        }
    }

    private func modern(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .background {
                shape.fill(style.rowBackground)
                shape.fill(LinearGradient(
                    colors: [style.accent.opacity(prominent ? 0.12 : (highlighted ? 0.09 : 0.035)), .clear, .black.opacity(scheme == .dark ? 0.06 : 0.015)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                shape.strokeBorder(LinearGradient(
                    colors: [Color.white.opacity(scheme == .dark ? 0.16 : 0.9), style.accent.opacity(highlighted ? 0.28 : 0.08), Color.primary.opacity(0.045)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(scheme == .dark ? (prominent ? 0.18 : 0.10) : 0.035),
                    radius: prominent ? 20 : 10, x: 0, y: prominent ? 10 : 5)
    }
}

extension View {
    func housekeepingCard(cornerRadius: CGFloat = 14, highlighted: Bool = false, prominent: Bool = false) -> some View {
        modifier(HousekeepingCardChrome(radius: cornerRadius, highlighted: highlighted, prominent: prominent))
    }
}

// MARK: - Buttons

/// Quiet shared controls with visible hover and press feedback. Classic 9
/// keeps its own drawn buttons.
struct HousekeepingButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    let style: UIStyle
    let kind: Kind
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(style.labelFont)
            .foregroundStyle(kind == .primary && enabled ? Color.white : style.text)
            .padding(.horizontal, kind == .quiet ? 9 : 13)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(kind == .primary ? style.accentShaded.opacity(enabled ? 1 : 0.22)
                          : Color.primary.opacity(hovering ? 0.08 : (kind == .quiet ? 0 : 0.04)))
                if kind == .primary {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(hovering ? 0.17 : 0.11), .clear, .black.opacity(0.09)],
                                             startPoint: .top, endPoint: .bottom))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(kind == .primary ? 0.28 : 0.12), Color.primary.opacity(0.06)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: kind == .quiet ? 0 : 0.75))
            .shadow(color: .black.opacity(kind == .primary && enabled ? 0.16 : 0), radius: 4, y: 2)
            .opacity(enabled ? 1 : 0.45)
            .brightness(configuration.isPressed ? -0.07 : 0)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 && enabled }
    }
}

struct RailButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    var isEnabled: Bool = true
    var help: String? = nil
    /// How long after the screen appears this one arrives, so the column fills
    /// in from the top instead of switching on all at once.
    var delay: Double = 0
    /// The one door on the rail that never stops moving. A pulse on the disc the
    /// app most wants pressed is the cheapest way to say which one that is, and
    /// on a rail of ten equals it is the only thing that says it at all.
    var breathes: Bool = false
    /// The one door that is not a symbol but the character itself.
    ///
    /// Every other door is a glyph in a coloured disc, which is right for a job
    /// and wrong for the housekeeper: the housekeeper is not a screen, it is who
    /// you go and talk to. So this disc carries the octopus, drawn the same way
    /// the menu bar draws it and on the same clock, and it works harder while the
    /// pointer is on it — the one place in the app where the mark is not a logo
    /// but a small animal noticing you.
    var showsOctopus: Bool = false
    let action: () -> Void

    @Environment(\.uiStyle) private var style
    @State private var hovering = false
    @State private var arrived = false
    @State private var blooming = false
    @ObservedObject private var budget = MotionBudget.shared
    @State private var onScreen = false

    private let diameter: CGFloat = 36

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                disc
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(labelColor)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(RailButtonStyle(tint: tint, enabled: isEnabled, hovering: hovering))
        .disabled(!isEnabled)
        // Arriving from the left rather than from above: the rail is a column, so
        // the direction the window has room for is sideways.
        .offset(x: arrived ? 0 : -16)
        .opacity(arrived ? 1 : 0)
        .onAppear {
            withAnimation(HousekeepingMotion.entrance.delay(delay)) { arrived = true }
        }
        .onHover { inside in
            hovering = inside && isEnabled
            guard hovering else { return }
            // A ring that leaves the disc when the pointer lands on it. It has to
            // be drawn at its small size for one frame before it can grow out of
            // it, which is why the animation starts on the next turn of the run
            // loop — set in the same turn, SwiftUI coalesces the two states and
            // the ring flies inwards instead.
            blooming = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                withAnimation(.easeOut(duration: 0.55)) { blooming = false }
            }
        }
        .help(help ?? title)
        .accessibilityLabel(title)
        .tracksOnScreen($onScreen)
    }

    /// The name brightens with the disc under the pointer. The two are one
    /// control, and a control that lights up in one half only reads as two.
    private var labelColor: Color {
        guard isEnabled else { return style.secondaryText.opacity(0.4) }
        return hovering ? style.text : style.secondaryText
    }

    private var disc: some View {
        ZStack {
            // A bloom that exists only under the pointer — the cheapest way to
            // make a small coloured object feel lit rather than painted.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(0.36), tint.opacity(0)],
                        center: .center,
                        startRadius: diameter * 0.34,
                        endRadius: diameter * 1.2
                    )
                )
                .frame(width: diameter * 2.4, height: diameter * 2.4)
                .opacity(hovering && isEnabled ? 1 : 0)

            // The socket. Without it the disc floats; with it the disc is
            // something taken out of the rail and raised.
            Circle()
                .fill(Color.black.opacity(0.32))
                .frame(width: diameter + 6, height: diameter + 6)
                .overlay {
                    Circle().strokeBorder(Color.black.opacity(0.38), lineWidth: 1)
                }

            // The ring that leaves the disc when the pointer arrives. It starts
            // where the socket ends and fades as it grows, so it reads as a knock
            // on the door rather than as a second border appearing.
            Circle()
                .strokeBorder(tint.opacity(0.55), lineWidth: 1.5)
                .frame(width: diameter + 6, height: diameter + 6)
                .scaleEffect(blooming ? 1 : 1.7)
                .opacity(blooming ? 0.85 : 0)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.60)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: diameter, height: diameter)
                .overlay {
                    Circle().strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.58), Color.white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
                .shadow(
                    color: tint.opacity(hovering ? 0.72 : 0.40),
                    radius: hovering ? 10 : 5,
                    y: hovering ? 4 : 2
                )

            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: diameter * 0.58, height: diameter * 0.30)
                .blur(radius: 2.5)
                .offset(y: -diameter * 0.25)

            glyph
                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
        }
        .frame(width: diameter + 6, height: diameter + 6)
        .scaleEffect(hovering && isEnabled ? 1.07 : 1)
        .animation(HousekeepingMotion.hover, value: hovering)
        .breathingHalo(tint, radius: 20, active: breathes && isEnabled)
    }

    /// A symbol in a disc, or the octopus in a disc. The clock is the same one
    /// the menu bar uses, so the small octopus on this rail and the small octopus
    /// in the menu bar are breathing in step — and both stop on the same budget,
    /// so a rail behind a closed window costs nothing either.
    @ViewBuilder
    private var glyph: some View {
        if showsOctopus {
            if budget.isTicking && onScreen {
                TimelineView(.periodic(from: .now, by: 1.0 / 20)) { context in
                    mark(at: context.date.timeIntervalSinceReferenceDate)
                }
            } else {
                mark(at: 0)
            }
        } else {
            Image(systemName: systemImage)
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func mark(at time: Double) -> some View {
        OctopusMark(
            time: time,
            color: .white,
            // It leans into the work when the pointer arrives, which is the whole
            // joke: this is the door that talks back.
            effort: hovering ? 1 : 0,
            // One colour on a coloured disc: the dress, the apron and the eyes read
            // as cut-outs rather than as separate inks.
            rendering: .singleColour
        )
        // Taller than it is wide, because the tentacles hang below the head and the
        // disc is round — squaring this crops the arms and the mark becomes an
        // octopus-shaped blob.
        .frame(width: diameter * 0.80, height: diameter * 0.80)
        .offset(y: diameter * 0.03)
    }
}

/// A bar with a length: work that can say how much of itself is left.
///
/// The Mac's own `ProgressView` draws a determinate bar only when it is handed a
/// value, and its bar ignores the app's two appearances entirely. This is the same
/// idea in the app's own ink, carrying the sentence that belongs above it and the
/// line that belongs under it, so a long operation can say "12 of 210" in one
/// place instead of a spinner that could mean anything.
struct ProgressBar: View {
    @Environment(\.uiStyle) private var style

    /// 0 … 1, or `nil` while the length of the work is still unknown — a pass that
    /// is still counting what it has to do. Clamped here rather than at every call
    /// site. `nil` draws a bar that travels instead of filling, so the two states
    /// look different and neither of them lies.
    var fraction: Double?
    var caption: String?
    var detail: String?
    var height: CGFloat = 8
    var tint: Color?

    private var clamped: Double { min(1, max(0, fraction ?? 0)) }

    @State private var travelling = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let caption {
                HStack(spacing: 8) {
                    Text(caption)
                        .font(style.labelFont)
                        .foregroundColor(style.text)
                    Spacer(minLength: 8)
                    if fraction != nil {
                        Text("\(Int((clamped * 100).rounded()))%")
                            .font(style.smallFont)
                            .foregroundColor(style.secondaryText)
                            .monospacedDigit()
                    }
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(style.border.opacity(0.30))

                    if fraction == nil {
                        // A third of the bar, travelling. The animation is on the
                        // offset of one capsule, so it costs a composited layer
                        // rather than a redraw of the view behind it.
                        Capsule()
                            .fill((tint ?? style.accent).opacity(0.85))
                            .frame(width: proxy.size.width / 3)
                            .offset(x: travelling ? proxy.size.width : -proxy.size.width / 3)
                            .animation(
                                .linear(duration: 1.15).repeatForever(autoreverses: false),
                                value: travelling
                            )
                            .onAppear { travelling = true }
                    } else {
                        Capsule()
                            .fill(tint ?? style.accent)
                            .frame(width: max(clamped > 0 ? 4 : 0, proxy.size.width * CGFloat(clamped)))
                            .animation(.easeOut(duration: 0.25), value: clamped)
                    }
                }
            }
            .frame(height: height)
            .clipShape(Capsule())

            if let detail {
                Text(detail)
                    .font(style.smallFont)
                    .foregroundColor(style.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(fraction == nil ? "working" : "\(Int((clamped * 100).rounded())) percent")
    }
}

/// The row highlight, the lift, and the spring on release.
struct RailButtonStyle: ButtonStyle {
    let tint: Color
    let enabled: Bool
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(hovering && enabled ? 0.13 : 0))
            )
            .scaleEffect(configuration.isPressed ? 0.97 : (hovering && enabled ? 1.015 : 1))
            .opacity(enabled ? 1 : 0.45)
            .animation(HousekeepingMotion.press, value: configuration.isPressed)
            .animation(HousekeepingMotion.hover, value: hovering)
    }
}

// MARK: - Hero meter

/// The big ring a screen shows while it is working, and after it has finished.
///
/// CleanMyMac puts a large centred dial where the important number is the
/// largest thing on screen. `progress` of `nil` means there is no number to
/// report yet, and the ring orbits instead of lying about being at zero.
struct HeroMeter: View {
    let progress: Double?
    let symbol: String
    let caption: String
    var detail: String? = nil
    var size: CGFloat = 176
    /// What sits in the middle when the number there is not a percentage.
    ///
    /// A reading that has finished has no part-of-a-whole left to report — it has
    /// an amount, "4.1 GB", and a percentage of nothing in particular would be a
    /// worse answer than the amount. The ring is still the right shape to hold it,
    /// so the ring stays and only the figure inside it changes.
    var centerText: String? = nil

    @Environment(\.uiStyle) private var style

    @State private var arrived = false
    @State private var orbiting = false

    private let strokeWidth: CGFloat = 12

    private var fraction: Double { max(0, min(1, progress ?? 0)) }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [style.accent.opacity(0.30), style.accent.opacity(0)],
                        center: .center,
                        startRadius: size * 0.16,
                        endRadius: size * 0.60
                    )
                )
                .frame(width: size * 1.5, height: size * 1.5)
                .scaleEffect(arrived ? 1 : 0.82)

            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: strokeWidth)
                .frame(width: size, height: size)

            progressRing
                .frame(width: size, height: size)

            readout
        }
        .frame(width: size * 1.5, height: size * 1.5)
        .onAppear {
            withAnimation(HousekeepingMotion.entrance) { arrived = true }
            if progress == nil {
                withAnimation(HousekeepingMotion.orbit) { orbiting = true }
            }
        }
    }

    @ViewBuilder
    private var progressRing: some View {
        let sweep = AngularGradient(
            gradient: Gradient(colors: [style.accentShaded, style.accent, style.accentLifted, style.accentShaded]),
            center: .center
        )
        if progress != nil {
            Circle()
                .trim(from: 0, to: arrived ? fraction : 0)
                .stroke(sweep, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: style.accent.opacity(0.55), radius: 10)
                .animation(HousekeepingMotion.settle, value: fraction)
                .animation(HousekeepingMotion.entrance, value: arrived)
        } else {
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(sweep, style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                .rotationEffect(.degrees(orbiting ? 360 : 0))
                .shadow(color: style.accent.opacity(0.55), radius: 10)
        }
    }

    private var readout: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(style.accent)
                .padding(.bottom, 2)

            if let centerText {
                Text(centerText)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.45)
                    .lineLimit(1)
                    .foregroundStyle(style.text)
                    .contentTransition(.numericText())
                    .animation(HousekeepingMotion.count, value: centerText)
                    .frame(maxWidth: size * 0.74)
            } else if progress != nil {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(style.text)
                    .contentTransition(.numericText())
                    .animation(HousekeepingMotion.count, value: fraction)
            }

            Text(caption)
                .font(style.bodyFont)
                .foregroundStyle(style.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: size * 0.72)

            if let detail {
                Text(detail)
                    .font(style.smallFont)
                    .foregroundStyle(style.secondaryText.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: size * 0.72)
            }
        }
    }
}

// MARK: - Small pieces

/// A tinted rounded square holding one glyph — the building block of every
/// checklist and sidebar in CleanMyMac's vocabulary.
struct IconChip: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [tint.opacity(0.34), tint.opacity(0.13)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                    .strokeBorder(tint.opacity(0.32), lineWidth: 1)
            }
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: size, height: size)
    }
}

/// A floating rounded container for a run of controls. Used to turn the job bar
/// from a flat strip into something that reads as an object sitting on the
/// window.
struct TrayBar<Content: View>: View {
    @Environment(\.uiStyle) private var style
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(style.border.opacity(0.22), lineWidth: 1)
            }
    }
}

/// A small state capsule — "Up to date", "3 changes behind".
struct BadgePill: View {
    let text: String
    let systemImage: String?
    let tint: Color

    @Environment(\.uiStyle) private var style

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 10, weight: .bold))
            }
            Text(text)
        }
        .font(style.smallFont.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.16)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.32), lineWidth: 1))
    }
}
