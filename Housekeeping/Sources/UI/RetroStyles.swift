// Housekeeping — Retro UI Styles
// Mac OS 9 / Platinum interface styling for SwiftUI

import SwiftUI
import AppKit

// MARK: - Color Palette (Mac OS 9)

struct RetroColors {
    // Classic Mac OS 9 palette
    static let titleBarGradientStart = Color(red: 176/255, green: 182/255, blue: 198/255)
    static let titleBarGradientEnd = Color(red: 130/255, green: 140/255, blue: 160/255)
    static let windowBackground = Color(red: 242/255, green: 242/255, blue: 238/255)
    static let panelBackground = Color(red: 226/255, green: 228/255, blue: 224/255)
    static let buttonFace = Color(red: 238/255, green: 238/255, blue: 234/255)
    static let buttonHighlight = Color.white
    static let buttonShadow = Color(red: 128/255, green: 128/255, blue: 128/255)
    static let darkText = Color(red: 20/255, green: 20/255, blue: 20/255)
    static let secondaryText = Color(red: 48/255, green: 48/255, blue: 48/255)
    static let warningText = Color(red: 108/255, green: 58/255, blue: 0/255)
    static let criticalText = Color(red: 148/255, green: 18/255, blue: 18/255)
    static let lightText = Color.white
    static let insetBorder = Color(red: 128/255, green: 128/255, blue: 128/255)
    static let outsetBorder = Color.white
    static let stripedBackground = Color(red: 200/255, green: 200/255, blue: 200/255)
    static let selectedItem = Color(red: 36/255, green: 91/255, blue: 168/255)
    static let selectionOverlay = Color(red: 190/255, green: 214/255, blue: 246/255)

    // Modern system colors
    static let systemBackground = Color(NSColor.controlBackgroundColor)
    static let systemText = Color(NSColor.textColor)
    static let systemSelectedText = Color(NSColor.selectedControlTextColor)
    static let systemSelectedBackground = Color(NSColor.selectedControlColor)
}

// MARK: - The app's own colour

/// The colour Housekeeping wears, taken from the octopus in its icon.
///
/// These are the icon's own pixels, weighted by how much of the tile each covers:
/// the lit red of its face, the shaded red it rolls off into, and the deep maroon
/// underneath both. The app wears them the way the icon does — the maroon is the
/// surface everything sits on, the lit red is for what wants attention. Nothing
/// here is a mood; it is the same red, from the same picture.
struct HousekeepingInk {
    /// The tile's lit face: what the icon is recognised by when it is small.
    static let red = Color(red: 144/255, green: 32/255, blue: 24/255)
    /// The same red lifted. For glyphs and links on maroon, where the tile's own
    /// value would sink into the background instead of standing on it.
    static let redLifted = Color(red: 205/255, green: 74/255, blue: 60/255)
    /// The shaded part of the tile, and the app's hairlines.
    static let redShaded = Color(red: 92/255, green: 15/255, blue: 10/255)
    /// The line between one surface and the next.
    static let hairline = Color(red: 122/255, green: 34/255, blue: 26/255)

    /// The icon's deepest maroon: the surface the window is made of.
    static let surface = Color(red: 40/255, green: 7/255, blue: 5/255)
    /// A surface raised off that one — panels, cards, the grouping behind a list.
    static let surfaceRaised = Color(red: 58/255, green: 12/255, blue: 9/255)

    /// The icon's sheen, warmed: light enough to read a paragraph by.
    static let text = Color(red: 242/255, green: 228/255, blue: 225/255)
    static let secondaryText = Color(red: 201/255, green: 164/255, blue: 157/255)

    // The three verdicts keep their usual meanings, but they have to be legible on
    // maroon and they must not be mistaken for the app's own red — a warning that
    // looks like the brand is a warning that does not read as one.
    static let positive = Color(red: 111/255, green: 199/255, blue: 152/255)
    static let caution = Color(red: 232/255, green: 168/255, blue: 79/255)
    static let negative = Color(red: 255/255, green: 108/255, blue: 86/255)
}

