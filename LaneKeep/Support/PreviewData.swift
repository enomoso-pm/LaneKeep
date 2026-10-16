#if DEBUG
import CoreGraphics
import Foundation
import LaneKeepCore

/// The sample data of the UI mock, for SwiftUI previews and UI snapshots. Debug builds only.
@MainActor
enum PreviewData {
    /// Shortcut labels shown instead of the real (UserDefaults-backed) shortcuts.
    static var shortcutTexts: [UUID: String] = [:]
    static var menuShortcutText: String?

    // Home: an external 27" display with the menu bar, the MacBook's display to its lower left.
    static let external27 = DisplaySnapshot(
        uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230",
        name: "外部 27インチ",
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415),
        isMain: true
    )

    static let builtin = DisplaySnapshot(
        uuid: "6AF54D6B-9C20-4C3A-8A11-6F2E9D6B1E01",
        name: "内蔵ディスプレイ",
        frame: CGRect(x: -1512, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: -1512, y: 0, width: 1512, height: 949),
        isMain: false,
        isBuiltin: true
    )

    static let office24 = DisplaySnapshot(
        uuid: "A1B2C3D4-0024-4F00-9000-24242424A024",
        name: "左 24インチ",
        frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055),
        isMain: false
    )

    static var homeDisplays: [DisplaySnapshot] {
        [external27, builtin]
    }

    static var workspaces: [Workspace] {
        [home, office, laptop]
    }

    static let home = Workspace(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
        name: "自宅デスク",
        color: .blue,
        icon: .home,
        shortcut: "preview.home",
        displays: [DisplayInfo(external27), DisplayInfo(builtin)],
        windows: [
            rule("Safari", "com.apple.Safari", on: external27, 2, 3, 48, 94),
            rule("VS Code", "com.microsoft.VSCode", title: "lanekeep", on: external27, 51, 3, 47, 62),
            rule("ターミナル", "com.apple.Terminal", on: external27, 51, 67, 47, 30),
            rule("Slack", "com.tinyspeck.slackmacgap", on: builtin, 3, 4, 94, 56),
            rule("ミュージック", "com.apple.Music", on: builtin, 3, 63, 46, 33, launch: false),
            rule("カレンダー", "com.apple.iCal", on: builtin, 51, 63, 46, 33)
        ]
    )

    static var office: Workspace {
        let center = DisplaySnapshot(
            uuid: external27.uuid,
            name: "中央 27インチ",
            frame: external27.frame,
            visibleFrame: external27.visibleFrame,
            isMain: true
        )
        let officeBuiltin = DisplaySnapshot(
            uuid: builtin.uuid,
            name: "内蔵ディスプレイ",
            frame: CGRect(x: 2560, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 2560, y: 0, width: 1512, height: 949),
            isMain: false,
            isBuiltin: true
        )
        return Workspace(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000002")!,
            name: "オフィス",
            color: .orange,
            icon: .office,
            shortcut: "preview.office",
            displays: [DisplayInfo(office24), DisplayInfo(center), DisplayInfo(officeBuiltin)],
            windows: [
                rule("Chrome", "com.google.Chrome", on: center, 2, 3, 60, 94),
                rule("VS Code", "com.microsoft.VSCode", on: center, 63, 3, 35, 94),
                rule("Slack", "com.tinyspeck.slackmacgap", on: office24, 3, 3, 94, 48),
                rule("メール", "com.apple.mail", on: office24, 3, 53, 94, 44),
                rule("Zoom", "us.zoom.xos", on: officeBuiltin, 4, 4, 92, 92, launch: false),
                rule("ターミナル", "com.apple.Terminal", on: center, 63, 60, 35, 37),
                rule("Notion", "notion.id", on: office24, 3, 53, 94, 44),
                rule("カレンダー", "com.apple.iCal", on: officeBuiltin, 4, 4, 92, 92)
            ]
        )
    }

    static var laptop: Workspace {
        let alone = DisplaySnapshot(
            uuid: builtin.uuid,
            name: "内蔵ディスプレイ",
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
            isMain: true,
            isBuiltin: true
        )
        return Workspace(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000003")!,
            name: "ノートPCのみ",
            color: .gray,
            icon: .laptop,
            shortcut: "preview.laptop",
            displays: [DisplayInfo(alone)],
            windows: [
                rule("Safari", "com.apple.Safari", on: alone, 2, 3, 64, 94),
                rule("Slack", "com.tinyspeck.slackmacgap", on: alone, 67, 3, 31, 46),
                rule("メモ", "com.apple.Notes", on: alone, 67, 51, 31, 46),
                rule("ターミナル", "com.apple.Terminal", on: alone, 67, 51, 31, 46)
            ]
        )
    }

    /// The windows of the home workspace as if they were on screen right now.
    static var homeWindows: [WindowSnapshot] {
        let primaryHeight = external27.frame.height
        return home.windows.enumerated().compactMap { offset, rule in
            guard let display = homeDisplays.first(where: { $0.uuid == rule.displayUUID }) else { return nil }
            let bounds = CoordinateConverter.accessibilityRect(fromAppKit: display.visibleFrame, primaryHeight: primaryHeight)
            return WindowSnapshot(
                pid: Int32(500 + offset),
                bundleID: rule.bundleID,
                appName: rule.appName,
                title: rule.titleContains.map { "README.md — \($0)" } ?? "\(rule.appName)",
                frame: RelativeGeometry.absoluteFrame(for: rule.relativeFrame, in: bounds),
                indexInApp: 0
            )
        }
    }

    static func installShortcutTexts() {
        shortcutTexts = [home.id: "⌃⌥1", office.id: "⌃⌥2", laptop.id: "⌃⌥3"]
        menuShortcutText = "⌃⌥L"
    }

    private static func rule(
        _ appName: String,
        _ bundleID: String,
        title: String? = nil,
        on display: DisplaySnapshot,
        _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat,
        launch: Bool = true
    ) -> WindowRule {
        WindowRule(
            bundleID: bundleID,
            appName: appName,
            titleContains: title,
            index: 0,
            displayUUID: display.uuid,
            relativeFrame: CGRect(x: x / 100, y: y / 100, width: width / 100, height: height / 100),
            launchIfClosed: launch
        )
    }
}
#endif
