import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A display drawn on the map ("配置図").
public struct MapDisplay: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// Top-left-origin global coordinates.
    public var frame: CGRect
    /// The area windows are relative to, in the same coordinates as `frame`.
    public var visibleFrame: CGRect
    public var role: DisplayRole

    public init(id: String, name: String, frame: CGRect, visibleFrame: CGRect, role: DisplayRole) {
        self.id = id
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.role = role
    }
}

/// A window drawn on the map.
public struct MapWindow: Equatable, Sendable, Identifiable {
    public var id: String
    public var displayID: String
    /// Relative to the display's visible frame (top-left origin).
    public var relativeFrame: CGRect
    public var label: String

    public init(id: String, displayID: String, relativeFrame: CGRect, label: String) {
        self.id = id
        self.displayID = displayID
        self.relativeFrame = relativeFrame
        self.label = label
    }
}

/// Scales the display arrangement into a view and places the windows inside the displays.
public struct DisplayMapLayout: Equatable, Sendable {
    public struct PlacedDisplay: Equatable, Sendable, Identifiable {
        public var display: MapDisplay
        /// In view coordinates.
        public var rect: CGRect
        public var id: String { display.id }
    }

    public struct PlacedWindow: Equatable, Sendable, Identifiable {
        public var window: MapWindow
        public var role: DisplayRole
        /// In view coordinates, clipped to the display.
        public var rect: CGRect
        public var id: String { window.id }
    }

    public var displays: [PlacedDisplay]
    public var windows: [PlacedWindow]

    /// - Parameters:
    ///   - size: The size of the map view.
    ///   - padding: Space around the arrangement.
    ///   - labelHeight: Space kept free below each display for its name.
    ///   - gap: Visual gap between displays that touch.
    public init(
        displays: [MapDisplay],
        windows: [MapWindow],
        size: CGSize,
        padding: CGFloat = 12,
        labelHeight: CGFloat = 16,
        gap: CGFloat = 6
    ) {
        guard
            !displays.isEmpty,
            size.width > 0,
            size.height > 0
        else {
            self.displays = []
            self.windows = []
            return
        }
        let bounds = displays.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let availableWidth = max(1, size.width - padding * 2)
        let availableHeight = max(1, size.height - padding * 2 - labelHeight)
        let scale = min(availableWidth / max(1, bounds.width), availableHeight / max(1, bounds.height))
        let contentSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let offset = CGPoint(
            x: (size.width - contentSize.width) / 2,
            y: padding + (availableHeight - contentSize.height) / 2
        )

        func project(_ rect: CGRect) -> CGRect {
            CGRect(
                x: offset.x + (rect.minX - bounds.minX) * scale,
                y: offset.y + (rect.minY - bounds.minY) * scale,
                width: rect.width * scale,
                height: rect.height * scale
            )
        }

        let inset = gap / 2
        var placedDisplays: [PlacedDisplay] = []
        var visibleRects: [String: CGRect] = [:]
        for display in displays {
            let full = project(display.frame)
            let rect = full.insetBy(dx: min(inset, full.width / 4), dy: min(inset, full.height / 4))
            placedDisplays.append(PlacedDisplay(display: display, rect: rect))
            // Map the visible frame with the same inset so that windows line up with the box.
            let visible = project(display.visibleFrame).intersection(full)
            visibleRects[display.id] = visible.isNull ? rect : visible.intersection(rect)
        }

        let roles = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0.role) })
        var placedWindows: [PlacedWindow] = []
        for window in windows {
            guard
                let container = visibleRects[window.displayID],
                let displayRect = placedDisplays.first(where: { $0.id == window.displayID })?.rect
            else {
                continue
            }
            let relative = window.relativeFrame
            let rect = CGRect(
                x: container.minX + relative.minX * container.width,
                y: container.minY + relative.minY * container.height,
                width: relative.width * container.width,
                height: relative.height * container.height
            ).intersection(displayRect)
            guard !rect.isNull, rect.width >= 1, rect.height >= 1 else { continue }
            placedWindows.append(PlacedWindow(window: window, role: roles[window.displayID] ?? .tertiary, rect: rect))
        }

        self.displays = placedDisplays
        self.windows = placedWindows
    }
}

extension MapDisplay {
    /// Map displays for the displays recorded in a workspace.
    public static func from(_ displays: [DisplayInfo]) -> [MapDisplay] {
        let primaryHeight = DisplayGeometry.primaryHeight(of: displays) ?? 0
        let roles = DisplayRoles.assign(displays)
        return DisplayRoles.ordered(displays).map { display in
            MapDisplay(
                id: display.uuid,
                name: display.name,
                frame: CoordinateConverter.flip(display.frame, primaryHeight: primaryHeight),
                visibleFrame: CoordinateConverter.flip(display.visibleFrame ?? display.frame, primaryHeight: primaryHeight),
                role: roles[display.uuid] ?? .tertiary
            )
        }
    }

    /// Map displays for the displays connected right now.
    public static func from(_ displays: [DisplaySnapshot]) -> [MapDisplay] {
        let primaryHeight = DisplayGeometry.primaryHeight(of: displays) ?? 0
        let roles = DisplayRoles.assign(displays)
        return DisplayRoles.ordered(displays).map { display in
            MapDisplay(
                id: display.uuid,
                name: display.name,
                frame: CoordinateConverter.flip(display.frame, primaryHeight: primaryHeight),
                visibleFrame: CoordinateConverter.flip(display.visibleFrame, primaryHeight: primaryHeight),
                role: roles[display.uuid] ?? .tertiary
            )
        }
    }
}
