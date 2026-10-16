import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Wording shared by the menu bar popover, the settings window and the command-line tool.
public enum DisplayText {
    /// 「外部 27インチ ＋ 内蔵ディスプレイ」 (displays in role order).
    public static func displayNames<Display: DisplayDescribing>(_ displays: [Display]) -> String {
        DisplayRoles.ordered(displays).map(\.name).joined(separator: " ＋ ")
    }

    /// 「2画面、6アプリ」; when an app has several windows: 「2画面、5アプリ・6ウィンドウ」.
    public static func workspaceMeta(_ workspace: Workspace) -> String {
        let displayCount = workspace.displays.count
        let apps = workspace.appCount
        let windows = workspace.windows.count
        if apps == windows {
            return "\(displayCount)画面、\(apps)アプリ"
        }
        return "\(displayCount)画面、\(apps)アプリ・\(windows)ウィンドウ"
    }

    /// The "ウィンドウの目印" column: 「タイトルに「lanekeep」」, 「最初のウィンドウ」, 「2番目のウィンドウ」…
    public static func marker(for rule: WindowRule) -> String {
        if let marker = rule.titleMarker {
            return "タイトルに「\(marker)」"
        }
        return rule.index == 0 ? "最初のウィンドウ" : "\(rule.index + 1)番目のウィンドウ"
    }

    /// 「左2% 上3%、幅48% 高さ94%」
    public static func relativeFrame(_ rect: CGRect) -> String {
        "左\(percent(rect.minX)) 上\(percent(rect.minY))、幅\(percent(rect.width)) 高さ\(percent(rect.height))"
    }

    /// 「起動する」/「何もしない」
    public static func launchOption(_ launchIfClosed: Bool) -> String {
        launchIfClosed ? "起動する" : "何もしない"
    }

    /// The warning shown before restoring when displays are missing (spec §3.4).
    public static func missingDisplaysNote(count: Int, fallback: MissingDisplayFallback) -> String {
        if let destination = fallback.destinationName {
            return "未接続の画面が\(count)台あります。その分は\(destination)に寄せて配置します"
        }
        return "未接続の画面が\(count)台あります。その画面のウィンドウは動かしません"
    }

    static func percent(_ value: CGFloat) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
