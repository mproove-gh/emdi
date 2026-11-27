import AppKit

/// Lays out one table line and draws its cell borders at the (hidden) pipes, which
/// `MarkdownTheme` has already spaced so that the columns line up from row to row.
final class TableRowLayoutFragment: MarkdownLayoutFragment {
    static let verticalPadding: CGFloat = 5

    var role: TableRowRole = []
    /// The `|` characters (relative to the paragraph) and how far after each one its border goes.
    var pipes: [(index: Int, borderOffset: CGFloat)] = []

    /// The row's cell area in fragment coordinates, and the x of each border.
    private var grid: (rect: CGRect, borders: [CGFloat])? {
        guard !role.contains(.delimiter), let first = textLineFragments.first,
              let last = textLineFragments.last(where: { $0.characterRange.length > 0 }) ?? textLineFragments.last,
              pipes.count >= 2 else { return nil }
        let borders = pipes.map { pipe in
            first.typographicBounds.minX + first.locationForCharacter(at: pipe.index).x + pipe.borderOffset
        }
        guard let left = borders.min(), let right = borders.max() else { return nil }
        let top = first.typographicBounds.minY - Self.verticalPadding
        let bottom = last.typographicBounds.maxY + Self.verticalPadding
        return (CGRect(x: left, y: top, width: right - left, height: bottom - top), borders)
    }

    /// Each drawn border, left to right, as the index of its `|` (relative to the paragraph) and its x
    /// in fragment coordinates. Empty when the row draws no grid (the delimiter row, a table shown as Markdown).
    var cellBorders: [(pipeIndex: Int, x: CGFloat)] {
        guard let grid else { return [] }
        return zip(pipes, grid.borders).map { ($0.index, $1) }.sorted { $0.x < $1.x }
    }

    override var renderingSurfaceBounds: CGRect {
        guard let grid else { return super.renderingSurfaceBounds }
        return super.renderingSurfaceBounds.union(grid.rect.insetBy(dx: -1, dy: -1))
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        // A table too wide even when shrunk is clipped (see `MarkdownTheme.clipRows`): stop it at the text
        // column's edge rather than in the margin.
        context.saveGState()
        defer { context.restoreGState() }
        let containerWidth = textLayoutManager?.textContainer?.size.width
        if let containerWidth {
            let left = point.x - layoutFragmentFrame.minX
            context.clip(to: CGRect(x: left - 2, y: point.y - 20, width: containerWidth + 3, height: layoutFragmentFrame.height + 40))
        }
        if let grid {
            drawGrid(grid.rect.offsetBy(dx: point.x, dy: point.y), borders: grid.borders.map { $0 + point.x }, in: context)
        }
        super.draw(at: point, in: context)
        if isClipped, let containerWidth, let grid {
            fadeRightEdge(of: grid.rect.offsetBy(dx: point.x, dy: point.y),
                          at: point.x - layoutFragmentFrame.minX + containerWidth, in: context)
        }
    }

    /// Set when the row is cut at the column's edge: its right end fades out to show there is more.
    var isClipped = false
    static let cornerRadius: CGFloat = 6
    private static let fadeWidth: CGFloat = 48

    /// The table is one rounded frame: each row draws its slice. The header is filled and ruled off,
    /// every other body row gets a faint fill, and the columns are separated by quieter lines.
    private func drawGrid(_ rect: CGRect, borders: [CGFloat], in context: CGContext) {
        let radius = Self.cornerRadius
        // Round only the table's outer corners: a taller rounded shape, clipped to this row.
        var shape = rect.insetBy(dx: 0.5, dy: 0)
        if !role.contains(.first) { shape.origin.y -= radius * 2; shape.size.height += radius * 2 }
        else { shape.origin.y += 0.5; shape.size.height -= 0.5 }
        if !role.contains(.last) { shape.size.height += radius * 2 } else { shape.size.height -= 0.5 }
        let path = CGPath(roundedRect: shape, cornerWidth: radius, cornerHeight: radius, transform: nil)

        context.saveGState()
        context.clip(to: rect.insetBy(dx: -1, dy: 0))
        let fill: NSColor? = role.contains(.header) ? EditorPalette.tableHeaderBackground
            : role.contains(.striped) ? EditorPalette.tableStripe : nil
        if let fill {
            context.addPath(path)
            context.setFillColor(fill.cgColor)
            context.fillPath()
        }
        // Lines between columns, inside the frame.
        let inner = borders.sorted().dropFirst().dropLast()
        if !inner.isEmpty {
            context.setStrokeColor(EditorPalette.tableColumnRule.cgColor)
            context.setLineWidth(1)
            context.strokeLineSegments(between: inner.flatMap { x -> [CGPoint] in
                let x = x.rounded(.down) + 0.5
                return [CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.maxY)]
            })
        }
        context.setStrokeColor(EditorPalette.border.cgColor)
        context.setLineWidth(1)
        if role.contains(.header) {
            context.strokeLineSegments(between: [CGPoint(x: rect.minX, y: rect.maxY - 0.5),
                                                 CGPoint(x: rect.maxX, y: rect.maxY - 0.5)])
        }
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    /// Fades the row out over the last points before the column's edge, in the page color.
    private func fadeRightEdge(of rect: CGRect, at edge: CGFloat, in context: CGContext) {
        let background = EditorPalette.background
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                        colors: [background.withAlphaComponent(0).cgColor, background.cgColor] as CFArray,
                                        locations: [0, 1]) else { return }
        let band = CGRect(x: edge - Self.fadeWidth, y: rect.minY - 1, width: Self.fadeWidth + 3, height: rect.height + 2)
        context.saveGState()
        context.clip(to: band)
        context.drawLinearGradient(gradient, start: CGPoint(x: band.minX, y: 0), end: CGPoint(x: edge, y: 0),
                                   options: .drawsAfterEndLocation)
        context.restoreGState()
    }
}
