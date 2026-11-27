import AppKit
import Testing
@testable import emdi

/// Checks the palette against WCAG contrast ratios, in light and dark.
struct EditorPaletteTests {
    private func resolved(_ color: NSColor, _ name: NSAppearance.Name) -> NSColor {
        var result = color
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB)!
        }
        return result
    }

    private func luminance(_ color: NSColor) -> CGFloat {
        func channel(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(color.redComponent) + 0.7152 * channel(color.greenComponent) + 0.0722 * channel(color.blueComponent)
    }

    private func contrast(_ a: NSColor, _ b: NSColor, _ name: NSAppearance.Name) -> CGFloat {
        let (la, lb) = (luminance(resolved(a, name)), luminance(resolved(b, name)))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    @Test func bodyTextIsHighContrast() {
        for name in appearances {
            #expect(contrast(EditorPalette.text, EditorPalette.background, name) >= 12)
        }
    }

    @Test func secondaryTextLinksAndCodeAreReadable() {
        let readable: [NSColor] = [EditorPalette.secondaryText, EditorPalette.link]
        let code: [NSColor] = [EditorPalette.codeKeyword, EditorPalette.codeType, EditorPalette.codeString,
                               EditorPalette.codeNumber, EditorPalette.codeComment, EditorPalette.codeAttribute,
                               EditorPalette.codeProperty]
        for name in appearances {
            for color in readable { #expect(contrast(color, EditorPalette.background, name) >= 4.5) }
            for color in code { #expect(contrast(color, EditorPalette.codeBlockBackground, name) >= 4.5) }
        }
    }

    @Test func calloutsAreReadable() {
        for name in appearances {
            for kind in CalloutKind.allCases {
                let tint = EditorPalette.calloutBackground(kind)
                #expect(contrast(EditorPalette.callout(kind), tint, name) >= 4.5, "\(kind) \(name.rawValue)")
                #expect(contrast(EditorPalette.text, tint, name) >= 10, "\(kind) \(name.rawValue)")
            }
        }
    }

    @Test func lightAndDarkReallyDiffer() {
        // Light is clearly light but not glaring (bright white tires the eyes).
        let light = luminance(resolved(EditorPalette.background, .aqua))
        #expect(light > 0.8 && light < 0.9)
        #expect(luminance(resolved(EditorPalette.background, .darkAqua)) < 0.05)
    }
}
