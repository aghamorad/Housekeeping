import SwiftUI

/// MediaDock 9's colours and type, resolved from the appearance of the house it
/// now lives in. MediaDock has no palette of its own any more: the same screen is
/// drawn twice, once as a classic front end and once in Housekeeping's Liquid
/// Glass, and which one a reader sees is the theme Housekeeping is wearing.
struct MediaDockSkin {
    let isRetro: Bool

    let desktop: Color
    let chrome: Color
    let paper: Color
    let field: Color
    let ink: Color
    let darkEdge: Color
    let midEdge: Color
    let highlight: Color
    let cyan: Color
    let green: Color
    let amber: Color
    let red: Color
    /// The wash behind a chosen row in the sidebar.
    let selection: Color
    /// The activity console's own dark ground. It is darker than a panel in both
    /// appearances because it is a terminal, not a card.
    let console: Color

    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        isRetro
            ? .system(size: size, weight: weight, design: .rounded)
            : .system(size: size, weight: weight)
    }

    static let retro = MediaDockSkin(
        isRetro: true,
        desktop: Color(red: 0.43, green: 0.45, blue: 0.46),
        chrome: Color(red: 0.82, green: 0.82, blue: 0.79),
        paper: Color(red: 0.91, green: 0.90, blue: 0.86),
        field: Color(red: 0.97, green: 0.96, blue: 0.91),
        ink: Color(red: 0.08, green: 0.09, blue: 0.09),
        darkEdge: Color(red: 0.18, green: 0.19, blue: 0.19),
        midEdge: Color(red: 0.48, green: 0.49, blue: 0.47),
        highlight: Color.white.opacity(0.86),
        cyan: Color(red: 0.03, green: 0.72, blue: 0.73),
        green: Color(red: 0.20, green: 0.66, blue: 0.34),
        amber: Color(red: 0.91, green: 0.59, blue: 0.12),
        red: Color(red: 0.78, green: 0.20, blue: 0.18),
        selection: Color(red: 0.91, green: 0.90, blue: 0.86),
        console: Color(red: 0.10, green: 0.11, blue: 0.11)
    )

    /// The house's own colours, taken from `HousekeepingInk` rather than restated:
    /// a panel here has to be the same maroon as a panel anywhere else, or the
    /// screen reads as another app wearing the house's wallpaper.
    static let glass = MediaDockSkin(
        isRetro: false,
        desktop: HousekeepingInk.surface,
        chrome: HousekeepingInk.surface,
        paper: HousekeepingInk.surfaceRaised,
        field: Color.white.opacity(0.06),
        ink: HousekeepingInk.text,
        darkEdge: HousekeepingInk.hairline,
        midEdge: HousekeepingInk.hairline.opacity(0.8),
        highlight: Color.white.opacity(0.10),
        cyan: HousekeepingInk.redLifted,
        green: HousekeepingInk.positive,
        amber: HousekeepingInk.caution,
        red: HousekeepingInk.negative,
        selection: HousekeepingInk.red.opacity(0.30),
        console: Color(red: 0.08, green: 0.02, blue: 0.015)
    )

    static func resolve(_ style: UIStyle) -> MediaDockSkin {
        style.isRetro ? .retro : .glass
    }

    var cardRadius: CGFloat { isRetro ? 0 : 14 }
    var fieldRadius: CGFloat { isRetro ? 0 : 10 }
    var buttonRadius: CGFloat { isRetro ? 0 : 9 }
}

private struct MediaDockSkinKey: EnvironmentKey {
    static let defaultValue = MediaDockSkin.glass
}

extension EnvironmentValues {
    var mediaDockSkin: MediaDockSkin {
        get { self[MediaDockSkinKey.self] }
        set { self[MediaDockSkinKey.self] = newValue }
    }
}

struct RaisedBorder: ViewModifier {
    var emphasized = false
    @Environment(\.mediaDockSkin) private var skin

    func body(content: Content) -> some View {
        Group {
            if skin.isRetro {
                retro(content)
            } else {
                glass(content)
            }
        }
    }

    private func retro(_ content: Content) -> some View {
        content
            .background(skin.chrome)
            .overlay(alignment: .top) { Rectangle().fill(skin.highlight).frame(height: emphasized ? 2 : 1) }
            .overlay(alignment: .leading) { Rectangle().fill(skin.highlight).frame(width: emphasized ? 2 : 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(skin.darkEdge).frame(height: emphasized ? 2 : 1) }
            .overlay(alignment: .trailing) { Rectangle().fill(skin.darkEdge).frame(width: emphasized ? 2 : 1) }
    }

    private func glass(_ content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: skin.cardRadius, style: .continuous)
        return content
            .background(
                shape.fill(skin.paper)
                    .overlay(
                        shape.fill(LinearGradient(
                            colors: [Color.white.opacity(emphasized ? 0.11 : 0.06), .clear],
                            startPoint: .top, endPoint: .bottom))
                    )
            )
            .overlay(shape.strokeBorder(skin.darkEdge, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.30), radius: 12, x: 0, y: 5)
    }
}

