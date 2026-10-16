import Foundation

/// How a workspace relates to the displays that are connected right now.
public enum WorkspaceAvailability: Equatable, Sendable {
    /// The signature matches: exactly the saved displays are connected (blue border in the list).
    case matchesCurrent
    /// Some displays that hold windows of the workspace are not connected.
    case missingDisplays(count: Int)
    /// Every display the workspace needs is connected, plus some others (spec §3.4: the extra
    /// displays are left alone).
    case available
}

extension Workspace {
    public func availability(currentDisplayUUIDs: Set<String>, currentSignature: String) -> WorkspaceAvailability {
        if !currentSignature.isEmpty, displaySignature == currentSignature {
            return .matchesCurrent
        }
        let neededUUIDs = Set(windows.map(\.displayUUID))
        let missing = neededUUIDs.subtracting(currentDisplayUUIDs).count
        return missing > 0 ? .missingDisplays(count: missing) : .available
    }

    public func availability(for displays: [DisplaySnapshot]) -> WorkspaceAvailability {
        availability(
            currentDisplayUUIDs: Set(displays.map(\.uuid)),
            currentSignature: DisplaySignature.make(displays.map(\.uuid))
        )
    }
}
