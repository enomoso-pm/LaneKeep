import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Column widths for the window rule table: the columns share the available width in proportion
/// to their weights (the column widths of the UI mock), and none gets narrower than its minimum.
public enum ColumnLayout {
    /// Splits `total` among the columns. When even the minimums do not fit, every column gets its
    /// minimum and the row is wider than `total`.
    public static func widths(total: CGFloat, weights: [CGFloat], minimums: [CGFloat]) -> [CGFloat] {
        precondition(weights.count == minimums.count, "One weight and one minimum per column")
        guard total.isFinite, total > minimums.reduce(0, +) else {
            return minimums
        }
        // Columns whose proportional share is below their minimum are pinned to the minimum, and
        // the rest is shared again among the others, until every share is large enough. Each pass
        // pins at least one column, and since the minimums fit, at least one column stays free.
        var pinned = Array(repeating: false, count: weights.count)
        while true {
            let pinnedWidth = weights.indices.filter { pinned[$0] }.map { minimums[$0] }.reduce(0, +)
            let freeWeight = weights.indices.filter { !pinned[$0] }.map { max(0, weights[$0]) }.reduce(0, +)
            let remaining = total - pinnedWidth
            var pinnedAnother = false
            for index in weights.indices where !pinned[index] {
                if share(of: index, remaining: remaining, freeWeight: freeWeight, weights: weights) < minimums[index] {
                    pinned[index] = true
                    pinnedAnother = true
                }
            }
            guard pinnedAnother else {
                return weights.indices.map { index in
                    pinned[index]
                        ? minimums[index]
                        : share(of: index, remaining: remaining, freeWeight: freeWeight, weights: weights)
                }
            }
        }
    }

    private static func share(of index: Int, remaining: CGFloat, freeWeight: CGFloat, weights: [CGFloat]) -> CGFloat {
        guard freeWeight > 0 else { return 0 }
        return remaining * max(0, weights[index]) / freeWeight
    }
}
