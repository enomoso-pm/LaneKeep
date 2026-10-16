import Foundation

/// Default shortcuts for new workspaces: ⌃⌥1, ⌃⌥2, … (spec §3.2).
public enum ShortcutSlots {
    public static let digits = 1...9

    /// The smallest digit that is not used yet, or `nil` when all nine are taken.
    public static func nextFreeDigit(used: Set<Int>) -> Int? {
        digits.first { !used.contains($0) }
    }

    /// The KeyboardShortcuts name for a workspace. Names must not contain dots.
    public static func shortcutName(for workspaceID: UUID) -> String {
        "restoreWorkspace-\(workspaceID.uuidString)"
    }
}
