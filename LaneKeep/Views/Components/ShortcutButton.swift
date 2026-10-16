import KeyboardShortcuts
import SwiftUI

/// A keyboard shortcut shown as a key cap, as in the mock. Clicking it opens a recorder to change
/// or remove the shortcut.
struct ShortcutButton: View {
    /// What the shortcut does, e.g. 「このワークスペースを復元」.
    let title: String
    /// The current shortcut ("⌃⌥1"), or `nil` when none is set.
    let text: String?
    let name: KeyboardShortcuts.Name?
    let onChange: () -> Void

    @State private var isEditing = false
    @State private var isHovering = false

    var body: some View {
        Button {
            isEditing = true
        } label: {
            KeyCap(text: text ?? "なし", isPlaceholder: text == nil, isHighlighted: isHovering || isEditing)
        }
        .buttonStyle(.plain)
        .disabled(name == nil)
        .onHover { isHovering = $0 }
        .help("クリックして変更")
        .accessibilityLabel(title)
        .accessibilityValue(text ?? "なし")
        .accessibilityHint("ショートカットを変更します")
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            if let name {
                ShortcutEditor(title: title, name: name, onChange: onChange)
            }
        }
    }
}

private struct ShortcutEditor: View {
    let title: String
    let name: KeyboardShortcuts.Name
    let onChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .laneText(13, .semibold)
                .foregroundStyle(Theme.ink)
            KeyboardShortcuts.Recorder(for: name, onChange: { _ in onChange() })
            HintText("枠を押してから、新しいキーの組み合わせを押してください。⌫ で削除、esc で取り消します。")
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
    }
}
