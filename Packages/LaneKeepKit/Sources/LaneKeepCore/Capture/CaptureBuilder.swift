import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A window that is on screen right now (read through the Accessibility API).
public struct WindowSnapshot: Equatable, Sendable, Identifiable {
    public var pid: Int32
    public var bundleID: String
    public var appName: String
    public var title: String
    /// Accessibility coordinates (origin at the top-left of the main display).
    public var frame: CGRect
    /// Position among the app's standard windows (minimized ones included).
    public var indexInApp: Int
    public var isMinimized: Bool
    public var isFullScreen: Bool

    public var id: String { "\(pid):\(indexInApp)" }

    public init(
        pid: Int32,
        bundleID: String,
        appName: String,
        title: String,
        frame: CGRect,
        indexInApp: Int,
        isMinimized: Bool = false,
        isFullScreen: Bool = false
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.indexInApp = indexInApp
        self.isMinimized = isMinimized
        self.isFullScreen = isFullScreen
    }
}

/// A window that can be saved, with the display it belongs to.
public struct CaptureCandidate: Equatable, Sendable, Identifiable {
    public var window: WindowSnapshot
    public var displayUUID: String
    /// Relative to the display's visible frame (top-left origin).
    public var relativeFrame: CGRect

    public var id: String { window.id }

    public init(window: WindowSnapshot, displayUUID: String, relativeFrame: CGRect) {
        self.window = window
        self.displayUUID = displayUUID
        self.relativeFrame = relativeFrame
    }
}

/// Builds workspaces from the windows that are on screen (spec §3.1).
public enum CaptureBuilder {
    /// Windows smaller than this (in points) are helper windows, not something to lay out.
    public static let minimumWindowSide: CGFloat = 40

