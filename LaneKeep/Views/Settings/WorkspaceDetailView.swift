import KeyboardShortcuts
import LaneKeepCore
import SwiftUI

/// The details of one workspace (spec §3.5): name, displays, map, rule table, auto-restore
/// conditions and shortcuts.
struct WorkspaceDetailView: View {
    let workspaceID: UUID
    @Environment(AppModel.self) private var model
    @State private var selectedRuleID: UUID?
    @State private var overwriteSession: CaptureSession?
    @State private var isConfirmingDelete = false
    @State private var ruleToDelete: WindowRule?

    var body: some View {
        if let workspace = model.workspace(workspaceID) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header(workspace)
                    statusLine(workspace)
                    DisplayMapView(
                        displays: MapDisplay.from(workspace.displays),
                        windows: workspace.windows.map { rule in
                            MapWindow(
                                id: rule.id.uuidString,
                                displayID: rule.displayUUID,
                                relativeFrame: rule.relativeFrame,
                                label: rule.appName
                            )
                        },
                        selectedWindowID: selectedRuleID?.uuidString,
                        onSelectWindow: { id in
                            let ruleID = UUID(uuidString: id)
                            selectedRuleID = selectedRuleID == ruleID ? nil : ruleID
                        }
                    )
                    .frame(height: 260)
                    WindowRuleTable(
                        workspace: workspace,
                        selection: $selectedRuleID,
                        onDelete: { ruleToDelete = $0 }
                    )
                    cards(workspace)
                }
                .padding(EdgeInsets(top: 20, leading: 24, bottom: 28, trailing: 24))
            }
            .scrollBounceBehavior(.basedOnSize)
            .sheet(item: $overwriteSession) { session in
                CaptureScreen(
                    session: session,
                    onCancel: { overwriteSession = nil },
                    onSave: {
                        model.applyOverwrite(session)
                        overwriteSession = nil
                    }
                )
                .frame(width: 420, height: 700)
                .background(Theme.window)
            }
            .confirmationDialog(
                "「\(workspace.name)」を削除しますか？",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    model.deleteWorkspace(workspaceID)
                }
            } message: {
                Text("記録したウィンドウの配置とショートカットが削除されます。この操作は取り消せません。")
            }
            .confirmationDialog(
                "このウィンドウ規則を削除しますか？",
                isPresented: Binding(
                    get: { ruleToDelete != nil },
                    set: { if !$0 { ruleToDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: ruleToDelete
            ) { rule in
                Button("削除", role: .destructive) {
                    if selectedRuleID == rule.id {
                        selectedRuleID = nil
                    }
                    model.deleteRule(rule.id, in: workspaceID)
                }
            } message: { rule in
                Text("「\(rule.appName)」（\(DisplayText.marker(for: rule))）は復元されなくなります。")
            }
        }
    }

    // MARK: - Header

    private func header(_ workspace: Workspace) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AppearanceButton(workspace: workspace)
            VStack(alignment: .leading, spacing: 2) {
                WorkspaceNameField(name: workspace.name) { newName in
                    model.update(workspaceID) { $0.name = newName }
                }
                Text("\(DisplayText.displayNames(workspace.displays))、\(workspace.appCount)アプリ")
                    .font(.lane(12))
                    .foregroundStyle(Theme.sub)
                    .lineLimit(2)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Button("今の配置で上書き") {
                    overwriteSession = model.makeOverwriteSession(for: workspaceID)
                }
                .buttonStyle(LaneButtonStyle())
                .disabled(model.isRestoring || !model.isAccessibilityGranted)
                .help("今開いているウィンドウの位置と大きさで記録し直します")
                Button("復元") {
                    model.restore(workspaceID, trigger: .manual)
                }
                .buttonStyle(LaneButtonStyle(prominent: true))
                .disabled(model.isRestoring)
                Menu {
                    Button("このワークスペースを削除…", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Text("…")
                        .font(.lane(15, .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("その他の操作")
                .accessibilityLabel("その他の操作")
            }
        }
    }

    @ViewBuilder
    private func statusLine(_ workspace: Workspace) -> some View {
        switch model.cardState(for: workspace) {
        case .restoring(let progress):
            CardStateView(state: .restoring(progress), fallback: model.preferences.missingDisplayFallback)
                .frame(maxWidth: 420, alignment: .leading)
        case .note(let text):
            CardStateView(state: .note(text), fallback: model.preferences.missingDisplayFallback)
        case .missingDisplays(let count):
            CardStateView(state: .missingDisplays(count), fallback: model.preferences.missingDisplayFallback)
        case .matchesCurrent, .plain:
            EmptyView()
        }
    }

    // MARK: - Cards

    private func cards(_ workspace: Workspace) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                autoRestoreCard(workspace)
                shortcutCard(workspace)
            }
            .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 16) {
                autoRestoreCard(workspace)
                shortcutCard(workspace)
            }
        }
    }

    private func autoRestoreCard(_ workspace: Workspace) -> some View {
        SettingsCard(title: "自動で復元する条件") {
            Toggle(isOn: binding(\.autoRestoreOnConnect)) {
                Text("この画面構成を検知したとき")
                    .font(.lane(13))
                    .foregroundStyle(Theme.ink)
            }
            .toggleStyle(LaneSwitchStyle())
            .frame(minHeight: 32)
            Toggle(isOn: binding(\.autoRestoreOnWake)) {
                Text("スリープ解除のとき")
                    .font(.lane(13))
                    .foregroundStyle(Theme.ink)
            }
            .toggleStyle(LaneSwitchStyle())
            .frame(minHeight: 32)
            HintText("画面はシリアル番号つきの識別子で見分けるので、差し込むポートが変わっても同じ画面として扱います。")
            if !model.preferences.autoRestoreEnabled {
                HintText("メニューの「つないだら自動で復元」がオフのため、いまは自動で復元しません。", color: Theme.warn)
            }
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: .infinity, alignment: .topLeading)
    }

    private func shortcutCard(_ workspace: Workspace) -> some View {
        SettingsCard(title: "ショートカット") {
            HStack(spacing: 8) {
                Text("このワークスペースを復元")
                    .font(.lane(13))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                if let name = model.shortcutName(for: workspace) {
                    KeyboardShortcuts.Recorder(for: name, onChange: { _ in
                        model.shortcutRecorded(for: name)
                    })
                    .fixedSize()
                }
            }
            HStack(spacing: 8) {
                Text("メニューを開く")
                    .font(.lane(13))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                KeyCap(text: model.menuShortcutText ?? "なし")
            }
            HStack(spacing: 0) {
                Text("足りない画面がある場合：")
                Text(model.preferences.missingDisplayFallback.title)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.ink)
                Button("（変更可）") {
                    model.settingsPane = .general
                }
                .buttonStyle(.link)
                .help("「一般」で変えられます")
            }
            .font(.lane(12))
            .foregroundStyle(Theme.sub)
            if let notice = model.shortcutNotice {
                HintText(notice, color: Theme.warn)
            }
        }
        .frame(minWidth: 280, idealWidth: 320, maxWidth: .infinity, alignment: .topLeading)
    }

    private func binding(_ keyPath: WritableKeyPath<Workspace, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.workspace(workspaceID)?[keyPath: keyPath] ?? false },
            set: { newValue in model.update(workspaceID) { $0[keyPath: keyPath] = newValue } }
        )
    }
}

