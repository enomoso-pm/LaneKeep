import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Where a window is right now, in the terms of a `WindowRule`.
public struct WindowLocation: Equatable, Sendable {
    /// The display that contains the window's center.
    public var displayUUID: String
    /// The window's frame relative to that display's visible area (top-left origin).
    public var relativeFrame: CGRect

    public init(displayUUID: String, relativeFrame: CGRect) {
        self.displayUUID = displayUUID
        self.relativeFrame = relativeFrame
    }
}

/// A window of one app as the matcher sees it.
public struct MatchableWindow: Equatable, Sendable {
    public var title: String
    /// Position of the window among all the app's windows (what `WindowRule.index` refers to).
    public var position: Int
    /// Where the window is now, if known.
    public var location: WindowLocation?

    public init(title: String, position: Int, location: WindowLocation? = nil) {
        self.title = title
        self.position = position
        self.location = location
    }
}

/// How rules without a title marker choose their window.
public enum MatchingStrategy: Sendable {
    /// The window closest to the rule's place (restoring workspaces).
    case closest
    /// Exactly the window at the rule's `index`, or none (the `lanekeep move --index` command,
    /// which names one particular window).
    case exactIndex
}

/// Decides which window each rule applies to (spec §6.3).
public enum WindowMatcher {
    /// Matches the rules of one app against that app's windows.
    ///
    /// 1. The caller has already narrowed everything down to one bundle ID.
    /// 2. Rules with a title marker take a free window whose title contains the marker
    ///    (case-insensitive). They do not fall back to another window: a rule that names a
    ///    specific document should not grab an unrelated one.
    /// 3. The other rules share the remaining windows. The Accessibility API lists an app's
    ///    windows front to back, so their order changes whenever another window of the app is
    ///    clicked; the saved `index` alone would swap windows around. Each rule therefore takes the
    ///    window that is closest to the rule's place (relative position and size on its display,
    ///    preferring the rule's display), and the saved order only breaks ties: then the rules,
    ///    lowest `index` first, take the windows in their current order.
    /// 4. A window is never assigned to two rules.
    ///
    /// - Parameters:
    ///   - rules: Rules of a single app.
    ///   - windows: That app's windows in Accessibility order.
    ///   - excluded: Indices into `windows` that are already taken (used while waiting for the
    ///     windows of a launching app to appear one by one).
    ///   - strategy: `.exactIndex` replaces step 3 with "the window at the rule's `index`".
    /// - Returns: For every rule (same order as `rules`) the index into `windows`, or `nil`.
    public static func assign(
        rules: [WindowRule],
        windows: [MatchableWindow],
        excluding excluded: Set<Int> = [],
        strategy: MatchingStrategy = .closest
    ) -> [Int?] {
        var assignment = [Int?](repeating: nil, count: rules.count)
        var taken = excluded

        let markerRules = rules.indices.filter { rules[$0].titleMarker != nil }
        assignClosest(markerRules, rules: rules, windows: windows, assignment: &assignment, taken: &taken) { rule, window in
            guard let marker = rule.titleMarker else { return false }
            return window.title.localizedCaseInsensitiveContains(marker)
        }
        let otherRules = rules.indices.filter { rules[$0].titleMarker == nil }
        switch strategy {
        case .closest:
            assignClosest(otherRules, rules: rules, windows: windows, assignment: &assignment, taken: &taken) { _, _ in true }
        case .exactIndex:
            assignClosest(otherRules, rules: rules, windows: windows, assignment: &assignment, taken: &taken) { rule, window in
                window.position == rule.index
            }
        }
        return assignment
    }

    /// Convenience for windows given in Accessibility order, where the position is the array index.
    public static func assign(rules: [WindowRule], titles: [String], excluding excluded: Set<Int> = []) -> [Int?] {
        assign(
            rules: rules,
            windows: titles.enumerated().map { MatchableWindow(title: $0.element, position: $0.offset) },
            excluding: excluded
        )
    }

    /// How far a window is from where a rule puts it: the distance between the centers plus half
    /// the difference in size (both relative to the display), plus a penalty when the window is
    /// on another display. A window whose place is unknown is farther than any known one.
    public static func distance(from rule: WindowRule, to location: WindowLocation?) -> Double {
        guard let location else { return unknownDistance }
        let target = rule.relativeFrame
        let current = location.relativeFrame
        let centers = hypot(Double(target.midX - current.midX), Double(target.midY - current.midY))
        let sizes = Double(abs(target.width - current.width) + abs(target.height - current.height))
        let display = location.displayUUID == rule.displayUUID ? 0 : otherDisplayPenalty
        let value = centers + sizes / 2 + display
        return value.isFinite ? value : unknownDistance
    }

    static let otherDisplayPenalty = 0.5
    static let unknownDistance = 10.0
    /// Weight of the saved order; small enough to only break ties between equally distant windows.
    static let orderWeight = 0.001

    /// Gives each rule the free, eligible window with the lowest cost, cheapest pairs first.
    private static func assignClosest(
        _ ruleIndices: [Int],
        rules: [WindowRule],
        windows: [MatchableWindow],
        assignment: inout [Int?],
        taken: inout Set<Int>,
        eligible: (WindowRule, MatchableWindow) -> Bool
    ) {
        guard !ruleIndices.isEmpty else { return }
        let freeWindows = windows.indices.filter { !taken.contains($0) }
        guard !freeWindows.isEmpty else { return }

        // The saved order of the rules and the current order of the windows, for tie-breaking.
        let ruleRank = rank(ruleIndices) { (rules[$0].index, $0) < (rules[$1].index, $1) }
        let windowRank = rank(freeWindows) { (windows[$0].position, $0) < (windows[$1].position, $1) }

        struct Pair {
            var cost: Double
            var ruleRank: Int
            var windowRank: Int
            var rule: Int
            var window: Int
        }
        var pairs: [Pair] = []
        for ruleIndex in ruleIndices {
            for windowIndex in freeWindows where eligible(rules[ruleIndex], windows[windowIndex]) {
                let order = Double(abs((ruleRank[ruleIndex] ?? 0) - (windowRank[windowIndex] ?? 0)))
                pairs.append(Pair(
                    cost: distance(from: rules[ruleIndex], to: windows[windowIndex].location) + order * orderWeight,
                    ruleRank: ruleRank[ruleIndex] ?? 0,
                    windowRank: windowRank[windowIndex] ?? 0,
                    rule: ruleIndex,
                    window: windowIndex
                ))
            }
        }
        pairs.sort { lhs, rhs in
            if lhs.cost != rhs.cost {
                return lhs.cost < rhs.cost
            }
            return (lhs.ruleRank, lhs.windowRank) < (rhs.ruleRank, rhs.windowRank)
        }
        for pair in pairs where assignment[pair.rule] == nil && !taken.contains(pair.window) {
            assignment[pair.rule] = pair.window
            taken.insert(pair.window)
        }
    }

    private static func rank(_ indices: [Int], by areInIncreasingOrder: (Int, Int) -> Bool) -> [Int: Int] {
        var ranks: [Int: Int] = [:]
        for (rank, index) in indices.sorted(by: areInIncreasingOrder).enumerated() {
            ranks[index] = rank
        }
        return ranks
    }
}
