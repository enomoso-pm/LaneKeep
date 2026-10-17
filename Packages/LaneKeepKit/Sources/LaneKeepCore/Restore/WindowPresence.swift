import Foundation

/// One of an app's windows as the window server reports it: on any desktop, shown or not.
public struct ServerWindow: Equatable, Sendable {
    public var layer: Int
    public var alpha: Double
    public var width: Double
    public var height: Double
    /// Whether the window is shown on its desktop ("ordered in"). `false` for a window that its app
    /// keeps after the user closed it; `nil` when the window server could not be asked.
    public var isOrderedIn: Bool?

    public init(layer: Int, alpha: Double, width: Double, height: Double, isOrderedIn: Bool?) {
        self.layer = layer
        self.alpha = alpha
        self.width = width
        self.height = height
        self.isOrderedIn = isOrderedIn
    }
}

/// Decides whether a running app that the Accessibility API shows without windows really has none,
/// before it is asked to open one (like clicking its Dock icon).
public enum WindowPresence {
    /// Whether the app shows a normal window on some desktop. Windows on another desktop are invisible
    /// to the Accessibility API, and asking such an app for a window would switch to that desktop, so
    /// they count.
    ///
    /// Windows that the app keeps after they were closed are shown nowhere and do not count: some apps
    /// (LINE, for one) keep their main window after it is closed and show it again when asked. When the
    /// window server could not be asked, a window counts, so that no window is opened unasked.
    public static func showsWindow(_ windows: [ServerWindow]) -> Bool {
        windows.contains { window in
            window.layer == 0
                && window.alpha > 0
                && window.width >= 50
                && window.height >= 50
                && window.isOrderedIn != false
        }
    }
}
