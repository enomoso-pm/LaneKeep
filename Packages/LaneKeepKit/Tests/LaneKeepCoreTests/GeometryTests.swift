import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import LaneKeepCore

@Suite("Coordinate conversion (spec §6.5)")
struct CoordinateConverterTests {
    let mainHeight: CGFloat = 1440

    @Test("A window on the main display")
    func windowOnMainDisplay() {
        // AppKit: 340 pt from the bottom, 1000 pt tall → its top edge is 100 pt below the top.
        let appKit = CGRect(x: 100, y: 340, width: 800, height: 1000)
        let ax = CoordinateConverter.accessibilityRect(fromAppKit: appKit, primaryHeight: mainHeight)
        #expect(ax == CGRect(x: 100, y: 100, width: 800, height: 1000))
    }

    @Test("Follows axY = mainScreenHeight - (nsY + height)")
    func formula() {
        let appKit = CGRect(x: -300, y: 12.5, width: 640, height: 480)
        let ax = CoordinateConverter.flip(appKit, primaryHeight: mainHeight)
        #expect(ax.minY == mainHeight - (appKit.minY + appKit.height))
        #expect(ax.minX == appKit.minX)
        #expect(ax.size == appKit.size)
    }

    @Test("The conversion is its own inverse", arguments: [
        CGRect(x: 0, y: 0, width: 2560, height: 1440),
        CGRect(x: -1512, y: -982, width: 1512, height: 982),
        CGRect(x: 2560, y: 600, width: 1920, height: 1080),
        CGRect(x: 10.5, y: -20.25, width: 300, height: 200)
    ])
    func roundTrip(rect: CGRect) {
        let ax = CoordinateConverter.accessibilityRect(fromAppKit: rect, primaryHeight: mainHeight)
        #expect(CoordinateConverter.appKitRect(fromAccessibility: ax, primaryHeight: mainHeight) == rect)
    }

    @Test("A display above the main display has negative Accessibility y")
    func displayAbove() {
        let above = CGRect(x: 0, y: 1440, width: 1920, height: 1080)
        let ax = CoordinateConverter.accessibilityRect(fromAppKit: above, primaryHeight: mainHeight)
        #expect(ax == CGRect(x: 0, y: -1080, width: 1920, height: 1080))
    }

    @Test("A display below the main display starts at the main display's height")
    func displayBelow() {
        let below = CGRect(x: -1512, y: -982, width: 1512, height: 982)
        let ax = CoordinateConverter.accessibilityRect(fromAppKit: below, primaryHeight: mainHeight)
        #expect(ax == CGRect(x: -1512, y: 1440, width: 1512, height: 982))
    }

    @Test("The main display maps onto itself")
    func mainDisplay() {
        let main = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        #expect(CoordinateConverter.flip(main, primaryHeight: mainHeight) == main)
    }

    @Test("Points flip around the main display's height")
    func points() {
        #expect(CoordinateConverter.flip(CGPoint(x: 10, y: 20), primaryHeight: 100) == CGPoint(x: 10, y: 80))
    }

    @Test("Rects with a negative height are standardized first")
    func negativeHeight() {
        let rect = CGRect(x: 0, y: 500, width: 100, height: -200)
        #expect(CoordinateConverter.flip(rect, primaryHeight: 1000) == CGRect(x: 0, y: 500, width: 100, height: 200))
    }
}

@Suite("Relative frames")
struct RelativeGeometryTests {
    let container = CGRect(x: 0, y: 25, width: 2560, height: 1415)

    @Test("Absolute → relative → absolute returns the same frame")
    func roundTrip() {
        let frame = CGRect(x: 51, y: 67, width: 1203, height: 877)
        let relative = RelativeGeometry.relativeFrame(of: frame, in: container)
        #expect(RelativeGeometry.absoluteFrame(for: relative, in: container) == frame)
    }

    @Test("A layout scales with the resolution")
    func scalesWithResolution() {
        let relative = CGRect(x: 0.5, y: 0.25, width: 0.5, height: 0.75)
        let small = CGRect(x: 0, y: 25, width: 1440, height: 875)
        #expect(RelativeGeometry.absoluteFrame(for: relative, in: small) == CGRect(x: 720, y: 244, width: 720, height: 656))
    }

    @Test("Offsets of non-main displays are taken into account")
    func displayOffset() {
        let builtin = CGRect(x: -1512, y: 491, width: 1512, height: 949)
        let frame = CGRect(x: -1512 + 151.2, y: 491 + 94.9, width: 756, height: 474.5)
        let relative = RelativeGeometry.relativeFrame(of: frame, in: builtin)
        #expect(relative.isClose(to: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5), tolerance: 0.00001))
    }

    @Test("Stored fractions are rounded to five decimals")
    func quantization() {
        let relative = RelativeGeometry.relativeFrame(of: CGRect(x: 1, y: 1, width: 1, height: 1), in: CGRect(x: 0, y: 0, width: 3, height: 3))
        #expect(relative.minX == 0.33333)
        #expect(relative.width == 0.33333)
    }

    @Test("A degenerate container yields .zero")
    func degenerateContainer() {
        #expect(RelativeGeometry.relativeFrame(of: CGRect(x: 1, y: 1, width: 10, height: 10), in: .zero) == .zero)
    }

    @Test("Absolute frames are whole points and never empty")
    func wholePoints() {
        let frame = RelativeGeometry.absoluteFrame(for: CGRect(x: 0.33333, y: 0.1, width: 0.00001, height: 0.5), in: CGRect(x: 0, y: 0, width: 1000, height: 333))
        #expect(frame == CGRect(x: 333, y: 33, width: 1, height: 167))
    }
}

@Suite("Keeping windows on screen (spec §6.6)")
struct FrameFittingTests {
    let bounds = CGRect(x: 0, y: 25, width: 1000, height: 800)

    @Test("A frame that fits is left alone")
    func fits() {
        let frame = CGRect(x: 100, y: 100, width: 300, height: 300)
        #expect(FrameFitting.fit(frame, into: bounds) == frame)
    }

    @Test("A frame that overflows the right and bottom edges is pulled back")
    func overflow() {
        let frame = CGRect(x: 900, y: 700, width: 300, height: 300)
        #expect(FrameFitting.fit(frame, into: bounds) == CGRect(x: 700, y: 525, width: 300, height: 300))
    }

    @Test("A frame left of or above the bounds is pushed in")
    func underflow() {
        let frame = CGRect(x: -50, y: 0, width: 300, height: 300)
        #expect(FrameFitting.fit(frame, into: bounds) == CGRect(x: 0, y: 25, width: 300, height: 300))
    }

    @Test("A frame larger than the bounds is aligned with the top-left corner")
    func larger() {
        let frame = CGRect(x: 300, y: 300, width: 1200, height: 900)
        #expect(FrameFitting.fit(frame, into: bounds) == CGRect(x: 0, y: 25, width: 1200, height: 900))
    }
}
