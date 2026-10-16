import Foundation

/// Turns a restore report into the single line shown on the workspace card (spec §3.2), e.g.
///
/// - 「6件すべて配置しました」
/// - 「8件を配置しました。うち2件はメイン画面に寄せています」
/// - 「3件を配置しました。Slackのウィンドウが見つからなかったので起動しています」
public enum RestoreSummary {
    public static func text(for report: RestoreReport) -> String {
        let results = report.results
        guard !results.isEmpty else {
            return "このワークスペースには配置するウィンドウがありません"
        }
        let placed = report.placedCount
        let redirected = report.redirectedCount
        if placed == results.count, redirected == 0 {
            return "\(placed)件すべて配置しました"
        }

        var sentences: [String] = []
        sentences.append(placed > 0 ? "\(placed)件を配置しました" : "配置できたウィンドウはありません")
        if redirected > 0, let destination = report.fallback.destinationName {
            sentences.append("うち\(redirected)件は\(destination)に寄せています")
        }

        func appNames(_ outcome: (RuleOutcome) -> Bool) -> [String] {
            results.filter { outcome($0.outcome) }.map(\.rule.appName)
        }

        let launching = appNames { $0 == .stillLaunching }
        if !launching.isEmpty {
            sentences.append("\(list(launching))のウィンドウが見つからなかったので起動しています")
        }
        let notFound = appNames { $0 == .windowNotFound }
        if !notFound.isEmpty {
            sentences.append("\(list(notFound))のウィンドウが見つかりませんでした")
        }
        let notRunning = appNames { $0 == .appNotRunning }
        if !notRunning.isEmpty {
            sentences.append("\(list(notRunning))は起動していないので飛ばしました")
        }
        let notInstalled = appNames { $0 == .appNotInstalled }
        if !notInstalled.isEmpty {
            sentences.append("\(list(notInstalled))はインストールされていません")
        }
        let failed = appNames { $0 == .moveFailed }
        if !failed.isEmpty {
            sentences.append("\(list(failed))のウィンドウは動かせませんでした")
        }
        let skipped = results.filter { $0.outcome == .skippedMissingDisplay }.count
        if skipped > 0 {
            sentences.append("\(skipped)件は画面がつながっていないので動かしていません")
        }
        if results.contains(where: { $0.outcome == .cancelled }) {
            sentences.append("途中で中止しました")
        }
        return sentences.joined(separator: "。")
    }

    /// 「Slack」「Slack、メモ」「Slack、メモほか2件」
    static func list(_ names: [String]) -> String {
        var seen = Set<String>()
        let unique = names.filter { seen.insert($0).inserted }
        if unique.count <= 2 {
            return unique.joined(separator: "、")
        }
        return unique.prefix(2).joined(separator: "、") + "ほか\(unique.count - 2)件"
    }
}
