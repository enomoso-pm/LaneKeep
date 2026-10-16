import Foundation
import Testing
@testable import LaneKeepCore

@Suite("Restore result line (spec §3.2)")
struct RestoreSummaryTests {
    func report(_ outcomes: [(String, RuleOutcome)], fallback: MissingDisplayFallback = .mainDisplay) -> RestoreReport {
        RestoreReport(
            workspaceID: UUID(),
            fallback: fallback,
            results: outcomes.map { name, outcome in
                RuleResult(rule: Fixtures.rule(name, display: "D", 0, 0, 10, 10), outcome: outcome)
            },
            startedAt: Date(),
            finishedAt: Date()
        )
    }

    let placed = RuleOutcome.placed(frame: .zero, redirected: false)
    let redirected = RuleOutcome.placed(frame: .zero, redirected: true)

    @Test("Everything placed")
    func allPlaced() {
        let names = ["Safari", "VS Code", "ターミナル", "Slack", "ミュージック", "カレンダー"]
        #expect(report(names.map { ($0, placed) }).summary == "6件すべて配置しました")
    }

    @Test("Some windows redirected to the main display")
    func redirectedWindows() {
        let outcomes: [(String, RuleOutcome)] = [
            ("Chrome", placed), ("VS Code", placed), ("Slack", redirected), ("メール", redirected),
            ("Zoom", placed), ("ターミナル", placed), ("Notion", placed), ("カレンダー", placed)
        ]
        #expect(report(outcomes).summary == "8件を配置しました。うち2件はメイン画面に寄せています")
        #expect(report(outcomes, fallback: .largestDisplay).summary == "8件を配置しました。うち2件はいちばん大きい画面に寄せています")
    }

    @Test("An app still launching")
    func launching() {
        let outcomes: [(String, RuleOutcome)] = [("Safari", placed), ("Slack", .stillLaunching), ("メモ", placed), ("ターミナル", placed)]
        #expect(report(outcomes).summary == "3件を配置しました。Slackのウィンドウが見つからなかったので起動しています")
    }

    @Test("Several problems are listed one after another")
    func combined() {
        let outcomes: [(String, RuleOutcome)] = [
            ("Safari", redirected), ("Slack", .stillLaunching), ("メモ", .windowNotFound),
            ("ミュージック", .appNotRunning), ("Zoom", .moveFailed), ("Notion", .skippedMissingDisplay)
        ]
        #expect(report(outcomes).summary == "1件を配置しました。うち1件はメイン画面に寄せています。Slackのウィンドウが見つからなかったので起動しています。メモのウィンドウが見つかりませんでした。ミュージックは起動していないので飛ばしました。Zoomのウィンドウは動かせませんでした。1件は画面がつながっていないので動かしていません")
    }

    @Test("Nothing could be placed")
    func nothingPlaced() {
        #expect(report([("Slack", .windowNotFound)]).summary == "配置できたウィンドウはありません。Slackのウィンドウが見つかりませんでした")
    }

    @Test("Long app lists are shortened and deduplicated")
    func appList() {
        #expect(RestoreSummary.list(["A"]) == "A")
        #expect(RestoreSummary.list(["A", "B"]) == "A、B")
        #expect(RestoreSummary.list(["A", "B", "A", "C", "D"]) == "A、Bほか2件")
    }

    @Test("Cancelled restores say so")
    func cancelled() {
        #expect(report([("Safari", placed), ("Slack", .cancelled)]).summary == "1件を配置しました。途中で中止しました")
    }
}
