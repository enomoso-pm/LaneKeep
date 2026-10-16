import Foundation

/// The second look after an automatic restore (see `RestoreEngine.review(_:of:)`).
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
