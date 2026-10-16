import Foundation
import Testing
@testable import LaneKeepCore

@Suite("Restoring a workspace (spec §6.4)")
struct RestoreEngineTests {
    func restore(
        _ workspace: Workspace,
        on displays: [DisplaySnapshot],
        fallback: MissingDisplayFallback = .mainDisplay,
        system: FakeWindowSystem,
        progress: @escaping (RestoreProgress) async -> Void = { _ in }
    ) async -> RestoreReport {
        let request = RestoreRequest(workspace: workspace, displays: displays, fallback: fallback, timing: Fixtures.fastTiming)
        return await RestoreEngine(system: system).run(request, progress: progress)
    }

    /// The frame (Accessibility coordinates) a rule should end up at on `display`.
    func expectedFrame(_ rule: WindowRule, on display: DisplaySnapshot, primaryHeight: CGFloat) -> CGRect {
        let bounds = CoordinateConverter.accessibilityRect(fromAppKit: display.visibleFrame, primaryHeight: primaryHeight)
        return RelativeGeometry.absoluteFrame(for: rule.relativeFrame, in: bounds)
    }

    @Test("Every window goes back to its saved place")
    func allPlaced() async {
        let workspace = Fixtures.homeWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)

        let report = await restore(workspace, on: Fixtures.homeDisplays, system: system)

