import SwiftUI

// MARK: - Buttons

/// The modern replacement for stock `.borderedProminent` / `.bordered`.
///
/// CleanMyMac and Mole both make the primary action read as a lit object: a
/// filled gradient pill with a halo, a slight lift under the pointer, and a
/// spring on release. Stock AppKit buttons have none of that, which is most of
/// why the app read as "system dialogue box" rather than "finished product".
///
/// Classic 9 never reaches here — `ThemeButton` sends it to `RetroButton`.
struct HousekeepingButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        /// For dense toolbars: no chrome until the pointer arrives.
        case quiet
    }

    let style: UIStyle
    let kind: Kind

    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(style.labelFont)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(fill)
            .overlay(border)
            .clipShape(shape)
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
            .scaleEffect(configuration.isPressed ? 0.965 : (hovering && enabled ? 1.02 : 1))
            .animation(HousekeepingMotion.press, value: configuration.isPressed)
            .animation(HousekeepingMotion.hover, value: hovering)
            .onHover { hovering = $0 && enabled }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: kind == .quiet ? 7 : 10, style: .continuous)
    }

    private var horizontalPadding: CGFloat {
        switch kind {
        case .primary: return 16
        case .secondary: return 14
        case .quiet: return 10
        }
    }

    private var verticalPadding: CGFloat {
        switch kind {
        case .primary: return 8
        case .secondary: return 7
        case .quiet: return 5
        }
    }

    private var foreground: Color {
        guard enabled else { return style.secondaryText }
        switch kind {
        case .primary: return .white
        case .secondary: return style.text
        case .quiet: return hovering ? style.text : style.secondaryText
        }
    }

    @ViewBuilder
    private var fill: some View {
        switch kind {
        case .primary:
            shape
                .fill(
                    LinearGradient(
                        colors: [style.accentLifted, style.accent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .brightness(hovering ? 0.06 : 0)
        case .secondary:
            shape.fill(hovering ? style.accent.opacity(0.16) : Color.white.opacity(0.07))
        case .quiet:
            shape.fill(hovering ? Color.white.opacity(0.09) : Color.clear)
        }
    }

    @ViewBuilder
    private var border: some View {
        switch kind {
        case .primary:
            // Light along the top edge, absent along the bottom — the cheap
            // trick that makes a flat fill read as a raised surface.
            shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.42), Color.white.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        case .secondary:
            shape.strokeBorder(style.border.opacity(hovering ? 0.55 : 0.28), lineWidth: 1)
        case .quiet:
            EmptyView()
        }
    }

    private var shadowColor: Color {
        guard enabled else { return .clear }
        switch kind {
        case .primary: return style.accent.opacity(hovering ? 0.55 : 0.36)
        case .secondary: return Color.black.opacity(0.25)
        case .quiet: return .clear
        }
    }

    private var shadowRadius: CGFloat {
        switch kind {
        case .primary: return hovering ? 15 : 9
        case .secondary: return 3
        case .quiet: return 0
        }
    }

    private var shadowY: CGFloat {
        switch kind {
        case .primary: return hovering ? 6 : 4
        case .secondary: return 1
        case .quiet: return 0
        }
    }
}

// MARK: - Rail

/// One destination on the navigation rail: a coloured disc with its name beside
/// it.
///
/// The bar the rail replaces was a row of rectangles reading left to right,
/// which is the shape of a toolbar and therefore the shape of a sequence — as
/// though the buttons were steps and one followed another. They are not: they
/// are separate doors into separate jobs, and a column says so.
///
/// Most of the drawing here is depth, and deliberately. A flat circle with a
/// glyph in it reads as a sticker printed on the rail; a disc that is lit along
/// its top edge, drops a shadow of its own colour, and sits inside a darker
/// socket reads as something raised off the surface and pressable — which is
/// the reason the lift under the pointer and the spring on release are worth
/// having at all. The hue is the other half: it says which kind of door this is
/// without the reader having to check which group of the rail they are in.
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

    private let diameter: CGFloat = 36

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                disc
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
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
    /// in the menu bar are breathing in step.
    @ViewBuilder
    private var glyph: some View {
        if showsOctopus {
            TimelineView(.periodic(from: .now, by: 1.0 / 12)) { context in
                OctopusMark(
                    time: context.date.timeIntervalSinceReferenceDate,
                    color: .white,
                    // It leans into the work when the pointer arrives, which is
                    // the whole joke: this is the door that talks back.
                    effort: hovering ? 1 : 0,
                    // One colour on a coloured disc: the dress, the apron and the
                    // eyes read as cut-outs rather than as separate inks.
                    rendering: .singleColour
                )
                // Taller than it is wide, because the tentacles hang below the
                // head and the disc is round — squaring this crops the arms and
                // the mark becomes an octopus-shaped blob.
                .frame(width: diameter * 0.80, height: diameter * 0.80)
                .offset(y: diameter * 0.03)
            }
        } else {
            Image(systemName: systemImage)
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
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
