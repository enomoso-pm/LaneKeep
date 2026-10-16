import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import LaneKeepCore

@Suite("Saving the current layout (spec §3.1)")
struct CaptureBuilderTests {
    let displays = Fixtures.homeDisplays
    // Accessibility coordinates. The external display spans x 0…2560, y 0…1440 (visible 25…1440);
    // the built-in one x -1512…0, y 458…1440 (visible 491…1440).
    func window(
        _ app: String,
        pid: Int32 = 1,
        index: Int = 0,
        title: String = "",
        _ frame: CGRect,
        minimized: Bool = false,
        fullScreen: Bool = false
    ) -> WindowSnapshot {
        WindowSnapshot(
            pid: pid,
            bundleID: "com.example.\(app.lowercased())",
            appName: app,
            title: title,
            frame: frame,
            indexInApp: index,
            isMinimized: minimized,
            isFullScreen: fullScreen
        )
    }

    @Test("Windows are assigned to displays and get relative frames")
    func assignsDisplays() {
        let candidates = CaptureBuilder.candidates(
            from: [
                window("Safari", CGRect(x: 51, y: 67, width: 1229, height: 1330)),
                window("Slack", pid: 2, CGRect(x: -1467, y: 529, width: 1421, height: 531))
            ],
            displays: displays
        )
        #expect(candidates.map(\.displayUUID) == ["EXT-27", "BUILTIN"])
        let safari = candidates[0].relativeFrame
        #expect(safari.isClose(to: CGRect(x: 51.0 / 2560, y: 42.0 / 1415, width: 1229.0 / 2560, height: 1330.0 / 1415), tolerance: 0.00001))
        let slack = candidates[1].relativeFrame
        #expect(slack.isClose(to: CGRect(x: 45.0 / 1512, y: 38.0 / 949, width: 1421.0 / 1512, height: 531.0 / 949), tolerance: 0.00001))
    }

    @Test("A window hanging off its display is recorded inside it (0…1)")
    func fitsIntoDisplay() throws {
        // Safari reaches 340 pt past the right edge of the external display; its center is still on it.
        let candidates = CaptureBuilder.candidates(
            from: [window("Safari", CGRect(x: 2300, y: 100, width: 600, height: 800))],
            displays: displays
        )
        let frame = try #require(candidates.first?.relativeFrame)
        #expect(frame.maxX == 1)
        #expect(frame.isClose(to: CGRect(x: 1 - 600.0 / 2560, y: 75.0 / 1415, width: 600.0 / 2560, height: 800.0 / 1415), tolerance: 0.00001))
    }

    @Test("Relative frames are moved and shrunk into 0…1")
    func fittedToUnit() {
        #expect(RelativeGeometry.fittedToUnit(CGRect(x: 0.9, y: -0.1, width: 0.25, height: 0.5)) == CGRect(x: 0.75, y: 0, width: 0.25, height: 0.5))
        #expect(RelativeGeometry.fittedToUnit(CGRect(x: -0.2, y: 0.3, width: 1.4, height: 0.2)) == CGRect(x: 0, y: 0.3, width: 1, height: 0.2))
        let inside = CGRect(x: 0.02, y: 0.03, width: 0.48, height: 0.94)
        #expect(RelativeGeometry.fittedToUnit(inside) == inside)
    }

    @Test("Minimized, full-screen, tiny, off-screen and excluded windows are left out")
    func filters() {
        let candidates = CaptureBuilder.candidates(
            from: [
                window("Minimized", CGRect(x: 100, y: 100, width: 500, height: 500), minimized: true),
                window("FullScreen", CGRect(x: 0, y: 0, width: 2560, height: 1440), fullScreen: true),
                window("Tiny", CGRect(x: 100, y: 100, width: 20, height: 20)),
                window("Offscreen", CGRect(x: 9000, y: 9000, width: 500, height: 500)),
                window("Excluded", CGRect(x: 100, y: 100, width: 500, height: 500)),
                window("Kept", CGRect(x: 100, y: 100, width: 500, height: 500))
            ],
            displays: displays,
            excludedBundleIDs: ["com.example.excluded"]
        )
        #expect(candidates.map(\.window.appName) == ["Kept"])
    }

    @Test("Sorted by display (blue first), then in reading order")
    func ordering() {
        let candidates = CaptureBuilder.candidates(
            from: [
                window("Calendar", pid: 6, CGRect(x: -740, y: 1090, width: 695, height: 313)),
                window("Terminal", pid: 3, CGRect(x: 1306, y: 973, width: 1203, height: 424)),
                window("Music", pid: 5, CGRect(x: -1467, y: 1090, width: 695, height: 313)),
                window("Slack", pid: 4, CGRect(x: -1467, y: 529, width: 1421, height: 531)),
                window("VSCode", pid: 2, CGRect(x: 1306, y: 67, width: 1203, height: 877)),
                window("Safari", pid: 1, CGRect(x: 51, y: 67, width: 1229, height: 1330))
            ],
            displays: displays
        )
        #expect(candidates.map(\.window.appName) == ["Safari", "VSCode", "Terminal", "Slack", "Music", "Calendar"])
    }