        #expect(report.summary == "6件すべて配置しました")
        for (result, rule) in zip(report.results, workspace.windows) {
            let display = Fixtures.homeDisplays.first { $0.uuid == rule.displayUUID }!
            let expected = expectedFrame(rule, on: display, primaryHeight: 1440)
            #expect(result.outcome == .placed(frame: expected, redirected: false))
            #expect(system.apps[rule.bundleID]?.windows.first?.frame == expected)
        }
    }

    @Test("Windows of a missing display go to the main display (spec §3.4)")
    func missingDisplayGoesToMain() async {
        let workspace = Fixtures.officeWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let connected = [Fixtures.office27, Fixtures.officeBuiltin]

        let report = await restore(workspace, on: connected, system: system)

        #expect(report.summary == "8件を配置しました。うち2件はメイン画面に寄せています")
        let slackRule = workspace.windows[2]
        let slackFrame = system.apps[slackRule.bundleID]?.windows.first?.frame
        // The relative frame is applied to the main display as it is.
        #expect(slackFrame == expectedFrame(slackRule, on: Fixtures.office27, primaryHeight: 1440))
    }

    @Test("The largest display can be the fallback")
    func largestFallback() async {
        let workspace = Fixtures.homeWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let big = DisplaySnapshot(
            uuid: "BIG", name: "Big",
            frame: CGRect(x: 1512, y: 0, width: 3840, height: 2160),
            visibleFrame: CGRect(x: 1512, y: 0, width: 3840, height: 2135),
            isMain: false
        )
        let connected = [Fixtures.builtinAlone, big]

        let report = await restore(workspace, on: connected, fallback: .largestDisplay, system: system)

        #expect(report.redirectedCount == 3)
        let safari = workspace.windows[0]
        #expect(system.apps[safari.bundleID]?.windows.first?.frame == expectedFrame(safari, on: big, primaryHeight: 982))
        #expect(report.summary == "6件を配置しました。うち3件はいちばん大きい画面に寄せています")
    }

    @Test("With the 'leave them' fallback, windows of missing displays are not touched")
    func skipFallback() async {
        let workspace = Fixtures.officeWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)

        let report = await restore(workspace, on: [Fixtures.office27, Fixtures.officeBuiltin], fallback: .skip, system: system)

        #expect(report.results[2].outcome == .skippedMissingDisplay)
        #expect(report.results[3].outcome == .skippedMissingDisplay)
        #expect(report.summary == "6件を配置しました。2件は画面がつながっていないので動かしていません")
        #expect(!system.events.contains("setFrame Slack 1 "))
    }

    @Test("A closed app is launched and its window placed once it appears")
    func launchesClosedApp() async {
        let workspace = Fixtures.laptopWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let slack = workspace.windows[1]
        let app = system.apps[slack.bundleID]!
        app.isRunning = false
        app.windowsAfterLaunch = app.windows
        app.windows = []
        app.lookupsBeforeWindowsAppear = 3

        let report = await restore(workspace, on: [Fixtures.builtinAlone], system: system)

        #expect(system.events.contains("launch \(slack.bundleID)"))
        #expect(report.results[1].outcome.isPlaced)
        #expect(report.summary == "4件すべて配置しました")
    }

    @Test("A launched app whose window does not show up in time is reported as launching")
    func launchTimeout() async {
        let workspace = Fixtures.laptopWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let slack = workspace.windows[1]
        system.apps[slack.bundleID]!.isRunning = false
        system.apps[slack.bundleID]!.windows = []

        let report = await restore(workspace, on: [Fixtures.builtinAlone], system: system)

        #expect(report.results[1].outcome == .stillLaunching)
        #expect(report.summary == "3件を配置しました。Slackのウィンドウが見つからなかったので起動しています")
    }

    @Test("Apps that should not be launched are skipped")
    func doesNotLaunch() async {
        let workspace = Fixtures.homeWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let music = workspace.windows[4]
        system.apps[music.bundleID]!.isRunning = false

        let report = await restore(workspace, on: Fixtures.homeDisplays, system: system)

        #expect(!system.events.contains("launch \(music.bundleID)"))
        #expect(report.results[4].outcome == .appNotRunning)
        #expect(report.summary == "5件を配置しました。ミュージックは起動していないので飛ばしました")
    }

    @Test("Apps that are not installed are reported")
    func notInstalled() async {
        let workspace = Fixtures.laptopWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let notes = workspace.windows[2]
        system.apps[notes.bundleID]!.isRunning = false
        system.apps[notes.bundleID]!.isInstalled = false

        let report = await restore(workspace, on: [Fixtures.builtinAlone], system: system)

        #expect(report.results[2].outcome == .appNotInstalled)
        #expect(report.summary == "3件を配置しました。メモはインストールされていません")
    }

    @Test("Minimized windows are restored before they are moved (step 3)")
    func unminimizes() async {
        let workspace = Fixtures.laptopWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let window = system.apps[workspace.windows[0].bundleID]!.windows[0]
        window.isMinimized = true

        let report = await restore(workspace, on: [Fixtures.builtinAlone], system: system)

        #expect(!window.isMinimized)
        #expect(report.results[0].outcome.isPlaced)
        let unminimize = system.events.firstIndex(of: "unminimize \(window.title)")
        let move = system.events.firstIndex(of: "setFrame \(window.title)")
        #expect(unminimize != nil && move != nil && unminimize! < move!)
    }

    @Test("When an app enforces a larger size, the window is kept inside the screen (§6.6)")
    func keepsEnlargedWindowOnScreen() async {
        var workspace = Fixtures.laptopWorkspace
        workspace.windows = [Fixtures.rule("Slack", display: "BUILTIN", 80, 50, 20, 50)]
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let window = system.apps[workspace.windows[0].bundleID]!.windows[0]
        window.minimumSize = CGSize(width: 600, height: 400)

        let report = await restore(workspace, on: [Fixtures.builtinAlone], system: system)

        // Visible area in Accessibility coordinates: x 0…1512, y 33…982.
        #expect(window.frame.size == CGSize(width: 600, height: 474))
        #expect(window.frame.maxX == 1512)
        #expect(window.frame.minY == 508)
        #expect(report.results[0].outcome == .placed(frame: window.frame, redirected: false))
    }

    @Test("Windows that cannot be resized are only moved")
    func fixedSizeWindow() async {
        var workspace = Fixtures.laptopWorkspace
        workspace.windows = [Fixtures.rule("Calculator", display: "BUILTIN", 10, 10, 50, 50)]
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let window = system.apps[workspace.windows[0].bundleID]!.windows[0]
        window.isResizable = false
        window.frame = CGRect(x: 900, y: 700, width: 230, height: 400)

        let report = await restore(workspace, on: [Fixtures.builtinAlone], system: system)

        #expect(window.frame.size == CGSize(width: 230, height: 400))
        #expect(window.frame.origin == CGPoint(x: 151, y: 128))
        #expect(report.results[0].outcome.isPlaced)
    }

    @Test("A window that does not end up where asked is moved once more")
    func retriesMove() async {
        var workspace = Fixtures.laptopWorkspace
        workspace.windows = [Fixtures.rule("Slack", display: "BUILTIN", 80, 50, 20, 50)]
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let window = system.apps[workspace.windows[0].bundleID]!.windows[0]
        window.minimumSize = CGSize(width: 600, height: 400)
        window.ignoredMoves = 1

        _ = await restore(workspace, on: [Fixtures.builtinAlone], system: system)

        #expect(window.frame.maxX == 1512)
        #expect(system.events.filter { $0.hasPrefix("setOrigin") }.count == 2)
    }

    @Test("Windows that refuse to move are reported")
    func moveFailed() async {
        let workspace = Fixtures.laptopWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        system.apps[workspace.windows[3].bundleID]!.windows[0].isMovable = false

        let report = await restore(workspace, on: [Fixtures.builtinAlone], system: system)

        #expect(report.results[3].outcome == .moveFailed)
        #expect(report.summary == "3件を配置しました。ターミナルのウィンドウは動かせませんでした")
    }

    @Test("A running app without windows is asked to open one")
    func reopensWindowlessApp() async {
        let workspace = Fixtures.laptopWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let notes = system.apps[workspace.windows[2].bundleID]!
        notes.windowsAfterLaunch = notes.windows
        notes.windows = []
        notes.lookupsBeforeWindowsAppear = 1

        let report = await restore(workspace, on: [Fixtures.builtinAlone], system: system)

        #expect(system.events.contains("reopen \(notes.bundleID)"))
        #expect(report.results[2].outcome.isPlaced)
    }

    @Test("Apps with windows on another desktop are not reopened")
    func windowsOnAnotherDesktop() async {
        let workspace = Fixtures.laptopWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let notes = system.apps[workspace.windows[2].bundleID]!
        notes.windows = []
        notes.hasWindowsOnOtherDesktops = true

        let report = await restore(workspace, on: [Fixtures.builtinAlone], system: system)

        #expect(report.results[2].outcome == .windowNotFound)
        #expect(report.summary == "3件を配置しました。メモのウィンドウが見つかりませんでした")
    }

    @Test("A running app whose windows do not match is not reopened")
    func noMatchingTitle() async {
        var workspace = Fixtures.homeWorkspace
        workspace.windows = [workspace.windows[1]] // VS Code, title must contain "lanekeep"
        let system = FakeWindowSystem()
        system.addApp(workspace.windows[0].bundleID, windows: [FakeWindow(title: "other project")])

        let report = await restore(workspace, on: Fixtures.homeDisplays, system: system)

        #expect(report.results[0].outcome == .windowNotFound)
        #expect(!system.events.contains { $0.hasPrefix("reopen") })
    }

    @Test("Hidden apps are shown again")
    func unhides() async {
        let workspace = Fixtures.laptopWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        system.apps[workspace.windows[0].bundleID]!.isHidden = true

        _ = await restore(workspace, on: [Fixtures.builtinAlone], system: system)

        #expect(system.events.contains("unhide \(workspace.windows[0].bundleID)"))
    }

    @Test("Two rules of one app get two different windows")
    func twoWindowsOfOneApp() async {
        var workspace = Fixtures.laptopWorkspace
        workspace.windows = [
            Fixtures.rule("Terminal", index: 0, display: "BUILTIN", 0, 0, 50, 100),
            Fixtures.rule("Terminal", index: 1, display: "BUILTIN", 50, 0, 50, 100)
        ]
        let system = FakeWindowSystem()
        let first = FakeWindow(title: "zsh 1")
        let second = FakeWindow(title: "zsh 2")
        system.addApp(workspace.windows[0].bundleID, windows: [first, second])

        let report = await restore(workspace, on: [Fixtures.builtinAlone], system: system)

        #expect(report.summary == "2件すべて配置しました")
        #expect(first.frame.minX == 0)
        #expect(second.frame.minX == 756)
    }

    @Test("Progress is reported for every rule")
    func progress() async {
        let workspace = Fixtures.homeWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let recorder = ProgressRecorder()

        _ = await restore(workspace, on: Fixtures.homeDisplays, system: system) { progress in
            recorder.values.append(progress)
        }

        #expect(recorder.values.first == RestoreProgress(completed: 0, total: 6))
        #expect(recorder.values.last == RestoreProgress(completed: 6, total: 6))
        #expect(recorder.values.map(\.completed) == Array(0...6))
    }

    @Test("Moves happen between beginArranging and endArranging")
    func arrangingBrackets() async {
        var workspace = Fixtures.laptopWorkspace
        workspace.windows = [workspace.windows[0]]
        let system = FakeWindowSystem()
        system.addApps(for: workspace)

        _ = await restore(workspace, on: [Fixtures.builtinAlone], system: system)

        let bundleID = workspace.windows[0].bundleID
        let begin = system.events.firstIndex(of: "begin \(bundleID)")
        let move = system.events.firstIndex { $0.hasPrefix("setFrame") }
        let end = system.events.firstIndex(of: "end \(bundleID)")
        #expect(begin != nil && move != nil && end != nil)
        #expect(begin! < move! && move! < end!)
    }

    @Test("An empty workspace finishes immediately")
    func emptyWorkspace() async {
        var workspace = Fixtures.laptopWorkspace
        workspace.windows = []
        let report = await restore(workspace, on: [Fixtures.builtinAlone], system: FakeWindowSystem())
        #expect(report.results.isEmpty)
        #expect(report.summary == "このワークスペースには配置するウィンドウがありません")
    }

    @Test("Cancelling stops the wait for launching apps")
    func cancellation() async {
        let workspace = Fixtures.laptopWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let slack = system.apps[workspace.windows[1].bundleID]!
        slack.isRunning = false
        slack.windows = []
        let request = RestoreRequest(
            workspace: workspace,
            displays: [Fixtures.builtinAlone],
            fallback: .mainDisplay,
            timing: RestoreTiming(windowWaitTimeout: .seconds(30), pollInterval: .milliseconds(5))
        )
        let task = Task {
            await RestoreEngine(system: system).run(request)
        }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let report = await task.value

        #expect(report.results[1].outcome == .cancelled)
        #expect(report.finishedAt.timeIntervalSince(report.startedAt) < 10)
    }
}

/// Collects progress values from the engine's callback.
final class ProgressRecorder {
    var values: [RestoreProgress] = []
}
