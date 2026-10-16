import LaneKeepCore
import SwiftUI

/// Screen 2: "今の配置を保存" (spec §3.1). Also used in the settings window to overwrite a
/// workspace with the current layout.
struct CaptureScreen: View {
    @Bindable var session: CaptureSession
    var onCancel: () -> Void
    var onSave: () -> Void

    @FocusState private var isNameFocused: Bool

    private var isOverwrite: Bool {
        if case .overwrite = session.mode {
            return true
        }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !isOverwrite {
                        nameField
                        colorField
                    }
                    mapField
                    windowList
                    options
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            saveButton
                .padding(12)
                .overlay(alignment: .top) {
                    Rectangle().fill(Theme.line).frame(height: 1)
                }
        }
        .onExitCommand(perform: onCancel)
        .onAppear {
            if !isOverwrite {
                isNameFocused = true
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onCancel) {
                LaneIconView(icon: .back, size: 18)
            }
            .buttonStyle(IconButtonStyle())
            .help(isOverwrite ? "キャンセル" : "一覧に戻る")
            .accessibilityLabel(isOverwrite ? "キャンセル" : "一覧に戻る")
            Spacer()
            Text(isOverwrite ? "今の配置で上書き" : "今の配置を保存")
                .font(.lane(14, .semibold))
                .foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(EdgeInsets(top: 14, leading: 12, bottom: 10, trailing: 12))
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel("名前")
            TextField("名前", text: $session.name, prompt: Text("例: 自宅デスク"))
                .textFieldStyle(.plain)
                .font(.lane(13))
                .foregroundStyle(Theme.ink)
                .labelsHidden()
                .focused($isNameFocused)
                .onSubmit { save() }
                .padding(.horizontal, 10)
                .frame(height: 36)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(isNameFocused ? Theme.accent : Theme.lineStrong, lineWidth: isNameFocused ? 1.5 : 1)
                )
                .accessibilityLabel("名前")
        }
    }

    private var colorField: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel("色")
            ColorSwatches(selection: $session.color)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("色")
        }
    }

    private var mapField: some View {
        VStack(alignment: .leading, spacing: 6) {
            FieldLabel("記録する配置")
            DisplayMapView(
                displays: MapDisplay.from(session.displays),
                windows: session.selectedCandidates.map { candidate in
                    MapWindow(
                        id: candidate.id,
                        displayID: candidate.displayUUID,
                        relativeFrame: candidate.relativeFrame,
                        label: candidate.window.appName
                    )
                }
            )
            .frame(height: 164)
        }
    }

    private var windowList: some View {
        let roles = DisplayRoles.assign(session.displays)
        let names = Dictionary(uniqueKeysWithValues: session.displays.map { ($0.uuid, $0.name) })
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                FieldLabel("対象のウィンドウ")
                Spacer()
                if !session.isLoading {
                    FieldLabel("\(session.selectedCandidates.count) / \(session.candidates.count)件")
                        .monospacedDigit()
                }
            }
            VStack(spacing: 0) {
                if session.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("ウィンドウを読み込んでいます…")
                    }
                    .font(.lane(13))
                    .foregroundStyle(Theme.sub)
                    .frame(maxWidth: .infinity, minHeight: 56)
                } else if session.candidates.isEmpty {
                    Text("保存できるウィンドウがありません")
                        .font(.lane(13))
                        .foregroundStyle(Theme.sub)
                        .frame(maxWidth: .infinity, minHeight: 56)
                } else {
                    ForEach(Array(session.candidates.enumerated()), id: \.element.id) { index, candidate in
                        if index > 0 {
                            Rectangle().fill(Theme.line).frame(height: 1)
                        }
                        CandidateRow(
                            candidate: candidate,
                            showsTitle: session.needsTitle(candidate),
                            displayName: names[candidate.displayUUID] ?? "",
                            role: roles[candidate.displayUUID] ?? .tertiary,
                            isSelected: Binding(
                                get: { session.isSelected(candidate) },
                                set: { session.setSelected($0, for: candidate) }
                            )
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .laneBox()
            Text("別のデスクトップにあるウィンドウと、しまってあるウィンドウは一覧に出ません。")
                .font(.lane(11))
                .foregroundStyle(Theme.sub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var options: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $session.launchIfClosed) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("閉じているアプリは起動してから配置")
                        .font(.lane(13))
                        .foregroundStyle(Theme.ink)
                    if isOverwrite {
                        Text("新しく加わるウィンドウに使います")
                            .font(.lane(11))
                            .foregroundStyle(Theme.sub)
                    }
                }
            }
            .toggleStyle(LaneSwitchStyle())
            .frame(minHeight: 40)
            Rectangle().fill(Theme.line).frame(height: 1)
            Toggle(isOn: $session.autoRestoreOnConnect) {
                Text("この画面構成をつないだら自動で復元")
                    .font(.lane(13))
                    .foregroundStyle(Theme.ink)
            }
            .toggleStyle(LaneSwitchStyle())
            .frame(minHeight: 40)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .laneBox()
    }

    private var saveButton: some View {
        let count = session.selectedCandidates.count
        let title: String
        if count == 0 {
            title = "ウィンドウを1つ以上選んでください"
        } else if isOverwrite {
            title = "\(count)件のウィンドウで上書き"
        } else {
            title = "\(count)件のウィンドウを保存"
        }
        return Button(title) { save() }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(count == 0 || session.isLoading)
            .keyboardShortcut(.defaultAction)
    }

    private func save() {
        guard !session.isLoading, !session.selectedCandidates.isEmpty else { return }
        onSave()
    }
}

/// One window in the list: checkbox, initial, app name, display.
private struct CandidateRow: View {
    let candidate: CaptureCandidate
    let showsTitle: Bool
    let displayName: String
    let role: DisplayRole
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack(spacing: 10) {
                AppInitialBadge(name: candidate.window.appName)
                VStack(alignment: .leading, spacing: 0) {
                    Text(candidate.window.appName)
                        .font(.lane(13))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if showsTitle, !candidate.window.title.isEmpty {
                        Text(candidate.window.title)
                            .font(.lane(11))
                            .foregroundStyle(Theme.sub)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                DisplayLabel(name: displayName, role: role)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .toggleStyle(.checkbox)
        .help(candidate.window.title)
    }
}

/// The small gray label above a field (".lbl").
struct FieldLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.lane(12))
            .foregroundStyle(Theme.sub)
    }
}
