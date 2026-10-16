import Foundation

/// Which of the three display colors a display is drawn in (spec §9).
///
/// - `primary`: accent (blue) — "1台目の画面"
/// - `secondary`: display2 (orange) — "2台目の画面"
/// - `tertiary`: gray
///
/// The built-in display is always orange so that it looks the same in every workspace (that is how
/// the UI mock draws it, even in the "ノートPCのみ" workspace). The main external display is blue.
public enum DisplayRole: Int, Comparable, Sendable, CaseIterable {
    case primary = 0
    case secondary = 1
    case tertiary = 2

    public static func < (lhs: DisplayRole, rhs: DisplayRole) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum DisplayRoles {
    /// Assigns a role to every display, keyed by UUID.
    public static func assign<Display: DisplayDescribing>(_ displays: [Display]) -> [String: DisplayRole] {
        var roles: [String: DisplayRole] = [:]
        let hasBuiltin = displays.contains(where: \.isBuiltin)
        for display in displays where display.isBuiltin {
            roles[display.uuid] = .secondary
        }
        // The main display first, then larger displays, then left to right.
        let externals = displays
            .filter { !$0.isBuiltin }
            .sorted { lhs, rhs in
                if lhs.isMain != rhs.isMain {
                    return lhs.isMain
                }
                let lhsArea = lhs.frame.width * lhs.frame.height
                let rhsArea = rhs.frame.width * rhs.frame.height
                if lhsArea != rhsArea {
                    return lhsArea > rhsArea
                }
                return lhs.frame.minX < rhs.frame.minX
            }
        for (position, display) in externals.enumerated() {
            switch position {
            case 0:
                roles[display.uuid] = .primary
            case 1 where !hasBuiltin:
                roles[display.uuid] = .secondary
            default:
                roles[display.uuid] = .tertiary
            }
        }
        return roles
    }

    /// Displays in role order (blue, orange, gray). Ties keep the left-to-right order.
    public static func ordered<Display: DisplayDescribing>(_ displays: [Display]) -> [Display] {
        let roles = assign(displays)
        let spatial = DisplayGeometry.spatiallyOrdered(displays)
        return spatial.enumerated()
            .sorted { lhs, rhs in
                let lhsRole = roles[lhs.element.uuid] ?? .tertiary
                let rhsRole = roles[rhs.element.uuid] ?? .tertiary
                if lhsRole != rhsRole {
                    return lhsRole < rhsRole
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
