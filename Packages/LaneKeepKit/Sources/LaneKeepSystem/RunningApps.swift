#if canImport(AppKit)
import AppKit
import CoreGraphics
import os

/// A running app, copied out of `NSRunningApplication` so it can cross threads.
public struct RunningAppInfo: Equatable, Sendable, Identifiable {
    public var pid: pid_t
    public var bundleID: String
    public var name: String
    public var isHidden: Bool
    public var bundleURL: URL?

    public var id: pid_t { pid }

    public init(pid: pid_t, bundleID: String, name: String, isHidden: Bool, bundleURL: URL?) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.isHidden = isHidden
        self.bundleURL = bundleURL
    }
}

@MainActor
public enum RunningApps {
    /// Running apps with a Dock icon (`activationPolicy == .regular`, spec §6.1), without
    /// LaneKeep itself.
    public static func regularApps() -> [RunningAppInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard
                app.activationPolicy == .regular,
                !app.isTerminated,
                app.processIdentifier != ownPID,
                let bundleID = app.bundleIdentifier
            else {
                return nil
            }
            return RunningAppInfo(
                pid: app.processIdentifier,
                bundleID: bundleID,
                name: app.localizedName ?? bundleID,
                isHidden: app.isHidden,
                bundleURL: app.bundleURL
            )
        }
    }

    /// The running instance of an app, preferring one with a Dock icon.
    public static func application(bundleID: String) -> NSRunningApplication? {
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).filter { !$0.isTerminated }
        return instances.first { $0.activationPolicy == .regular } ?? instances.first
    }
}

@MainActor
enum AppLauncher {
    /// Asks Launch Services to open the app. Returns `false` when it is not installed.
    ///
    /// For a running app this works like clicking its Dock icon, which makes most apps open a
    /// window when they have none.
    static func open(bundleID: String, activate: Bool) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        configuration.addsToRecentItems = false
        // No completion handler: the restore engine watches for the windows itself.
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
        return true
    }
}

/// Asks the window server about windows on all desktops (Spaces), which the Accessibility API
/// cannot see. Needs no permission: window titles are not read.
enum WindowServerProbe {
    /// Whether the process has a normal window anywhere, including other desktops.
    static func hasWindows(pid: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, CGWindowID(0)) as? [[String: Any]] else {
            // When in doubt, assume it has windows so that no window is opened unasked.
            return true
        }
        return list.contains { info in
            guard
                info["kCGWindowOwnerPID"] as? pid_t == pid,
                (info["kCGWindowLayer"] as? Int ?? 0) == 0,
                (info["kCGWindowAlpha"] as? Double ?? 1) > 0,
                let boundsDictionary = info["kCGWindowBounds"] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else {
                return false
            }
            return bounds.width >= 50 && bounds.height >= 50
        }
    }
}

enum Log {
    static let restore = Logger(subsystem: "LaneKeep", category: "restore")
    static let capture = Logger(subsystem: "LaneKeep", category: "capture")
}
#endif
