import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import LaneKeepCore

/// The office of the fixtures — monitor A (the 24" on the left), B (the 27" in the middle, the
/// main display) and C (the built-in display on the right) — with every window out of place.
final class Office {
    let system = FakeWindowSystem()
    // Accessibility coordinates: A spans x -1920…0, B x 0…2560, C x 2560…4072.
    let slack = FakeWindow(title: "Slack", frame: CGRect(x: -1800, y: 500, width: 700, height: 500))
    let mail = FakeWindow(title: "メール", frame: CGRect(x: -1700, y: 900, width: 600, height: 400))
    /// On A, yet close to where the Terminal rule of set B puts its window on B.
    let terminalA = FakeWindow(title: "ターミナル A", frame: CGRect(x: -768, y: 1018, width: 672, height: 390))
    let chrome = FakeWindow(title: "Chrome", frame: CGRect(x: 300, y: 300, width: 900, height: 600))
    let vscode = FakeWindow(title: "VS Code", frame: CGRect(x: 1300, y: 400, width: 800, height: 700))
    /// On B, far from where the Terminal rule of set B puts it.
    let terminalB = FakeWindow(title: "ターミナル B", frame: CGRect(x: 100, y: 100, width: 300, height: 200))
    let calendar = FakeWindow(title: "カレンダー", frame: CGRect(x: 2600, y: 600, width: 500, height: 400))

    init() {
        system.addApp("com.example.slack", windows: [slack])
        system.addApp("com.apple.mail", windows: [mail])
        system.addApp("com.apple.Terminal", windows: [terminalA, terminalB])
        system.addApp("com.example.chrome", windows: [chrome])
        system.addApp("com.example.vscode", windows: [vscode])
        system.addApp("com.apple.iCal", windows: [calendar])
    }

    var windows: [FakeWindow] {
        [slack, mail, terminalA, chrome, vscode, terminalB, calendar]
    }

    var windowsOnA: [FakeWindow] {
        [slack, mail, terminalA]
    }

    func frames(of windows: [FakeWindow]) -> [CGRect] {
        windows.map(\.frame)
    }
}

@Suite("Sets that leave the other monitors alone")
struct LeavesOtherDisplaysAloneTests {
    func monitorSet(_ name: String, _ rules: [WindowRule]) -> Workspace {
        Workspace(
            name: name,
            displays: Fixtures.officeDisplays.map(DisplayInfo.init),
            windows: rules,
            autoRestoreOnConnect: false,
            leavesOtherDisplaysAlone: true
        )
    }

    /// The set for monitor A.
    var setA: Workspace {
        monitorSet("A", [
            Fixtures.rule("Slack", display: "OFFICE-24", 3, 3, 94, 48),
            Fixtures.rule("メール", bundleID: "com.apple.mail", display: "OFFICE-24", 3, 53, 94, 44),
            Fixtures.rule("ターミナル", bundleID: "com.apple.Terminal", display: "OFFICE-24", 50, 50, 45, 45)
        ])
    }

    /// The set for monitor B.
    var setB: Workspace {
        monitorSet("B", [
            Fixtures.rule("Chrome", display: "OFFICE-27", 2, 3, 60, 94),
            Fixtures.rule("VS Code", display: "OFFICE-27", 63, 3, 35, 94),
            Fixtures.rule("ターミナル", bundleID: "com.apple.Terminal", display: "OFFICE-27", 63, 60, 35, 37)
        ])
    }

    func restore(
        _ workspace: Workspace,
        on displays: [DisplaySnapshot] = Fixtures.officeDisplays,
        in office: Office
    ) async -> RestoreReport {
        let request = RestoreRequest(workspace: workspace, displays: displays, fallback: .mainDisplay, timing: Fixtures.fastTiming)
        return await RestoreEngine(system: office.system).run(request)
    }

    /// Where a rule puts its window (Accessibility coordinates).
    func frame(for rule: WindowRule) -> CGRect {
        let display = Fixtures.officeDisplays.first { $0.uuid == rule.displayUUID }!
        let visibleArea = CoordinateConverter.accessibilityRect(fromAppKit: display.visibleFrame, primaryHeight: 1440)
        return RelativeGeometry.absoluteFrame(for: rule.relativeFrame, in: visibleArea)
    }

    @Test("Only the windows on the set's monitor are arranged")
    func onlyItsMonitor() async {
        let office = Office()
        let others = [office.chrome, office.vscode, office.terminalB, office.calendar]
        let before = office.frames(of: others)

        let report = await restore(setA, in: office)

        #expect(report.summary == "3件すべて配置しました")
        #expect(office.slack.frame.isClose(to: frame(for: setA.windows[0])))
        #expect(office.mail.frame.isClose(to: frame(for: setA.windows[1])))
        #expect(office.terminalA.frame.isClose(to: frame(for: setA.windows[2])))
        #expect(office.frames(of: others) == before)
    }

