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
    /// 4. For launched apps, apps that were asked to open a window and apps that did not answer,
    ///    the engine checks every `pollInterval` and places windows as they appear, for at most
    ///    `windowWaitTimeout` per app, counted from when the waiting starts.
    ///
    /// - Parameter progress: Called after every rule that has been dealt with.
    public func run(
        _ request: RestoreRequest,
        progress: @escaping (RestoreProgress) async -> Void = { _ in }
    ) async -> RestoreReport {
        await runForReview(request, progress: progress).report
    }

    /// Runs the restore and also returns the windows it placed, for `review(_:of:currentDisplays:)`.
    public func runForReview(
        _ request: RestoreRequest,
        progress: @escaping (RestoreProgress) async -> Void = { _ in }
    ) async -> RestoreResult<System.Handle> {
        let run = RestoreRun(system: system, request: request, progress: progress)
        let report = await run.execute()
        return RestoreResult(report: report, placements: run.placements)
    }

    /// Looks once more at the windows a restore placed. Right after a display is connected, macOS
    /// keeps moving windows for a few seconds, so a window may have left its place again.
    ///
    /// Windows that are now `tolerance` (2 pt) or more away from where the restore left them get
    /// their size and position again, like in the restore. Nothing is launched or reopened;
    /// windows that are gone or have been minimized since are left alone. Stops when the task is
    /// cancelled.
    ///
    /// Does nothing unless `currentDisplays` are the displays of the restore (`request.displays`)
    /// in the same places. Their visible areas may have changed since (the Dock moved to another
    /// display): windows go into the visible areas as they are now.
    ///
    /// - Returns: How many windows were put back.
    public func review(
        _ placements: [PlacedWindow<System.Handle>],
        of request: RestoreRequest,
        currentDisplays: [DisplaySnapshot]
    ) async -> Int {
        guard DisplayGeometry.isSameArrangement(request.displays, currentDisplays) else { return 0 }
        var request = request
        request.displays = currentDisplays
        let run = RestoreRun(system: system, request: request, progress: { _ in })
        return await run.review(placements)
    }
}

/// A window a restore placed.
public struct PlacedWindow<Handle: Hashable> {
    /// Index of the rule in the workspace.
    public var ruleIndex: Int
    public var handle: Handle
    /// Where the restore left the window (Accessibility coordinates).
    public var frame: CGRect

    public init(ruleIndex: Int, handle: Handle, frame: CGRect) {
        self.ruleIndex = ruleIndex
        self.handle = handle
        self.frame = frame
    }
}

/// The report of a restore and the windows it placed.
public struct RestoreResult<Handle: Hashable> {
    public var report: RestoreReport
    public var placements: [PlacedWindow<Handle>]
}

/// The state of one restore.
private final class RestoreRun<System: WindowSystem> {
    /// How LaneKeep came to wait for an app's windows.
    enum Origin {
        /// The app was running with windows.
        case running
        /// LaneKeep launched it.
        case launched
        /// It was running without a window and was asked to open one.
        case reopened
    }

    /// The rules of one app that still need a window.
    struct AppWork {
        var bundleID: String
        var remaining: [Int]
        var origin: Origin
        var deadline: ContinuousClock.Instant?
        var placedHandles: Set<System.Handle> = []
        var lastWindowCount = 0
        /// The app did not answer the last time its windows were asked for.
        var isBusy = false
        /// The titles of the app's windows at the last check, and how many checks in a row they
        /// stayed the same: windows of a launching app come one by one and get their titles late.
        var lastTitles: [String]?
        var unchangedChecks = 0
    }

    /// Windows within this many points of the requested frame count as placed exactly.
    private let tolerance: CGFloat = 2
    /// While waiting for an app, rules without a title marker are only matched once the windows
    /// have stopped changing for this many checks…
    private let settledChecks = 1
    /// …and all marker rules found their window and there are enough windows; or, failing that,
    /// once the windows have not changed for this many checks, or in the last tenth of the wait.
    private let patientChecks = 3

