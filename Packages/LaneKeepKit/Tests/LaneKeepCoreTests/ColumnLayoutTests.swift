import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import LaneKeepCore

@Suite("Rule table columns")
struct ColumnLayoutTests {
    // The column widths of the mock's table, and the narrowest each column may get.
    let weights: [CGFloat] = [150, 182, 172, 235, 109]
    let minimums: [CGFloat] = [110, 130, 146, 196, 96]

    @Test("At the mock's width the columns are the mock's")
    func mockWidth() {
        let widths = ColumnLayout.widths(total: 848, weights: weights, minimums: minimums)
        #expect(widths == weights)
    }

    @Test("Wider tables grow every column in proportion")
    func wider() {
        let widths = ColumnLayout.widths(total: 1696, weights: weights, minimums: minimums)
        #expect(widths == weights.map { $0 * 2 })
    }

    @Test("Columns below their minimum are pinned and the rest share what is left")
    func narrow() {
        let widths = ColumnLayout.widths(total: 700, weights: weights, minimums: minimums)
        #expect(abs(widths.reduce(0, +) - 700) < 0.001)
        for (width, minimum) in zip(widths, minimums) {
            #expect(width >= minimum - 0.001)
        }
        // The position column would get 194 pt in proportion; it keeps its minimum instead.
        #expect(widths[3] == 196)
        // The first two columns keep their proportion to each other.
        #expect(abs(widths[0] / widths[1] - 150.0 / 182.0) < 0.001)
    }

    @Test("When even the minimums do not fit, every column gets its minimum")
    func tooNarrow() {
        #expect(ColumnLayout.widths(total: 500, weights: weights, minimums: minimums) == minimums)
        #expect(ColumnLayout.widths(total: .infinity, weights: weights, minimums: minimums) == minimums)
    }

    @Test("Exactly the sum of the minimums")
    func exactMinimum() {
        let total = minimums.reduce(0, +)
        #expect(ColumnLayout.widths(total: total, weights: weights, minimums: minimums) == minimums)
    }
}