/// The burgundy identity is shared by the modern window and its controls.
/// Light mode keeps the same warm undertone with sufficient text contrast.
enum HousekeepingPalette {
    private static func adaptive(dark: (CGFloat, CGFloat, CGFloat), light: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: 1)
        })
    }

    static let background = adaptive(dark: (38, 12, 16), light: (249, 244, 241))
    static let sidebar = adaptive(dark: (28, 14, 17), light: (239, 229, 224))
    static let panel = adaptive(dark: (51, 29, 33), light: (255, 252, 250))
    static let raised = adaptive(dark: (64, 37, 41), light: (240, 228, 223))
    static let accent = adaptive(dark: (234, 177, 158), light: (158, 47, 39))
    static let button = adaptive(dark: (151, 57, 58), light: (158, 47, 39))
}

// MARK: - Retro Typography

struct RetroTypography {
    static let titleFont = Font.system(size: 14, weight: .bold)
    static let bodyFont = Font.system(size: 13)
    static let smallFont = Font.system(size: 12)
    static let buttonFont = Font.system(size: 13, weight: .semibold)
}

// MARK: - Retro Views

struct RetroWindowBackground<Content: View>: View {
    let title: String
    let subtitle: String?
    let onClose: (() -> Void)?
    let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        onClose: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onClose = onClose
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            TitleBarView(title: title, subtitle: subtitle, onClose: onClose)
                .frame(height: 28)
            content()
                .background(RetroColors.windowBackground)
                .border(RetroColors.outsetBorder, width: 1)
        }
        .border(RetroColors.insetBorder, width: 1)
    }
}

struct TitleBarView: View {
    let title: String
    let subtitle: String?
    var onClose: (() -> Void)? = nil

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.91), Color(white: 0.75)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 2) {
                ForEach(0..<6, id: \.self) { _ in
                    Rectangle().fill(Color.black.opacity(0.16)).frame(height: 1)
                }
            }.padding(.horizontal, 12)
            HStack(spacing: 8) {
                Text(title).font(RetroTypography.titleFont)
                if let subtitle {
                    Text("·").foregroundStyle(RetroColors.secondaryText)
                    Text(subtitle).font(RetroTypography.smallFont)
                }
            }
            .foregroundStyle(RetroColors.darkText)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Color(white: 0.85))
        }
        .overlay(alignment: .top) { Rectangle().fill(.white).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(RetroColors.insetBorder).frame(height: 1) }
    }
}

struct CloseButton: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        let isDark = colorScheme == .dark
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .circular)
                .fill(Color(red: isDark ? 0.9 : 128/255, green: isDark ? 0.9 : 128/255, blue: isDark ? 0.9 : 128/255))
                .border(Color(red: 64/255, green: 64/255, blue: 64/255), width: 1)
            RoundedRectangle(cornerRadius: 1, style: .circular)
                .fill(Color.white)
                .border(Color(red: isDark ? 0.9 : 192/255, green: isDark ? 0.9 : 192/255, blue: isDark ? 0.9 : 192/255), width: 1)
            Text("✕")
                .font(Font.system(size: 9, weight: .bold, design: .default))
                .foregroundColor(.black)
        }
    }
}

// MARK: - Retro Controls

struct RetroButton: View {
    let label: String
    let action: () -> Void
    var isDefault: Bool = false

    var body: some View {
        Button(action: action) {
            Text(label).lineLimit(1)
        }
        .buttonStyle(RetroButtonStyle(isDefault: isDefault))
    }
}

struct RetroInsetPanel: View {
    var content: AnyView
    let padding: CGFloat

    init(padding: CGFloat = 8, @ViewBuilder content: @escaping () -> some View) {
        self.content = AnyView(content())
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(RetroColors.panelBackground)
                    Rectangle().fill(Color(red: 128/255, green: 128/255, blue: 128/255)).frame(width: 1).offset(x: -1)
                    Rectangle().fill(Color(red: 128/255, green: 128/255, blue: 128/255)).frame(height: 1).offset(y: -1)
                    Rectangle().fill(Color.white).frame(width: 1).offset(x: 1)
                    Rectangle().fill(Color.white).frame(height: 1).offset(y: 1)
                }
            )
    }
}

struct RetroDisclosureTriangle: View {
    let isExpanded: Bool

    var body: some View {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(RetroTypography.smallFont)
            .foregroundColor(RetroColors.darkText)
            .scaleEffect(x: 1.2, y: 1.0)
    }
}

