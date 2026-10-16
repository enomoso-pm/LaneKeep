import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Window frames are stored relative to the visible frame of their display so that a layout
/// survives resolution and scaling changes (spec §5). All rects here use the top-left origin of the
/// Accessibility coordinate system.
public enum RelativeGeometry {
    /// Stored fractions are rounded to this many steps per unit (sub-pixel even on 8K displays) to
    /// keep `workspaces.json` readable.
    public static let precision: CGFloat = 100_000

    /// `frame` expressed as fractions of `container` (0…1 when the window is fully inside).
    public static func relativeFrame(of frame: CGRect, in container: CGRect) -> CGRect {
        let frame = frame.standardized
        let container = container.standardized
        guard container.width > 0, container.height > 0 else {
            return .zero
        }
        return CGRect(
            x: quantize((frame.minX - container.minX) / container.width),
            y: quantize((frame.minY - container.minY) / container.height),
            width: quantize(frame.width / container.width),
            height: quantize(frame.height / container.height)
        )
    }

    /// The absolute frame for `relative` inside `container`, snapped to whole points.
    ///
    /// The edges are rounded rather than origin and size, so that windows that touched when they
    /// were saved still touch, and a window that filled the container does not grow past it.
    public static func absoluteFrame(for relative: CGRect, in container: CGRect) -> CGRect {
        let container = container.standardized
        let minX = (container.minX + relative.minX * container.width).rounded()
        let minY = (container.minY + relative.minY * container.height).rounded()
        let maxX = (container.minX + (relative.minX + relative.width) * container.width).rounded()
        let maxY = (container.minY + (relative.minY + relative.height) * container.height).rounded()
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    /// Moves (and if need be shrinks) a relative frame so that it lies within 0…1: windows are
    /// saved fully inside their display, as the spec's 0–1 range says, even if one hung off an
    /// edge when it was saved.
    public static func fittedToUnit(_ relative: CGRect) -> CGRect {
        let width = min(max(relative.width, 0), 1)
        let height = min(max(relative.height, 0), 1)
        return CGRect(
            x: quantize(min(max(relative.minX, 0), 1 - width)),
            y: quantize(min(max(relative.minY, 0), 1 - height)),
            width: quantize(width),
            height: quantize(height)
        )
    }

    private static func quantize(_ value: CGFloat) -> CGFloat {
        (value * precision).rounded() / precision
    }
}

/// Keeps a window on screen when the app did not accept the requested size (spec §6.6).
public enum FrameFitting {
    /// Moves `frame` (without resizing it) so that it lies inside `bounds`. If the frame is larger
    /// than `bounds` in a dimension, it is aligned with the left / top edge so that the title bar
    /// stays reachable.
    public static func fit(_ frame: CGRect, into bounds: CGRect) -> CGRect {
        var origin = frame.origin
        if frame.width >= bounds.width {
            origin.x = bounds.minX
        } else {
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - frame.width)
        }
        if frame.height >= bounds.height {
            origin.y = bounds.minY
        } else {
            origin.y = min(max(origin.y, bounds.minY), bounds.maxY - frame.height)
        }
        return CGRect(origin: origin, size: frame.size)
    }
}

extension CGPoint {
    /// Largest per-axis distance to `other`.
    func maxAxisDistance(to other: CGPoint) -> CGFloat {
        max(abs(x - other.x), abs(y - other.y))
    }
}

extension CGSize {
    func maxAxisDistance(to other: CGSize) -> CGFloat {
        max(abs(width - other.width), abs(height - other.height))
    }
}