struct InsetBorder: ViewModifier {
    @Environment(\.mediaDockSkin) private var skin

    func body(content: Content) -> some View {
        Group {
            if skin.isRetro {
                content
                    .background(skin.field)
                    .overlay(alignment: .top) { Rectangle().fill(skin.darkEdge).frame(height: 1) }
                    .overlay(alignment: .leading) { Rectangle().fill(skin.darkEdge).frame(width: 1) }
                    .overlay(alignment: .bottom) { Rectangle().fill(skin.highlight).frame(height: 1) }
                    .overlay(alignment: .trailing) { Rectangle().fill(skin.highlight).frame(width: 1) }
            } else {
                let shape = RoundedRectangle(cornerRadius: skin.fieldRadius, style: .continuous)
                content
                    .background(shape.fill(skin.field))
                    .overlay(shape.strokeBorder(skin.darkEdge, lineWidth: 1))
            }
        }
    }
}

extension View {
    func raisedBorder(emphasized: Bool = false) -> some View { modifier(RaisedBorder(emphasized: emphasized)) }
    func insetBorder() -> some View { modifier(InsetBorder()) }
}

struct MediaDockButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        MediaDockButtonBody(configuration: configuration, prominent: prominent)
    }
}

/// Split out of the style so the button can read the environment. `makeBody`
/// runs outside the view hierarchy's dynamic properties; a small view does not.
private struct MediaDockButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.mediaDockSkin) private var skin
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Group {
            if skin.isRetro {
                retro
            } else {
                glass
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var label: some View {
        configuration.label
            .font(skin.font(12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
    }

    private var retro: some View {
        label
            .foregroundStyle(skin.ink.opacity(configuration.isPressed ? 0.62 : 1))
            .background(prominent ? skin.paper : skin.chrome)
            .raisedBorder(emphasized: prominent)
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
    }

    private var glass: some View {
        let shape = RoundedRectangle(cornerRadius: skin.buttonRadius, style: .continuous)
        return label
            .foregroundStyle(prominent ? Color.white : skin.ink)
            .background(
                shape.fill(
                    prominent
                        ? AnyShapeStyle(LinearGradient(
                            colors: [HousekeepingInk.redLifted, HousekeepingInk.red],
                            startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(Color.white.opacity(configuration.isPressed ? 0.12 : 0.07))
                )
            )
            .overlay(
                shape.strokeBorder(prominent ? Color.white.opacity(0.14) : skin.darkEdge, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct RetroPanel<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.mediaDockSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(skin.font(10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(skin.isRetro ? skin.ink : skin.secondaryInk)
                Rectangle().fill(skin.midEdge).frame(height: 1)
            }
            content()
        }
        .foregroundStyle(skin.ink)
        .padding(14)
        .raisedBorder()
    }
}

extension MediaDockSkin {
    /// A panel heading in Liquid Glass is a quiet label rather than a heading;
    /// in Classic 9 it is the same ink as the card, which is what the bevel came
    /// from.
    var secondaryInk: Color { isRetro ? ink : HousekeepingInk.secondaryText }
}

struct StatusLight: View {
    let color: Color
    @Environment(\.mediaDockSkin) private var skin

    var body: some View {
        Group {
            if skin.isRetro {
                Rectangle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                    .overlay(Rectangle().stroke(skin.darkEdge, lineWidth: 1))
                    .shadow(color: color.opacity(0.45), radius: 2)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .shadow(color: color.opacity(0.65), radius: 4)
            }
        }
    }
}

struct RetroTextField: View {
    let placeholder: String
    @Binding var text: String
    @Environment(\.mediaDockSkin) private var skin

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(skin.isRetro ? .system(size: 13, design: .monospaced) : .system(size: 13))
            .foregroundStyle(skin.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .insetBorder()
    }
}

struct PropertyRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    @Environment(\.mediaDockSkin) private var skin

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(skin.font(12, weight: .semibold))
                .foregroundStyle(skin.secondaryInk)
                .frame(width: 122, alignment: .trailing)
            content()
                .font(skin.font(12))
            Spacer(minLength: 0)
        }
    }
}

struct ThinRule: View {
    @Environment(\.mediaDockSkin) private var skin
    var body: some View { Rectangle().fill(skin.midEdge.opacity(0.7)).frame(height: 1) }
}
