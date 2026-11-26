import AppKit

/// Which ends of a code block a line is on, for the rounded corners.
struct CodeBlockEdges: OptionSet {
    let rawValue: Int
    static let top = CodeBlockEdges(rawValue: 1 << 0)
    static let bottom = CodeBlockEdges(rawValue: 1 << 1)
}

/// Lays out one line of a code block and paints its background across the whole text container width.
/// Consecutive lines touch, so together they draw one rounded panel.
final class CodeBlockLayoutFragment: NSTextLayoutFragment {
    static let verticalPadding: CGFloat = 6
    private static let cornerRadius: CGFloat = 6

    var edges: CodeBlockEdges = []

    /// The panel rect in fragment coordinates.
    private var panelRect: CGRect {
        let frame = layoutFragmentFrame
        let width = textLayoutManager?.textContainer?.size.width ?? frame.width
        var top: CGFloat = 0
        var bottom = frame.height
        if edges.contains(.top) {
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
        context.setFillColor(NSColor.textColor.withAlphaComponent(0.06).cgColor)
        context.fillPath()
        context.restoreGState()

        super.draw(at: point, in: context)
    }
}
