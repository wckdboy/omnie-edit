import OmnieEditCore
import SwiftUI

struct GlassSearchField: View {
    let prompt: String
    @Binding var text: String
    var width: CGFloat
    @FocusState.Binding var isFocused: Bool
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
                    .onTapGesture { text = "" }
                    .accessibilityLabel("Clear search")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: width)
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(1)
        .modifier(GlassSearchSurface())
        .accessibilityElement(children: .contain)
    }
}

private struct GlassSearchSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect()
        } else {
            content
                .background(.thinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(.primary.opacity(0.12), lineWidth: 0.5)
                }
        }
    }
}

/// Omnie's brand gradient: purple into orange. Used sparingly, on the app's
/// most prominent custom controls only (the create action, the active tab).
enum BrandGradient {
    static let accent = LinearGradient(
        colors: [
            Color(red: 0.62, green: 0.18, blue: 0.86),
            Color(red: 0.98, green: 0.58, blue: 0.16),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Fills `shape` with the brand gradient, then lays clear Liquid Glass over it
/// on iOS 26+ so the gradient reads through the material's specular highlight
/// instead of being tinted flat. A gradient can't be passed to `Glass.tint`
/// (it only accepts `Color`), so this is built directly rather than through a
/// button style — which also sidesteps `buttonStyle` not reliably reaching a
/// `Menu`'s label the way it does a plain `Button`.
private struct GradientGlassBackground<S: Shape>: ViewModifier {
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .background(BrandGradient.accent, in: shape)
                .glassEffect(.clear.interactive(), in: shape)
        } else {
            content.background(BrandGradient.accent, in: shape)
        }
    }
}

extension View {
    func gradientGlassBackground<S: Shape>(in shape: S) -> some View {
        modifier(GradientGlassBackground(shape: shape))
    }

    /// The app's one "primary action" treatment: a round, elevated,
    /// gradient-glass icon for the single most important action in a toolbar
    /// (e.g. create). Apply directly to a label's content.
    func primaryGlassIcon() -> some View {
        frame(width: 44, height: 44)
            .foregroundStyle(.white)
            .gradientGlassBackground(in: Circle())
    }
}
import UIKit

struct RGBA: Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    var uiColor: UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

// A palette entry is usable wherever a `Color` is: as a style (`foregroundStyle`, `tint`)
// and as a view (`palette.background.ignoresSafeArea()`), the same way `Color` is both.
extension RGBA: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        color.resolve(in: environment)
    }
}

extension RGBA: View {
    var body: some View {
        color
    }
}

struct Palette: Equatable {
    var background: RGBA
    var gutter: RGBA
    var text: RGBA
    var secondary: RGBA
    var hairline: RGBA
    var keyword: RGBA
    var string: RGBA
    var comment: RGBA
    var number: RGBA
    var heading: RGBA
    var match: RGBA
    var currentMatch: RGBA
    var keywordBold: Bool

    static func resolve(_ theme: AppTheme, _ scheme: ColorScheme) -> Palette {
        switch theme {
        case .system:
            return scheme == .dark ? .dark : .light
        case .light:
            return .light
        case .dark:
            return .dark
        case .monochrome:
            return scheme == .dark ? .monochromeDark : .monochromeLight
        }
    }

    static let light = Palette(
        background: RGBA(red: 0.965, green: 0.965, blue: 0.957),
        gutter: RGBA(red: 0.945, green: 0.945, blue: 0.937),
        text: RGBA(red: 0.086, green: 0.086, blue: 0.086),
        secondary: RGBA(red: 0.431, green: 0.431, blue: 0.416),
        hairline: RGBA(red: 0.847, green: 0.847, blue: 0.831),
        keyword: RGBA(red: 0.122, green: 0.227, blue: 0.373),
        string: RGBA(red: 0.118, green: 0.302, blue: 0.196),
        comment: RGBA(red: 0.541, green: 0.541, blue: 0.525),
        number: RGBA(red: 0.416, green: 0.243, blue: 0.071),
        heading: RGBA(red: 0.086, green: 0.086, blue: 0.086),
        match: RGBA(red: 0.086, green: 0.086, blue: 0.086, alpha: 0.06),
        currentMatch: RGBA(red: 0.086, green: 0.086, blue: 0.086, alpha: 0.14),
        keywordBold: false
    )

