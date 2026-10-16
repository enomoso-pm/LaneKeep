#if canImport(AppKit)
import ApplicationServices
import Foundation

/// Accessibility attribute names.
///
/// Literal values rather than the `kAX…Attribute` constants: those are C globals, and with Swift 6
/// strict concurrency checking literals avoid any question about shared mutable state.
enum AXAttribute {
    static let windows = "AXWindows"
    static let role = "AXRole"
    static let subrole = "AXSubrole"
    static let title = "AXTitle"
    static let position = "AXPosition"
    static let size = "AXSize"
    static let minimized = "AXMinimized"
    static let fullScreen = "AXFullScreen"
    /// Set by assistive apps; while it is on, some apps (Chromium, Electron) animate window
    /// changes and drop moves.
    static let enhancedUserInterface = "AXEnhancedUserInterface"
}

enum AXRoleValue {
    static let window = "AXWindow"
    static let standardWindow = "AXStandardWindow"
}

extension AXUIElement {
    func copyValue(_ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    func string(_ attribute: String) -> String? {
        copyValue(attribute) as? String
    }

    func bool(_ attribute: String) -> Bool? {
        copyValue(attribute) as? Bool
    }

    func elements(_ attribute: String) -> [AXUIElement] {
        copyValue(attribute) as? [AXUIElement] ?? []
    }

    func point(_ attribute: String) -> CGPoint? {
        guard let value = copyValue(attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        // The type was checked above, so the cast cannot fail.
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    func size(_ attribute: String) -> CGSize? {
        guard let value = copyValue(attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    func isSettable(_ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(self, attribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    @discardableResult
    func set(_ attribute: String, to value: CFTypeRef) -> AXError {
        AXUIElementSetAttributeValue(self, attribute as CFString, value)
    }

    @discardableResult
    func setPosition(_ point: CGPoint) -> AXError {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        return set(AXAttribute.position, to: value)
    }

    @discardableResult
    func setSize(_ size: CGSize) -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
        return set(AXAttribute.size, to: value)
    }

    /// Position and size in Accessibility coordinates.
    var frame: CGRect? {
        guard let position = point(AXAttribute.position), let size = size(AXAttribute.size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    /// A regular document/app window: not a sheet, a panel, a tooltip or a full-screen window.
    var isStandardNonFullScreenWindow: Bool {
        if let role = string(AXAttribute.role), role != AXRoleValue.window {
            return false
        }
        guard string(AXAttribute.subrole) == AXRoleValue.standardWindow else {
            return false
        }
        return bool(AXAttribute.fullScreen) != true
    }
}

enum AXReader {
    /// The windows LaneKeep works with, in Accessibility order. Saving and restoring both use this
    /// list, so a window's index means the same thing in both.
    static func standardWindows(of application: AXUIElement) -> [AXUIElement] {
        application.elements(AXAttribute.windows).filter(\.isStandardNonFullScreenWindow)
    }
}

/// Process-wide Accessibility settings.
public enum AccessibilityTuning {
    /// Limits how long a single Accessibility call waits for an app that does not respond (the
    /// system default is several seconds).
    public static func configureMessagingTimeout(seconds: Float = 1) {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), seconds)
    }
}
#endif
