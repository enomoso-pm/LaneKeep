import AppKit

/// Opens and closes the `MenuBarExtra` window from code.
///
/// SwiftUI has no API for this, so the bridge clicks LaneKeep's status item button the way the
/// user would, which keeps SwiftUI's own idea of whether the window is shown in sync.
@MainActor
enum StatusItemBridge {
    /// The menu bar window, once it has been shown.
    static weak var menuWindow: NSWindow?

    static var isMenuOpen: Bool {
        menuWindow?.isVisible ?? false
    }

    static func toggleMenu() {
        statusButton()?.performClick(nil)
    }

    static func openMenu() {
        if !isMenuOpen {
            toggleMenu()
        }
    }

    static func closeMenu() {
        if isMenuOpen {
            toggleMenu()
        }
    }

    private static func statusButton() -> NSStatusBarButton? {
        for window in NSApp.windows where window.className.contains("NSStatusBarWindow") {
            if let button = findButton(in: window.contentView) {
                return button
            }
        }
        return nil
    }

    private static func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton {
            return button
        }
        for subview in view.subviews {
            if let button = findButton(in: subview) {
                return button
            }
        }
        return nil
    }
}
