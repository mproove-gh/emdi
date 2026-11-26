import AppKit

/// Lays out a task item and draws a checkbox where its hidden `- [ ] ` prefix is.
final class TaskLayoutFragment: NSTextLayoutFragment {
    /// Horizontal room reserved for the checkbox (kern on the prefix's last character).
    static let checkboxWidth: CGFloat = 24
    private static let checkboxSize: CGFloat = 15

    /// The hidden prefix, relative to the paragraph.
    var prefixRange = NSRange(location: 0, length: 0)
    var isChecked = false

    /// The checkbox in fragment coordinates. Also used for hit testing clicks.
    var checkboxRect: CGRect {
        guard let line = textLineFragments.first else { return .zero }
        let origin = line.typographicBounds.origin
        let x = origin.x + line.locationForCharacter(at: prefixRange.location).x
        // Centre on the lowercase letters of the body text.
        let middle = origin.y + line.glyphOrigin.y - MarkdownLayoutMetrics.bodyXHeight / 2
        let size = Self.checkboxSize
        return CGRect(x: x, y: middle - size / 2, width: size, height: size)
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(checkboxRect)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)

        let color: NSColor = isChecked ? .controlAccentColor : .secondaryLabelColor
        let configuration = NSImage.SymbolConfiguration(pointSize: Self.checkboxSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: isChecked ? [.white, color] : [color]))
        guard let image = NSImage(systemSymbolName: isChecked ? "checkmark.square.fill" : "square",
                                  accessibilityDescription: isChecked ? "Done" : "To do")?
            .withSymbolConfiguration(configuration) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        image.draw(in: checkboxRect.offsetBy(dx: point.x, dy: point.y))
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Font metrics the layout fragments need, readable off the main actor.
enum MarkdownLayoutMetrics {
    static let bodyXHeight: CGFloat = NSFont.systemFont(ofSize: 15).xHeight
}
