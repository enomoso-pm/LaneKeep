import Foundation
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
}
