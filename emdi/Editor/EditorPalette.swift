import AppKit

/// emdi's colors. Each one has a light and a dark value and resolves when it is drawn, so the editor
/// follows the appearance chosen in Settings (System, Light or Dark) without restyling.
///
/// Light is warm paper with near-black ink; dark is a soft charcoal with off-white text, never pure
/// black or pure white, which tire the eyes. Text contrast is above 12:1 in both, and dimmed text
/// above 4.5:1. The emdi orange is used only for the text cursor.
enum EditorPalette {
    static let background = dynamic(light: 0xFBFAF7, dark: 0x1D1D1F)
    static let text = dynamic(light: 0x1F1F22, dark: 0xE7E5E1)
    /// Quotes, list markers, finished tasks.
    static let secondaryText = dynamic(light: 0x5F5F66, dark: 0xA3A19D)
    /// Revealed syntax (`**`, `#`, fences) and rules: visible but quiet.
    static let syntax = dynamic(light: 0xA9A8A4, dark: 0x67666A)
    static let link = dynamic(light: 0x1F5FBF, dark: 0x6AA8F7)
    static let inlineCodeBackground = dynamic(light: 0xEFEDE8, dark: 0x2B2B2E)
    static let codeBlockBackground = dynamic(light: 0xF3F1EC, dark: 0x262629)
    static let tableHeaderBackground = dynamic(light: 0xF3F1EC, dark: 0x28282B)
    static let border = dynamic(light: 0xDAD7D0, dark: 0x3C3C40)
    static let checkbox = dynamic(light: 0x8A8984, dark: 0x7D7C80)
    static let checkboxChecked = dynamic(light: 0x2F6FD6, dark: 0x5B9BF0)
    static let cursor = dynamic(light: 0xE8621A, dark: 0xF2782F)

    // Code, after Xcode's default themes, tuned for the backgrounds above.
    static let codeKeyword = dynamic(light: 0x9B2393, dark: 0xF56BAE)
    static let codeType = dynamic(light: 0x1D6A7A, dark: 0x6BD3E8)
    static let codeString = dynamic(light: 0xB6381F, dark: 0xF08A6C)
    static let codeNumber = dynamic(light: 0x3B33C9, dark: 0xD6C474)
    static let codeComment = dynamic(light: 0x646B73, dark: 0x8F969E)
    static let codeAttribute = dynamic(light: 0x815F03, dark: 0xF2A65A)
    static let codeProperty = dynamic(light: 0x2E6E58, dark: 0x7CC4A8)

    static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            color(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        }
    }

    private static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
