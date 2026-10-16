import Foundation
import Testing
@testable import LaneKeepCore

/// The displays as the monitor sees them, changed by the tests.
@MainActor
final class FakeScreens {
    var signature: String

    init(_ signature: String) {
        self.signature = signature
    }
}

/// What the monitor reported.
@MainActor
final class MonitorRecorder {
    var changes = 0
    var settled: [AutoRestoreTrigger] = []
}

@Suite("Noticing display changes from several sources (spec §6.2)")
@MainActor
struct DisplayChangeMonitorTests {
    /// Short enough for tests, long enough to tell "within the burst" from "after it".
    let settle: Duration = .milliseconds(60)

    func makeMonitor(_ screens: FakeScreens, _ recorder: MonitorRecorder, settle: Duration? = nil) -> DisplayChangeMonitor {
        let monitor = DisplayChangeMonitor(initialSignature: screens.signature, settleDelay: settle ?? self.settle) {
            screens.signature
        }
        monitor.onDisplaysChanged = { recorder.changes += 1 }
        monitor.onSettled = { recorder.settled.append($0) }
        return monitor
    }

    /// Waits until the monitor has had time to settle (several settle delays).
    func waitForSettling() async {
        try? await Task.sleep(for: settle * 5)
    }

    @Test("Signals from several sources about one change lead to one evaluation")
    func oneChangeManySources() async {
        let screens = FakeScreens("EXT")
        let recorder = MonitorRecorder()
        let monitor = makeMonitor(screens, recorder)

        // The dock reconnects: the Quartz callback, the notification, "screens did wake" and the
        // periodic check all notice.
        screens.signature = "EXT|OTHER"
        monitor.displaysMayHaveChanged()
        monitor.displaysMayHaveChanged()
        monitor.checkForMissedChange()
        monitor.displaysMayHaveChanged()
        await waitForSettling()
        monitor.checkForMissedChange()
        monitor.displaysMayHaveChanged()
        await waitForSettling()

        #expect(recorder.settled == [.displaysChanged])
    }

    @Test("A change no notification reported is found by the periodic check")
    func missedNotification() async {
        let screens = FakeScreens("BUILTIN")
        let recorder = MonitorRecorder()
        let monitor = makeMonitor(screens, recorder)

        screens.signature = "EXT"
        monitor.checkForMissedChange()
        #expect(recorder.changes == 1)
        await waitForSettling()

        #expect(recorder.settled == [.displaysChanged])
    }

    @Test("The periodic check does nothing while the displays stay the same")
    func checkWithoutChange() async {
        let screens = FakeScreens("EXT")
        let recorder = MonitorRecorder()
        let monitor = makeMonitor(screens, recorder)

        for _ in 0..<5 {
            monitor.checkForMissedChange()
        }
        await waitForSettling()

        #expect(recorder.changes == 0)
        #expect(recorder.settled.isEmpty)
    }

    @Test("Notifications without a change of displays restore nothing")
    func notificationWithoutChange() async {
        let screens = FakeScreens("EXT")
        let recorder = MonitorRecorder()
        let monitor = makeMonitor(screens, recorder)

        // A resolution change, a moving Dock.
        monitor.displaysMayHaveChanged()
        monitor.displaysMayHaveChanged()
        await waitForSettling()

        #expect(recorder.changes == 2)
        #expect(recorder.settled.isEmpty)
    }

    @Test("The evaluation waits until the signals stop")
    func debounce() async {
        let screens = FakeScreens("EXT")
        let recorder = MonitorRecorder()
        // A longer delay, so that slow test machines still send the signals well within it.
        let settle: Duration = .milliseconds(300)
        let monitor = makeMonitor(screens, recorder, settle: settle)

        screens.signature = "EXT|OTHER"
        monitor.displaysMayHaveChanged()
        // Signals keep coming for longer than the settle delay…
        for _ in 0..<6 {
            try? await Task.sleep(for: settle / 5)
            monitor.displaysMayHaveChanged()
        }
        // …so nothing was evaluated yet.
        #expect(recorder.settled.isEmpty)
        try? await Task.sleep(for: settle * 3)
        #expect(recorder.settled == [.displaysChanged])
    }

    @Test("A wake and a change during the same burst are evaluated together")
    func wakeAndChange() async {
        let screens = FakeScreens("BUILTIN")
        let recorder = MonitorRecorder()
        let monitor = makeMonitor(screens, recorder)

        monitor.didWake()
        screens.signature = "EXT"
        monitor.checkForMissedChange()
        await waitForSettling()

        #expect(recorder.settled == [[.displaysChanged, .wake]])
    }

    @Test("A display that drops out between two checks is noticed as well")
    func briefDropout() async {
        let screens = FakeScreens("EXT")
        let recorder = MonitorRecorder()
        let monitor = makeMonitor(screens, recorder)

        screens.signature = "BUILTIN"
        monitor.checkForMissedChange()
        screens.signature = "EXT"
        monitor.checkForMissedChange()
        await waitForSettling()

        #expect(recorder.settled == [.displaysChanged])
    }

    @Test("A cancelled evaluation does not happen")
    func cancel() async {
        let screens = FakeScreens("EXT")
        let recorder = MonitorRecorder()
        let monitor = makeMonitor(screens, recorder)

        screens.signature = "OTHER"
        monitor.displaysMayHaveChanged()
        monitor.cancelPendingEvaluation()
        await waitForSettling()

        #expect(recorder.settled.isEmpty)
    }
}
