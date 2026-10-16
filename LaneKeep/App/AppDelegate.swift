import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if SnapshotRenderer.isRequested {
            SnapshotRenderer.renderAndQuit()
            return
        }
        #endif
        // Two copies would both restore windows when displays change.
        if isAnotherInstanceRunning() {
            NSApp.terminate(nil)
            return
        }
        AppModel.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.flushPendingSaves()
    }

    /// Opening LaneKeep again (from Finder or Spotlight) while it runs shows the settings, since
    /// there is no Dock icon to click.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.openSettings()
        return false
    }

    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0.processIdentifier != ownPID && !$0.isTerminated }
    }
}
