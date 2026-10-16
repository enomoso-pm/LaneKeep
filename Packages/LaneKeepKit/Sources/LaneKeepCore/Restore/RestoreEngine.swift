import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Puts the windows of a workspace back where they were saved (spec §6.4).
///
/// The engine is independent of the Accessibility API: everything it does to apps and windows goes
/// through a `WindowSystem`, which keeps the logic testable.
public struct RestoreEngine<System: WindowSystem> {
    public let system: System

    public init(system: System) {
        self.system = system
    }

    /// Runs the restore.
    ///
    /// 1. Rules whose display is gone (and should not be redirected) are skipped.
    /// 2. Apps that are not running are launched when a rule allows it; hidden apps are shown.
    /// 3. Windows of running apps are matched (spec §6.3) and placed right away.
    /// 4. For launched apps, the engine checks every `pollInterval` and places windows as they
    ///    appear, for at most `windowWaitTimeout` per app.
    ///
    /// - Parameter progress: Called after every rule that has been dealt with.
    public func run(
        _ request: RestoreRequest,
        progress: @escaping (RestoreProgress) async -> Void = { _ in }
    ) async -> RestoreReport {
        let run = RestoreRun(system: system, request: request, progress: progress)
        return await run.execute()
    }
}

/// The state of one restore.
private final class RestoreRun<System: WindowSystem> {
    /// The rules of one app that still need a window.
    struct AppWork {
        var bundleID: String
        var remaining: [Int]
        var deadline: ContinuousClock.Instant?
        var placedHandles: Set<System.Handle> = []
        var lastWindowCount = 0
    }

    /// Windows within this many points of the requested frame count as placed exactly.
    private let tolerance: CGFloat = 2

    private let system: System
    private let request: RestoreRequest
    private let progress: (RestoreProgress) async -> Void
    private let rules: [WindowRule]
    private let targets: [PlacementTarget?]
    private let primaryHeight: CGFloat
    private let clock = ContinuousClock()
    private var outcomes: [RuleOutcome?]
    private var completed = 0

    init(system: System, request: RestoreRequest, progress: @escaping (RestoreProgress) async -> Void) {
        self.system = system
        self.request = request
        self.progress = progress
        self.rules = request.workspace.windows
        self.targets = request.workspace.windows.map {
            PlacementPlanner.target(for: $0, displays: request.displays, fallback: request.fallback)
        }
        self.primaryHeight = DisplayGeometry.primaryHeight(of: request.displays) ?? 0
        self.outcomes = Array(repeating: nil, count: request.workspace.windows.count)
    }

    func execute() async -> RestoreReport {
        let startedAt = Date()
        await progress(RestoreProgress(completed: 0, total: rules.count))

        for index in rules.indices where targets[index] == nil {
            await finish(index, .skippedMissingDisplay)
        }

        var running: [AppWork] = []
        var launching: [AppWork] = []
        for (bundleID, indices) in pendingRulesByApp() {
            guard !Task.isCancelled else { break }
            switch await system.runningState(of: bundleID) {
            case .running(let isHidden):
                if isHidden {
                    await system.unhide(bundleID)
                }
                running.append(AppWork(bundleID: bundleID, remaining: indices))
            case .notRunning:
                let launchable = indices.filter { rules[$0].launchIfClosed }
                for index in indices where !rules[index].launchIfClosed {
                    await finish(index, .appNotRunning)
                }
                guard !launchable.isEmpty else { continue }
                switch await system.requestLaunch(of: bundleID) {
                case .requested:
                    launching.append(AppWork(bundleID: bundleID, remaining: launchable, deadline: newDeadline()))
                case .notInstalled:
                    for index in launchable {
                        await finish(index, .appNotInstalled)
                    }
                }
            }
        }

        for var work in running {
            guard !Task.isCancelled else { break }
            await placeAvailableWindows(&work)
            guard !work.remaining.isEmpty else { continue }

            // The app runs but has no window at all, e.g. its window was closed: ask it to open one,
            // like clicking its Dock icon, and wait for it like for a launched app.
            let reopenable = work.remaining.filter { rules[$0].launchIfClosed }
            if work.lastWindowCount == 0, !reopenable.isEmpty, await system.requestReopenIfWindowless(work.bundleID) {
                for index in work.remaining where !rules[index].launchIfClosed {
                    await finish(index, .windowNotFound)
                }
                work.remaining = reopenable
                work.deadline = newDeadline()
                launching.append(work)
            } else {
                for index in work.remaining {
                    await finish(index, .windowNotFound)
                }
            }
        }

        while !launching.isEmpty, !Task.isCancelled {
            for position in launching.indices {
                await placeAvailableWindows(&launching[position])
            }
            var stillWaiting: [AppWork] = []
            for work in launching where !work.remaining.isEmpty {
                if let deadline = work.deadline, clock.now >= deadline {
                    for index in work.remaining {
                        await finish(index, .stillLaunching)
                    }
                } else {
                    stillWaiting.append(work)
                }
            }
            launching = stillWaiting
            if !launching.isEmpty {
                try? await Task.sleep(for: request.timing.pollInterval)
            }
        }

        let results = rules.indices.map { index in
            RuleResult(rule: rules[index], outcome: outcomes[index] ?? .cancelled)
        }
        return RestoreReport(
            workspaceID: request.workspace.id,
            fallback: request.fallback,
            results: results,
            startedAt: startedAt,
            finishedAt: Date()
        )
    }

