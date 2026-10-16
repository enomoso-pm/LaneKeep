import AppKit
import LaneKeepCore
import LaneKeepSystem

/// Watches for display changes and wake-ups (spec §6.2).
///
/// - `onDisplaysChanged` fires right away so the UI can follow along.
/// - `onSettled` fires once things have been quiet for two seconds — connecting a display
///   produces a burst of notifications — and only when the set of displays actually changed or
///   the Mac woke up.
@MainActor
final class DisplayMonitor {
    var onDisplaysChanged: (() -> Void)?
    var onSettled: ((AutoRestoreTrigger) -> Void)?

    private var tracker: AutoRestoreTracker
    private var pendingEvaluation: Task<Void, Never>?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private let settleDelay: Duration

    init(initialSignature: String, settleDelay: Duration = .seconds(2)) {
        tracker = AutoRestoreTracker(initialSignature: initialSignature)
        self.settleDelay = settleDelay
    }

    func start() {
        guard observers.isEmpty else { return }
        let screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screenParametersDidChange()
            }
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let wakeToken = workspaceCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.didWake()
            }
        }
        observers = [(NotificationCenter.default, screenToken), (workspaceCenter, wakeToken)]
    }

    func stop() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers = []
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
    }

    private func screenParametersDidChange() {
        onDisplaysChanged?()
        scheduleEvaluation()
    }

    private func didWake() {
        tracker.noteWake()
        scheduleEvaluation()
    }

    /// Waits until no notification has arrived for `settleDelay`, then evaluates once.
    private func scheduleEvaluation() {
        pendingEvaluation?.cancel()
        let delay = settleDelay
        pendingEvaluation = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.evaluate()
        }
    }

    private func evaluate() {
        pendingEvaluation = nil
        let signature = DisplaySignature.make(ScreenReader.currentDisplays().map(\.uuid))
        if let trigger = tracker.evaluate(currentSignature: signature) {
            onSettled?(trigger)
        }
    }
}
