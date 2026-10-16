import LaneKeepCore
import LaneKeepSystem
import SwiftUI

/// The window rules of a workspace (spec §3.5): app, window marker, display, position and size,
/// and what to do when the app is closed. Selecting a row highlights the window on the map.
struct WindowRuleTable: View {
    let workspace: Workspace
    @Binding var selection: UUID?
    var onDelete: (WindowRule) -> Void

    var body: some View {
        let roles = DisplayRoles.assign(workspace.displays)
        VStack(spacing: 0) {
            RuleColumns(
                app: Text("アプリ"),
                marker: Text("ウィンドウの目印"),
                display: Text("画面"),
                frame: Text("位置とサイズ"),
                launch: Text("閉じていたら")
            )
            .font(.lane(12, .medium))
            .foregroundStyle(Theme.sub)
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            if workspace.windows.isEmpty {
                separator
                Text("ウィンドウ規則がありません。「今の配置で上書き」で記録できます。")
                    .font(.lane(13))
                    .foregroundStyle(Theme.sub)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            ForEach(workspace.windows) { rule in
                separator
                RuleRow(
                    rule: rule,
                    workspaceID: workspace.id,
                    displayName: workspace.display(withUUID: rule.displayUUID)?.name ?? "不明な画面",
                    role: roles[rule.displayUUID] ?? .tertiary,
                    isSelected: selection == rule.id,
                    onSelect: { selection = selection == rule.id ? nil : rule.id },
                    onDelete: { onDelete(rule) }
                )
            }
        }
        .laneBox()
        .onDeleteCommand {
            if let id = selection, let rule = workspace.windows.first(where: { $0.id == id }) {
                onDelete(rule)
            }
        }
    }

    private var separator: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }
}

/// Lays out the five columns the same way in the header and in every row.
private struct RuleColumns<App: View, Marker: View, Display: View, Frame: View, Launch: View>: View {
    let app: App
    let marker: Marker
    let display: Display
    let frame: Frame
    let launch: Launch

    var body: some View {
        HStack(spacing: 0) {
            app.frame(minWidth: 110, maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
            marker.frame(minWidth: 120, maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10)
            display.frame(width: 150, alignment: .leading).padding(.horizontal, 10)
            frame.frame(width: 178, alignment: .leading).padding(.horizontal, 10)
            launch.frame(width: 92, alignment: .leading).padding(.horizontal, 10)
        }
    }
}

private struct RuleRow: View {
    let rule: WindowRule
    let workspaceID: UUID
    let displayName: String
    let role: DisplayRole
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    @Environment(AppModel.self) private var model
    @State private var isHovering = false
    @State private var isEditingMarker = false

    var body: some View {
        RuleColumns(
            app: HStack(spacing: 8) {
                AppInitialBadge(name: rule.appName)
                Text(rule.appName)
                    .font(.lane(13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            },
            marker: HStack(spacing: 4) {
                Text(DisplayText.marker(for: rule))
                    .font(.lane(12))
                    .foregroundStyle(Theme.sub)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if isHovering || isSelected {
                    Button("変更") { isEditingMarker = true }
                        .buttonStyle(.link)
                        .font(.lane(12))
                }
            }
            .popover(isPresented: $isEditingMarker, arrowEdge: .bottom) {
                MarkerEditor(rule: rule) { marker in
                    model.updateRule(rule.id, in: workspaceID) { $0.titleContains = marker }
                    isEditingMarker = false
                } onCancel: {
                    isEditingMarker = false
                }
            },
            display: DisplayLabel(name: displayName, role: role, pill: true),
            frame: Text(DisplayText.relativeFrame(rule.relativeFrame))
                .font(.lane(12))
                .foregroundStyle(Theme.sub)
                .lineLimit(1)
                .minimumScaleFactor(0.85),
            launch: Menu {
                Button("起動する") { setLaunch(true) }
                Button("何もしない") { setLaunch(false) }
            } label: {
                Text(DisplayText.launchOption(rule.launchIfClosed))
                    .font(.lane(12))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("アプリが起動していないときの動き")
        )
        .padding(.vertical, 8)
        .background(isSelected ? Theme.accentSoft : (isHovering ? Theme.muted : .clear))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("ウィンドウの目印を変更…") { isEditingMarker = true }
            Menu("閉じていたら") {
                Button("起動する") { setLaunch(true) }
                Button("何もしない") { setLaunch(false) }
            }
            Divider()
            Button("この規則を削除…", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.appName)、\(DisplayText.marker(for: rule))、\(displayName)、\(DisplayText.relativeFrame(rule.relativeFrame))、閉じていたら\(DisplayText.launchOption(rule.launchIfClosed))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "ウィンドウの目印を変更") { isEditingMarker = true }
        .accessibilityAction(named: "削除", onDelete)
    }

    private func setLaunch(_ launch: Bool) {
        model.updateRule(rule.id, in: workspaceID) { $0.launchIfClosed = launch }
    }
}

/// Edits `titleContains`: the text the window title must contain. Suggests the titles of the
/// app's windows that are open right now.
private struct MarkerEditor: View {
    let rule: WindowRule
    let onSave: (String?) -> Void
    let onCancel: () -> Void

    @State private var text: String
    @State private var suggestions: [String] = []

    init(rule: WindowRule, onSave: @escaping (String?) -> Void, onCancel: @escaping () -> Void) {
        self.rule = rule
        self.onSave = onSave
        self.onCancel = onCancel
        _text = State(initialValue: rule.titleContains ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ウィンドウの目印")
                .font(.lane(13, .semibold))
            HintText("タイトルにこの文字を含む\(rule.appName)のウィンドウを選びます。空欄なら\(rule.index == 0 ? "最初" : "\(rule.index + 1)番目")のウィンドウを使います。")
            TextField("タイトルに含む文字", text: $text, prompt: Text("例: プロジェクト名"))
                .textFieldStyle(.roundedBorder)
            if !suggestions.isEmpty {
                FieldLabel("今開いているウィンドウ")
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(suggestions, id: \.self) { title in
                        Button {
                            text = title
                        } label: {
                            Text(title)
                                .font(.lane(12))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainTextButtonStyle(color: Theme.ink, weight: .regular, size: 12))
                    }
                }
            }
            HStack {
                Spacer()
                Button("キャンセル", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340)
        .task {
            suggestions = await Self.openWindowTitles(bundleID: rule.bundleID)
        }
    }

    private func save() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(trimmed.isEmpty ? nil : trimmed)
    }

    private static func openWindowTitles(bundleID: String) async -> [String] {
        guard AccessibilityPermission.isGranted,
              let app = RunningApps.regularApps().first(where: { $0.bundleID == bundleID }) else {
            return []
        }
        let windows = await Task.detached { WindowCatalog.windows(of: app) }.value
        var seen = Set<String>()
        return windows.map(\.title).filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(6).map { $0 }
    }
}
