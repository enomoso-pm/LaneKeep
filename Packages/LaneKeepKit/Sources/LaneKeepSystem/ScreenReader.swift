#if canImport(AppKit)
import AppKit
import ApplicationServices
import LaneKeepCore

/// Reads the connected displays (spec §6.2).
@MainActor
public enum ScreenReader {
    /// The displays connected right now, the main display (`NSScreen.screens.first`) first.
    public static func currentDisplays() -> [DisplaySnapshot] {
        let screens = NSScreen.screens
        guard let mainScreen = screens.first else {
            return []
        }
        let entries: [(screen: NSScreen, displayID: CGDirectDisplayID, uuid: String)] = screens.compactMap { screen in
            guard let displayID = displayID(of: screen) else { return nil }
            return (screen, displayID, displayUUID(displayID) ?? "display-\(displayID)")
        }
        let identifiers = DisplayIdentity.uniqueIdentifiers(
            rawUUIDs: entries.map { $0.uuid },
            frames: entries.map { $0.screen.frame }
        )
        return zip(entries, identifiers).map { entry, identifier in
            DisplaySnapshot(
                uuid: identifier,
                name: entry.screen.localizedName,
                frame: entry.screen.frame,
                visibleFrame: entry.screen.visibleFrame,
                isMain: entry.screen == mainScreen,
                isBuiltin: CGDisplayIsBuiltin(entry.displayID) != 0
            )
        }
    }

    public static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    /// The UUID macOS derives from vendor, model and serial number. Unlike the display ID it stays
    /// the same when the display is reconnected or plugged into another port.
    public nonisolated static func displayUUID(_ displayID: CGDirectDisplayID) -> String? {
        guard
            let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
            let string = CFUUIDCreateString(nil, uuid)
        else {
            return nil
        }
        return string as String
    }
}
#endif
