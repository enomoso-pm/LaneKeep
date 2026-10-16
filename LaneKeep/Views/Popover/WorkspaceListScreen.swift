import LaneKeepCore
import SwiftUI

/// Screen 1: the connected displays and the saved workspaces.
struct WorkspaceListScreen: View {
    @Environment(AppModel.self) private var model

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
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.workspaces) { workspace in
                        WorkspaceCard(workspace: workspace)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }
            .scrollBounceBehavior(.basedOnSize)
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

    private var autoRestoreBinding: Binding<Bool> {
        Binding(
            get: { model.preferences.autoRestoreEnabled },
            set: { model.setAutoRestoreEnabled($0) }
        )
    }
}

/// One workspace in the list (".ws").
struct WorkspaceCard: View {
    let workspace: Workspace
    @Environment(AppModel.self) private var model

    var body: some View {
        let state = model.cardState(for: workspace)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                WorkspaceTile(color: workspace.color, icon: workspace.icon)
                VStack(alignment: .leading, spacing: 0) {
                    Text(workspace.name)
                        .laneText(14, .semibold)
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(DisplayText.workspaceMeta(workspace))
                        .laneText(12)
                        .foregroundStyle(Theme.sub)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                Button {
                    model.restore(workspace.id, trigger: .manual)
                } label: {
                    HStack(spacing: 6) {
                        Text("復元")
                        if let shortcut = model.shortcutText(for: workspace) {
                            Text(shortcut)
                                .font(.lane(11, .medium))
                                .foregroundStyle(Theme.sub)
                        }
                    }
                }
                .buttonStyle(LaneButtonStyle())
                .disabled(model.isRestoring)
                .accessibilityLabel("「\(workspace.name)」を復元")
            }
            CardStateView(state: state, fallback: model.preferences.missingDisplayFallback)
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(isHighlighted(state) ? Theme.accent : Theme.line, lineWidth: 1.5)
        )
        .contextMenu {
            Button("復元") { model.restore(workspace.id, trigger: .manual) }
                .disabled(model.isRestoring)
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
