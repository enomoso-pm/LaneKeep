#if canImport(AppKit)
import AppKit
import LaneKeepCore

/// Moves LaneKeep into an Applications folder when it was opened straight from the disk image
/// (see `InstallLocation`).
public enum AppInstaller {
    /// Where the running app is.
    public static var currentLocation: InstallLocation {
        let url = Bundle.main.bundleURL
        let isReadOnly = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        return InstallLocation.classify(
            bundlePath: url.path,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser.path,
            isOnReadOnlyVolume: isReadOnly
        )
    }

    /// Copies the running app into /Applications, or into ~/Applications when /Applications is not
    /// writable (an account that is not an administrator), and returns the copy. An older LaneKeep
    /// there goes to the Trash.
    ///
    /// macOS already let the user open this app, so the quarantine flag is removed from the copy:
    /// with it, macOS would run the moved app from a random read-only copy again.
    public static func copyToApplications() throws -> URL {
        let fileManager = FileManager.default
        let source = Bundle.main.bundleURL
        let systemFolder = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let folder: URL
        if fileManager.isWritableFile(atPath: systemFolder.path) {
            folder = systemFolder
        } else {
            folder = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let destination = folder.appendingPathComponent(source.lastPathComponent, isDirectory: true)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.trashItem(at: destination, resultingItemURL: nil)
        }
        try fileManager.copyItem(at: source, to: destination)
        removeQuarantine(from: destination)
        return destination
    }

    /// Opens the app at `url` once this process has quit, then quits. The new copy would quit at
    /// once while this one runs (only one LaneKeep at a time), so a small shell waits for this
    /// process to end before it opens the copy.
    @MainActor
    public static func relaunch(at url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "while /bin/kill -0 \"$1\" 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$2\"",
            "sh",
            String(ProcessInfo.processInfo.processIdentifier),
            url.path
        ]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func removeQuarantine(from url: URL) {
        let name = "com.apple.quarantine"
        removexattr(url.path, name, XATTR_NOFOLLOW)
        guard let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) else {
            return
        }
        for case let item as URL in items {
            removexattr(item.path, name, XATTR_NOFOLLOW)
        }
    }
}
#endif