    private let system: System
    private let request: RestoreRequest
    private let progress: (RestoreProgress) async -> Void
    private let rules: [WindowRule]
    private let targets: [PlacementTarget?]
    /// For a workspace that leaves other displays alone: the only displays windows are taken from.
    private let ownDisplays: Set<String>?
    private let primaryHeight: CGFloat
    private let clock = ContinuousClock()
    private var outcomes: [RuleOutcome?]
    private var completed = 0
    /// The windows that were placed, in the order they were placed.
    private(set) var placements: [PlacedWindow<System.Handle>] = []

    init(system: System, request: RestoreRequest, progress: @escaping (RestoreProgress) async -> Void) {
        self.system = system
        self.request = request
        self.progress = progress
        self.rules = request.workspace.windows
        self.targets = request.workspace.windows.map {
            PlacementPlanner.target(for: $0, displays: request.displays, fallback: request.fallback)
        }
        self.ownDisplays = request.workspace.leavesOtherDisplaysAlone ? request.workspace.ruleDisplayUUIDs : nil
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
        var waiting: [AppWork] = []
        for (bundleID, indices) in pendingRulesByApp() {
            guard !Task.isCancelled else { break }
            switch await system.runningState(of: bundleID) {
            case .running(let isHidden):
                if isHidden {
                    await system.unhide(bundleID)
                }
                running.append(AppWork(bundleID: bundleID, remaining: indices, origin: .running))
            case .notRunning:
                // Launch the app if any of its rules allows it. Once it runs, all of its rules
                // can use its windows.
                guard indices.contains(where: { rules[$0].launchIfClosed }) else {
                    for index in indices {
                        await finish(index, .appNotRunning)
                    }
                    continue
                }
                switch await system.requestLaunch(of: bundleID) {
                case .requested:
                    waiting.append(AppWork(bundleID: bundleID, remaining: indices, origin: .launched))
                case .notInstalled:
                    for index in indices {
                        await finish(index, .appNotInstalled)
                    }
                }
            }
        }

        for var work in running {
            guard !Task.isCancelled else { break }
            await placeAvailableWindows(&work, waiting: false)
            guard !Task.isCancelled else { break }
            guard !work.remaining.isEmpty else { continue }

            if work.isBusy {
                // The app did not answer, which happens while apps rearrange themselves after a
                // display change: keep asking for a while.
                waiting.append(work)
            } else if work.lastWindowCount == 0,
                      work.remaining.contains(where: { rules[$0].launchIfClosed }),
                      await system.requestReopenIfWindowless(work.bundleID) {
                // The app runs but has no window at all, e.g. its window was closed: it was asked to
                // open one, like clicking its Dock icon. Wait for it like for a launched app.
                work.origin = .reopened
                waiting.append(work)
            } else {
                for index in work.remaining {
                    await finish(index, .windowNotFound)
                }
            }
        }

        // The wait starts now, after the running apps have been arranged, so that launching apps
        // get the full time however long that took.
        let waitDeadline = clock.now.advanced(by: request.timing.windowWaitTimeout)
        for position in waiting.indices {
            waiting[position].deadline = waitDeadline
        }
        while !waiting.isEmpty, !Task.isCancelled {
            for position in waiting.indices {
                guard !Task.isCancelled else { break }
                await placeAvailableWindows(&waiting[position], waiting: true)
            }
            guard !Task.isCancelled else { break }
            var stillWaiting: [AppWork] = []
            for work in waiting where !work.remaining.isEmpty {
                if let deadline = work.deadline, clock.now >= deadline {
                    for index in work.remaining {
                        await finish(index, timeoutOutcome(for: work))
                    }
                } else {
                    stillWaiting.append(work)
                }
            }
            waiting = stillWaiting
            if !waiting.isEmpty {
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

    /// Why a rule of an app that was waited for in vain has no window.
    private func timeoutOutcome(for work: AppWork) -> RuleOutcome {
        if work.isBusy {
            return .appNotResponding
        }
        if work.origin == .launched, work.lastWindowCount == 0 {
            return .stillLaunching
        }
        return .windowNotFound
    }

    private func finish(_ index: Int, _ outcome: RuleOutcome) async {
        guard outcomes[index] == nil else { return }
        outcomes[index] = outcome
        completed += 1
        await progress(RestoreProgress(completed: completed, total: rules.count))
    }

    /// Matches the app's current windows against its remaining rules and places the matches.
    ///
    /// - Parameter waiting: The app is launching or opening a window. Its windows may still be
    ///   coming in, so rules without a title marker hold back until the windows have settled.
    private func placeAvailableWindows(_ work: inout AppWork, waiting: Bool) async {
        guard !work.remaining.isEmpty else { return }
        guard let windows = await system.windows(of: work.bundleID) else {
            work.isBusy = true
            return
        }
        work.isBusy = false
        work.lastWindowCount = windows.count
        let titles = windows.map(\.title).sorted()
        if titles == work.lastTitles {
            work.unchangedChecks += 1
        } else {
            work.lastTitles = titles
            work.unchangedChecks = 0
        }
        guard !windows.isEmpty else { return }

        let matchable = windows.enumerated().map { position, window in
            MatchableWindow(title: window.title, position: position, location: location(of: window))
        }
        let placed = work.placedHandles
        var taken = Set(windows.indices.filter { placed.contains(windows[$0].handle) })
        // A workspace that leaves other displays alone takes no window from them. The windows of
        // an app it launched or asked to open a window are new, and are taken wherever they open.
        if let ownDisplays, work.origin == .running {
            taken.formUnion(matchable.indices.filter { index in
                guard let display = matchable[index].location?.displayUUID else { return true }
                return !ownDisplays.contains(display)
            })
        }
        let markerRules = work.remaining.filter { rules[$0].titleMarker != nil }
        let otherRules = work.remaining.filter { rules[$0].titleMarker == nil }

        var matches: [(rule: Int, window: SystemWindow<System.Handle>)] = []
        let markerAssignment = WindowMatcher.assign(
            rules: markerRules.map { rules[$0] },
            windows: matchable,
            excluding: taken
        )
        for (rule, window) in zip(markerRules, markerAssignment) {
            if let window {
                matches.append((rule, windows[window]))
                taken.insert(window)
            }
        }

        if !otherRules.isEmpty {
            var release = true
            if waiting {
                let allMarkersFound = matches.count == markerRules.count
                let enoughWindows = windows.count - taken.count >= otherRules.count
                let lastChance = request.timing.windowWaitTimeout / 10
                let nearlyOver = work.deadline.map { clock.now >= $0.advanced(by: .zero - lastChance) } ?? true
                release = (work.unchangedChecks >= settledChecks && allMarkersFound && enoughWindows)
                    || work.unchangedChecks >= patientChecks
                    || nearlyOver
            }
            if release {
                let assignment = WindowMatcher.assign(
                    rules: otherRules.map { rules[$0] },
                    windows: matchable,
                    excluding: taken,
                    strategy: request.matching
                )
                for (rule, window) in zip(otherRules, assignment) {
                    if let window {
                        matches.append((rule, windows[window]))
                    }
                }
            }
        }
        guard !matches.isEmpty else { return }

        await system.beginArranging(work.bundleID)
        for match in matches {
            guard !Task.isCancelled else { break }
            let outcome = await place(rule: match.rule, window: match.window)
            work.placedHandles.insert(match.window.handle)
            work.remaining.removeAll { $0 == match.rule }
            if case .placed(let frame, _) = outcome {
                placements.append(PlacedWindow(ruleIndex: match.rule, handle: match.window.handle, frame: frame))
            }
            await finish(match.rule, outcome)
        }
        await system.endArranging(work.bundleID)
    }

    /// See `RestoreEngine.review(_:of:currentDisplays:)`.
    func review(_ placements: [PlacedWindow<System.Handle>]) async -> Int {
        var corrected = 0
        // App by app, so that each app is prepared for moves once.
        var order: [String] = []
        var byApp: [String: [PlacedWindow<System.Handle>]] = [:]
        for placement in placements where rules.indices.contains(placement.ruleIndex) {
            let bundleID = rules[placement.ruleIndex].bundleID
            if byApp[bundleID] == nil {
                order.append(bundleID)
            }
            byApp[bundleID, default: []].append(placement)
        }
        for bundleID in order {
            var arranging = false
            for placement in byApp[bundleID] ?? [] {
                guard !Task.isCancelled else { break }
                // Gone (closed, or its app quit), minimized by the user, or still in place.
                guard let current = await system.frame(of: placement.handle),
                      !(await system.isMinimized(placement.handle)),
                      !current.isWithin(tolerance, of: placement.frame)
                else {
                    continue
                }
                if !arranging {
                    await system.beginArranging(bundleID)
                    arranging = true
                }
                let window = SystemWindow(handle: placement.handle, title: "", isMinimized: false, frame: current)
                if await place(rule: placement.ruleIndex, window: window).isPlaced {
                    corrected += 1
                }
            }
            if arranging {
                await system.endArranging(bundleID)
            }
            guard !Task.isCancelled else { break }
        }
        return corrected
    }

    /// The display a window is on and its frame relative to that display's visible area.
    private func location(of window: SystemWindow<System.Handle>) -> WindowLocation? {
        guard let frame = window.frame,
              let display = DisplayGeometry.display(forAccessibilityRect: frame, among: request.displays, primaryHeight: primaryHeight)
        else {
            return nil
        }
        let bounds = CoordinateConverter.accessibilityRect(fromAppKit: display.visibleFrame, primaryHeight: primaryHeight)
        return WindowLocation(displayUUID: display.uuid, relativeFrame: RelativeGeometry.relativeFrame(of: frame, in: bounds))
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
        // Stopped (the displays of a second look changed, automatic restores were turned off):
        // move nothing more. Checked again before every further move; a cancelled wait ends early.
        guard !Task.isCancelled else {
            return .cancelled
        }
        var applied = await system.setFrame(desired, of: window.handle) == .applied
        var current = await system.frame(of: window.handle)
        if !applied || current == nil {
            // A busy app may answer late and move the window anyway: look again before trying once more.
            try? await Task.sleep(for: request.timing.retryDelay)
            guard !Task.isCancelled else {
                return .cancelled
            }
            current = await system.frame(of: window.handle)
            if current.map({ !$0.isWithin(tolerance, of: desired) }) ?? true {
                applied = await system.setFrame(desired, of: window.handle) == .applied
                current = await system.frame(of: window.handle)
            }
        }
        guard var actual = current ?? (applied ? desired : nil) else {
            return .moveFailed
        }

        // The size is not the one asked for. A slow app may still be applying it, so before
        // concluding that the app refuses it, wait, set the frame once more and look again. Then
        // the second result counts: the same size as the first time means the app refuses it;
        // otherwise it has come closer, possibly all the way.
        if actual.size.maxAxisDistance(to: desired.size) > tolerance {
            try? await Task.sleep(for: request.timing.retryDelay)
            guard !Task.isCancelled else {
                return .cancelled
            }
            if await system.setFrame(desired, of: window.handle) == .applied {
                applied = true
            }
            actual = await system.frame(of: window.handle) ?? actual
        }
        // A size the app does not take (minimum size, fixed-size window): keep the window inside
        // the visible area instead of letting it hang off the edge (spec §6.6).
        var expectedOrigin = desired.origin
        if actual.size.maxAxisDistance(to: desired.size) > tolerance {
            expectedOrigin = FrameFitting.fit(CGRect(origin: desired.origin, size: actual.size), into: bounds).origin
        }
        // Some apps adjust their window asynchronously; move it again if it is not where expected.
        for attempt in 0..<2 where actual.origin.maxAxisDistance(to: expectedOrigin) > tolerance {
            if attempt > 0 {
                try? await Task.sleep(for: request.timing.retryDelay)
            }
            guard !Task.isCancelled else {
                return .cancelled
            }
            _ = await system.setOrigin(expectedOrigin, of: window.handle)
            actual = await system.frame(of: window.handle) ?? actual
        }

        // Placed if the window is where it was asked to go, or if it moved and the app put it
        // somewhere else on the target display.
        let displayBounds = CoordinateConverter.accessibilityRect(fromAppKit: target.display.frame, primaryHeight: primaryHeight)
        let isWhereExpected = actual.origin.maxAxisDistance(to: expectedOrigin) <= tolerance
        guard isWhereExpected || (applied && displayBounds.contains(CGPoint(x: actual.midX, y: actual.midY))) else {
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

private extension CGRect {
    func isWithin(_ tolerance: CGFloat, of other: CGRect) -> Bool {
        origin.maxAxisDistance(to: other.origin) <= tolerance && size.maxAxisDistance(to: other.size) <= tolerance
    }
}
