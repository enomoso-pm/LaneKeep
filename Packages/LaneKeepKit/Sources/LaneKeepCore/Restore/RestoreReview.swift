import Foundation

/// The second look after an automatic restore (see `RestoreEngine.review(_:of:currentDisplays:)`).
public enum RestoreReview {
    /// How long after an automatic restore has finished the windows are looked at again: right
    /// after a display is connected, macOS keeps moving windows for a few seconds.
    public static let delay: Duration = .milliseconds(2500)

    /// Only automatic restores get a second look, and only when they placed a window. Restores
    /// the user starts happen when things have settled.
    public static func isNeeded(isAutomatic: Bool, report: RestoreReport) -> Bool {
        isAutomatic && report.placedCount > 0
    }

    /// The restore's result line, with the windows the second look put back:
    /// 「6件すべて配置しました。あとから動いた2件を置き直しました」
    public static func summary(_ summary: String, corrected: Int) -> String {
        guard corrected > 0 else { return summary }
        return "\(summary)。あとから動いた\(corrected)件を置き直しました"
    }
}

/// Waits `RestoreReview.delay` before the second look, and drops it when the displays change in
/// the meantime: the positions it would set were worked out for the displays of the restore. A
/// change while the second look runs stops it.
///
/// Changes are seen through `displaysChanged(to:)`, which the app calls whenever it reads the
/// displays, whichever way it learned that they may have changed.
@MainActor
public final class RestoreReviewScheduler {
    private let delay: Duration
    private var pending: (displays: [DisplaySnapshot], task: Task<Void, Never>)?

    public init(delay: Duration = RestoreReview.delay) {
        self.delay = delay
    }

    /// Plans the second look at a restore that placed windows for `displays`, instead of one that
    /// has not finished yet.
    ///
    /// - Parameters:
    ///   - review: Looks at the windows and returns how many it put back.
    ///   - completion: Called with that number, unless the second look was dropped or stopped.
    public func schedule(
        for displays: [DisplaySnapshot],
        review: @escaping @MainActor () async -> Int,
        completion: @escaping @MainActor (_ corrected: Int) -> Void
    ) {
        cancel()
        let delay = delay
        let task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let corrected = await review()
            guard !Task.isCancelled else { return }
            self?.pending = nil
            completion(corrected)
        }
        pending = (displays, task)
    }

    /// The displays connected now. A second look planned for other displays, or for the same
    /// ones arranged differently, is dropped, or stopped if it is running.
    public func displaysChanged(to displays: [DisplaySnapshot]) {
        guard let pending, !DisplayGeometry.isSameArrangement(pending.displays, displays) else { return }
        cancel()
    }

    /// Drops the second look, or stops it if it is running.
    public func cancel() {
        pending?.task.cancel()
        pending = nil
    }
}