    static let dark = Palette(
        background: RGBA(red: 0.063, green: 0.063, blue: 0.063),
        gutter: RGBA(red: 0.086, green: 0.086, blue: 0.086),
        text: RGBA(red: 0.902, green: 0.902, blue: 0.890),
        secondary: RGBA(red: 0.557, green: 0.557, blue: 0.541),
        hairline: RGBA(red: 0.165, green: 0.165, blue: 0.165),
        keyword: RGBA(red: 0.773, green: 0.831, blue: 0.918),
        string: RGBA(red: 0.773, green: 0.839, blue: 0.769),
        comment: RGBA(red: 0.478, green: 0.478, blue: 0.463),
        number: RGBA(red: 0.878, green: 0.765, blue: 0.627),
        heading: RGBA(red: 0.902, green: 0.902, blue: 0.890),
        match: RGBA(red: 0.902, green: 0.902, blue: 0.890, alpha: 0.08),
        currentMatch: RGBA(red: 0.902, green: 0.902, blue: 0.890, alpha: 0.16),
        keywordBold: false
    )

    static let monochromeLight = Palette(
        background: RGBA(red: 1, green: 1, blue: 1),
        gutter: RGBA(red: 0.949, green: 0.949, blue: 0.949),
        text: RGBA(red: 0, green: 0, blue: 0),
        secondary: RGBA(red: 0.416, green: 0.416, blue: 0.416),
        hairline: RGBA(red: 0.878, green: 0.878, blue: 0.878),
        keyword: RGBA(red: 0, green: 0, blue: 0),
        string: RGBA(red: 0.227, green: 0.227, blue: 0.227),
        comment: RGBA(red: 0.541, green: 0.541, blue: 0.541),
        number: RGBA(red: 0, green: 0, blue: 0),
        heading: RGBA(red: 0, green: 0, blue: 0),
        match: RGBA(red: 0, green: 0, blue: 0, alpha: 0.06),
        currentMatch: RGBA(red: 0, green: 0, blue: 0, alpha: 0.14),
        keywordBold: true
    )

    static let monochromeDark = Palette(
        background: RGBA(red: 0, green: 0, blue: 0),
        gutter: RGBA(red: 0.039, green: 0.039, blue: 0.039),
        text: RGBA(red: 1, green: 1, blue: 1),
        secondary: RGBA(red: 0.604, green: 0.604, blue: 0.604),
        hairline: RGBA(red: 0.165, green: 0.165, blue: 0.165),
        keyword: RGBA(red: 1, green: 1, blue: 1),
        string: RGBA(red: 0.784, green: 0.784, blue: 0.784),
        comment: RGBA(red: 0.478, green: 0.478, blue: 0.478),
        number: RGBA(red: 1, green: 1, blue: 1),
        heading: RGBA(red: 1, green: 1, blue: 1),
        match: RGBA(red: 1, green: 1, blue: 1, alpha: 0.10),
        currentMatch: RGBA(red: 1, green: 1, blue: 1, alpha: 0.20),
        keywordBold: true
    )
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.light
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension Palette {
    /// Bridges this SwiftUI-facing palette to the plain `UIColor` bag the
    /// Runestone adapter in `OmnieEditCore` renders with.
    var editorColorTheme: EditorColorTheme {
        EditorColorTheme(
            background: background.uiColor,
            text: text.uiColor,
            gutterBackground: gutter.uiColor,
            secondary: secondary.uiColor,
            hairline: hairline.uiColor,
            keyword: keyword.uiColor,
            string: string.uiColor,
            comment: comment.uiColor,
            number: number.uiColor,
            matchBackground: match.uiColor,
            currentMatchBackground: currentMatch.uiColor,
            keywordBold: keywordBold
        )
    }
}
