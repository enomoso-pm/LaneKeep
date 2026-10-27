import LaneKeepCore
import SwiftUI

/// Screen 1: the connected displays and the saved workspaces.
struct WorkspaceListScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The card the list scrolls to, to show the box for its new shortcut.
    @State private var cardToReveal: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header
            connectedDisplays
                .padding(.horizontal, 12)
            banners
            sectionHeader
            list
            footer
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                LaneIconView(icon: .brand, size: 22)
                Text("LaneKeep")
                    .font(.lane(15, .semibold))
            }
            .foregroundStyle(Theme.ink)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                model.openSettings()
            } label: {
                LaneIconView(icon: .gear, size: 18)
            }
            .buttonStyle(IconButtonStyle())
            .help("設定を開く")
            .accessibilityLabel("設定を開く")
            .keyboardShortcut(",", modifiers: .command)
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 10, trailing: 12))
    }

    private var connectedDisplays: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DisplayGlyph(displays: MapDisplay.from(model.displays))
                VStack(alignment: .leading, spacing: 0) {
                    Text("接続中のディスプレイ")
                        .laneText(12)
                        .foregroundStyle(Theme.sub)
                    Text(model.currentDisplaysText)
                        .laneText(14, .semibold)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            Toggle(isOn: autoRestoreBinding) {
                Text("つないだら自動で復元")
                    .font(.lane(13))
                    .foregroundStyle(Theme.ink2)
            }
            .toggleStyle(LaneSwitchStyle())
            .help("オフにすると、どのワークスペースも自動では復元しません")
        }
        .padding(12)
        .laneBox()
    }

    @ViewBuilder
    private var banners: some View {
        if let problem = model.storageProblem {
            Banner(text: problem, color: Theme.warn) {
                Button("閉じる") { model.dismissStorageProblem() }
                    .buttonStyle(PlainTextButtonStyle(color: Theme.ink, size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
        if !model.isAccessibilityGranted {
            Banner(text: "アクセシビリティの許可がないため、保存と復元ができません", color: Theme.warn) {
                Button("許可する") { model.onboardingDismissed = false }
                    .buttonStyle(PlainTextButtonStyle(color: Theme.accentInk, weight: .semibold, size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
        }
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("ワークスペース")
                .laneText(12, .semibold)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text("\(model.workspaces.count)件")
                .laneText(12)
        }
        .foregroundStyle(Theme.sub)
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 8, trailing: 16))
    }

    @ViewBuilder
    private var list: some View {
        if model.workspaces.isEmpty {
            VStack(spacing: 8) {
                LaneIconView(icon: .workspace(.display), size: 28, color: Theme.sub)
                Text("まだワークスペースがありません")
                    .laneText(13, .semibold)
                    .foregroundStyle(Theme.ink2)
                Text("ウィンドウを並べたら「今の配置を保存…」で記録しましょう。次からはワンクリックで、画面をつないだときは自動で元に戻ります。")
                    .laneText(12)
                    .foregroundStyle(Theme.sub)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.workspaces) { workspace in
                            WorkspaceCard(workspace: workspace)
                                .id(workspace.id)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .scrollBounceBehavior(.basedOnSize)
                .task(id: recordingBox) {
                    // The box for a new shortcut opens under the card, maybe below the bottom of
                    // the list: once it is laid out, scroll as little as it takes to show it.
                    guard case .shortcut(let id) = model.listEditing else { return }
                    try? await Task.sleep(for: .milliseconds(30))
                    cardToReveal = id
                }
                .onChange(of: cardToReveal) { _, id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                        proxy.scrollTo(id)
                    }
                    cardToReveal = nil
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                model.beginCapture()
            } label: {
                HStack(spacing: 8) {
                    LaneIconView(icon: .plus, size: 16)
                    Text("今の配置を保存…")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.isRestoring)

            HStack {
                if let shortcut = model.menuShortcutText {
                    Text("\(shortcut) でこのメニューを開く")
                        .laneText(12)
                } else {
                    Button("メニューを開くショートカットを設定…") { model.openSettings(.general) }
                        .buttonStyle(PlainTextButtonStyle(size: 12))
                        .padding(.leading, -8)
                }
                Spacer()
                Button("終了") { model.quit() }
                    .buttonStyle(PlainTextButtonStyle(height: Theme.Size.buttonHeight, horizontalPadding: 12))
                    .keyboardShortcut("q", modifiers: .command)
            }
            .foregroundStyle(Theme.sub)
        }
        .padding(12)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
        .padding(.top, 12)
    }

    /// Changes when the box for a new shortcut opens, closes, or gets a longer message.
    private var recordingBox: String {
        guard case .shortcut(let id) = model.listEditing else { return "" }
        return id.uuidString + (model.recordingProblem ?? "")
    }

    private var autoRestoreBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.autoRestoreEnabled },
            set: { model.setAutoRestoreEnabled($0) }
        )
    }
}

/// One workspace in the list (".ws"). A double-click on the name renames it, and the key next to
/// "復元" records a new shortcut, both in the card (spec §3.2).
struct WorkspaceCard: View {
    let workspace: Workspace
    @Environment(AppModel.self) private var model

    var body: some View {
        let state = model.cardState(for: workspace)
        let isRenaming = model.isRenaming(workspace.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                WorkspaceTile(color: workspace.color, icon: workspace.icon)
                VStack(alignment: .leading, spacing: 0) {
                    if isRenaming {
                        WorkspaceNameEditor()
                    } else {
                        Text(workspace.name)
                            .laneText(14, .semibold)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .onTapGesture(count: 2) {
                                model.beginRenaming(workspace.id)
                            }
                            .help("ダブルクリックで名前を変更")
                    }
                    Text(DisplayText.workspaceMeta(workspace))
                        .laneText(12)
                        .foregroundStyle(Theme.sub)
                }
                .accessibilityElement(children: isRenaming ? .contain : .combine)
                .accessibilityAction(named: "名前を変更") {
                    model.beginRenaming(workspace.id)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    WorkspaceShortcutKey(workspace: workspace)
                    Button("復元") {
                        model.finishListEditing()
                        model.restore(workspace.id, trigger: .manual)
                    }
                    .buttonStyle(LaneButtonStyle())
                    .disabled(model.isRestoring)
                    .accessibilityLabel("「\(workspace.name)」を復元")
                }
            }
            if model.isRecordingShortcut(workspace.id) {
                ShortcutRecordingRow(problem: model.recordingProblem) {
                    model.cancelShortcutRecording()
                }
            } else if let notice = model.shortcutNotice(for: workspace) {
                HintText(notice, color: Theme.warn)
            }
            CardStateView(state: state, fallback: model.missingDisplayFallback(for: workspace))
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(isHighlighted(state) ? Theme.accent : Theme.line, lineWidth: 1.5)
        )
        .contextMenu {
            Button("復元") {
                model.finishListEditing()
                model.restore(workspace.id, trigger: .manual)
            }
            .disabled(model.isRestoring)
            Divider()
            Button("名前を変更") { model.beginRenaming(workspace.id) }
            Button("ショートカットを変更…") { model.beginShortcutRecording(workspace.id) }
                .disabled(model.shortcutName(for: workspace) == nil)
            Divider()
            Button("設定で開く…") { model.openSettings(.workspace(workspace.id)) }
        }
    }

    /// Blue border: matches the connected displays, or is being restored.
    private func isHighlighted(_ state: WorkspaceCardState) -> Bool {
        if case .restoring = state {
            return true
        }
        return model.isMatchingCurrentDisplays(workspace)
    }
}

