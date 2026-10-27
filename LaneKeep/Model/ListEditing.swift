import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import LaneKeepCore

/// What the menu bar window is changing in place (spec §3.2): the name of a workspace, after a
/// double-click on it, or its restore shortcut, after a click on its key.
enum ListEditing: Equatable {
    case name(UUID)
    case shortcut(UUID)
}

/// Watches the menu bar window while a workspace is changed in its list.
///
/// A click that does not start in the name field ends the change, as clicking elsewhere ends
/// renaming a file in the Finder. While a shortcut is recorded, every key press goes to the model
/// instead of the window, and the global shortcuts are off, so that pressing the shortcut of
/// another workspace records it rather than restoring that workspace.
///
/// The shortcut is recorded here instead of with KeyboardShortcuts' recorder, which the settings
/// use: that recorder reports a key combination that macOS or the app's menu already uses with an
/// alert sheet on its window, and the menu bar window is a panel that is not made for sheets.
/// `ShortcutAvailability` makes the same checks, and the card says what is wrong.
@MainActor
final class ListEditingMonitor {
    private var monitors: [Any] = []
    private var pausedShortcuts: [KeyboardShortcuts.Name] = []
    private var clickStartedOutsideTextField = false

    /// Calls `onClickOutside` after a click in `window` that did not start in a text field, once
    /// the click has done its own work. A right click calls it at once, before its menu opens.
    func watchClicks(in window: NSWindow?, onClickOutside: @escaping @MainActor () -> Void) {
        add(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown]) { [weak self, weak window] event in
            MainActor.assumeIsolated {
                guard let self, let window, event.window === window else { return }
                switch event.type {
                case .leftMouseDown:
                    self.clickStartedOutsideTextField = !Self.isInTextField(event, in: window)
                case .leftMouseUp:
                    guard self.clickStartedOutsideTextField else { return }
                    self.clickStartedOutsideTextField = false
                    // A button that starts another change runs first.
                    Task { @MainActor in
                        onClickOutside()
                    }
                case .rightMouseDown:
                    if !Self.isInTextField(event, in: window) {
                        onClickOutside()
                    }
                default:
                    break
                }
            }
            return event
        })
    }

    /// Calls `onEscape` for esc in `window`, except while an input method is composing text, where
    /// esc belongs to the input method.
    func watchEscape(in window: NSWindow?, onEscape: @escaping @MainActor () -> Void) {
        add(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard
                    let window,
                    event.window === window,
                    event.keyCode == UInt16(kVK_Escape),
                    Self.modifiers(of: event).isEmpty,
                    !((window.firstResponder as? NSTextView)?.hasMarkedText() ?? false)
                else {
                    return false
                }
                onEscape()
                return true
            }
            return handled ? nil : event
        })
    }

    /// Sends every key press in `window` to `onKey` instead of the window, with the global
    /// `shortcuts` off until `stop()`.
    func recordKeys(
        in window: NSWindow?,
        pausing shortcuts: [KeyboardShortcuts.Name],
        onKey: @escaping @MainActor (NSEvent) -> Void
    ) {
        add(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let window, event.window === window else { return false }
                onKey(event)
                return true
            }
            return handled ? nil : event
        })
        KeyboardShortcuts.disable(shortcuts)
        pausedShortcuts += shortcuts
    }

    /// Stops watching and turns the global shortcuts back on.
    func stop() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
        clickStartedOutsideTextField = false
        if !pausedShortcuts.isEmpty {
            KeyboardShortcuts.enable(pausedShortcuts)
            pausedShortcuts.removeAll()
        }
    }

    private func add(_ monitor: Any?) {
        if let monitor {
            monitors.append(monitor)
        }
    }

    /// Whether the click is on a text field or the text being edited in it.
    private static func isInTextField(_ event: NSEvent, in window: NSWindow) -> Bool {
        var view = window.contentView?.hitTest(event.locationInWindow)
        while let current = view {
            if current is NSTextField || current is NSTextView {
                return true
            }
            view = current.superview
        }
        return false
    }

    // MARK: - Key presses

    static func key(of event: NSEvent) -> ShortcutKeyPress.Key {
        if event.keyCode == UInt16(kVK_Escape) {
            return .escape
        }
        switch event.specialKey {
        case .tab?:
            return .tab
        case .delete?, .deleteForward?, .backspace?:
            return .delete
        case let key? where (NSEvent.SpecialKey.f1.rawValue...NSEvent.SpecialKey.f35.rawValue).contains(key.rawValue):
            return .function
        default:
            return .other
        }
    }

    static func modifiers(of event: NSEvent) -> ShortcutKeyPress.Modifiers {
        let flags = event.modifierFlags
        var modifiers: ShortcutKeyPress.Modifiers = []
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        return modifiers
    }
}

