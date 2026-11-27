import AppKit

/// Lays out a bullet list item and draws its bullet where the hidden `-`, `*` or `+` is:
/// a disc at the top level, a circle one level down, a square below that, as in Typora.
final class ListItemLayoutFragment: MarkdownLayoutFragment {
    /// The hidden marker character, relative to the paragraph.
    var bulletIndex = 0
    var depth = 0

    private var markerFont: NSFont {
        if let string = (textElement as? NSTextParagraph)?.attributedString, bulletIndex < string.length,
           let font = string.attribute(.font, at: bulletIndex, effectiveRange: nil) as? NSFont {
            return font
        }
        return .systemFont(ofSize: 15)
    }

    /// The bullet in fragment coordinates: centred on the marker character's own width (its kern
    /// excluded) and on the lowercase letters of the text.
    var bulletRect: CGRect {
        guard let line = textLineFragments.first else { return .zero }
        let font = markerFont
        let origin = line.typographicBounds.origin
        let width = ("-" as NSString).size(withAttributes: [.font: font]).width
        let centerX = origin.x + line.locationForCharacter(at: bulletIndex).x + width / 2
        let centerY = origin.y + line.glyphOrigin.y - font.xHeight / 2
        let size = (font.xHeight * (depth >= 2 ? 0.68 : 0.78) * 2).rounded() / 2
        return CGRect(x: centerX - size / 2, y: centerY - size / 2, width: size, height: size)
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(bulletRect)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        let rect = bulletRect.offsetBy(dx: point.x, dy: point.y)
        context.saveGState()
        // In a quote the bullet takes the quote's quieter color, like its text (callouts keep normal text).
        let color = (quoteBars != nil && callout == nil ? EditorPalette.secondaryText : EditorPalette.text).cgColor
        switch depth {
        case 0:
            context.setFillColor(color)
            context.fillEllipse(in: rect)
        case 1:
            context.setStrokeColor(color)
            context.setLineWidth(1)
            context.strokeEllipse(in: rect.insetBy(dx: 0.5, dy: 0.5))
        default:
            context.setFillColor(color)
            context.fill(rect)
        }
        context.restoreGState()
    }
}
