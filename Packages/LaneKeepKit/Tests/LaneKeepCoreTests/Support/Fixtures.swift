import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
@testable import LaneKeepCore

/// Display configurations from the UI mock.
enum Fixtures {
    // An external 27" display with the menu bar, a MacBook's built-in display to its lower left.
    static let external27 = DisplaySnapshot(
        uuid: "EXT-27",
        name: "外部 27インチ",
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415),
        isMain: true
    )

    static let builtin = DisplaySnapshot(
        uuid: "BUILTIN",
        name: "内蔵ディスプレイ",
        frame: CGRect(x: -1512, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: -1512, y: 0, width: 1512, height: 949),
        isMain: false,
        isBuiltin: true
    )

    /// The built-in display on its own (it is then the main display).
    static let builtinAlone = DisplaySnapshot(
        uuid: "BUILTIN",
        name: "内蔵ディスプレイ",
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
        isMain: true,
        isBuiltin: true
    )

    // Office: a 24" display on the left, a 27" in the middle (main), the built-in on the right.
    static let office24 = DisplaySnapshot(
        uuid: "OFFICE-24",
        name: "左 24インチ",
        frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
        visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055),
        isMain: false
    )

    static let office27 = DisplaySnapshot(
        uuid: "OFFICE-27",
        name: "中央 27インチ",
        frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 0, y: 70, width: 2560, height: 1345),
        isMain: true
    )

    static let officeBuiltin = DisplaySnapshot(
        uuid: "BUILTIN",
        name: "内蔵ディスプレイ",
        frame: CGRect(x: 2560, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 2560, y: 0, width: 1512, height: 949),
        isMain: false,
        isBuiltin: true
    )

    static let homeDisplays = [external27, builtin]

    /// `homeDisplays` once the Dock has moved to the built-in display: the same displays in the
    /// same places, with less room at the bottom of the built-in one.
    static var homeDisplaysWithDockOnBuiltin: [DisplaySnapshot] {
        var builtin = builtin
        builtin.visibleFrame.origin.y += 60
        builtin.visibleFrame.size.height -= 60
        return [external27, builtin]
    }
    static let officeDisplays = [office24, office27, officeBuiltin]

    static func rule(
        _ appName: String,
        bundleID: String? = nil,
        index: Int = 0,
        title: String? = nil,
        display: String,
        _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat,
        launch: Bool = true
    ) -> WindowRule {
        WindowRule(
            bundleID: bundleID ?? "com.example.\(appName.lowercased().replacingOccurrences(of: " ", with: ""))",
            appName: appName,
            titleContains: title,
            index: index,
            displayUUID: display,
            relativeFrame: CGRect(x: x / 100, y: y / 100, width: width / 100, height: height / 100),
            launchIfClosed: launch
        )
    }

    static var homeWorkspace: Workspace {
        Workspace(
            name: "自宅デスク",
            color: .blue,
            icon: .home,
            displays: homeDisplays.map(DisplayInfo.init),
            windows: [
                rule("Safari", display: "EXT-27", 2, 3, 48, 94),
                rule("VS Code", title: "lanekeep", display: "EXT-27", 51, 3, 47, 62),
                rule("ターミナル", bundleID: "com.apple.Terminal", display: "EXT-27", 51, 67, 47, 30),
                rule("Slack", display: "BUILTIN", 3, 4, 94, 56),
                rule("ミュージック", bundleID: "com.apple.Music", display: "BUILTIN", 3, 63, 46, 33, launch: false),
                rule("カレンダー", bundleID: "com.apple.iCal", display: "BUILTIN", 51, 63, 46, 33)
            ]
        )
    }

    static var officeWorkspace: Workspace {
        Workspace(
            name: "オフィス",
            color: .orange,
            icon: .office,
            displays: officeDisplays.map(DisplayInfo.init),
            windows: [
                rule("Chrome", display: "OFFICE-27", 2, 3, 60, 94),
                rule("VS Code", display: "OFFICE-27", 63, 3, 35, 94),
                rule("Slack", display: "OFFICE-24", 3, 3, 94, 48),
                rule("メール", bundleID: "com.apple.mail", display: "OFFICE-24", 3, 53, 94, 44),
                rule("Zoom", display: "BUILTIN", 4, 4, 92, 92, launch: false),
                rule("ターミナル", bundleID: "com.apple.Terminal", display: "OFFICE-27", 63, 60, 35, 37),
                rule("Notion", display: "BUILTIN", 3, 53, 94, 44),
                rule("カレンダー", bundleID: "com.apple.iCal", display: "BUILTIN", 4, 4, 92, 92)
            ]
        )
    }

    static var laptopWorkspace: Workspace {
        Workspace(
            name: "ノートPCのみ",
            color: .gray,
            icon: .laptop,
            displays: [DisplayInfo(builtinAlone)],
            windows: [
                rule("Safari", display: "BUILTIN", 2, 3, 64, 94),
                rule("Slack", display: "BUILTIN", 67, 3, 31, 46),
                rule("メモ", bundleID: "com.apple.Notes", display: "BUILTIN", 67, 51, 31, 46),
                rule("ターミナル", bundleID: "com.apple.Terminal", display: "BUILTIN", 67, 51, 31, 46)
            ]
        )
    }

    /// Timing that keeps the engine tests fast.
    static let fastTiming = RestoreTiming(
        windowWaitTimeout: .milliseconds(250),
        pollInterval: .milliseconds(5),
        unminimizeTimeout: .milliseconds(30),
        unminimizeSettleDelay: .zero,
        retryDelay: .zero
    )
}

/// Ways the displays change after a restore on `Fixtures.homeDisplays` (the 27" monitor and the
/// built-in display).
enum DisplayChange: String, CaseIterable, Sendable {
    /// The monitor was unplugged.
    case unplugged
    /// The lid was closed while the monitor stays connected. The signature stays the same.
    case lidClosed
    /// The monitor got another resolution.
    case resolutionChanged

    var displays: [DisplaySnapshot] {
        switch self {
        case .unplugged:
            return [Fixtures.builtinAlone]
        case .lidClosed:
            return [Fixtures.external27]
        case .resolutionChanged:
            var external = Fixtures.external27
            external.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
            external.visibleFrame = CGRect(x: 0, y: 0, width: 1920, height: 1055)
            return [external, Fixtures.builtin]
        }
    }
}

extension CGRect {
    /// Approximate equality for geometry assertions.
    func isClose(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
