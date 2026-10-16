import AppKit
import CoreGraphics
import LaneKeepCore
import LaneKeepSystem

/// Watches for display changes and wake-ups (spec §6.2) and hands them to a
/// `DisplayChangeMonitor`, which waits for things to settle and decides what happened.
///
/// macOS does not always post `didChangeScreenParametersNotification` (e.g. after sleep), so
/// there are several sources, all handled the same way:
/// - `NSApplication.didChangeScreenParametersNotification`
/// - the Quartz display reconfiguration callback (the call before a reconfiguration is ignored)
/// - `NSWorkspace.screensDidWakeNotification`
/// - a check of the display signature every 1.5 seconds, which only acts when it changed
///
/// `NSWorkspace.didWakeNotification` reports that the Mac woke up (for "restore on wake").
@MainActor
final class DisplayMonitor {
    var onDisplaysChanged: (() -> Void)? {
        get { changes.onDisplaysChanged }
        set { changes.onDisplaysChanged = newValue }
    }

    var onSettled: ((AutoRestoreTrigger) -> Void)? {
        get { changes.onSettled }
        set { changes.onSettled = newValue }
    }

    /// The monitor the Quartz callback reports to (it cannot capture anything).
    fileprivate static weak var current: DisplayMonitor?

    private let changes: DisplayChangeMonitor
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var checkTimer: Timer?
    private var isReconfigurationCallbackRegistered = false

    init(initialSignature: String, settleDelay: Duration = .seconds(2)) {
        changes = DisplayChangeMonitor(initialSignature: initialSignature, settleDelay: settleDelay) {
            DisplaySignature.make(for: ScreenReader.currentDisplays())
        }
    }

    func start() {
        guard observers.isEmpty else { return }
        let screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.changes.displaysMayHaveChanged()
            }
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let screensWakeToken = workspaceCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.changes.displaysMayHaveChanged()
            }
        }
        let wakeToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.changes.didWake()
            }
        }
        observers = [
            (NotificationCenter.default, screenToken),
            (workspaceCenter, screensWakeToken),
            (workspaceCenter, wakeToken)
        ]

        Self.current = self
        isReconfigurationCallbackRegistered = CGDisplayRegisterReconfigurationCallback(displayReconfigured, nil) == .success

        let interval = DisplayChangeMonitor.checkInterval
        let seconds = Double(interval.components.seconds) + Double(interval.components.attoseconds) / 1e18
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.changes.checkForMissedChange()
            }
        }
        timer.tolerance = 0.3
        // Common modes: keep checking while a menu is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        checkTimer = timer
    }

    func stop() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers = []
        if isReconfigurationCallbackRegistered {
            CGDisplayRemoveReconfigurationCallback(displayReconfigured, nil)
            isReconfigurationCallbackRegistered = false
        }
        if Self.current === self {
            Self.current = nil
        }
        checkTimer?.invalidate()
        checkTimer = nil
        changes.cancelPendingEvaluation()
    }

    fileprivate func quartzReconfigured() {
        changes.displaysMayHaveChanged()
    }
}

/// Called by Quartz before and after every display reconfiguration (connecting, disconnecting,
/// moving, mirroring…). Only the calls after one matter; they go to the main actor.
private func displayReconfigured(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard !flags.contains(.beginConfigurationFlag) else { return }
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            DisplayMonitor.current?.quartzReconfigured()
        }
    }
}
