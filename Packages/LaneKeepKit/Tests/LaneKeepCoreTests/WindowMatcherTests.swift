import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import LaneKeepCore

@Suite("Window matching (spec §6.3)")
struct WindowMatcherTests {
    func rule(index: Int = 0, title: String? = nil) -> WindowRule {
        Fixtures.rule("App", index: index, title: title, display: "D", 0, 0, 50, 50)
    }

    @Test("Rules take the window at their saved position")
    func byIndex() {
        let assignment = WindowMatcher.assign(rules: [rule(index: 1), rule(index: 0)], titles: ["A", "B"])
        #expect(assignment == [1, 0])
    }

    @Test("A title marker wins over the position, case-insensitively")
    func byTitle() {
        let assignment = WindowMatcher.assign(
            rules: [rule(index: 0, title: "LaneKeep")],
            titles: ["notes.txt — Visual Studio Code", "README.md — lanekeep — Visual Studio Code"]
        )
        #expect(assignment == [1])
    }

    @Test("A title rule does not fall back to an unrelated window")
    func titleWithoutFallback() {
        #expect(WindowMatcher.assign(rules: [rule(title: "Budget")], titles: ["Untitled"]) == [nil])
    }

    @Test("Blank markers are ignored")
    func blankMarker() {
        #expect(WindowMatcher.assign(rules: [rule(index: 0, title: "  ")], titles: ["A"]) == [0])
    }

    @Test("A window is never assigned twice")
    func noDoubleAssignment() {
        let assignment = WindowMatcher.assign(
            rules: [rule(title: "Doc"), rule(index: 0), rule(index: 0)],
            titles: ["Doc 1", "Other", "Doc 2"]
        )
        #expect(assignment == [0, 1, 2])
        #expect(Set(assignment.compactMap { $0 }).count == 3)
    }

    @Test("When the saved position is taken or gone, the first free window is used")
    func fallback() {
        // The title rule takes window 0, so the index-0 rule falls back to window 1.
        #expect(WindowMatcher.assign(rules: [rule(title: "Main"), rule(index: 0)], titles: ["Main", "Second"]) == [0, 1])
        // Index 5 does not exist.
        #expect(WindowMatcher.assign(rules: [rule(index: 5)], titles: ["Only"]) == [0])
    }

    @Test("More rules than windows leaves the rest unmatched")
    func moreRulesThanWindows() {
        #expect(WindowMatcher.assign(rules: [rule(index: 0), rule(index: 1)], titles: ["Only"]) == [0, nil])
    }

    @Test("Lower indices are served first")
    func lowestIndexFirst() {
        // Only one window: it goes to the index-0 rule even though the index-3 rule comes first.
        #expect(WindowMatcher.assign(rules: [rule(index: 3), rule(index: 0)], titles: ["Only"]) == [nil, 0])
    }

    @Test("Excluded windows are skipped")
    func excluded() {
        #expect(WindowMatcher.assign(rules: [rule(index: 0)], titles: ["Placed", "New"], excluding: [0]) == [1])
    }

    @Test("Positions can differ from array indices")
    func explicitPositions() {
        let windows = [MatchableWindow(title: "A", position: 2), MatchableWindow(title: "B", position: 5)]
        #expect(WindowMatcher.assign(rules: [rule(index: 5), rule(index: 2)], windows: windows) == [1, 0])
    }

    @Test("No windows, no matches")
    func empty() {
        #expect(WindowMatcher.assign(rules: [rule()], titles: []) == [nil])
        #expect(WindowMatcher.assign(rules: [], titles: ["A"]).isEmpty)
    }

    // MARK: - Where the windows are

