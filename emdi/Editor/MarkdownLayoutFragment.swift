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
/// side, whatever the line also is (a list item, a heading, …). In a callout it also paints the tint,
/// colors the outer bar, and on the first line draws the icon and title.
class MarkdownLayoutFragment: NSTextLayoutFragment {
    /// Room kept for the icon before a callout's own title, in multiples of the text size.
    static let calloutIconRoom: CGFloat = 1.5

    var quoteBars: QuoteBars?
    var callout: CalloutKind?
    var calloutTitle: NSAttributedString?

    private var textLeft: CGFloat {
        -layoutFragmentFrame.minX + (textLayoutManager?.textContainer?.lineFragmentPadding ?? 5)
    }

    /// The bars in fragment coordinates, each the full height of the fragment so consecutive lines join up.
    private var barRects: [CGRect] {
        guard let quoteBars else { return [] }
        let left = textLeft
        return (0..<quoteBars.depth).map { level in
            CGRect(x: left + CGFloat(level) * quoteBars.step, y: 0, width: QuoteBars.barWidth,
                   height: layoutFragmentFrame.height)
        }
    }

    /// The callout tint, from the bar to the right edge of the text column.
    private var tintRect: CGRect? {
        guard callout != nil, let first = barRects.first else { return nil }
        let width = (textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width)
            - 2 * (textLayoutManager?.textContainer?.lineFragmentPadding ?? 5)
        return CGRect(x: first.minX, y: 0, width: width, height: layoutFragmentFrame.height)
    }

    /// The icon and the title's origin on the callout's first line, in fragment coordinates.
    private var titleLayout: (icon: CGRect, titleOrigin: CGPoint, font: NSFont)? {
        guard calloutTitle != nil, let line = textLineFragments.first else { return nil }
        let font = (calloutTitle?.length ?? 0) > 0
            ? calloutTitle?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil
        let size = font?.pointSize ?? bodyFont(of: line)?.pointSize ?? 15
        let baseline = line.typographicBounds.minY + line.glyphOrigin.y
        let capHeight = (font ?? bodyFont(of: line))?.capHeight ?? size * 0.7
        let x = line.typographicBounds.minX + line.locationForCharacter(at: 0).x
        let icon = CGRect(x: x, y: baseline - capHeight / 2 - size / 2, width: size, height: size)
        let titleOrigin = CGPoint(x: x + (size * 1.4).rounded(), y: baseline - (font?.ascender ?? size))
        return (icon, titleOrigin, font ?? .systemFont(ofSize: size))
    }

    private func bodyFont(of line: NSTextLineFragment) -> NSFont? {
        let string = line.attributedString
        guard string.length > 0 else { return nil }
        return string.attribute(.font, at: max(0, string.length - 1), effectiveRange: nil) as? NSFont
    }

    override var renderingSurfaceBounds: CGRect {
        var bounds = barRects.reduce(super.renderingSurfaceBounds) { $0.union($1) }
        if let tintRect { bounds = bounds.union(tintRect) }
        if let titleLayout, let calloutTitle {
            bounds = bounds.union(titleLayout.icon)
                .union(CGRect(origin: titleLayout.titleOrigin, size: calloutTitle.size()))
        }
        return bounds
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let bars = barRects
        context.saveGState()
        if let tintRect, let callout {
            context.setFillColor(EditorPalette.calloutBackground(callout).cgColor)
            context.fill(tintRect.offsetBy(dx: point.x, dy: point.y))
        }
        for (level, bar) in bars.enumerated() {
            let color = level == 0 && callout != nil ? EditorPalette.callout(callout!) : EditorPalette.quoteBar
            context.setFillColor(color.cgColor)
            context.fill(bar.offsetBy(dx: point.x, dy: point.y))
        }
        context.restoreGState()

        if let callout, let calloutTitle, let layout = titleLayout {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            let configuration = NSImage.SymbolConfiguration(pointSize: layout.font.pointSize, weight: .semibold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [EditorPalette.callout(callout)]))
            if let image = NSImage(systemSymbolName: Self.symbol(for: callout), accessibilityDescription: callout.title)?
                .withSymbolConfiguration(configuration) {
                // Keep the symbol's proportions inside the square.
                var rect = layout.icon
                let aspect = image.size.width / max(image.size.height, 1)
                if aspect > 1 { rect = rect.insetBy(dx: 0, dy: (rect.height - rect.width / aspect) / 2) }
                else { rect = rect.insetBy(dx: (rect.width - rect.height * aspect) / 2, dy: 0) }
                image.draw(in: rect.offsetBy(dx: point.x, dy: point.y))
            }
            calloutTitle.draw(at: CGPoint(x: layout.titleOrigin.x + point.x, y: layout.titleOrigin.y + point.y))
            NSGraphicsContext.restoreGraphicsState()
        }
        super.draw(at: point, in: context)
    }

    private static func symbol(for kind: CalloutKind) -> String {
        switch kind {
        case .note: "info.circle"
        case .tip: "lightbulb"
        case .important: "exclamationmark.bubble"
        case .warning: "exclamationmark.triangle"
        case .caution: "exclamationmark.octagon"
        }
    }
}
