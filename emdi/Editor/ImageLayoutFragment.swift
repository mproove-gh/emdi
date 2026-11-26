import AppKit

/// The value of `.blockImage`: the loaded image and the size to show it at.
final class BlockImage: NSObject {
    let image: NSImage
    let size: CGSize

    init(image: NSImage, size: CGSize) {
        self.image = image
        self.size = size
    }
}

/// Lays out a paragraph that holds only an image and draws the image in the space
/// its paragraph style reserves above the (hidden or dimmed) `![alt](path)` line.
final class ImageLayoutFragment: NSTextLayoutFragment {
    /// Space between the image and the source line under it.
    static let gap: CGFloat = 4

    var blockImage: BlockImage?

    private var imageRect: CGRect? {
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
        if let blockImage, let imageRect {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            blockImage.image.draw(in: imageRect.offsetBy(dx: point.x, dy: point.y), from: .zero, operation: .sourceOver,
                                  fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
        }
        super.draw(at: point, in: context)
    }
}
