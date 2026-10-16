import AppKit
import SwiftUI

/// Reports whether the window that hosts a SwiftUI view is on screen.
///
/// The menu bar window is shown and hidden rather than created and destroyed, so `onAppear`
/// alone does not say when the user opened it. Occlusion changes do.
struct WindowVisibilityReader: NSViewRepresentable {
    var onChange: (_ isVisible: Bool, _ window: NSWindow) -> Void

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: ObservingView, context: Context) {
        nsView.onChange = onChange
    }

    final class ObservingView: NSView {
        var onChange: ((Bool, NSWindow) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var lastReported: Bool?

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
            let visible = !closing && window.isVisible && window.occlusionState.contains(.visible)
            guard visible != lastReported else { return }
            lastReported = visible
            onChange?(visible, window)
        }
    }
}
