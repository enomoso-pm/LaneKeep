import AppKit
import SwiftUI

/// Owns the settings window (spec §4, screen 4: a regular window with a sidebar).
///
/// The window is created on demand with AppKit instead of a SwiftUI `Window` scene: a menu bar
/// app must not open it at launch or restore it from a previous session, and it has to be brought
/// in front of other apps explicitly because LaneKeep has no Dock icon.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(model: AppModel) {
        let window = self.window ?? makeWindow(model: model)
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    private func makeWindow(model: AppModel) -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsRootView().environment(model))
        hosting.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: hosting)
        window.title = "LaneKeep 設定"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.setContentSize(NSSize(width: 1120, height: 860))
        window.center()
        window.setFrameAutosaveName("LaneKeepSettingsWindow")
        return window
    }
}
