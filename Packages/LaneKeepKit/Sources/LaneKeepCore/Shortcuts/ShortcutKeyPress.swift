import Foundation

/// What a key press means while a new restore shortcut is recorded in the menu bar window
/// (spec §3.2). The rules are those of the shortcut recorder in the settings: esc and tab stop
/// recording, ⌫ or ⌦ removes the shortcut, and a key needs ⌃, ⌥ or ⌘ unless it is a function key.
public enum ShortcutKeyPress: Equatable, Sendable {
    /// Stop recording and keep the shortcut as it is.
    case cancel
    /// Remove the shortcut.
    case remove
    /// Not a shortcut on its own: ⌃, ⌥ or ⌘ has to be held too.
    case needsModifier
    /// A key combination to use as the shortcut.
    case shortcut

    /// The keys that mean something of their own while recording.
    public enum Key: Equatable, Sendable {
        case escape
        case tab
        /// ⌫ or ⌦.
        case delete
        /// F1, F2… which work without a modifier.
        case function
        case other
    }

    /// The modifier keys held down.
    public struct Modifiers: OptionSet, Equatable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let command = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    public static func interpret(_ key: Key, modifiers: Modifiers) -> ShortcutKeyPress {
        if modifiers.isEmpty {
            switch key {
            case .escape, .tab:
                return .cancel
            case .delete:
                return .remove
            case .function, .other:
                break
            }
        }
        // ⇧ alone does not make a shortcut: with it, a key only types another character.
        if key == .function || !modifiers.subtracting(.shift).isEmpty {
            return .shortcut
        }
        return .needsModifier
    }
}
