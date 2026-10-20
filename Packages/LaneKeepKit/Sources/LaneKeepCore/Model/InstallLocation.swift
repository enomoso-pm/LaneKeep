import Foundation

/// Where the running app is, as far as the accessibility permission is concerned.
///
/// Opened straight from the disk image, LaneKeep runs from a read-only volume, or, when the image
/// was downloaded, macOS runs it from a random read-only copy instead (App Translocation). From
/// there the permission prompt may not show and the permission may not stick, and the login item
/// would point to a place that is gone once the image is ejected. So the app asks to be moved to
/// an Applications folder before it asks for the permission.
public enum InstallLocation: Equatable, Sendable {
    /// In /Applications or ~/Applications.
    case applications
    /// Run by macOS from a random read-only copy, because it was opened where it was downloaded.
    case translocated
    /// Straight from the disk image, or another read-only volume.
    case diskImage
    /// Anywhere else (Downloads, the desktop…): this works, it is just not where apps usually are.
    case elsewhere

    /// Whether to ask the user to move the app first.
    public var needsMove: Bool {
        self == .translocated || self == .diskImage
    }

    /// - Parameters:
    ///   - bundlePath: The path of the running app bundle.
    ///   - homeDirectory: The user's home folder, for ~/Applications.
    ///   - isOnReadOnlyVolume: Whether the bundle is on a read-only volume.
    public static func classify(bundlePath: String, homeDirectory: String, isOnReadOnlyVolume: Bool) -> InstallLocation {
        if bundlePath.contains("/AppTranslocation/") {
            return .translocated
        }
        if isOnReadOnlyVolume {
            return .diskImage
        }
        let home = homeDirectory.hasSuffix("/") ? String(homeDirectory.dropLast()) : homeDirectory
        if bundlePath.hasPrefix("/Applications/") || bundlePath.hasPrefix(home + "/Applications/") {
            return .applications
        }
        return .elsewhere
    }
}