struct RetroCheckbox: View {
    let isChecked: Bool
    var isMixed: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isChecked {
                    RoundedRectangle(cornerRadius: 1, style: .circular)
                        .fill(RetroColors.darkText).frame(width: 18, height: 18)
                    Text("✓").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                } else if isMixed {
                    RoundedRectangle(cornerRadius: 1, style: .circular)
                        .fill(Color.white).frame(width: 18, height: 18)
                        .border(RetroColors.darkText, width: 2)
                    Text("–").font(.system(size: 13, weight: .bold)).foregroundColor(RetroColors.darkText)
                } else {
                    RoundedRectangle(cornerRadius: 1, style: .circular)
                        .fill(Color.white).frame(width: 18, height: 18)
                        .border(RetroColors.darkText, width: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 22, height: 22)
    }
}

struct RetroProgressView: View {
    let progress: Float
    let label: String

    /// The track's full width. The filled part is a fraction of this, so the two
    /// numbers have to be the same number.
    private let trackWidth: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(RetroTypography.smallFont).foregroundColor(RetroColors.darkText)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1, style: .circular)
                    .fill(Color(red: 200/255, green: 200/255, blue: 200/255))
                    .frame(width: trackWidth, height: 16)
                    .border(Color(red: 128/255, green: 128/255, blue: 128/255), width: 1)
                if progress > 0 {
                    RoundedRectangle(cornerRadius: 1, style: .circular)
                        .fill(Color(red: 130/255, green: 170/255, blue: 255/255))
                        .frame(
                            width: trackWidth * CGFloat(min(max(progress, 0), 1)),
                            height: 14
                        )
                        .padding(.leading, 1)
                }
            }
            .frame(width: trackWidth)
        }
    }
}

/// Housekeeping has two appearances, not two applications. These tokens are the
/// whole difference between them: every screen is built once and reads its
/// colours, fonts, and chrome from here. Keeping the difference this narrow is
/// what stops one appearance from quietly falling behind the other.
struct UIStyle {
    let theme: AppState.Theme

    var isRetro: Bool { theme == .classic9 }

    let text: Color
    let secondaryText: Color
    let accent: Color
    /// The accent at the light end, for the top of a gradient or the bright part
    /// of a sweep. Equal to `accent` in Classic 9, which is flat by nature.
    let accentLifted: Color
    /// The accent at the dark end.
    let accentShaded: Color
    let border: Color
    let rowSelection: Color
    let rowBackground: Color
    let windowBackground: Color
    let groupingBackground: Color
    let positive: Color
    let caution: Color
    let negative: Color

    let titleFont: Font
    let bodyFont: Font
    let smallFont: Font
    let labelFont: Font
    let pathFont: Font

    static func resolve(_ theme: AppState.Theme) -> UIStyle {
        switch theme {
        case .classic9:
            return UIStyle(
                theme: theme,
                text: RetroColors.darkText,
                secondaryText: RetroColors.secondaryText,
                accent: RetroColors.selectedItem,
                accentLifted: RetroColors.selectedItem,
                accentShaded: RetroColors.selectedItem,
                border: RetroColors.insetBorder,
                rowSelection: RetroColors.selectionOverlay,
                rowBackground: RetroColors.panelBackground,
                windowBackground: RetroColors.windowBackground,
                groupingBackground: RetroColors.panelBackground,
                positive: Color(red: 22/255, green: 108/255, blue: 54/255),
                caution: RetroColors.warningText,
                negative: RetroColors.criticalText,
                titleFont: Font.system(size: 22, weight: .bold),
                bodyFont: RetroTypography.bodyFont,
                smallFont: RetroTypography.smallFont,
                labelFont: RetroTypography.smallFont.bold(),
                pathFont: Font.system(size: 11, weight: .regular, design: .monospaced)
            )
        case .liquidGlass:
            return UIStyle(
                theme: theme,
                text: .primary,
                secondaryText: .secondary,
                accent: HousekeepingPalette.accent,
                accentLifted: HousekeepingPalette.accent,
                accentShaded: HousekeepingPalette.button,
                border: Color.primary.opacity(0.10),
                rowSelection: HousekeepingPalette.accent.opacity(0.13),
                rowBackground: HousekeepingPalette.panel,
                windowBackground: HousekeepingPalette.background,
                groupingBackground: HousekeepingPalette.raised,
                positive: .green,
                caution: .orange,
                negative: .red,
                titleFont: .system(size: 27, weight: .semibold),
                bodyFont: .system(size: 14),
                smallFont: .system(size: 12),
                labelFont: .system(size: 13, weight: .semibold),
                pathFont: .system(size: 11, design: .monospaced)
            )
        }
    }
}

private struct UIStyleKey: EnvironmentKey {
    static let defaultValue = UIStyle.resolve(.liquidGlass)
}