    /// Rule indices that still need work, grouped by app in order of first appearance.
    private func pendingRulesByApp() -> [(bundleID: String, indices: [Int])] {
        var order: [String] = []
        var groups: [String: [Int]] = [:]
        for index in rules.indices where outcomes[index] == nil {
            let bundleID = rules[index].bundleID
            if groups[bundleID] == nil {
                order.append(bundleID)
            }
            groups[bundleID, default: []].append(index)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    private func newDeadline() -> ContinuousClock.Instant {
        clock.now.advanced(by: request.timing.windowWaitTimeout)
    }

    private func finish(_ index: Int, _ outcome: RuleOutcome) async {
        guard outcomes[index] == nil else { return }
        outcomes[index] = outcome
        completed += 1
        await progress(RestoreProgress(completed: completed, total: rules.count))
    }

    /// Matches the app's current windows against its remaining rules and places the matches.
    private func placeAvailableWindows(_ work: inout AppWork) async {
        guard !work.remaining.isEmpty else { return }
        let windows = await system.windows(of: work.bundleID)
        work.lastWindowCount = windows.count
        guard !windows.isEmpty else { return }

        let taken = Set(windows.indices.filter { work.placedHandles.contains(windows[$0].handle) })
        let assignment = WindowMatcher.assign(
            rules: work.remaining.map { rules[$0] },
            titles: windows.map(\.title),
            excluding: taken
        )
        let matches: [(rule: Int, window: SystemWindow<System.Handle>)] = zip(work.remaining, assignment).compactMap { rule, window in
            window.map { (rule, windows[$0]) }
        }
        guard !matches.isEmpty else { return }

        await system.beginArranging(work.bundleID)
        for match in matches {
            guard !Task.isCancelled else { break }
            let outcome = await place(rule: match.rule, window: match.window)
            work.placedHandles.insert(match.window.handle)
            work.remaining.removeAll { $0 == match.rule }
            await finish(match.rule, outcome)
        }
        await system.endArranging(work.bundleID)
    }

    private func place(rule index: Int, window: SystemWindow<System.Handle>) async -> RuleOutcome {
        guard let target = targets[index] else {
            return .skippedMissingDisplay
        }
        let bounds = CoordinateConverter.accessibilityRect(fromAppKit: target.display.visibleFrame, primaryHeight: primaryHeight)
        let desired = RelativeGeometry.absoluteFrame(for: rules[index].relativeFrame, in: bounds)

        if window.isMinimized {
            await unminimize(window.handle)
        }
        guard await system.setFrame(desired, of: window.handle) == .applied else {
            return .moveFailed
        }
        var actual = await system.frame(of: window.handle) ?? desired

        // An app may refuse the requested size (minimum size, fixed-size window). Then keep the
        // window inside the visible area instead of letting it hang off the edge (spec §6.6).
        var expectedOrigin = desired.origin
        if actual.size.maxAxisDistance(to: desired.size) > tolerance {
            expectedOrigin = FrameFitting.fit(CGRect(origin: desired.origin, size: actual.size), into: bounds).origin
        }
        // Some apps adjust their window asynchronously; move it again if it is not where expected.
        for attempt in 0..<2 where actual.origin.maxAxisDistance(to: expectedOrigin) > tolerance {
            if attempt > 0 {
                try? await Task.sleep(for: request.timing.retryDelay)
            }
            _ = await system.setOrigin(expectedOrigin, of: window.handle)
            actual = await system.frame(of: window.handle) ?? actual
        }

        let displayBounds = CoordinateConverter.accessibilityRect(fromAppKit: target.display.frame, primaryHeight: primaryHeight)
        guard displayBounds.contains(CGPoint(x: actual.midX, y: actual.midY)) else {
            return .moveFailed
        }
        return .placed(frame: actual, redirected: target.redirected)
    }

    private func unminimize(_ window: System.Handle) async {
        _ = await system.unminimize(window)
        let deadline = clock.now.advanced(by: request.timing.unminimizeTimeout)
        while await system.isMinimized(window), clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        // Let the un-minimize animation finish, otherwise it can put the window back.
        try? await Task.sleep(for: request.timing.unminimizeSettleDelay)
    }
}