/// Whether a key combination can become a restore shortcut: the checks of KeyboardShortcuts'
/// recorder, put into a sentence for the card instead of an alert.
@MainActor
enum ShortcutAvailability {
    static func problem(with shortcut: KeyboardShortcuts.Shortcut, pressedWith event: NSEvent) -> String? {
        if isTakenBySystem(shortcut) {
            return "\(shortcut) は macOS のショートカットに使われています。ほかのキーを押してください"
        }
        if let title = menuWindowKeys[shortcut] ?? NSApp.mainMenu.flatMap({ menuItem(matching: event, in: $0)?.title }) {
            return "\(shortcut) は「\(title)」に使われています。ほかのキーを押してください"
        }
        return nil
    }

    /// The keys of the menu bar window itself, which the user sees right there while recording
    /// (see `WorkspaceListScreen`). As a global shortcut, ⌘Q would restore a workspace in every app.
    private static let menuWindowKeys: [KeyboardShortcuts.Shortcut: String] = [
        KeyboardShortcuts.Shortcut(.q, modifiers: .command): "終了",
        KeyboardShortcuts.Shortcut(.comma, modifiers: .command): "設定を開く"
    ]

    /// The shortcuts turned on in System Settings › Keyboard › Keyboard Shortcuts. F12 on its own
    /// is left out, as KeyboardShortcuts does.
    private static func isTakenBySystem(_ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        guard shortcut != KeyboardShortcuts.Shortcut(.f12) else { return false }
        var hotKeys: Unmanaged<CFArray>?
        guard
            CopySymbolicHotKeys(&hotKeys) == noErr,
            let list = hotKeys?.takeRetainedValue() as? [[String: Any]]
        else {
            return false
        }
        return list.contains { hotKey in
            guard
                (hotKey[kHISymbolicHotKeyEnabled] as? Bool) == true,
                let keyCode = hotKey[kHISymbolicHotKeyCode] as? Int,
                let modifiers = hotKey[kHISymbolicHotKeyModifiers] as? Int
            else {
                return false
            }
            return KeyboardShortcuts.Shortcut(carbonKeyCode: keyCode, carbonModifiers: modifiers) == shortcut
        }
    }

    /// An item of the app's own menu with the same key equivalent. LaneKeep never shows that menu,
    /// but its key equivalents work while LaneKeep is in front.
    private static func menuItem(matching event: NSEvent, in menu: NSMenu) -> NSMenuItem? {
        let relevant: NSEvent.ModifierFlags = [.control, .option, .command, .shift]
        let character = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let modifiers = event.modifierFlags.intersection(relevant)
        for item in menu.items {
            var equivalent = item.keyEquivalent
            var mask = item.keyEquivalentModifierMask.intersection(relevant)
            // An upper-case key equivalent stands for the key with ⇧.
            if equivalent.lowercased() != equivalent {
                equivalent = equivalent.lowercased()
                mask.insert(.shift)
            }
            if !equivalent.isEmpty, equivalent == character, mask == modifiers {
                return item
            }
            if let submenu = item.submenu, let found = menuItem(matching: event, in: submenu) {
                return found
            }
        }
        return nil
    }
}
