import Testing
@testable import LaneKeepCore

@Suite("Recording a restore shortcut in the menu bar window")
struct ShortcutKeyPressTests {
    private func interpret(_ key: ShortcutKeyPress.Key, _ modifiers: ShortcutKeyPress.Modifiers = []) -> ShortcutKeyPress {
        ShortcutKeyPress.interpret(key, modifiers: modifiers)
    }

    @Test("esc and tab on their own stop recording")
    func cancel() {
        #expect(interpret(.escape) == .cancel)
        #expect(interpret(.tab) == .cancel)
    }

    @Test("⌫ or ⌦ on its own removes the shortcut")
    func remove() {
        #expect(interpret(.delete) == .remove)
    }

    @Test("A key with ⌃, ⌥ or ⌘ becomes the shortcut, also with ⇧")
    func shortcut() {
        #expect(interpret(.other, [.control, .option]) == .shortcut)
        #expect(interpret(.other, .command) == .shortcut)
        #expect(interpret(.other, .option) == .shortcut)
        #expect(interpret(.other, [.command, .shift]) == .shortcut)
    }

    @Test("A key alone or with ⇧ only is not a shortcut")
    func needsModifier() {
        #expect(interpret(.other) == .needsModifier)
        #expect(interpret(.other, .shift) == .needsModifier)
        #expect(interpret(.tab, .shift) == .needsModifier)
        #expect(interpret(.escape, .shift) == .needsModifier)
    }

    @Test("Function keys work without a modifier")
    func functionKeys() {
        #expect(interpret(.function) == .shortcut)
        #expect(interpret(.function, .shift) == .shortcut)
    }

    @Test("esc and ⌫ with a modifier are key combinations like any other")
    func specialKeysWithModifiers() {
        #expect(interpret(.escape, .control) == .shortcut)
        #expect(interpret(.delete, .option) == .shortcut)
    }
}
