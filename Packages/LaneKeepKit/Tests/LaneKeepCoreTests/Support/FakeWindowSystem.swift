import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import LaneKeepCore

/// A window of the fake system. Identity is the object identity.
final class FakeWindow: Hashable, CustomStringConvertible {
    var title: String
    var frame: CGRect
    var isMinimized: Bool
    var isResizable = true
    var isMovable = true
    var minimumSize = CGSize.zero
    /// The next this many `setOrigin` calls are acknowledged but have no effect.
    var ignoredMoves = 0
    /// The next this many `setFrame` calls report a failure although the window does move (an app
    /// that answers too late).
    var lateFrameChanges = 0
    /// A closed window: its handle no longer answers.
    var isClosed = false
    /// The next this many `setFrame` calls move the window but leave its size as it was (an app
    /// that applies sizes late).
    var lateResizes = 0

    init(title: String, frame: CGRect = CGRect(x: 0, y: 0, width: 400, height: 300), isMinimized: Bool = false) {
        self.title = title
        self.frame = frame
        self.isMinimized = isMinimized
    }

    static func == (lhs: FakeWindow, rhs: FakeWindow) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    var description: String { "FakeWindow(\(title))" }
}

final class FakeApp {
    let bundleID: String
    var isInstalled = true
    var isRunning: Bool
    var isHidden = false
    var windows: [FakeWindow]
    /// Windows that show up after the app was launched or reopened, after `lookupsBeforeWindowsAppear`
    /// further window lookups.
    var windowsAfterLaunch: [FakeWindow] = []
    var lookupsBeforeWindowsAppear = 0
    /// Simulates an app whose only windows are on another desktop.
    var hasWindowsOnOtherDesktops = false
    /// The next this many window lookups get no answer (a busy app).
    var unansweredLookups = 0
    /// Called on every window lookup with the number of lookups so far, to change windows over time.
    var onLookup: ((FakeApp, Int) -> Void)?
    private(set) var lookups = 0
    private(set) var wasLaunchedOrReopened = false

    init(bundleID: String, isRunning: Bool, windows: [FakeWindow]) {
        self.bundleID = bundleID
        self.isRunning = isRunning
        self.windows = windows
    }

    func markLaunched() {
        wasLaunchedOrReopened = true
    }

    func noteLookup() {
        lookups += 1
        onLookup?(self, lookups)
    }
}

/// An in-memory `WindowSystem` that records what the engine asked for.
final class FakeWindowSystem: WindowSystem {
    typealias Handle = FakeWindow

    private(set) var apps: [String: FakeApp] = [:]
    private(set) var events: [String] = []

    @discardableResult
    func addApp(_ bundleID: String, running: Bool = true, windows: [FakeWindow] = []) -> FakeApp {
        let app = FakeApp(bundleID: bundleID, isRunning: running, windows: windows)
        apps[bundleID] = app
        return app
    }

    /// Adds running apps with one window each for every rule of the workspace.
    func addApps(for workspace: Workspace) {
        for rule in workspace.windows {
            let app = apps[rule.bundleID] ?? addApp(rule.bundleID)
            app.windows.append(FakeWindow(title: "\(rule.appName) \(app.windows.count + 1) \(rule.titleContains ?? "")"))
        }
    }

    func runningState(of bundleID: String) async -> RunningState {
        guard let app = apps[bundleID], app.isRunning else { return .notRunning }
        return .running(isHidden: app.isHidden)
    }

    func requestLaunch(of bundleID: String) async -> LaunchRequestResult {
        events.append("launch \(bundleID)")
        guard let app = apps[bundleID], app.isInstalled else { return .notInstalled }
        app.isRunning = true
        app.markLaunched()
        return .requested
    }

    func requestReopenIfWindowless(_ bundleID: String) async -> Bool {
        events.append("reopen \(bundleID)")
        guard let app = apps[bundleID], app.isRunning, !app.hasWindowsOnOtherDesktops else { return false }
        app.markLaunched()
        return true
    }

    func unhide(_ bundleID: String) async {
        events.append("unhide \(bundleID)")
        apps[bundleID]?.isHidden = false
    }

    /// Time each `setFrame` takes, to simulate slow apps.
    var setFrameDelay: Duration = .zero
    /// Called after every `setFrame` that moved a window, e.g. to change things right then.
    var onSetFrame: ((FakeWindow) -> Void)?

    func windows(of bundleID: String) async -> [SystemWindow<FakeWindow>]? {
        guard let app = apps[bundleID], app.isRunning else { return [] }
        app.noteLookup()
        if app.unansweredLookups > 0 {
            app.unansweredLookups -= 1
            events.append("busy \(bundleID)")
            return nil
        }
        if app.wasLaunchedOrReopened, !app.windowsAfterLaunch.isEmpty {
            if app.lookupsBeforeWindowsAppear > 0 {
                app.lookupsBeforeWindowsAppear -= 1
            } else {
                app.windows.insert(contentsOf: app.windowsAfterLaunch, at: 0)
                app.windowsAfterLaunch = []
            }
        }
        return app.windows.map { SystemWindow(handle: $0, title: $0.title, isMinimized: $0.isMinimized, frame: $0.frame) }
    }

    func beginArranging(_ bundleID: String) async {
        events.append("begin \(bundleID)")
    }

    func endArranging(_ bundleID: String) async {
        events.append("end \(bundleID)")
    }

    func unminimize(_ window: FakeWindow) async -> Bool {
        events.append("unminimize \(window.title)")
        window.isMinimized = false
        return true
    }

    func isMinimized(_ window: FakeWindow) async -> Bool {
        window.isMinimized
    }

    func setFrame(_ frame: CGRect, of window: FakeWindow) async -> FrameChangeResult {
        if setFrameDelay > .zero {
            try? await Task.sleep(for: setFrameDelay)
        }
        guard window.isMovable, !window.isClosed else { return .failed }
        var size = window.isResizable ? frame.size : window.frame.size
        if window.lateResizes > 0 {
            window.lateResizes -= 1
            size = window.frame.size
        }
        size.width = max(size.width, window.minimumSize.width)
        size.height = max(size.height, window.minimumSize.height)
        window.frame = CGRect(origin: frame.origin, size: size)
        events.append("setFrame \(window.title)")
        onSetFrame?(window)
        if window.lateFrameChanges > 0 {
            window.lateFrameChanges -= 1
            return .failed
        }
        return .applied
    }

    func setOrigin(_ origin: CGPoint, of window: FakeWindow) async -> Bool {
        guard window.isMovable else { return false }
        events.append("setOrigin \(window.title)")
        if window.ignoredMoves > 0 {
            window.ignoredMoves -= 1
            return true
        }
        window.frame.origin = origin
        return true
    }

    func frame(of window: FakeWindow) async -> CGRect? {
        window.isClosed ? nil : window.frame
    }
}
