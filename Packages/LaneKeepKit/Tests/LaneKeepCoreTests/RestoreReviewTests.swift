import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import LaneKeepCore

@Suite("A second look after automatic restores")
struct RestoreReviewTests {
    func request(_ workspace: Workspace) -> RestoreRequest {
        RestoreRequest(workspace: workspace, displays: [Fixtures.builtinAlone], fallback: .mainDisplay, timing: Fixtures.fastTiming)
    }

    /// What macOS does for a few seconds after a display is connected: it moves a window that
    /// had just been put in place.
    func simulateMacOSMoving(_ window: FakeWindow, by offset: CGSize, resizingTo size: CGSize? = nil) {
        window.frame.origin.x += offset.width
        window.frame.origin.y += offset.height
        if let size {
            window.frame.size = size
        }
    }

    func window(of rule: WindowRule, in system: FakeWindowSystem) -> FakeWindow {
        system.apps[rule.bundleID]!.windows[0]
    }

    @Test("Windows that moved by themselves after the restore are put back")
    func putsMovedWindowsBack() async {
        let workspace = Fixtures.laptopWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let engine = RestoreEngine(system: system)
        let result = await engine.runForReview(request(workspace))
        #expect(result.report.summary == "4件すべて配置しました")
        #expect(result.placements.count == 4)

        let safari = window(of: workspace.windows[0], in: system)
        let slack = window(of: workspace.windows[1], in: system)
        let notes = window(of: workspace.windows[2], in: system)
        let placedSafari = safari.frame
        let placedSlack = slack.frame
        let placedNotes = notes.frame
        simulateMacOSMoving(safari, by: CGSize(width: 40, height: 25))
        simulateMacOSMoving(slack, by: .zero, resizingTo: CGSize(width: 900, height: 700))
        // Within the 2 pt tolerance: not worth moving.
        simulateMacOSMoving(notes, by: CGSize(width: 1, height: 0))
        let eventsBefore = system.events.count

        let corrected = await engine.review(result.placements, of: request(workspace))

        #expect(corrected == 2)
        #expect(safari.frame == placedSafari)
        #expect(slack.frame == placedSlack)
        #expect(notes.frame == placedNotes.offsetBy(dx: 1, dy: 0))
        let reviewEvents = system.events.dropFirst(eventsBefore)
        #expect(reviewEvents.filter { $0.hasPrefix("setFrame") }.count == 2)
        #expect(!reviewEvents.contains("setFrame \(notes.title)"))
        #expect(!reviewEvents.contains { $0.hasPrefix("launch") || $0.hasPrefix("reopen") })
    }

    @Test("Windows that stayed in place are not touched")
    func leavesWindowsInPlace() async {
        let workspace = Fixtures.laptopWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let engine = RestoreEngine(system: system)
        let result = await engine.runForReview(request(workspace))
        let eventsBefore = system.events.count

        let corrected = await engine.review(result.placements, of: request(workspace))

        #expect(corrected == 0)
        #expect(system.events.count == eventsBefore)
    }

    @Test("Closed windows, minimized windows and quit apps are left alone; nothing is launched")
    func skipsWhatIsGone() async {
        let workspace = Fixtures.laptopWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let engine = RestoreEngine(system: system)
        let result = await engine.runForReview(request(workspace))

        let closed = window(of: workspace.windows[0], in: system)
        simulateMacOSMoving(closed, by: CGSize(width: 50, height: 0))
        closed.isClosed = true
        let minimized = window(of: workspace.windows[1], in: system)
        simulateMacOSMoving(minimized, by: CGSize(width: 50, height: 0))
        minimized.isMinimized = true
        // The app quit: its window is gone with it.
        let notesApp = system.apps[workspace.windows[2].bundleID]!
        notesApp.isRunning = false
        notesApp.windows[0].isClosed = true
        let eventsBefore = system.events.count

        let corrected = await engine.review(result.placements, of: request(workspace))

        #expect(corrected == 0)
        let reviewEvents = system.events.dropFirst(eventsBefore)
        #expect(reviewEvents.isEmpty)
        #expect(minimized.isMinimized)
    }

    @Test("A cancelled review does nothing (another restore was started)")
    func cancelled() async {
        let (restored, restoredContinuation) = AsyncStream<Void>.makeStream()
        let task = Task { () -> (corrected: Int, untouched: Bool) in
            let workspace = Fixtures.laptopWorkspace
            let system = FakeWindowSystem()
            system.addApps(for: workspace)
            let engine = RestoreEngine(system: system)
            let request = RestoreRequest(workspace: workspace, displays: [Fixtures.builtinAlone], fallback: .mainDisplay, timing: Fixtures.fastTiming)
            let result = await engine.runForReview(request)
            let safari = system.apps[workspace.windows[0].bundleID]!.windows[0]
            safari.frame.origin.x += 40
            let moved = safari.frame
            restoredContinuation.yield()
            // The review starts only once the task is cancelled, so that the outcome does not
            // depend on timing.
            while !Task.isCancelled {
                await Task.yield()
            }
            let corrected = await engine.review(result.placements, of: request)
            return (corrected, safari.frame == moved)
        }
        for await _ in restored {
            break
        }
        task.cancel()
        let outcome = await task.value

        #expect(outcome.corrected == 0)
        #expect(outcome.untouched)
    }

    @Test("Only automatic restores that placed windows get a second look")
    func whenNeeded() async {
        let workspace = Fixtures.laptopWorkspace
        let system = FakeWindowSystem()
        system.addApps(for: workspace)
        let report = await RestoreEngine(system: system).run(request(workspace))
        let nothingPlaced = RestoreReport(
            workspaceID: workspace.id,
            fallback: .mainDisplay,
            results: workspace.windows.map { RuleResult(rule: $0, outcome: .windowNotFound) },
            startedAt: Date(),
            finishedAt: Date()
        )

        #expect(RestoreReview.isNeeded(isAutomatic: true, report: report))
        #expect(!RestoreReview.isNeeded(isAutomatic: false, report: report))
        #expect(!RestoreReview.isNeeded(isAutomatic: true, report: nothingPlaced))
        #expect(RestoreReview.delay == .milliseconds(2500))
    }

    @Test("The result line tells how many windows were put back")
    func summary() {
        #expect(RestoreReview.summary("6件すべて配置しました", corrected: 2) == "6件すべて配置しました。あとから動いた2件を置き直しました")
        #expect(RestoreReview.summary("6件すべて配置しました", corrected: 0) == "6件すべて配置しました")
    }
}
