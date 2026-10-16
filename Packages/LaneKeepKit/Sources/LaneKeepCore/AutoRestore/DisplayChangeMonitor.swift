import Foundation

/// Turns display-change signals from several sources into one evaluation per burst (spec §6.2).
///
/// macOS does not always say when displays change: after sleep, or when a dock reconnects,
/// `didChangeScreenParametersNotification` can be missing. So the app listens to several sources —
/// that notification, the Quartz display reconfiguration callback, "screens did wake" — and also
/// checks the signature every `checkInterval`.
///
/// Whatever the source, a signal takes the same path: the tracker sees the displays connected at
/// that moment, and the evaluation waits until no signal has come for `settleDelay` (two seconds).
/// The tracker reports a change only once, so several sources noticing the same change never
/// restore twice.
@MainActor
public final class DisplayChangeMonitor {
    /// How often the app compares the signature with the last one it saw.
    public static let checkInterval: Duration = .milliseconds(1500)

    /// Called on every signal, right away, so that the UI can follow along.
    public var onDisplaysChanged: (() -> Void)?
    /// Called once things have settled, with what happened.
    public var onSettled: ((AutoRestoreTrigger) -> Void)?

    private var tracker: AutoRestoreTracker
    private var lastObservedSignature: String
    private let settleDelay: Duration
    private let currentSignature: @MainActor () -> String
    private var pendingEvaluation: Task<Void, Never>?

    /// - Parameter currentSignature: The signature of the displays connected right now.
    public init(
        initialSignature: String,
        settleDelay: Duration = .seconds(2),
        currentSignature: @escaping @MainActor () -> String
    ) {
        tracker = AutoRestoreTracker(initialSignature: initialSignature)
        lastObservedSignature = initialSignature
        self.settleDelay = settleDelay
        self.currentSignature = currentSignature
    }

    /// A notification or callback said that the displays may have changed.
    public func displaysMayHaveChanged() {
        let signature = currentSignature()
        lastObservedSignature = signature
        tracker.noteSignature(signature)
        onDisplaysChanged?()
        scheduleEvaluation()
    }

    /// The periodic check. When the displays differ from the last ones seen — a change nobody
    /// reported — it is handled like a notification; otherwise nothing happens.
    public func checkForMissedChange() {
        guard currentSignature() != lastObservedSignature else { return }
        displaysMayHaveChanged()
    }

    /// The Mac woke from sleep.
    public func didWake() {
        tracker.noteWake()
        scheduleEvaluation()
    }

    /// Drops an evaluation that is waiting for things to settle.
    public func cancelPendingEvaluation() {
        pendingEvaluation?.cancel()
        pendingEvaluation = nil
    }

    /// Waits until no signal has arrived for `settleDelay`, then evaluates once.
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
        let signature = currentSignature()
        lastObservedSignature = signature
        if let trigger = tracker.evaluate(currentSignature: signature) {
            onSettled?(trigger)
        }
    }
}
