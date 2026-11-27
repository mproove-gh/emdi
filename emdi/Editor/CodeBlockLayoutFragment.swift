import AppKit

/// Which ends of a code block a line is on, for the rounded corners.
struct CodeBlockEdges: OptionSet {
    let rawValue: Int
    static let top = CodeBlockEdges(rawValue: 1 << 0)
    static let bottom = CodeBlockEdges(rawValue: 1 << 1)
    /// The opening fence of a fenced block, drawn as a header: language, Copy, and a rule under it.
    static let header = CodeBlockEdges(rawValue: 1 << 2)
}

/// Lays out one line of a code block and paints its background across the whole text container width.
/// Consecutive lines touch, so together they draw one rounded panel.
final class CodeBlockLayoutFragment: MarkdownLayoutFragment {
    static let verticalPadding: CGFloat = 6
    private static let cornerRadius: CGFloat = 6

    var edges: CodeBlockEdges = []
    /// The block's language, drawn on its hidden opening fence. Drawing only: it is not in the text,
    /// so it is never copied.
    var languageLabel: NSAttributedString?
    /// The header's "Copy" label, drawn at the right. Hovering the block puts a real button over it.
    var copyLabel: NSAttributedString?

    /// Space between the header's rule and the first line of code.
    static let headerGap: CGFloat = 8
    /// How far the Copy label sits from the panel's right edge.
    static let copyInset: CGFloat = 12

    /// The panel rect in fragment coordinates.
    private var panelRect: CGRect {
        let frame = layoutFragmentFrame
        let width = textLayoutManager?.textContainer?.size.width ?? frame.width
        var top: CGFloat = 0
        var bottom = frame.height
        if edges.contains(.header) {
            top = textLineFragments.first?.typographicBounds.minY ?? 0
        } else if edges.contains(.top) {
            top = (textLineFragments.first?.typographicBounds.minY ?? 0) - Self.verticalPadding
        }
        if edges.contains(.bottom) {
            // Skip the empty "extra" line TextKit adds after a final newline at the end of the document.
            let lastLine = textLineFragments.last(where: { $0.characterRange.length > 0 }) ?? textLineFragments.last
            bottom = (lastLine?.typographicBounds.maxY ?? frame.height) + Self.verticalPadding
        }
        return CGRect(x: -frame.minX, y: top, width: width, height: bottom - top)
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(panelRect)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let panel = panelRect.offsetBy(dx: point.x, dy: point.y)
        // Round only the outer corners: draw a taller rounded rect and clip it to this line.
        var shape = panel
        if !edges.contains(.top) { shape.origin.y -= Self.cornerRadius; shape.size.height += Self.cornerRadius }
        if !edges.contains(.bottom) { shape.size.height += Self.cornerRadius }

        context.saveGState()
        context.clip(to: panel)
        context.addPath(CGPath(roundedRect: shape, cornerWidth: Self.cornerRadius, cornerHeight: Self.cornerRadius,
                               transform: nil))
        context.setFillColor(EditorPalette.codeBlockBackground.cgColor)
        context.fillPath()
        context.restoreGState()

        if edges.contains(.header), let line = textLineFragments.first {
            let bounds = line.typographicBounds
            // The rule under the header, across the panel.
            context.saveGState()
            context.setFillColor(EditorPalette.border.cgColor)
            context.fill(CGRect(x: panel.minX, y: point.y + bounds.maxY, width: panel.width, height: 1))
            context.restoreGState()

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            if let languageLabel {
                let size = languageLabel.size()
                let x = bounds.minX + line.locationForCharacter(at: 0).x
                languageLabel.draw(at: CGPoint(x: point.x + x, y: point.y + bounds.midY - size.height / 2))
            }
            if let copyLabel {
                let rect = Self.copyRect(for: copyLabel, panelMaxX: panel.maxX, midY: point.y + bounds.midY)
                Self.drawCopy(copyLabel, in: rect)
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        super.draw(at: point, in: context)
    }

    /// Where the Copy icon and label go, right-aligned in the header, in the coordinates of `panelMaxX` and `midY`.
    static func copyRect(for label: NSAttributedString, panelMaxX: CGFloat, midY: CGFloat) -> CGRect {
        let size = label.size()
        let width = size.height + 4 + size.width
        return CGRect(x: panelMaxX - copyInset - width, y: midY - size.height / 2, width: width, height: size.height)
    }

    /// The copy icon then the label, in the label's own color.
    static func drawCopy(_ label: NSAttributedString, in rect: CGRect) {
        let color = label.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor ?? .secondaryLabelColor
        let font = label.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 11)
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize * 0.9, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        if let image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) {
            let side = rect.height
            let aspect = image.size.width / max(image.size.height, 1)
            let iconHeight = min(side, side / max(aspect, 1)) * 0.85
            let iconWidth = iconHeight * aspect
            image.draw(in: CGRect(x: rect.minX + (side - iconWidth) / 2, y: rect.midY - iconHeight / 2,
                                  width: iconWidth, height: iconHeight))
        }
        label.draw(at: CGPoint(x: rect.minX + rect.height + 4, y: rect.minY))
    }
}
