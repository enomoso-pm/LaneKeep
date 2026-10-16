import Foundation

/// Why an automatic restore is being considered.
public struct AutoRestoreTrigger: OptionSet, Equatable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The set of connected displays changed.
    public static let displaysChanged = AutoRestoreTrigger(rawValue: 1 << 0)
    /// The Mac woke from sleep.
    public static let wake = AutoRestoreTrigger(rawValue: 1 << 1)
}

/// Turns the stream of screen-change and wake notifications into restore triggers.
///
/// `didChangeScreenParametersNotification` also fires for resolution changes or a moving Dock, so
/// only an actual change of the display signature counts as "displays changed" (spec §6.2). A
/// display that drops out and comes back before things settle (a loose cable, a KVM switch) counts
/// too: macOS moves its windows away at once, so they need to be put back.
public struct AutoRestoreTracker: Equatable, Sendable {
    public private(set) var lastSignature: String
    private var wakePending = false
    private var sawOtherConfiguration = false

    public init(initialSignature: String) {
        lastSignature = initialSignature
    }

    public mutating func noteWake() {
        wakePending = true
    }

    /// Call on every screen-change notification with the displays connected at that moment.
    public mutating func noteSignature(_ signature: String) {
        if !signature.isEmpty, signature != lastSignature {
            sawOtherConfiguration = true
        }
    }

    /// Call once things have settled (after the debounce). Returns the triggers that apply, or
    /// `nil` when nothing relevant happened.
    ///
    /// An empty signature (no display reported, as can happen for a moment while displays
    /// reconnect) is ignored and does not replace the last known configuration.
    public mutating func evaluate(currentSignature: String) -> AutoRestoreTrigger? {
        guard !currentSignature.isEmpty else {
            return nil
        }
        var trigger: AutoRestoreTrigger = []
        if currentSignature != lastSignature || sawOtherConfiguration {
            trigger.insert(.displaysChanged)
            lastSignature = currentSignature
            sawOtherConfiguration = false
        }
        if wakePending {
            trigger.insert(.wake)
            wakePending = false
        }
        return trigger.isEmpty ? nil : trigger
    }
}

/// Picks the workspace to restore automatically (spec §3.3).
public enum AutoRestorePolicy {
    /// The workspace whose signature matches the current displays and whose auto-restore setting
    /// covers the trigger. When several match, the one used most recently wins; never-used ones
    /// come last, ties keep the list order.
    ///
    /// - Parameter masterSwitch: The "つないだら自動で復元" toggle. When off, nothing is restored.
    public static func workspaceToRestore(
        among workspaces: [Workspace],
        currentSignature: String,
        trigger: AutoRestoreTrigger,
        masterSwitch: Bool
    ) -> Workspace? {
        guard masterSwitch, !currentSignature.isEmpty, !trigger.isEmpty else {
            return nil
        }
        let candidates = workspaces.enumerated().filter { _, workspace in
            guard workspace.displaySignature == currentSignature, !workspace.windows.isEmpty else {
                return false
            }
            return (trigger.contains(.displaysChanged) && workspace.autoRestoreOnConnect)
                || (trigger.contains(.wake) && workspace.autoRestoreOnWake)
        }
        let best = candidates.min { lhs, rhs in
            let lhsDate = lhs.element.lastUsedAt ?? .distantPast
            let rhsDate = rhs.element.lastUsedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.offset < rhs.offset
        }
        return best?.element
    }
}
