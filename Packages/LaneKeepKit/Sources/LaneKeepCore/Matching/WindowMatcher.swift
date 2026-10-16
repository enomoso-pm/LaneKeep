import Foundation

/// A window of one app as the matcher sees it.
public struct MatchableWindow: Equatable, Sendable {
    public var title: String
    /// Position of the window among all the app's windows (what `WindowRule.index` refers to).
    public var position: Int

    public init(title: String, position: Int) {
        self.title = title
        self.position = position
    }
}

/// Decides which window each rule applies to (spec §6.3).
public enum WindowMatcher {
    /// Matches the rules of one app against that app's windows.
    ///
    /// 1. The caller has already narrowed everything down to one bundle ID.
    /// 2. Rules with a title marker take the first free window whose title contains the marker
    ///    (case-insensitive). They do not fall back to another window: a rule that names a
    ///    specific document should not grab an unrelated one.
    /// 3. The other rules, lowest `index` first, take the window at their saved position. When
    ///    that window is gone or already taken, they take the first free window instead.
    /// 4. A window is never assigned to two rules.
    ///
    /// - Parameters:
    ///   - rules: Rules of a single app.
    ///   - windows: That app's windows in Accessibility order.
    ///   - excluded: Indices into `windows` that are already taken (used while waiting for the
    ///     windows of a launching app to appear one by one).
    /// - Returns: For every rule (same order as `rules`) the index into `windows`, or `nil`.
    public static func assign(
        rules: [WindowRule],
        windows: [MatchableWindow],
        excluding excluded: Set<Int> = []
    ) -> [Int?] {
        var assignment = [Int?](repeating: nil, count: rules.count)
        var taken = excluded

        for (ruleIndex, rule) in rules.enumerated() {
            guard let marker = rule.titleMarker else { continue }
            let match = windows.indices.first { index in
                !taken.contains(index) && windows[index].title.localizedCaseInsensitiveContains(marker)
            }
            if let match {
                assignment[ruleIndex] = match
                taken.insert(match)
            }
        }

        let positionalRules = rules.indices
            .filter { rules[$0].titleMarker == nil }
            .sorted { (rules[$0].index, $0) < (rules[$1].index, $1) }
        for ruleIndex in positionalRules {
            let wanted = rules[ruleIndex].index
            let exact = windows.indices.first { windows[$0].position == wanted && !taken.contains($0) }
            guard let match = exact ?? windows.indices.first(where: { !taken.contains($0) }) else {
                continue
            }
            assignment[ruleIndex] = match
            taken.insert(match)
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
}