/// The name of a workspace while it is renamed in the list. Return or a click elsewhere keeps the
/// new name, esc puts the old one back.
private struct WorkspaceNameEditor: View {
    @Environment(AppModel.self) private var model
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("名前", text: draft)
            .textFieldStyle(.plain)
            .font(.lane(14, .semibold))
            .foregroundStyle(Theme.ink)
            .labelsHidden()
            .focused($isFocused)
            .padding(.horizontal, 6)
            .frame(height: 24)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
            )
            // The text stays where the name was.
            .padding(.leading, -7)
            .onSubmit { model.commitRenaming() }
            .onExitCommand { model.cancelRenaming() }
            .onAppear { isFocused = true }
            .task {
                // Once the field has the focus: the whole name selected, so that typing replaces
                // it, as when renaming in the Finder.
                try? await Task.sleep(for: .milliseconds(50))
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
            .accessibilityLabel("ワークスペースの名前")
    }

    private var draft: Binding<String> {
        Binding(
            get: { model.nameDraft },
            set: { model.nameDraft = $0 }
        )
    }
}

/// The restore shortcut of a workspace as a key, as in the settings. Clicking it waits in the card
/// for a new key combination.
private struct WorkspaceShortcutKey: View {
    let workspace: Workspace
    @Environment(AppModel.self) private var model
    @State private var isHovering = false

