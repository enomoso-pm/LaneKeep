#if canImport(AppKit)
import ApplicationServices
import Foundation
import LaneKeepCore
import os

/// Reads the windows that are on screen (spec §6.1).
public enum WindowCatalog {
    /// Standard windows of all regular apps (minimized ones included and marked as such, full-screen
    /// ones left out), in app order and Accessibility order within each app.
    ///
    /// Windows on other desktops are not visible to the Accessibility API for most apps (a known
    /// limitation, spec §6.1). The Accessibility calls run off the main thread, one app after the
    /// other; an app that does not respond only costs the messaging timeout.
    public static func snapshot() async -> [WindowSnapshot] {
        let apps = await MainActor.run { RunningApps.regularApps() }
        return await Task.detached(priority: .userInitiated) {
            var snapshots: [WindowSnapshot] = []
            for app in apps {
                // An app that is busy for a moment gets a second chance.
                if let windows = windows(of: app) ?? retryAfterPause(app) {
                    snapshots += windows
                } else {
                    Log.restore.info("\(app.bundleID, privacy: .public) did not answer; its windows are not listed")
                }
            }
            return snapshots
        }.value
    }

    private static func retryAfterPause(_ app: RunningAppInfo) -> [WindowSnapshot]? {
        Thread.sleep(forTimeInterval: 0.3)
        return windows(of: app)
    }

    /// The windows of one app, or `nil` when it did not answer.
    public static func windows(of app: RunningAppInfo) -> [WindowSnapshot]? {
        let element = AXUIElementCreateApplication(app.pid)
        guard let standardWindows = AXReader.standardWindows(of: element) else {
            return nil
        }
        var snapshots: [WindowSnapshot] = []
        for (index, window) in standardWindows.enumerated() {
            guard let frame = window.frame else { continue }
            snapshots.append(
                WindowSnapshot(
                    pid: app.pid,
                    bundleID: app.bundleID,
                    appName: app.name,
                    title: window.string(AXAttribute.title) ?? "",
                    frame: frame,
                    indexInApp: index,
                    isMinimized: window.bool(AXAttribute.minimized) ?? false,
                    isFullScreen: false
                )
            )
        }
        return snapshots
    }
}
#endif
