#if canImport(AppKit)
import ApplicationServices
import Foundation
import LaneKeepCore

/// Reads the windows that are on screen (spec §6.1).
public enum WindowCatalog {
    /// Standard windows of all regular apps (minimized and full-screen ones included, marked as
    /// such), in app order and Accessibility order within each app.
    ///
    /// Windows on other desktops are not visible to the Accessibility API for most apps (a known
    /// limitation, spec §6.1). The calls run concurrently and off the main thread, so a hanging app
    /// only delays the result by the messaging timeout.
    public static func snapshot() async -> [WindowSnapshot] {
        let apps = await MainActor.run { RunningApps.regularApps() }
        return await withTaskGroup(of: (Int, [WindowSnapshot]).self) { group in
            for (position, app) in apps.enumerated() {
                group.addTask {
                    (position, windows(of: app))
                }
            }
            var byPosition: [Int: [WindowSnapshot]] = [:]
            for await (position, windows) in group {
                byPosition[position] = windows
            }
            return apps.indices.flatMap { byPosition[$0] ?? [] }
        }
    }

    /// The windows of one app.
    public static func windows(of app: RunningAppInfo) -> [WindowSnapshot] {
        let element = AXUIElementCreateApplication(app.pid)
        var snapshots: [WindowSnapshot] = []
        for (index, window) in AXReader.standardWindows(of: element).enumerated() {
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
