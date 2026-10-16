import SwiftUI

/// LaneKeep: remembers where your windows go for each display setup and puts them back — with one
/// click, a shortcut, or automatically when the displays are connected.
@main
struct LaneKeepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverRootView()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The status item: the brand glyph, with a dot while the permission is missing.
private struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Image(nsImage: model.isAccessibilityGranted ? MenuBarIcon.normal : MenuBarIcon.attention)
            .accessibilityLabel("LaneKeep")
    }
}
