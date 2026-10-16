import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// The "画面構成の署名": the UUIDs of the connected displays, sorted and joined with `|`
/// (spec §2, §6.2).
public enum DisplaySignature {
    public static let separator: Character = "|"

    /// The signature of a display configuration. Everything that compares configurations uses
    /// this one function.
    ///
    /// The built-in display is left out as soon as an external display is connected: a MacBook
    /// docked with its lid closed has the same external displays as with the lid open, and should
    /// match the same workspaces. With the built-in display alone, its UUID is the signature —
    /// never an empty string, which means "no displays" and is ignored by automatic restores.
    public static func make<Display: DisplayDescribing>(for displays: [Display]) -> String {
        let externals = displays.filter { !$0.isBuiltin }
        return joined((externals.isEmpty ? displays : externals).map(\.uuid))
    }

    /// The UUIDs sorted and joined.
    static func joined<UUIDs: Sequence>(_ uuids: UUIDs) -> String where UUIDs.Element == String {
        uuids.sorted().joined(separator: String(separator))
    }

    public static func components(of signature: String) -> [String] {
        signature.split(separator: separator).map(String.init)
    }
}

public enum DisplayIdentity {
    /// Makes the display UUIDs unique.
    ///
    /// `CGDisplayCreateUUIDFromDisplayID` derives the UUID from vendor, model and serial number, so
    /// it does not change when a monitor is plugged into another port. Two identical monitors that
    /// do not report a serial number get the same UUID, though. The second and later ones —
    /// ordered left to right, then top to bottom — get a `#2`, `#3`… suffix so that the signature
    /// and the window rules can still tell them apart.
    ///
    /// - Parameters:
    ///   - rawUUIDs: UUIDs as reported by the system, one per display.
    ///   - frames: AppKit frames of the same displays, in the same order.
    /// - Returns: Unique identifiers in the same order as the input.
    public static func uniqueIdentifiers(rawUUIDs: [String], frames: [CGRect]) -> [String] {
        precondition(rawUUIDs.count == frames.count, "Every display needs a frame")
        var result = rawUUIDs
        let groups = Dictionary(grouping: rawUUIDs.indices, by: { rawUUIDs[$0] })
        for (uuid, indices) in groups where indices.count > 1 {
            let ordered = indices.sorted { lhs, rhs in
                if frames[lhs].minX != frames[rhs].minX {
                    return frames[lhs].minX < frames[rhs].minX
                }
                return frames[lhs].maxY > frames[rhs].maxY
            }
            for (position, index) in ordered.enumerated() where position > 0 {
                result[index] = "\(uuid)#\(position + 1)"
            }
        }
        return result
    }
}
