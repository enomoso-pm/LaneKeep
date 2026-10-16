import SwiftUI

/// The content of the menu bar window (spec §4, screens 1–3), 360 pt wide.
struct PopoverRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .frame(width: Theme.Size.popoverWidth, height: height)
            .background(Theme.window)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: screen)
            .background(
                WindowVisibilityReader { isVisible, window in
                    model.popoverVisibilityChanged(isVisible, window: window)
                }
            )
    }

    private enum Screen: Equatable {
        case onboarding
        case list
        case capture
    }

    private var screen: Screen {
        if model.showsOnboarding {
            return .onboarding
        }
        return model.popoverRoute == .capture && model.captureSession != nil ? .capture : .list
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .onboarding:
            OnboardingScreen()
                .transition(.opacity)
        case .capture:
            if let session = model.captureSession {
                CaptureScreen(
                    session: session,
                    onCancel: { model.cancelCapture() },
                    onSave: { model.saveCapture(session) }
                )
                .transition(.opacity)
            }
        case .list:
            WorkspaceListScreen()
                .transition(.opacity)
        }
    }

    /// The heights of the mock, limited to the screen the window is on.
    private var height: CGFloat {
        let preferred: CGFloat = switch screen {
        case .onboarding: 560
        case .list: 620
        case .capture: 720
        }
        return min(preferred, max(420, model.availableScreenHeight - 24))
    }
}
