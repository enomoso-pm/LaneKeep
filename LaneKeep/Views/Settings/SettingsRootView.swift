import LaneKeepCore
import SwiftUI

/// Screen 4: the settings window — sidebar on the left, details on the right (spec §3.5).
struct SettingsRootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 0) {
            // 220 pt with the divider, as in the mock.
            SettingsSidebar()
                .frame(width: 219)
            Rectangle()
                .fill(Theme.line)
                .frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.window)
        // Wide enough for the rule table's narrowest columns next to the sidebar.
        .frame(minWidth: 980, minHeight: 640)
    }

    @ViewBuilder
    private var detail: some View {
        switch model.settingsPane {
        case .workspace(let id):
            if model.workspace(id) != nil {
                WorkspaceDetailView(workspaceID: id)
                    .id(id)
            } else {
                NoWorkspaceView()
            }
        case .general:
            GeneralSettingsView()
        case .excludedApps:
            ExcludedAppsView()
        }
    }
}

private struct SettingsSidebar: View {
    @Environment(AppModel.self) private var model
    @State private var workspaceToDelete: Workspace?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.workspaces) { workspace in
                    SidebarButton(title: workspace.name, isSelected: model.settingsPane == .workspace(workspace.id)) {
                        WorkspaceTile(color: workspace.color, icon: workspace.icon, size: 24)
                    } action: {
                        model.settingsPane = .workspace(workspace.id)
                    }
                    .contextMenu {
                        Button("復元") { model.restore(workspace.id, trigger: .manual) }
                            .disabled(model.isRestoring)
                        Divider()
                        Button("このワークスペースを削除…", role: .destructive) {
                            workspaceToDelete = workspace
                        }
                    }
                }
                if model.workspaces.isEmpty {
                    Text("ワークスペースはまだありません")
                        .laneText(12)
                        .foregroundStyle(Theme.sub)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                Rectangle()
                    .fill(Theme.line)
                    .frame(height: 1)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                SidebarButton(title: "一般", isSelected: model.settingsPane == .general) {
                    EmptyView()
                } action: {
                    model.settingsPane = .general
                }
                SidebarButton(title: "除外するアプリ", isSelected: model.settingsPane == .excludedApps) {
                    EmptyView()
                } action: {
                    model.settingsPane = .excludedApps
                }
            }
            .padding(12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("設定の項目")
        .confirmationDialog(
            "「\(workspaceToDelete?.name ?? "")」を削除しますか？",
            isPresented: Binding(
                get: { workspaceToDelete != nil },
                set: { if !$0 { workspaceToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: workspaceToDelete
        ) { workspace in
            Button("削除", role: .destructive) {
                model.deleteWorkspace(workspace.id)
            }
        } message: { _ in
            Text("記録したウィンドウの配置とショートカットが削除されます。この操作は取り消せません。")
        }
    }
}

/// A sidebar row (".side-btn"): 40 pt high, blue tint when selected.
private struct SidebarButton<Icon: View>: View {
    let title: String
    let isSelected: Bool
    @ViewBuilder var icon: () -> Icon
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon()
                Text(title)
                    .font(.lane(14, isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Theme.accentInk : Theme.ink)
            .padding(.horizontal, 10)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                    .fill(isSelected ? Theme.accentSoft : (isHovering ? Theme.muted : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Shown when no workspace is selected (or the selected one was deleted).
private struct NoWorkspaceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            LaneIconView(icon: .workspace(.display), size: 36, color: Theme.sub)
            Text(model.workspaces.isEmpty ? "ワークスペースはまだありません" : "ワークスペースを選んでください")
                .laneText(15, .semibold)
                .foregroundStyle(Theme.ink2)
            if model.workspaces.isEmpty {
                Text("メニューバーの LaneKeep から「今の配置を保存…」を選ぶと、ここで細かく設定できます。")
                    .laneText(13)
                    .foregroundStyle(Theme.sub)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A titled card for the settings pages (".card").
struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .laneText(13, .bold)
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
        // Fills the row height so that cards side by side end at the same line.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .laneBox()
    }
}

/// Small explanatory text under a setting.
struct HintText: View {
    let text: String
    var color: Color = Theme.sub

    init(_ text: String, color: Color = Theme.sub) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .laneText(12)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
#Preview("設定") {
    SettingsRootView()
        .environment(AppModel.preview())
        .frame(width: 1120, height: 860)
}
#endif