    /// The windows that can be saved, sorted by display (blue, orange, gray) and then in reading
    /// order within each display.
    ///
    /// Leaves out minimized and full-screen windows, windows of excluded apps, tiny windows and
    /// windows that are not on any display. Each window belongs to the display that contains its
    /// center (spec §6.1); a window that hangs off its display is recorded as if moved inside it.
    public static func candidates(
        from windows: [WindowSnapshot],
        displays: [DisplaySnapshot],
        excludedBundleIDs: Set<String> = []
    ) -> [CaptureCandidate] {
        guard let primaryHeight = DisplayGeometry.primaryHeight(of: displays) else {
            return []
        }
        let roles = DisplayRoles.assign(displays)
        let displayOrder = Dictionary(
            DisplayRoles.ordered(displays).enumerated().map { ($0.element.uuid, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        let candidates: [CaptureCandidate] = windows.compactMap { window in
            guard
                !window.isMinimized,
                !window.isFullScreen,
                !excludedBundleIDs.contains(window.bundleID),
                window.frame.width >= minimumWindowSide,
                window.frame.height >= minimumWindowSide,
                let display = DisplayGeometry.display(
                    forAccessibilityRect: window.frame,
                    among: displays,
                    primaryHeight: primaryHeight
                )
            else {
                return nil
            }
            let visibleFrame = CoordinateConverter.accessibilityRect(fromAppKit: display.visibleFrame, primaryHeight: primaryHeight)
            return CaptureCandidate(
                window: window,
                displayUUID: display.uuid,
                relativeFrame: RelativeGeometry.fittedToUnit(RelativeGeometry.relativeFrame(of: window.frame, in: visibleFrame))
            )
        }

        return candidates.sorted { lhs, rhs in
            let lhsKey = sortKey(lhs, roles: roles, displayOrder: displayOrder)
            let rhsKey = sortKey(rhs, roles: roles, displayOrder: displayOrder)
            return lhsKey < rhsKey
        }
    }

    /// Rules for the selected windows, in the given order. The saved `index` is the window's
    /// position among all windows of its app, so leaving a window out does not shift the others.
    public static func rules(from candidates: [CaptureCandidate], launchIfClosed: Bool) -> [WindowRule] {
        candidates.map { candidate in
            WindowRule(
                bundleID: candidate.window.bundleID,
                appName: candidate.window.appName,
                index: candidate.window.indexInApp,
                displayUUID: candidate.displayUUID,
                relativeFrame: candidate.relativeFrame,
                launchIfClosed: launchIfClosed
            )
        }
    }

    /// Rules for an overwrite ("今の配置で上書き"): positions come from the selected windows, while
    /// the title markers and launch options of the rules they replace are kept.
    public static func rules(
        from candidates: [CaptureCandidate],
        replacing previous: [WindowRule],
        launchIfClosedForNewWindows: Bool
    ) -> [WindowRule] {
        let matches = matchPrevious(previous, to: candidates)
        return candidates.map { candidate in
            var rule = WindowRule(
                bundleID: candidate.window.bundleID,
                appName: candidate.window.appName,
                index: candidate.window.indexInApp,
                displayUUID: candidate.displayUUID,
                relativeFrame: candidate.relativeFrame,
                launchIfClosed: launchIfClosedForNewWindows
            )
            if let old = matches[candidate.id] {
                rule.id = old.id
                rule.titleContains = old.titleContains
                rule.launchIfClosed = old.launchIfClosed
            }
            return rule
        }
    }

    /// For each candidate, the existing rule that describes the same window (if any).
    public static func matchPrevious(_ previous: [WindowRule], to candidates: [CaptureCandidate]) -> [String: WindowRule] {
        var result: [String: WindowRule] = [:]
        let rulesByApp = Dictionary(grouping: previous, by: \.bundleID)
        let candidatesByApp = Dictionary(grouping: candidates, by: \.window.bundleID)
        for (bundleID, rules) in rulesByApp {
            guard let appCandidates = candidatesByApp[bundleID]?.sorted(by: { $0.window.indexInApp < $1.window.indexInApp }) else {
                continue
            }
            let windows = appCandidates.map { candidate in
                MatchableWindow(
                    title: candidate.window.title,
                    position: candidate.window.indexInApp,
                    location: WindowLocation(displayUUID: candidate.displayUUID, relativeFrame: candidate.relativeFrame)
                )
            }
            for (ruleIndex, windowIndex) in WindowMatcher.assign(rules: rules, windows: windows).enumerated() {
                if let windowIndex {
                    result[appCandidates[windowIndex].id] = rules[ruleIndex]
                }
            }
        }
        return result
    }

    public static func workspace(
        name: String,
        color: WorkspaceColor,
        icon: WorkspaceIcon,
        candidates: [CaptureCandidate],
        displays: [DisplaySnapshot],
        launchIfClosed: Bool,
        autoRestoreOnConnect: Bool,
        now: Date = Date()
    ) -> Workspace {
        Workspace(
            name: normalizedName(name, fallback: suggestedName(for: displays, existingNames: [])),
            color: color,
            icon: icon,
            displays: DisplayRoles.ordered(displays).map(DisplayInfo.init),
            windows: rules(from: candidates, launchIfClosed: launchIfClosed),
            autoRestoreOnConnect: autoRestoreOnConnect,
            autoRestoreOnWake: false,
            lastUsedAt: now
        )
    }

    /// A default name: "ノートPCのみ" when only the built-in display is connected, otherwise the
    /// first free "ワークスペースN".
    public static func suggestedName(for displays: [DisplaySnapshot], existingNames: [String]) -> String {
        let existing = Set(existingNames)
        if !displays.isEmpty, displays.allSatisfy(\.isBuiltin), !existing.contains("ノートPCのみ") {
            return "ノートPCのみ"
        }
        var number = existingNames.count + 1
        while existing.contains("ワークスペース\(number)") {
            number += 1
        }
        return "ワークスペース\(number)"
    }

    public static func suggestedIcon(for displays: [DisplaySnapshot]) -> WorkspaceIcon {
        !displays.isEmpty && displays.allSatisfy(\.isBuiltin) ? .laptop : .display
    }

    /// The first color no other workspace uses yet.
    public static func suggestedColor(existing: [WorkspaceColor]) -> WorkspaceColor {
        WorkspaceColor.allCases.first { !existing.contains($0) } ?? .blue
    }

    public static func normalizedName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private struct SortKey: Comparable {
        var role: Int
        var display: Int
        var row: Int
        var x: CGFloat
        var y: CGFloat
        var app: String
        var index: Int

        static func < (lhs: SortKey, rhs: SortKey) -> Bool {
            if (lhs.role, lhs.display, lhs.row) != (rhs.role, rhs.display, rhs.row) {
                return (lhs.role, lhs.display, lhs.row) < (rhs.role, rhs.display, rhs.row)
            }
            return (lhs.x, lhs.y, lhs.app, lhs.index) < (rhs.x, rhs.y, rhs.app, rhs.index)
        }
    }

    private static func sortKey(
        _ candidate: CaptureCandidate,
        roles: [String: DisplayRole],
        displayOrder: [String: Int]
    ) -> SortKey {
        SortKey(
            role: (roles[candidate.displayUUID] ?? .tertiary).rawValue,
            display: displayOrder[candidate.displayUUID] ?? .max,
            // Windows whose top edges are within 10% of the display height count as one row.
            row: Int((candidate.relativeFrame.minY * 10).rounded()),
            x: candidate.relativeFrame.minX,
            y: candidate.relativeFrame.minY,
            app: candidate.window.appName,
            index: candidate.window.indexInApp
        )
    }
}