    @Test("Rules keep the window's position within its app")
    func rulesKeepIndex() {
        let candidates = CaptureBuilder.candidates(
            from: [window("Terminal", index: 1, CGRect(x: 100, y: 100, width: 500, height: 500))],
            displays: displays
        )
        let rules = CaptureBuilder.rules(from: candidates, launchIfClosed: false)
        #expect(rules.count == 1)
        #expect(rules[0].index == 1)
        #expect(rules[0].launchIfClosed == false)
        #expect(rules[0].titleContains == nil)
        #expect(rules[0].displayUUID == "EXT-27")
    }

    @Test("A new workspace records the current displays")
    func workspace() {
        let candidates = CaptureBuilder.candidates(
            from: [window("Safari", CGRect(x: 51, y: 67, width: 1229, height: 1330))],
            displays: displays
        )
        let now = Date(timeIntervalSince1970: 1_000)
        let workspace = CaptureBuilder.workspace(
            name: "  自宅デスク ",
            color: .green,
            icon: .home,
            candidates: candidates,
            displays: displays,
            launchIfClosed: true,
            autoRestoreOnConnect: true,
            now: now
        )
        #expect(workspace.name == "自宅デスク")
        #expect(workspace.displaySignature == "BUILTIN|EXT-27")
        #expect(workspace.displays.map(\.uuid) == ["EXT-27", "BUILTIN"])
        #expect(workspace.displays[0].visibleFrame == Fixtures.external27.visibleFrame)
        #expect(workspace.windows.count == 1)
        #expect(workspace.autoRestoreOnConnect)
        #expect(!workspace.autoRestoreOnWake)
        #expect(workspace.lastUsedAt == now)
    }

    @Test("Overwriting keeps title markers and launch options of matching rules")
    func overwriteKeepsRuleOptions() {
        let previous = [
            Fixtures.rule("VSCode", bundleID: "com.example.vscode", index: 0, title: "lanekeep", display: "EXT-27", 0, 0, 50, 50, launch: false),
            Fixtures.rule("Safari", bundleID: "com.example.safari", index: 0, display: "EXT-27", 0, 0, 50, 50, launch: false)
        ]
        let candidates = CaptureBuilder.candidates(
            from: [
                window("VSCode", index: 0, title: "notes — other", CGRect(x: 100, y: 100, width: 500, height: 500)),
                window("VSCode", index: 1, title: "main.swift — lanekeep", CGRect(x: 700, y: 100, width: 500, height: 500)),
                window("Notes", pid: 3, CGRect(x: 100, y: 700, width: 500, height: 500))
            ],
            displays: displays
        )
        let rules = CaptureBuilder.rules(from: candidates, replacing: previous, launchIfClosedForNewWindows: true)
        let lanekeep = rules.first { $0.index == 1 && $0.bundleID == "com.example.vscode" }
        #expect(lanekeep?.titleContains == "lanekeep")
        #expect(lanekeep?.launchIfClosed == false)
        #expect(lanekeep?.id == previous[0].id)
        let other = rules.first { $0.index == 0 && $0.bundleID == "com.example.vscode" }
        #expect(other?.titleContains == nil)
        #expect(other?.launchIfClosed == true)
        #expect(rules.first { $0.bundleID == "com.example.notes" }?.launchIfClosed == true)
    }

    @Test("Suggested names")
    func suggestedNames() {
        #expect(CaptureBuilder.suggestedName(for: [Fixtures.builtinAlone], existingNames: []) == "ノートPCのみ")
        #expect(CaptureBuilder.suggestedName(for: [Fixtures.builtinAlone], existingNames: ["ノートPCのみ"]) == "ワークスペース2")
        #expect(CaptureBuilder.suggestedName(for: displays, existingNames: ["A", "B"]) == "ワークスペース3")
        #expect(CaptureBuilder.suggestedName(for: displays, existingNames: ["ワークスペース1"]) == "ワークスペース2")
    }

    @Test("Suggested icon and color")
    func suggestions() {
        #expect(CaptureBuilder.suggestedIcon(for: [Fixtures.builtinAlone]) == .laptop)
        #expect(CaptureBuilder.suggestedIcon(for: displays) == .display)
        #expect(CaptureBuilder.suggestedColor(existing: []) == .blue)
        #expect(CaptureBuilder.suggestedColor(existing: [.blue, .orange]) == .green)
        #expect(CaptureBuilder.suggestedColor(existing: WorkspaceColor.allCases) == .blue)
    }

    @Test("No displays, no candidates")
    func noDisplays() {
        let candidates = CaptureBuilder.candidates(
            from: [window("Safari", CGRect(x: 0, y: 0, width: 500, height: 500))],
            displays: []
        )
        #expect(candidates.isEmpty)
    }
}
