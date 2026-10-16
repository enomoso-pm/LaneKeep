import Foundation
import KeyboardShortcuts
import LaneKeepCore

/// Global keyboard shortcuts (spec §3.2, §3.5): one to open the menu (⌃⌥L by default) and one per
/// workspace (⌃⌥1, ⌃⌥2…).
@MainActor
final class ShortcutCenter {
    static let toggleMenu = KeyboardShortcuts.Name("toggleMenu")
    static let defaultMenuShortcut = KeyboardShortcuts.Shortcut(.l, modifiers: [.control, .option])

    /// Posted by KeyboardShortcuts whenever a shortcut is set or removed.
    static let didChangeNotification = Notification.Name("KeyboardShortcuts_shortcutByNameDidChange")

    private static let digitKeys: [Int: KeyboardShortcuts.Key] = [
        1: .one, 2: .two, 3: .three, 4: .four, 5: .five, 6: .six, 7: .seven, 8: .eight, 9: .nine
    ]
    private static let menuShortcutAssignedKey = "LaneKeep.didAssignInitialMenuShortcut"

    var onToggleMenu: (() -> Void)?
    var onRestore: ((UUID) -> Void)?

    /// Gives the menu its default shortcut on first launch. Afterwards the user's choice
    /// (including "none") is kept.
    func prepareMenuShortcut() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.menuShortcutAssignedKey) else { return }
        defaults.set(true, forKey: Self.menuShortcutAssignedKey)
        if KeyboardShortcuts.getShortcut(for: Self.toggleMenu) == nil {
            KeyboardShortcuts.setShortcut(Self.defaultMenuShortcut, for: Self.toggleMenu)
        }
    }

    /// (Re)registers the handlers. Call whenever workspaces are added or removed.
    func registerHandlers(for workspaces: [Workspace]) {
        KeyboardShortcuts.removeAllHandlers()
        KeyboardShortcuts.onKeyUp(for: Self.toggleMenu) { [weak self] in
            self?.onToggleMenu?()
        }
        for workspace in workspaces {
            guard let name = Self.name(for: workspace) else { continue }
            let id = workspace.id
            KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
                self?.onRestore?(id)
            }
        }
    }

    static func name(for workspace: Workspace) -> KeyboardShortcuts.Name? {
        workspace.shortcut.map { KeyboardShortcuts.Name($0) }
    }

    /// Gives a workspace a shortcut name and, if it has no key yet, the first free ⌃⌥digit.
    func assignDefaultShortcut(to workspace: inout Workspace, others: [Workspace]) {
        if workspace.shortcut == nil {
            workspace.shortcut = ShortcutSlots.shortcutName(for: workspace.id)
        }
        guard let name = Self.name(for: workspace), KeyboardShortcuts.getShortcut(for: name) == nil else {
            return
        }
        var taken = Set(others.compactMap { other in
            Self.name(for: other).flatMap { KeyboardShortcuts.getShortcut(for: $0) }
        })
        if let menu = KeyboardShortcuts.getShortcut(for: Self.toggleMenu) {
            taken.insert(menu)
        }
        for digit in ShortcutSlots.digits {
            guard let key = Self.digitKeys[digit] else { continue }
            let shortcut = KeyboardShortcuts.Shortcut(key, modifiers: [.control, .option])
            if !taken.contains(shortcut) {
                KeyboardShortcuts.setShortcut(shortcut, for: name)
                return
            }
        }
    }

    func removeShortcut(of workspace: Workspace) {
        if let name = Self.name(for: workspace) {
            KeyboardShortcuts.setShortcut(nil, for: name)
        }
    }

    /// "⌃⌥1", or `nil` when no shortcut is set.
    func text(for workspace: Workspace) -> String? {
        Self.name(for: workspace).flatMap { KeyboardShortcuts.getShortcut(for: $0)?.description }
    }

    var menuShortcutText: String? {
        KeyboardShortcuts.getShortcut(for: Self.toggleMenu)?.description
    }

    /// After the user recorded `name`, removes the same key combination from every other action
    /// so that one shortcut never does two things. Returns a sentence describing what was removed.
    func resolveConflicts(after name: KeyboardShortcuts.Name, workspaces: [Workspace]) -> String? {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return nil }
        var removedFrom: [String] = []
        if name != Self.toggleMenu, KeyboardShortcuts.getShortcut(for: Self.toggleMenu) == shortcut {
            KeyboardShortcuts.setShortcut(nil, for: Self.toggleMenu)
            removedFrom.append("「メニューを開く」")
        }
        for workspace in workspaces {
            guard let other = Self.name(for: workspace), other != name else { continue }
            if KeyboardShortcuts.getShortcut(for: other) == shortcut {
                KeyboardShortcuts.setShortcut(nil, for: other)
                removedFrom.append("「\(workspace.name)」")
            }
        }
        guard !removedFrom.isEmpty else { return nil }
        return "\(shortcut.description) を\(removedFrom.joined(separator: "、"))から外しました"
    }
}
