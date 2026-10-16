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

/// The answer to reading an attribute.
enum AXRead {
    case value(CFTypeRef)
    /// The element has no such attribute, or no value for it.
    case missing
    /// The app did not answer in time (`kAXErrorCannotComplete`): it is busy or hangs.
    case noAnswer
}

extension AXUIElement {
    func read(_ attribute: String) -> AXRead {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(self, attribute as CFString, &value) {
        case .success:
            return value.map(AXRead.value) ?? .missing
        case .cannotComplete:
            return .noAnswer
        default:
            return .missing
        }
    }

    func copyValue(_ attribute: String) -> CFTypeRef? {
        if case .value(let value) = read(attribute) {
            return value
        }
        return nil
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

    /// Whether this is a regular document/app window: not a sheet, a panel, a tooltip or a
    /// full-screen window. `nil` when the app did not answer.
    var isStandardNonFullScreenWindow: Bool? {
        switch read(AXAttribute.role) {
        case .noAnswer:
            return nil
        case .value(let role):
            if (role as? String) != AXRoleValue.window {
                return false
            }
        case .missing:
            break
        }
        switch read(AXAttribute.subrole) {
        case .noAnswer:
            return nil
        case .value(let subrole):
            guard (subrole as? String) == AXRoleValue.standardWindow else {
                return false
            }
        case .missing:
            return false
        }
        switch read(AXAttribute.fullScreen) {
        case .noAnswer:
            return nil
        case .value(let value):
            return (value as? Bool) != true
        case .missing:
            return true
        }
    }
}

enum AXReader {
    /// The windows LaneKeep works with, in Accessibility order. Saving and restoring both use this
    /// list, so a window's index means the same thing in both.
    ///
    /// `nil` when the app did not answer, so that a busy app is not mistaken for one without
    /// windows, and no window is silently left out of the list.
    static func standardWindows(of application: AXUIElement) -> [AXUIElement]? {
        let windows: [AXUIElement]
        switch application.read(AXAttribute.windows) {
        case .noAnswer:
            return nil
        case .missing:
            return []
        case .value(let value):
            windows = value as? [AXUIElement] ?? []
        }
        var standard: [AXUIElement] = []
        for window in windows {
            guard let isStandard = window.isStandardNonFullScreenWindow else {
                return nil
            }
            if isStandard {
                standard.append(window)
            }
        }
        return standard
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
