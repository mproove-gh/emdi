import AppKit

/// Lays out the last line of an H1 or H2 and draws a thin rule under it, across the text column.
final class HeadingLayoutFragment: MarkdownLayoutFragment {
    /// How far below the text the rule is drawn.
    var ruleGap: CGFloat = 4

    private var ruleRect: CGRect {
        let frame = layoutFragmentFrame
        let width = textLayoutManager?.textContainer?.size.width ?? frame.width
        let padding = textLayoutManager?.textContainer?.lineFragmentPadding ?? 0
        // Skip the empty "extra" line TextKit adds after a final newline at the end of the document.
        let line = textLineFragments.last(where: { $0.characterRange.length > 0 }) ?? textLineFragments.last
        let bottom = line?.typographicBounds.maxY ?? frame.height
        return CGRect(x: -frame.minX + padding, y: (bottom + ruleGap).rounded(.down), width: width - 2 * padding, height: 1)
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
