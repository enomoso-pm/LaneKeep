#if canImport(AppKit)
import AppKit
import ApplicationServices
import LaneKeepCore

/// `WindowSystem` backed by the Accessibility API and `NSWorkspace`.
///
/// Accessibility calls are made on whatever thread the restore runs on (never the main thread when
/// started through `LiveRestore`); AppKit objects are only touched on the main actor.
public final class AXWindowSystem: WindowSystem {
    public typealias Handle = AXUIElement

    /// Apps whose `AXEnhancedUserInterface` was switched off for the move, to switch it back on.
    private var suspendedEnhancedUI: [String: AXUIElement] = [:]

    public init() {}

    public func runningState(of bundleID: String) async -> RunningState {
        await MainActor.run {
            guard let app = RunningApps.application(bundleID: bundleID) else {
                return RunningState.notRunning
            }
            return RunningState.running(isHidden: app.isHidden)
        }
    }

    public func requestLaunch(of bundleID: String) async -> LaunchRequestResult {
        let opened = await MainActor.run { AppLauncher.open(bundleID: bundleID, activate: false) }
        Log.restore.info("Launching \(bundleID, privacy: .public): \(opened ? "requested" : "not installed", privacy: .public)")
        return opened ? .requested : .notInstalled
    }

    public func requestReopenIfWindowless(_ bundleID: String) async -> Bool {
        guard let pid = await processIdentifier(of: bundleID) else {
            return false
        }
        // Windows on another desktop are invisible to the Accessibility API; do not open a new
        // window for an app that only looks windowless from here.
        guard !WindowServerProbe.hasWindows(pid: pid) else {
            return false
        }
        Log.restore.info("Reopening \(bundleID, privacy: .public), it has no windows")
        // Activation is what makes Launch Services send the "reopen" event.
        return await MainActor.run { AppLauncher.open(bundleID: bundleID, activate: true) }
    }

    public func unhide(_ bundleID: String) async {
        await MainActor.run {
            _ = RunningApps.application(bundleID: bundleID)?.unhide()
        }
    }

    public func windows(of bundleID: String) async -> [SystemWindow<AXUIElement>] {
        guard let pid = await processIdentifier(of: bundleID) else {
            return []
        }
        let application = AXUIElementCreateApplication(pid)
        return AXReader.standardWindows(of: application).map { window in
            SystemWindow(
                handle: window,
                title: window.string(AXAttribute.title) ?? "",
                isMinimized: window.bool(AXAttribute.minimized) ?? false
            )
        }
    }

    public func beginArranging(_ bundleID: String) async {
        guard suspendedEnhancedUI[bundleID] == nil, let pid = await processIdentifier(of: bundleID) else {
            return
        }
        let application = AXUIElementCreateApplication(pid)
        if application.bool(AXAttribute.enhancedUserInterface) == true,
           application.set(AXAttribute.enhancedUserInterface, to: kCFBooleanFalse) == .success {
            suspendedEnhancedUI[bundleID] = application
        }
    }

    public func endArranging(_ bundleID: String) async {
        if let application = suspendedEnhancedUI.removeValue(forKey: bundleID) {
            application.set(AXAttribute.enhancedUserInterface, to: kCFBooleanTrue)
        }
    }

    public func unminimize(_ window: AXUIElement) async -> Bool {
        window.set(AXAttribute.minimized, to: kCFBooleanFalse) == .success
    }

    public func isMinimized(_ window: AXUIElement) async -> Bool {
        window.bool(AXAttribute.minimized) ?? false
    }

    public func setFrame(_ frame: CGRect, of window: AXUIElement) async -> FrameChangeResult {
        let resizable = window.isSettable(AXAttribute.size)
        // Size, position, size: moving to a display with another resolution can change the size
        // on the way (spec §6.4 step 6).
        if resizable {
            window.setSize(frame.size)
        }
        let moved = window.setPosition(frame.origin)
        if resizable {
            window.setSize(frame.size)
        }
        if moved == .success {
            return .applied
        }
        // Some apps report an error although the window did move.
        if let position = window.point(AXAttribute.position),
           abs(position.x - frame.minX) <= 2, abs(position.y - frame.minY) <= 2 {
            return .applied
        }
        Log.restore.error("Could not move a window: AXError \(moved.rawValue, privacy: .public)")
        return .failed
    }

    public func setOrigin(_ origin: CGPoint, of window: AXUIElement) async -> Bool {
        window.setPosition(origin) == .success
    }

    public func frame(of window: AXUIElement) async -> CGRect? {
        window.frame
    }

    private func processIdentifier(of bundleID: String) async -> pid_t? {
        await MainActor.run { RunningApps.application(bundleID: bundleID)?.processIdentifier }
    }
}

/// Runs restores against the real system.
public enum LiveRestore {
    /// Restores a workspace. The work happens off the main thread; `progress` is called after
    /// every window rule.
    public static func run(
        _ request: RestoreRequest,
        progress: @escaping @Sendable (RestoreProgress) async -> Void = { _ in }
    ) async -> RestoreReport {
        let task = Task.detached(priority: .userInitiated) {
            await RestoreEngine(system: AXWindowSystem()).run(request, progress: progress)
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
#endif