extension EnvironmentValues {
    var uiStyle: UIStyle {
        get { self[UIStyleKey.self] }
        set { self[UIStyleKey.self] = newValue }
    }
}

// MARK: - Theme-aware chrome

/// Shared panels keep a thin border and a restrained raised surface.
private struct ThemePanelChrome: ViewModifier {
    @Environment(\.uiStyle) private var style
    let isRetro: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isRetro {
            content.background(RetroColors.panelBackground)
                .overlay(Rectangle().stroke(RetroColors.insetBorder, lineWidth: 1))
        } else {
            content
                .housekeepingCard(cornerRadius: 12)
        }
    }
}

struct ThemePanel<Content: View>: View {
    @Environment(\.uiStyle) private var style
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .modifier(ThemePanelChrome(isRetro: style.isRetro))
    }
}

struct ThemeButton: View {
    @Environment(\.uiStyle) private var style
    let title: String
    var systemImage: String? = nil
    var isPrimary: Bool = false
    var isEnabled: Bool = true
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        content
            .disabled(!isEnabled)
            // Classic 9 draws no disabled state of its own, so it is dimmed here.
            // The modern button style reads `isEnabled` itself and dims its own
            // fill, edges and shadow — dimming twice would read as "broken"
            // rather than "unavailable".
            .opacity(style.isRetro && !isEnabled ? 0.4 : 1)
            .helpIfPresent(help)
            // SwiftUI does not derive an accessibility name from a drawn label, so
            // without this every button in Housekeeping reaches VoiceOver — and any
            // script driving the app — as an unnamed "button".
            .accessibilityLabel(title)
            .accessibilityHint(help ?? "")
    }

    @ViewBuilder
    private var content: some View {
        if style.isRetro {
            RetroButton(label: title, action: action, isDefault: isPrimary)
        } else {
            Button(action: action) { label }
                .buttonStyle(HousekeepingButtonStyle(style: style, kind: isPrimary ? .primary : .secondary))
        }
    }

    @ViewBuilder
    private var label: some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

struct ThemeCheckbox: View {
    @Environment(\.uiStyle) private var style
    let isChecked: Bool
    /// Some but not all of what this box stands for are ticked. A group heading
    /// that showed an empty box while three of its rows were ticked would be
    /// saying something untrue about those three.
    var isMixed: Bool = false
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Group {
            if style.isRetro {
                RetroCheckbox(isChecked: isChecked, isMixed: isMixed, action: action)
            } else {
                Button(action: action) {
                    Image(systemName: isChecked ? "checkmark.square.fill"
                                          : (isMixed ? "minus.square.fill" : "square"))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(isChecked ? style.accent : (isMixed ? style.accent : style.secondaryText))
                }
                .buttonStyle(.plain)
            }
        }
        .helpIfPresent(help ?? (isChecked ? "Remove from the cleanup review" : "Add to the cleanup review"))
        .accessibilityLabel(isMixed ? "Some are ticked" : (isChecked ? "Untick" : "Tick for the cleanup review"))
    }
}

private struct HelpIfPresent: ViewModifier {
    let text: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let text, !text.isEmpty {
            content.help(text)
        } else {
            content
        }
    }
}

extension View {
    func helpIfPresent(_ text: String?) -> some View {
        modifier(HelpIfPresent(text: text))
    }
}

// MARK: - Button style

struct RetroButtonStyle: ButtonStyle {
    let isDefault: Bool
    init(isDefault: Bool = false) { self.isDefault = isDefault }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(RetroTypography.buttonFont)
            .foregroundStyle(RetroColors.darkText)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(configuration.isPressed ? Color(white: 0.76) : RetroColors.buttonFace)
            .overlay(Rectangle().strokeBorder(Color(white: isDefault ? 0.18 : 0.4), lineWidth: isDefault ? 2 : 1))
            .overlay(alignment: .top) { Rectangle().fill(configuration.isPressed ? Color(white: 0.5) : .white).frame(height: 1).padding(.horizontal, 2).padding(.top, 2) }
            .overlay(alignment: .leading) { Rectangle().fill(configuration.isPressed ? Color(white: 0.5) : .white).frame(width: 1).padding(.vertical, 2).padding(.leading, 2) }
            .overlay(alignment: .bottom) { Rectangle().fill(configuration.isPressed ? .white : Color(white: 0.6)).frame(height: 1).padding(.horizontal, 2).padding(.bottom, 2) }
    }
}
