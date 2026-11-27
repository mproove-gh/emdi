import AppKit

/// The value of `.blockImage`: the loaded image and the size to show it at, or, for a local file that
/// can't be loaded, the label of the placeholder drawn instead.
final class BlockImage: NSObject {
    let image: NSImage?
    /// The image file, opened in Quick Look on a double-click.
    let url: URL?
    let size: CGSize
    let missingLabel: NSAttributedString?

    init(image: NSImage, url: URL?, size: CGSize) {
        self.image = image
        self.url = url
        self.size = size
        missingLabel = nil
    }

    init(missing label: NSAttributedString, url: URL, size: CGSize) {
        image = nil
        self.url = url
        self.size = size
        missingLabel = label
    }

    /// Value equality, so restyling doesn't count an unchanged image paragraph as changed.
    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? BlockImage else { return false }
        return other.image === image && other.size == size && other.url == url && other.missingLabel == missingLabel
    }

    override var hash: Int { image.map { ObjectIdentifier($0).hashValue } ?? url.hashValue }
}

/// Lays out a paragraph that holds only an image and draws the image in the space
/// its paragraph style reserves above the (hidden or dimmed) `![alt](path)` line.
final class ImageLayoutFragment: MarkdownLayoutFragment {
    /// Space between the image and the source line under it.
    static let gap: CGFloat = 4

    var blockImage: BlockImage?

    /// Where the image (or its placeholder) is drawn, in fragment coordinates.
    var imageRect: CGRect? {
        guard let blockImage, let line = textLineFragments.first else { return nil }
        let size = blockImage.size
        let bounds = line.typographicBounds
        return CGRect(x: bounds.minX, y: bounds.minY - Self.gap - size.height, width: size.width, height: size.height)
    }

    override var renderingSurfaceBounds: CGRect {
        guard let imageRect else { return super.renderingSurfaceBounds }
        return super.renderingSurfaceBounds.union(imageRect)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        if let blockImage, let imageRect, let label = blockImage.missingLabel {
            drawPlaceholder(label, in: imageRect.offsetBy(dx: point.x, dy: point.y), context: context)
        } else if let blockImage, let image = blockImage.image, let imageRect {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            image.draw(in: imageRect.offsetBy(dx: point.x, dy: point.y), from: .zero, operation: .sourceOver,
                                  fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
        }
        super.draw(at: point, in: context)
    }

    /// A dashed frame with an icon and "Image not found: path", where the image would be.
    private func drawPlaceholder(_ label: NSAttributedString, in rect: CGRect, context: CGContext) {
        context.saveGState()
        let path = CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 6, cornerHeight: 6, transform: nil)
        context.addPath(path)
        context.setFillColor(EditorPalette.tableStripe.cgColor)
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(EditorPalette.border.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 3])
        context.strokePath()
        context.restoreGState()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let font = label.attribute(.font, at: 0, effectiveRange: nil) as? NSFont ?? .systemFont(ofSize: 12)
        let labelSize = label.size()
        let iconSize = font.pointSize * 1.3
        let configuration = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [EditorPalette.secondaryText]))
        var x = rect.minX + 14
        if let icon = NSImage(systemSymbolName: "photo.badge.exclamationmark", accessibilityDescription: "Missing image")?
            .withSymbolConfiguration(configuration) {
            let height = iconSize
            let width = height * icon.size.width / max(icon.size.height, 1)
            icon.draw(in: CGRect(x: x, y: rect.midY - height / 2, width: width, height: height))
            x += width + 8
        }
        let available = rect.maxX - 14 - x
        label.draw(with: CGRect(x: x, y: rect.midY - labelSize.height / 2, width: max(available, 0), height: labelSize.height),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        NSGraphicsContext.restoreGraphicsState()
    }
}
