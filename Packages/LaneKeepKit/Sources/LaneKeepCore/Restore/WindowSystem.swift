import Foundation

/// Whether an app is running.
public enum RunningState: Equatable, Sendable {
    case notRunning
    case running(isHidden: Bool)
}

public enum LaunchRequestResult: Equatable, Sendable {
    /// The system was asked to launch the app. Its windows may take a while to appear.
    case requested
    /// No app with that bundle ID is installed.
    case notInstalled
}

public enum FrameChangeResult: Equatable, Sendable {
    /// The window was moved (and resized, if it is resizable).
    case applied
    /// The window could not be moved.
    case failed
}

/// A window as the restore engine sees it.
public struct SystemWindow<Handle: Hashable> {
    public var handle: Handle
    public var title: String
    public var isMinimized: Bool

    public init(handle: Handle, title: String, isMinimized: Bool) {
        self.handle = handle
        self.title = title
        self.isMinimized = isMinimized
    }
}

/// Everything the restore engine needs from the operating system.
///
/// The production implementation talks to the Accessibility API and `NSWorkspace`; tests use an
/// in-memory fake. All frames are in Accessibility coordinates (top-left origin).
///
/// An instance is used by one restore at a time, from a single task.
public protocol WindowSystem: AnyObject {
    associatedtype Handle: Hashable

    func runningState(of bundleID: String) async -> RunningState
    func requestLaunch(of bundleID: String) async -> LaunchRequestResult
    /// Asks a running app that has no window on any desktop to open one (like clicking its Dock
    /// icon). Returns `false` when the app has windows elsewhere or could not be asked.
    func requestReopenIfWindowless(_ bundleID: String) async -> Bool
    func unhide(_ bundleID: String) async

    /// The app's standard, non-full-screen windows in Accessibility order (minimized ones
    /// included). Empty when the app is not running or exposes no windows.
    func windows(of bundleID: String) async -> [SystemWindow<Handle>]

    /// Called before and after moving windows of an app, e.g. to switch off
    /// `AXEnhancedUserInterface`, which makes some apps animate and ignore moves.
    func beginArranging(_ bundleID: String) async
    func endArranging(_ bundleID: String) async

    func unminimize(_ window: Handle) async -> Bool
    func isMinimized(_ window: Handle) async -> Bool
    /// Sets size, then position, then size again (spec §6.4 step 6). Windows that cannot be
    /// resized are only moved.
    func setFrame(_ frame: CGRect, of window: Handle) async -> FrameChangeResult
    func setOrigin(_ origin: CGPoint, of window: Handle) async -> Bool
    func frame(of window: Handle) async -> CGRect?
}