    var body: some View {
        let text = model.shortcutText(for: workspace)
        Button {
            model.beginShortcutRecording(workspace.id)
        } label: {
            KeyCap(
                text: text ?? "なし",
                isPlaceholder: text == nil,
                isHighlighted: isHovering || model.isRecordingShortcut(workspace.id),
                // As wide as "⌃⌥2", so that the keys of the cards line up.
                minWidth: 54
            )
        }
        .buttonStyle(.plain)
        .disabled(model.shortcutName(for: workspace) == nil)
        .onHover { isHovering = $0 }
        .help("クリックして変更")
        .accessibilityLabel("「\(workspace.name)」のショートカット")
        .accessibilityValue(text ?? "なし")
        .accessibilityHint("ショートカットを変更します")
    }
}

/// The box in a workspace card while its new shortcut is recorded, with what is wrong with the
/// last key combination pressed, if anything.
private struct ShortcutRecordingRow: View {
    let problem: String?
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("新しいキーを押してください")
                    .laneText(13, .semibold)
                    .foregroundStyle(Theme.accentInk)
                Spacer(minLength: 8)
                Button("取り消す", action: onCancel)
                    .buttonStyle(PlainTextButtonStyle(size: 12))
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(height: 36)
            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 1.5)
            )
            HintText(problem ?? "⌫ で削除、esc で取り消します。", color: problem == nil ? Theme.sub : Theme.warn)
        }
    }
}

/// The line under a workspace: progress, result, or how it relates to the connected displays.
struct CardStateView: View {
    let state: WorkspaceCardState
    let fallback: MissingDisplayFallback

    var body: some View {
        switch state {
        case .restoring(let progress):
            VStack(alignment: .leading, spacing: 6) {
                LaneProgressBar(fraction: progress.fraction)
                Text("配置中… \(progress.completed) / \(progress.total)")
                    .laneText(12)
                    .foregroundStyle(Theme.ink2)
                    .monospacedDigit()
            }
        case .note(let text):
            Text(text)
                .laneText(12)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        case .matchesCurrent:
            HStack(alignment: .top, spacing: 6) {
                LaneIconView(icon: .check, size: 14)
                    .padding(.top, 2)
                Text("今つながっている構成と一致")
                    .laneText(12)
            }
            .foregroundStyle(Theme.accentInk)
            .accessibilityElement(children: .combine)
        case .missingDisplays(let count):
            Text(DisplayText.missingDisplaysNote(count: count, fallback: fallback))
                .laneText(12)
                .foregroundStyle(Theme.warn)
                .fixedSize(horizontal: false, vertical: true)
        case .plain:
            EmptyView()
        }
    }
}

/// A one-line notice with an action.
struct Banner<Action: View>: View {
    let text: String
    let color: Color
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(text)
                .laneText(12)
                .foregroundStyle(color)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            action()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .laneBox()
    }
}

#if DEBUG
#Preview("一覧") {
    PopoverRootView()
        .environment(AppModel.preview())
}

#Preview("復元中") {
    PopoverRootView()
        .environment(AppModel.preview(.restoring))
}

#Preview("復元の結果") {
    PopoverRootView()
        .environment(AppModel.preview(.finished))
}

#Preview("ワークスペースなし") {
    PopoverRootView()
        .environment(AppModel.preview(.empty))
}
#endif
