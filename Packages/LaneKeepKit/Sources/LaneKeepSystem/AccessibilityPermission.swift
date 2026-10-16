#if canImport(AppKit)
import AppKit
import ApplicationServices

/// The only permission LaneKeep needs (spec §7).
public enum AccessibilityPermission {
    /// Whether LaneKeep may read and move other apps' windows. Changes take effect immediately, so
    /// polling this is enough to notice when the user flips the switch.
    public static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt. It also adds LaneKeep to the list in System Settings, so the user
    /// only has to turn the switch on instead of adding the app by hand.
    @discardableResult
    public static func requestWithSystemPrompt() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// System Settings › Privacy & Security › Accessibility.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!

    @MainActor
    public static func openSystemSettings() {
        NSWorkspace.shared.open(settingsURL)
    }
}
#endif