    func placedRule(index: Int, title: String? = nil, display: String = "D", _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> WindowRule {
        Fixtures.rule("App", index: index, title: title, display: display, x, y, width, height)
    }

    func window(_ title: String, position: Int, display: String = "D", _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> MatchableWindow {
        MatchableWindow(
            title: title,
            position: position,
            location: WindowLocation(
                displayUUID: display,
                relativeFrame: CGRect(x: x / 100, y: y / 100, width: width / 100, height: height / 100)
            )
        )
    }

    @Test("Windows go to the rule whose place they are closest to, whatever their order")
    func closestPlaceWins() {
        // Saved with the left window in front (index 0). Now the right one is in front.
        let rules = [placedRule(index: 0, 0, 0, 50, 100), placedRule(index: 1, 50, 0, 50, 100)]
        let windows = [window("right", position: 0, 52, 2, 48, 96), window("left", position: 1, 3, 4, 45, 90)]
        #expect(WindowMatcher.assign(rules: rules, windows: windows) == [1, 0])
    }

    @Test("Windows that macOS moved to another display keep their arrangement")
    func movedToAnotherDisplay() {
        // Saved on the external display; after it was unplugged both windows sit on the laptop,
        // still left and right.
        let rules = [placedRule(index: 0, display: "EXT", 0, 0, 50, 100), placedRule(index: 1, display: "EXT", 50, 0, 50, 100)]
        let windows = [
            window("right", position: 0, display: "BUILTIN", 45, 10, 55, 80),
            window("left", position: 1, display: "BUILTIN", 0, 10, 55, 80)
        ]
        #expect(WindowMatcher.assign(rules: rules, windows: windows) == [1, 0])
    }

    @Test("A window on the rule's display is preferred")
    func sameDisplayPreferred() {
        let rules = [placedRule(index: 0, display: "D", 0, 0, 50, 50)]
        let windows = [window("elsewhere", position: 0, display: "E", 0, 0, 50, 50), window("here", position: 1, display: "D", 0, 0, 50, 50)]
        #expect(WindowMatcher.assign(rules: rules, windows: windows) == [1])
    }

    @Test("When an earlier window is gone, the others keep their order")
    func earlierWindowGone() {
        // Windows 1 and 2 were saved; window 0 has been closed since, so they are at 0 and 1 now.
        let assignment = WindowMatcher.assign(rules: [rule(index: 1), rule(index: 2)], titles: ["old 1", "old 2"])
        #expect(assignment == [0, 1])
    }

    @Test("Of several windows with the marker, the closest one is taken")
    func closestMarkedWindow() {
        let rules = [placedRule(index: 0, title: "Doc", 50, 0, 50, 100)]
        let windows = [window("Doc A", position: 0, 0, 0, 50, 100), window("Doc B", position: 1, 50, 0, 50, 100)]
        #expect(WindowMatcher.assign(rules: rules, windows: windows) == [1])
    }

    @Test("With the exact-index strategy only the window at the saved position is taken")
    func exactIndex() {
        let rules = [placedRule(index: 1, 0, 0, 50, 100)]
        let windows = [window("closest", position: 0, 0, 0, 50, 100), window("second", position: 1, 50, 0, 50, 100)]
        #expect(WindowMatcher.assign(rules: rules, windows: windows) == [0])
        #expect(WindowMatcher.assign(rules: rules, windows: windows, strategy: .exactIndex) == [1])
        #expect(WindowMatcher.assign(rules: [placedRule(index: 3, 0, 0, 50, 100)], windows: windows, strategy: .exactIndex) == [nil])
    }

    @Test("A window whose place is unknown counts as farther than any known one")
    func unknownPlace() {
        let rule = placedRule(index: 0, 0, 0, 50, 50)
        let far = WindowLocation(displayUUID: "E", relativeFrame: CGRect(x: 0.9, y: 0.9, width: 0.1, height: 0.1))
        #expect(WindowMatcher.distance(from: rule, to: far) < WindowMatcher.distance(from: rule, to: nil))
        #expect(WindowMatcher.distance(from: rule, to: WindowLocation(displayUUID: "D", relativeFrame: rule.relativeFrame)) == 0)
    }
}
