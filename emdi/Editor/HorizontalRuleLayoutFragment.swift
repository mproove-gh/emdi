import AppKit

/// Draws a `---` line (whose characters are hidden) as a thin rule across the text column.
final class HorizontalRuleLayoutFragment: NSTextLayoutFragment {
    private var ruleRect: CGRect {
        let frame = layoutFragmentFrame
        let width = textLayoutManager?.textContainer?.size.width ?? frame.width
        let padding = textLayoutManager?.textContainer?.lineFragmentPadding ?? 0
        let line = textLineFragments.first?.typographicBounds ?? CGRect(x: 0, y: 0, width: width, height: frame.height)
        return CGRect(x: -frame.minX + padding, y: (line.midY).rounded(.down), width: width - 2 * padding, height: 1)
    }

    override var renderingSurfaceBounds: CGRect {
        super.renderingSurfaceBounds.union(ruleRect)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        context.setFillColor(EditorPalette.border.cgColor)
        context.fill(ruleRect.offsetBy(dx: point.x, dy: point.y))
        super.draw(at: point, in: context)
    }
}
