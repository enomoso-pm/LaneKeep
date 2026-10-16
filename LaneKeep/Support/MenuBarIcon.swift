import AppKit

/// The menu bar icon: the brand glyph from the mock (a monitor and a portrait display) as a
/// template image, so macOS tints it for light, dark and highlighted menu bars.
@MainActor
enum MenuBarIcon {
    static let normal = make(attention: false)
    /// With a small dot, shown while the accessibility permission is missing.
    static let attention = make(attention: true)

    private static let pointSize: CGFloat = 18

    private static func make(attention: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        for scale in [1, 2, 3] as [CGFloat] {
            if let representation = bitmap(scale: scale, attention: attention) {
                image.addRepresentation(representation)
            }
        }
        image.isTemplate = true
        image.accessibilityDescription = "LaneKeep"
        return image
    }

    private static func bitmap(scale: CGFloat, attention: Bool) -> NSBitmapImageRep? {
        let pixels = Int(pointSize * scale)
        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        // Draw in the mock's 22-unit viewBox with the origin at the top-left.
        let unit = pointSize / 22 * scale
        context.translateBy(x: 0, y: CGFloat(pixels))
        context.scaleBy(x: unit, y: -unit)
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(1.7)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.addPath(CGPath(roundedRect: CGRect(x: 2, y: 5, width: 11, height: 8), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil))
        if attention {
            // Leave room for the dot in the top-right corner.
            context.addPath(CGPath(roundedRect: CGRect(x: 14.5, y: 8.5, width: 5.5, height: 6.5), cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
        } else {
            context.addPath(CGPath(roundedRect: CGRect(x: 14.5, y: 3, width: 5.5, height: 12), cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
        }
        context.move(to: CGPoint(x: 6, y: 17))
        context.addLine(to: CGPoint(x: 9, y: 17))
        context.strokePath()

        if attention {
            context.fillEllipse(in: CGRect(x: 15, y: 1, width: 5, height: 5))
        }

        guard let cgImage = context.makeImage() else { return nil }
        let representation = NSBitmapImageRep(cgImage: cgImage)
        representation.size = NSSize(width: pointSize, height: pointSize)
        return representation
    }
}
