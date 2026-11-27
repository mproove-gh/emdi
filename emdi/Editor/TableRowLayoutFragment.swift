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
        if let containerWidth = textLayoutManager?.textContainer?.size.width {
            let left = point.x - layoutFragmentFrame.minX
            context.clip(to: CGRect(x: left - 2, y: point.y - 20, width: containerWidth + 3, height: layoutFragmentFrame.height + 40))
        }
        if let grid {
            let rect = grid.rect.offsetBy(dx: point.x, dy: point.y)
            context.saveGState()
            if role.contains(.header) {
                context.setFillColor(EditorPalette.tableHeaderBackground.cgColor)
                context.fill(rect)
            }
            context.setStrokeColor(EditorPalette.border.cgColor)
            context.setLineWidth(1)
            var segments: [CGPoint] = []
            if role.contains(.first) {
                segments += [CGPoint(x: rect.minX, y: rect.minY + 0.5), CGPoint(x: rect.maxX, y: rect.minY + 0.5)]
            }
            segments += [CGPoint(x: rect.minX, y: rect.maxY - 0.5), CGPoint(x: rect.maxX, y: rect.maxY - 0.5)]
            for x in grid.borders {
                let x = (x + point.x).rounded(.down) + 0.5
                segments += [CGPoint(x: x, y: rect.minY), CGPoint(x: x, y: rect.maxY)]
            }
            context.strokeLineSegments(between: segments)
            context.restoreGState()
        }
        super.draw(at: point, in: context)
    }
}
