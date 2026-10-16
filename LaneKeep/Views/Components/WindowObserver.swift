import AppKit
import SwiftUI

/// Whether a window is shown.
enum WindowVisibility: Equatable {
    /// On screen and at least partly visible.
    case shown
    /// Still open, but nothing of it can be seen, e.g. because the display is asleep.
    case covered
    /// Closed or ordered out.
    case hidden
}

/// Reports whether the window that hosts a SwiftUI view is on screen.
///
/// The menu bar window is shown and hidden rather than created and destroyed, so `onAppear`
/// alone does not say when the user opened it. Occlusion changes do.
struct WindowVisibilityReader: NSViewRepresentable {
    var onChange: (_ visibility: WindowVisibility, _ window: NSWindow) -> Void

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ObservingView, context: Context) {
        nsView.onChange = onChange
    }

    final class ObservingView: NSView {
        var onChange: ((WindowVisibility, NSWindow) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var lastReported: WindowVisibility?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for observer in observers {
                NotificationCenter.default.removeObserver(observer)
            }
            observers = []
            lastReported = nil
            guard let window else { return }
            let names: [Notification.Name] = [
                NSWindow.didChangeOcclusionStateNotification,
                NSWindow.didBecomeKeyNotification,
                NSWindow.willCloseNotification
            ]
            for name in names {
                observers.append(
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] notification in
                        let closing = notification.name == NSWindow.willCloseNotification
                        MainActor.assumeIsolated {
                            self?.report(closing: closing)
                        }
                    }
                )
            }
            report(closing: false)
        }

        private func report(closing: Bool) {
            guard let window else { return }
            let visibility: WindowVisibility
            if closing || !window.isVisible {
                visibility = .hidden
            } else if window.occlusionState.contains(.visible) {
                visibility = .shown
            } else {
                visibility = .covered
            }
            guard visibility != lastReported else { return }
            lastReported = visibility
            onChange?(visibility, window)
        }
    }
}
