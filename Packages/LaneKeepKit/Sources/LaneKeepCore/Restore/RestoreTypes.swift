import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Timing of a restore (spec §6.4: wait up to 10 seconds for a window, checking every 250 ms).
public struct RestoreTiming: Equatable, Sendable {
    public var windowWaitTimeout: Duration
    public var pollInterval: Duration
    /// How long to wait for a minimized window to come back.
    public var unminimizeTimeout: Duration
    /// Extra time for the un-minimize animation before the window is moved.
    public var unminimizeSettleDelay: Duration
    /// Pause before the second attempt at moving a window that did not end up where asked.
    public var retryDelay: Duration

    public init(
        windowWaitTimeout: Duration = .seconds(10),
        pollInterval: Duration = .milliseconds(250),
        unminimizeTimeout: Duration = .seconds(1),
        unminimizeSettleDelay: Duration = .milliseconds(350),
        retryDelay: Duration = .milliseconds(150)
    ) {
        self.windowWaitTimeout = windowWaitTimeout
        self.pollInterval = pollInterval
        self.unminimizeTimeout = unminimizeTimeout
        self.unminimizeSettleDelay = unminimizeSettleDelay
        self.retryDelay = retryDelay
    }

    public static let standard = RestoreTiming()
}

public struct RestoreRequest: Sendable {
    public var workspace: Workspace
    /// The displays connected right now.
    public var displays: [DisplaySnapshot]
    public var fallback: MissingDisplayFallback
    public var timing: RestoreTiming
    public var matching: MatchingStrategy

    public init(
        workspace: Workspace,
        displays: [DisplaySnapshot],
        fallback: MissingDisplayFallback,
        timing: RestoreTiming = .standard,
        matching: MatchingStrategy = .closest
    ) {
        self.workspace = workspace
        self.displays = displays
        self.fallback = fallback
        self.timing = timing
        self.matching = matching
    }
}

public struct RestoreProgress: Equatable, Sendable {
    public var completed: Int
    public var total: Int

    public init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }

    public var fraction: Double {
        total > 0 ? Double(completed) / Double(total) : 1
    }
}

/// What happened to one window rule.
public enum RuleOutcome: Equatable, Sendable {
    /// The window is in place. `redirected` means it went to the fallback display.
    case placed(frame: CGRect, redirected: Bool)
    /// Its display is not connected and the fallback is "leave it".
    case skippedMissingDisplay
    /// The app is not running and the rule says not to launch it.
    case appNotRunning
    /// The rule says to launch the app, but it is not installed.
    case appNotInstalled
    /// The app was launched, but the window had not appeared when the wait ended.
    case stillLaunching
    /// The app is running, but no matching window was found.
    case windowNotFound
    /// The app did not answer the Accessibility API until the wait ended.
    case appNotResponding
    /// The window refused to move.
    case moveFailed
    /// The restore was cancelled before this rule was handled, or while its window was being placed.
    case cancelled

    public var isPlaced: Bool {
        if case .placed = self { return true }
        return false
    }

    public var isRedirected: Bool {
        if case .placed(_, let redirected) = self { return redirected }
        return false
    }
}

public struct RuleResult: Equatable, Sendable {
    public var rule: WindowRule
    public var outcome: RuleOutcome

    public init(rule: WindowRule, outcome: RuleOutcome) {
        self.rule = rule
        self.outcome = outcome
    }
}

public struct RestoreReport: Equatable, Sendable {
    public var workspaceID: UUID
    public var fallback: MissingDisplayFallback
    /// One result per window rule, in the order of the workspace.
    public var results: [RuleResult]
    public var startedAt: Date
    public var finishedAt: Date

    public init(
        workspaceID: UUID,
        fallback: MissingDisplayFallback,
        results: [RuleResult],
        startedAt: Date,
        finishedAt: Date
    ) {
        self.workspaceID = workspaceID
        self.fallback = fallback
        self.results = results
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    public var placedCount: Int {
        results.filter(\.outcome.isPlaced).count
    }

    public var redirectedCount: Int {
        results.filter(\.outcome.isRedirected).count
    }

    /// The one-line result shown on the workspace card (spec §3.2).
    public var summary: String {
        RestoreSummary.text(for: self)
    }
}

/// Which display a rule's window goes to.
public struct PlacementTarget: Equatable, Sendable {
    public var display: DisplaySnapshot
    /// `true` when the saved display is missing and the fallback display is used instead.
    public var redirected: Bool

    public init(display: DisplaySnapshot, redirected: Bool) {
        self.display = display
        self.redirected = redirected
    }
}

public enum PlacementPlanner {
    /// The saved display when it is connected, otherwise the fallback (spec §3.4, §6.4 step 4).
    /// `nil` when the window should be left alone.
    public static func target(
        for rule: WindowRule,
        displays: [DisplaySnapshot],
        fallback: MissingDisplayFallback
    ) -> PlacementTarget? {
        if let saved = displays.first(where: { $0.uuid == rule.displayUUID }) {
            return PlacementTarget(display: saved, redirected: false)
        }
        let replacement: DisplaySnapshot?
        switch fallback {
        case .mainDisplay:
            replacement = displays.first(where: \.isMain) ?? displays.first
        case .largestDisplay:
            replacement = largest(of: displays)
        case .skip:
            replacement = nil
        }
        return replacement.map { PlacementTarget(display: $0, redirected: true) }
    }

    /// The display with the largest area; the main display wins ties.
    public static func largest(of displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        displays.max { lhs, rhs in
            let lhsArea = lhs.frame.width * lhs.frame.height
            let rhsArea = rhs.frame.width * rhs.frame.height
            if lhsArea != rhsArea {
                return lhsArea < rhsArea
            }
            return !lhs.isMain && rhs.isMain
        }
    }
}
