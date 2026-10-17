import Testing
@testable import LaneKeepCore

@Suite("Whether a running app without visible windows shows one on some desktop")
struct WindowPresenceTests {
    private func window(
        layer: Int = 0, alpha: Double = 1, width: Double = 707, height: Double = 923, isOrderedIn: Bool?
    ) -> ServerWindow {
        ServerWindow(layer: layer, alpha: alpha, width: width, height: height, isOrderedIn: isOrderedIn)
    }

    @Test("A window shown on another desktop counts, so the app is not asked for another one")
    func shownOnAnotherDesktop() {
        #expect(WindowPresence.showsWindow([window(isOrderedIn: true)]))
    }

    @Test("A window the app keeps after it was closed does not count")
    func keptAfterClosing() {
        // What LINE had after its window was closed (2026-10-17): the hidden main window and thin,
        // equally hidden strips.
        let windows = [window(width: 604, height: 417, isOrderedIn: false)]
            + Array(repeating: window(width: 1920, height: 30, isOrderedIn: false), count: 8)
        #expect(!WindowPresence.showsWindow(windows))
    }

    @Test("One shown window is enough, next to hidden ones")
    func shownAndHidden() {
        #expect(WindowPresence.showsWindow([window(isOrderedIn: false), window(isOrderedIn: true)]))
    }

    @Test("When the window server cannot be asked, a window counts, as before")
    func unknown() {
        #expect(WindowPresence.showsWindow([window(isOrderedIn: nil)]))
    }

    @Test("Strips, other layers and transparent windows never count")
    func notNormalWindows() {
        #expect(!WindowPresence.showsWindow([
            window(width: 1920, height: 30, isOrderedIn: true),
            window(layer: 3, isOrderedIn: true),
            window(alpha: 0, isOrderedIn: true),
        ]))
        #expect(!WindowPresence.showsWindow([]))
    }
}
