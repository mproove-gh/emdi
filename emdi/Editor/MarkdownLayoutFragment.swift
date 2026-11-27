import AppKit

/// The bars of a quote line: one per nesting level, `step` apart. Compares by value, so restyling
/// leaves unchanged quote lines alone.
final class QuoteBars: NSObject {
    let depth: Int
    let step: CGFloat
    static let barWidth: CGFloat = 3

    init(depth: Int, step: CGFloat) {
        self.depth = depth
        self.step = step
    }

    /// How far the quote's text is shifted right.
    var indent: CGFloat { CGFloat(depth) * step }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? QuoteBars else { return false }
        return depth == other.depth && step == other.step
    }

    override var hash: Int { depth.hashValue ^ step.hashValue }
}

/// The base of emdi's layout fragments. On a quote line it draws the quote's bars down the left
/// side, whatever the line also is (a list item, a heading, …).
class MarkdownLayoutFragment: NSTextLayoutFragment {
    var quoteBars: QuoteBars?

    /// The bars in fragment coordinates, each the full height of the fragment so consecutive lines join up.
    private var barRects: [CGRect] {
        guard let quoteBars else { return [] }
        let frame = layoutFragmentFrame
        let left = -frame.minX + (textLayoutManager?.textContainer?.lineFragmentPadding ?? 5)
        return (0..<quoteBars.depth).map { level in
            CGRect(x: left + CGFloat(level) * quoteBars.step, y: 0, width: QuoteBars.barWidth, height: frame.height)
        }
    }

    override var renderingSurfaceBounds: CGRect {
        barRects.reduce(super.renderingSurfaceBounds) { $0.union($1) }
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let bars = barRects
        if !bars.isEmpty {
            context.saveGState()
            context.setFillColor(EditorPalette.quoteBar.cgColor)
            for bar in bars { context.fill(bar.offsetBy(dx: point.x, dy: point.y)) }
            context.restoreGState()
        }
        super.draw(at: point, in: context)
    }
}