/// The workspace name as an editable title. Commits on Return or when the field loses focus; an
/// empty name puts the old one back.
private struct WorkspaceNameField: View {
    let name: String
    let onCommit: (String) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("名前", text: $text)
            .textFieldStyle(.plain)
            .font(.lane(20, .bold))
            .foregroundStyle(Theme.ink)
            .focused($isFocused)
            .onSubmit { commit() }
            .onAppear { text = name }
            .onChange(of: name) { _, newName in
                if !isFocused {
                    text = newName
                }
            }
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    commit()
                }
            }
            .accessibilityLabel("ワークスペースの名前")
            .help("クリックして名前を変更")
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            text = name
        } else if trimmed != name {
            onCommit(trimmed)
        }
    }
}

/// The workspace tile; clicking it lets the user pick another color and glyph.
private struct AppearanceButton: View {
    let workspace: Workspace
    @Environment(AppModel.self) private var model
    @State private var isShowingPicker = false

    var body: some View {
        Button {
            isShowingPicker = true
        } label: {
            WorkspaceTile(color: workspace.color, icon: workspace.icon, size: 40)
        }
        .buttonStyle(.plain)
        .help("色とアイコンを変更")
        .accessibilityLabel("色とアイコンを変更")
        .popover(isPresented: $isShowingPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                FieldLabel("色")
                ColorSwatches(selection: Binding(
                    get: { model.workspace(workspace.id)?.color ?? workspace.color },
                    set: { color in model.update(workspace.id) { $0.color = color } }
                ))
                FieldLabel("アイコン")
                HStack(spacing: 8) {
                    ForEach(WorkspaceIcon.allCases, id: \.self) { icon in
                        Button {
                            model.update(workspace.id) { $0.icon = icon }
                        } label: {
                            WorkspaceTile(color: workspace.color, icon: icon, size: 32)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(workspace.icon == icon ? Theme.ink : .clear, lineWidth: 2)
                                        .padding(-3)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(icon.displayName)
                        .accessibilityLabel(icon.displayName)
                        .accessibilityAddTraits(workspace.icon == icon ? .isSelected : [])
                    }
                }
            }
            .padding(16)
        }
    }
}
