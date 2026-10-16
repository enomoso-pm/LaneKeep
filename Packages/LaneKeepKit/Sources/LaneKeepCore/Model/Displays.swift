import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// What every display description (saved or live) has in common.
public protocol DisplayDescribing {
    /// `CGDisplayCreateUUIDFromDisplayID`, made unique when two monitors report the same value.
    var uuid: String { get }
    /// `NSScreen.localizedName`.
    var name: String { get }
    /// AppKit global coordinates (origin at the bottom-left of the main display, y grows upwards).
    var frame: CGRect { get }
    /// The display with the menu bar (`NSScreen.screens.first`).
    var isMain: Bool { get }
    var isBuiltin: Bool { get }
}

/// A display as recorded in a workspace (spec §5).
public struct DisplayInfo: Codable, Equatable, Sendable, DisplayDescribing {
    public var uuid: String
    public var name: String
    /// Global AppKit coordinates at the time the workspace was saved.
    public var frame: CGRect
    public var isMain: Bool
    /// Not in the original spec; used to give the built-in display a consistent color.
    public var isBuiltin: Bool
    /// `NSScreen.visibleFrame` at save time. Optional because it is only needed to draw the map
    /// precisely; placement always uses the live `visibleFrame` of the target display.
    public var visibleFrame: CGRect?

    public init(
        uuid: String,
        name: String,
        frame: CGRect,
        isMain: Bool,
        isBuiltin: Bool = false,
        visibleFrame: CGRect? = nil
    ) {
        self.uuid = uuid
        self.name = name
        self.frame = frame
        self.isMain = isMain
        self.isBuiltin = isBuiltin
        self.visibleFrame = visibleFrame
    }

    public init(_ snapshot: DisplaySnapshot) {
        self.init(
            uuid: snapshot.uuid,
            name: snapshot.name,
            frame: snapshot.frame,
            isMain: snapshot.isMain,
            isBuiltin: snapshot.isBuiltin,
            visibleFrame: snapshot.visibleFrame
        )
    }

    private enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case frame
        case isMain
        case isBuiltin
        case visibleFrame
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "ディスプレイ"
        frame = try container.decodeRectIfPresent(forKey: .frame) ?? .zero
        isMain = try container.decodeIfPresent(Bool.self, forKey: .isMain) ?? false
        isBuiltin = try container.decodeIfPresent(Bool.self, forKey: .isBuiltin) ?? false
        visibleFrame = try container.decodeRectIfPresent(forKey: .visibleFrame)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(name, forKey: .name)
        try container.encodeRect(frame, forKey: .frame)
        try container.encode(isMain, forKey: .isMain)
        try container.encode(isBuiltin, forKey: .isBuiltin)
        try container.encodeRectIfPresent(visibleFrame, forKey: .visibleFrame)
    }
}

/// A display that is connected right now.
public struct DisplaySnapshot: Equatable, Sendable, Identifiable, DisplayDescribing {
    public var uuid: String
    public var name: String
    /// AppKit global coordinates.
    public var frame: CGRect
    /// `NSScreen.visibleFrame` (without the menu bar and the Dock), AppKit global coordinates.
    public var visibleFrame: CGRect
    public var isMain: Bool
    public var isBuiltin: Bool

    public var id: String { uuid }

    public init(
        uuid: String,
        name: String,
        frame: CGRect,
        visibleFrame: CGRect,
        isMain: Bool,
        isBuiltin: Bool = false
    ) {
        self.uuid = uuid
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isMain = isMain
        self.isBuiltin = isBuiltin
    }
}

public enum DisplayGeometry {
    /// Height of the main display, needed to convert between AppKit and Accessibility coordinates.
    ///
    /// Falls back to the display whose frame starts at the origin, which is where AppKit always puts
    /// the main display.
    public static func primaryHeight<Display: DisplayDescribing>(of displays: [Display]) -> CGFloat? {
        let main = displays.first(where: \.isMain) ?? displays.first(where: { $0.frame.origin == .zero })
        return (main ?? displays.first)?.frame.height
    }

    /// The display a point (in Accessibility coordinates) belongs to.
    ///
    /// The display that contains the point wins; otherwise the one with the largest overlap with
    /// `rect` (a window that is mostly off-screen), otherwise `nil`.
    public static func display<Display: DisplayDescribing>(
        forAccessibilityRect rect: CGRect,
        among displays: [Display],
        primaryHeight: CGFloat
    ) -> Display? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let framesAX = displays.map { CoordinateConverter.accessibilityRect(fromAppKit: $0.frame, primaryHeight: primaryHeight) }
        if let index = framesAX.firstIndex(where: { $0.contains(center) }) {
            return displays[index]
        }
        var best: (index: Int, area: CGFloat)?
        for (index, frame) in framesAX.enumerated() {
            let overlap = frame.intersection(rect)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let area = overlap.width * overlap.height
            if let current = best, current.area >= area {
                continue
            }
            best = (index, area)
        }
        return best.map { displays[$0.index] }
    }

    /// Orders displays left to right, then top to bottom.
    public static func spatiallyOrdered<Display: DisplayDescribing>(_ displays: [Display]) -> [Display] {
        displays.sorted { lhs, rhs in
            if lhs.frame.minX != rhs.frame.minX {
                return lhs.frame.minX < rhs.frame.minX
            }
            return lhs.frame.maxY > rhs.frame.maxY
        }
    }

    /// Whether two lists describe the same displays in the same places: the same displays (the
    /// built-in one included), with the same frames and the same main display. The order does
    /// not matter, nor do the visible frames, which change when the Dock moves to another display.
    ///
    /// Unlike the signature, this also tells when the lid was closed while a monitor stays
    /// connected, or when a resolution or the arrangement changed: positions worked out for the
    /// old displays no longer apply then.
    public static func isSameArrangement(_ lhs: [DisplaySnapshot], _ rhs: [DisplaySnapshot]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let byUUID: (DisplaySnapshot, DisplaySnapshot) -> Bool = { $0.uuid < $1.uuid }
        return lhs.sorted(by: byUUID).elementsEqual(rhs.sorted(by: byUUID)) { left, right in
            left.uuid == right.uuid && left.frame == right.frame && left.isMain == right.isMain
        }
    }
}
