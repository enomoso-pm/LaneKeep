import AppKit
import KeyboardShortcuts
import LaneKeepCore
import LaneKeepSystem
import SwiftUI

/// "一般" (spec §3.5): launch at login, the menu shortcut, and where windows of missing displays go.
struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("一般")
                    .laneText(20, .bold)
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.bottom, 4)
                startupCard
                autoRestoreCard
                shortcutCard
                fallbackCard
                permissionCard
                dataCard
                Text("LaneKeep \(Self.version)")
                    .laneText(12)
                    .foregroundStyle(Theme.sub)
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(EdgeInsets(top: 20, leading: 24, bottom: 28, trailing: 24))
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { model.loginItem.refresh() }
    }

    private var startupCard: some View {
        SettingsCard(title: "起動") {
            Toggle(isOn: Binding(
                get: { model.loginItem.isEnabled },
                set: { model.loginItem.setEnabled($0) }
            )) {
                Text("ログイン時に起動")
                    .laneText(13)
                    .foregroundStyle(Theme.ink)
            }
            .toggleStyle(LaneSwitchStyle())
            .frame(minHeight: 32)
            if model.loginItem.requiresApproval {
                HStack(spacing: 8) {
                    HintText("「システム設定」の「ログイン項目」で LaneKeep を許可してください。", color: Theme.warn)
                    Button("ログイン項目を開く") { model.loginItem.openSystemSettings() }
                        .buttonStyle(.link)
                        .font(.lane(12))
                }
            }
            if let error = model.loginItem.errorMessage {
                HintText(error, color: Theme.warn)
            }
            HintText("画面をつないだときの自動復元は、LaneKeep が起動しているあいだだけ働きます。")
        }
    }

    private var autoRestoreCard: some View {
        SettingsCard(title: "自動で復元") {
            Toggle(isOn: Binding(
                get: { model.preferences.autoRestoreEnabled },
                set: { model.setAutoRestoreEnabled($0) }
            )) {
                Text("つないだら自動で復元")
                    .laneText(13)
                    .foregroundStyle(Theme.ink)
            }
            .toggleStyle(LaneSwitchStyle())
            .frame(minHeight: 32)
            HintText("全体のスイッチです。オフにすると、どのワークスペースも自動では復元しません。メニューのスイッチと同じものです。")
        }
    }

    private var shortcutCard: some View {
        SettingsCard(title: "ショートカット") {
            HStack(spacing: 8) {
                Text("メニューを開く")
                    .laneText(13)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                ShortcutButton(
                    title: "メニューを開く",
                    text: model.menuShortcutText,
                    name: ShortcutCenter.toggleMenu,
                    onChange: { model.shortcutRecorded(for: ShortcutCenter.toggleMenu) }
                )
                Button("初期設定に戻す") { model.resetMenuShortcut() }
                    .buttonStyle(LaneButtonStyle(height: 28))
                    .disabled(model.menuShortcutText == ShortcutCenter.defaultMenuShortcut.description)
                    .help("⌃⌥L に戻します")
            }
            HintText("ワークスペースごとの復元のショートカットは、各ワークスペースのページで変えられます。")
            if let notice = model.shortcutNotice {
                HintText(notice, color: Theme.warn)
            }
        }
    }

    private var fallbackCard: some View {
        SettingsCard(title: "足りない画面の寄せ先") {
            Picker("足りない画面の寄せ先", selection: Binding(
                get: { model.preferences.missingDisplayFallback },
                set: { value in model.updatePreferences { $0.missingDisplayFallback = value } }
            )) {
                ForEach(MissingDisplayFallback.allCases, id: \.self) { fallback in
                    Text(fallback.title).tag(fallback)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .font(.lane(13))
            HintText("保存したときの画面がつながっていないとき、その画面にあったウィンドウをどうするかを選びます。寄せる場合は、位置と大きさの割合をそのまま当てはめます。")
        }
    }

    private var permissionCard: some View {
        SettingsCard(title: "アクセシビリティ") {
            HStack(spacing: 10) {
                Circle()
                    .fill(model.isAccessibilityGranted ? Theme.accent : Theme.display2)
                    .frame(width: 10, height: 10)
                Text(model.isAccessibilityGranted ? "許可されています" : "まだ許可されていません")
                    .laneText(13)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                if !model.isAccessibilityGranted {
                    Button("システム設定を開く") { model.requestAccessibilityPermission() }
                        .buttonStyle(LaneButtonStyle(prominent: true))
                }
            }
            .accessibilityElement(children: .combine)
            HintText("他のアプリのウィンドウの位置を読み取って動かすためだけに使います。キー入力や画面の内容は記録しません。")
        }
    }

    private var dataCard: some View {
        SettingsCard(title: "保存データ") {
            HStack(spacing: 8) {
                Text(model.dataDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .laneText(12)
                    .foregroundStyle(Theme.ink2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Spacer(minLength: 8)
                Button("Finderで表示") { revealDataDirectory() }
                    .buttonStyle(LaneButtonStyle(height: 28))
            }
            HintText("ワークスペースは workspaces.json、設定は preferences.json に保存しています。")
            if let problem = model.storageProblem {
                HintText(problem, color: Theme.warn)
            }
        }
    }

    private func revealDataDirectory() {
        let directory = model.dataDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short)（\(build)）"
    }
}
