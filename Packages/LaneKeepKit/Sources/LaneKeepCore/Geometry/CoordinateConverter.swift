import Foundation

/// Converts between the two global coordinate systems macOS uses (spec §6.5).
///
/// - AppKit (`NSScreen.frame`, `NSWindow.frame`): origin at the bottom-left corner of the main
///   display, y grows upwards.
/// - Accessibility / Quartz (`kAXPositionAttribute`, `CGDisplayBounds`): origin at the top-left
///   corner of the main display, y grows downwards.
///
/// The x axis is shared. For y: `axY = mainScreenHeight - (nsY + height)`, where
/// `mainScreenHeight` is the height of the main display's frame. The transform is its own inverse,
/// so the same function converts in both directions.
public enum CoordinateConverter {
    /// The single place where the y axis is flipped.
    public static func flip(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        let rect = rect.standardized
        return CGRect(
            x: rect.minX,
            y: primaryHeight - (rect.minY + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    public static func accessibilityRect(fromAppKit rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        flip(rect, primaryHeight: primaryHeight)
    }

    public static func appKitRect(fromAccessibility rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        flip(rect, primaryHeight: primaryHeight)
    }

    /// A point is a rect without size.
    public static func flip(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        flip(CGRect(origin: point, size: .zero), primaryHeight: primaryHeight).origin
    }
}
