import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import LaneKeepCore

/// What a planned second look did: a stand-in for the windows it would put back.
@MainActor
final class ReviewProbe {
    /// Where the restore left the window.
    let placedFrame = CGRect(x: 100, y: 100, width: 900, height: 700)
    /// Where macOS moved it afterwards.
    let movedFrame = CGRect(x: 160, y: 140, width: 900, height: 700)
    private(set) var frame: CGRect
    private(set) var runs = 0
    private(set) var completions: [Int] = []

    init() {
        frame = movedFrame
    }

    /// The second look: puts the window back.
    func review() -> Int {
        runs += 1
        frame = placedFrame
        return 1
    }

    func complete(_ corrected: Int) {
        completions.append(corrected)
    }
}

@Suite("The second look is dropped when the displays change")
@MainActor
struct RestoreReviewSchedulerTests {
    /// The wait before the second look, short for the tests.
    let delay: Duration = .milliseconds(100)

    func schedule(_ scheduler: RestoreReviewScheduler, _ probe: ReviewProbe) {
        scheduler.schedule(for: Fixtures.homeDisplays) {
            probe.review()
        } completion: { corrected in
            probe.complete(corrected)
        }
    }

    /// Waits until a second look that was not dropped would long have run.
    func waitPastTheDelay() async {
        try? await Task.sleep(for: delay * 4)
    }

    @Test("A display change during the wait: the second look does not run, the window is not moved", arguments: DisplayChange.allCases)
    func changeDuringTheWait(_ change: DisplayChange) async {
        let scheduler = RestoreReviewScheduler(delay: delay)
        let probe = ReviewProbe()
        schedule(scheduler, probe)
        await Task.yield()

        scheduler.displaysChanged(to: change.displays)
        await waitPastTheDelay()

        #expect(probe.runs == 0)
        #expect(probe.completions.isEmpty)
        #expect(probe.frame == probe.movedFrame)
    }

    @Test("Displays read again with the displays in their places: the second look runs")
    func noChange() async {
        let scheduler = RestoreReviewScheduler(delay: delay)
        let probe = ReviewProbe()
        schedule(scheduler, probe)
        await Task.yield()

        // A notification without a change (the order of the displays does not matter), then the
        // Dock moving to the other display.
        scheduler.displaysChanged(to: Array(Fixtures.homeDisplays.reversed()))
        scheduler.displaysChanged(to: Fixtures.homeDisplaysWithDockOnBuiltin)
        await waitPastTheDelay()

        #expect(probe.runs == 1)
        #expect(probe.completions == [1])
        #expect(probe.frame == probe.placedFrame)
    }

    @Test("A display change while the second look runs stops it, and its result is dropped")
    func changeWhileRunning() async {
        let scheduler = RestoreReviewScheduler(delay: .zero)
        let probe = ReviewProbe()
        let (started, startedContinuation) = AsyncStream<Void>.makeStream()
        let (finished, finishedContinuation) = AsyncStream<Bool>.makeStream()
        scheduler.schedule(for: Fixtures.homeDisplays) {
            startedContinuation.yield()
            // Looking at the windows takes a while; stopping cuts it short.
            try? await Task.sleep(for: .seconds(30))
            finishedContinuation.yield(Task.isCancelled)
            return 1
        } completion: { corrected in
            probe.complete(corrected)
        }
        for await _ in started {
            break
        }

        scheduler.displaysChanged(to: DisplayChange.unplugged.displays)
        var wasStopped = false
        for await cancelled in finished {
            wasStopped = cancelled
            break
        }
        await Task.yield()

        #expect(wasStopped)
        #expect(probe.completions.isEmpty)
    }

    @Test("Cancelling drops the second look (another restore started, automatic restores turned off)")
    func cancelled() async {
        let scheduler = RestoreReviewScheduler(delay: delay)
        let probe = ReviewProbe()
        schedule(scheduler, probe)

        scheduler.cancel()
        await waitPastTheDelay()

        #expect(probe.runs == 0)
        #expect(probe.frame == probe.movedFrame)
    }
}