    @Test("Arranging B later leaves A alone, even when A's windows have moved since")
    func thenB() async {
        let office = Office()
        _ = await restore(setA, in: office)
        // The user moves things on A a little.
        office.slack.frame.origin.x += 30
        office.terminalA.frame.origin.y -= 20
        let onA = office.frames(of: office.windowsOnA)
        let eventsBefore = office.system.events.count

        let report = await restore(setB, in: office)

        #expect(report.summary == "3件すべて配置しました")
        #expect(office.chrome.frame.isClose(to: frame(for: setB.windows[0])))
        #expect(office.vscode.frame.isClose(to: frame(for: setB.windows[1])))
        // The Terminal window on B, although the one on A is closer to where the rule puts it.
        #expect(office.terminalB.frame.isClose(to: frame(for: setB.windows[2])))
        #expect(office.frames(of: office.windowsOnA) == onA)
        let touchedOnA = office.system.events.dropFirst(eventsBefore).filter { event in
            office.windowsOnA.contains { event.hasSuffix(" \($0.title)") }
        }
        #expect(touchedOnA.isEmpty)
    }

    @Test("Without the setting, a set takes the closest window, even from another monitor")
    func withoutTheSetting() async {
        let office = Office()
        var setA = setA
        var setB = setB
        setA.leavesOtherDisplaysAlone = false
        setB.leavesOtherDisplaysAlone = false
        _ = await restore(setA, in: office)
        let terminalB = office.terminalB.frame

        _ = await restore(setB, in: office)

        // B's Terminal rule pulls the window over from A.
        #expect(office.terminalA.frame.isClose(to: frame(for: setB.windows[2])))
        #expect(office.terminalB.frame == terminalB)
    }

    @Test("A window the set needs that is only on another monitor stays there")
    func neededWindowElsewhere() async {
        let office = Office()
        let notion = FakeWindow(title: "Notion", frame: CGRect(x: 1400, y: 300, width: 800, height: 600))
        office.system.addApp("com.example.notion", windows: [notion])
        var setA = setA
        setA.windows.append(Fixtures.rule("Notion", display: "OFFICE-24", 3, 53, 94, 44))
        let before = notion.frame

        let report = await restore(setA, in: office)

        #expect(notion.frame == before)
        #expect(report.results.last?.outcome == .windowNotFound)
        #expect(report.summary == "3件を配置しました。Notionのウィンドウが見つかりませんでした")
        // The app has a window, so it is not asked to open another one.
        #expect(!office.system.events.contains { $0.hasPrefix("reopen") || $0.hasPrefix("launch") })
    }

    @Test("Rules for a monitor that is not connected are skipped, not moved to another monitor")
    func missingMonitor() async {
        let office = Office()
        let before = office.frames(of: office.windows)

        // Monitor A is unplugged.
        let report = await restore(setA, on: [Fixtures.office27, Fixtures.officeBuiltin], in: office)

        #expect(report.fallback == .skip)
        #expect(report.results.allSatisfy { $0.outcome == .skippedMissingDisplay })
        #expect(report.summary == "配置できたウィンドウはありません。3件は画面がつながっていないので動かしていません")
        #expect(office.frames(of: office.windows) == before)
    }

    @Test("The window of an app it launches is placed, wherever the app opens it")
    func launchedApp() async {
        let office = Office()
        let slackApp = office.system.apps["com.example.slack"]!
        slackApp.isRunning = false
        slackApp.windows = []
        // Slack opens its window on B.
        let slack = FakeWindow(title: "Slack", frame: CGRect(x: 300, y: 300, width: 900, height: 600))
        slackApp.windowsAfterLaunch = [slack]

        let report = await restore(setA, in: office)

        #expect(report.summary == "3件すべて配置しました")
        #expect(slack.frame.isClose(to: frame(for: setA.windows[0])))
    }

    @Test("The list says that windows for a missing monitor stay where they are")
    func missingMonitorNote() {
        #expect(setA.missingDisplayFallback(preferred: .mainDisplay) == .skip)
        var plain = setA
        plain.leavesOtherDisplaysAlone = false
        #expect(plain.missingDisplayFallback(preferred: .largestDisplay) == .largestDisplay)
        let note = DisplayText.missingDisplaysNote(count: 1, fallback: setA.missingDisplayFallback(preferred: .mainDisplay))
        #expect(note == "未接続の画面が1台あります。その画面のウィンドウは動かしません")
    }

    @Test("The setting is saved; older files load with it off")
    func coding() throws {
        let data = try JSONEncoder().encode(setA)
        #expect(try JSONDecoder().decode(Workspace.self, from: data).leavesOtherDisplaysAlone)

        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "leavesOtherDisplaysAlone")
        let older = try JSONSerialization.data(withJSONObject: object)
        #expect(!(try JSONDecoder().decode(Workspace.self, from: older).leavesOtherDisplaysAlone))
    }
}
