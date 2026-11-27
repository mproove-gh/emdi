import AppKit

/// emdi's colors. Each one has a light and a dark value and resolves when it is drawn, so the editor
/// follows the appearance chosen in Settings (System, Light or Dark) without restyling.
///
/// Light is a soft, warm paper (#F6F4EE) with near-black ink; dark is a soft charcoal (#252528) with off-white
/// text. Never pure white or pure black, which tire the eyes. Text contrast is above 12:1 in both, and
/// dimmed text above 4.5:1. The emdi orange is used only for the text cursor.
enum EditorPalette {
    static let background = dynamic(light: 0xF6F4EE, dark: 0x252528)
    static let text = dynamic(light: 0x1F1F22, dark: 0xE7E5E1)
    /// Quotes, list markers, finished tasks.
    static let secondaryText = dynamic(light: 0x58585F, dark: 0xA3A19D)
    /// Revealed syntax (`**`, `#`, fences) and rules: visible but quiet.
    static let syntax = dynamic(light: 0xA4A29C, dark: 0x6E6D72)
    static let link = dynamic(light: 0x1C58B3, dark: 0x6AA8F7)
    static let inlineCodeBackground = dynamic(light: 0xE9E6DD, dark: 0x323236)
    static let codeBlockBackground = dynamic(light: 0xECE9E0, dark: 0x2D2D31)
    static let tableHeaderBackground = dynamic(light: 0xEAE7DD, dark: 0x343438)
    static let border = dynamic(light: 0xD5D2C8, dark: 0x444448)
    /// Every other table row, and the quieter lines between table columns.
    static let tableStripe = dynamic(light: 0xEFECE5, dark: 0x2B2B2E)
    static let tableColumnRule = dynamic(light: 0xE3E0D7, dark: 0x39393D)
    /// The bars down the side of block quotes.
    static let quoteBar = dynamic(light: 0xD8D4CA, dark: 0x4D4D52)
    static let checkbox = dynamic(light: 0x85837D, dark: 0x7D7C80)
    static let checkboxChecked = dynamic(light: 0x2F6FD6, dark: 0x5B9BF0)
    /// Callouts: the bar, icon and title in the kind's color, over a faint tint of it. The colors are
    /// made once: a dynamic color compares by identity, and a new instance on each restyle would make
    /// every callout paragraph look changed (see `MarkdownTheme.apply`).
    static func callout(_ kind: CalloutKind) -> NSColor { calloutColors[kind]! }
    static func calloutBackground(_ kind: CalloutKind) -> NSColor { calloutBackgrounds[kind]! }

    private static let calloutColors: [CalloutKind: NSColor] = [
        .note: dynamic(light: 0x1C58B3, dark: 0x6AA8F7),
        .tip: dynamic(light: 0x1D6B35, dark: 0x5CC27A),
        .important: dynamic(light: 0x6E3AB8, dark: 0xB592F0),
        .warning: dynamic(light: 0x7D5200, dark: 0xE0A93A),
        .caution: dynamic(light: 0xAE2A20, dark: 0xF27467),
    ]

    private static let calloutBackgrounds: [CalloutKind: NSColor] = calloutColors.mapValues { accent in
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let base = resolve(background, dark: dark)
            return base.blended(withFraction: dark ? 0.10 : 0.08, of: resolve(accent, dark: dark)) ?? base
        }
    }

    static let cursor = dynamic(light: 0xE8621A, dark: 0xF2782F)

    // Code, after Xcode's default themes, tuned for the backgrounds above.
    static let codeKeyword = dynamic(light: 0x921F8A, dark: 0xF56BAE)
    static let codeType = dynamic(light: 0x185F6E, dark: 0x6BD3E8)
    static let codeString = dynamic(light: 0xA6311A, dark: 0xF08A6C)
    static let codeNumber = dynamic(light: 0x3B33C9, dark: 0xD6C474)
    static let codeComment = dynamic(light: 0x575E66, dark: 0x8F969E)
    static let codeAttribute = dynamic(light: 0x735402, dark: 0xF2A65A)
    static let codeProperty = dynamic(light: 0x29634F, dark: 0x7CC4A8)

    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            color(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        }
    }

    /// The light or dark value of a palette color, whatever the current appearance (used by the theme previews).
    static func resolve(_ color: NSColor, dark: Bool) -> NSColor {
        var resolved = color
        NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
