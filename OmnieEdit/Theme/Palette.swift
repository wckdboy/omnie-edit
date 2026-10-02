import OmnieEditCore
import SwiftUI
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
