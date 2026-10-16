import SwiftUI

/// Screen 3: asks for the accessibility permission (spec §3.6).
struct OnboardingScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LaneIconView(icon: .permission, size: 48, color: Theme.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text("ウィンドウを動かす許可が必要です")
                    .font(.lane(18, .bold))
                    .foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("他のアプリのウィンドウの位置を読み取って動かすために、アクセシビリティの許可を使います。キー入力や画面の内容は記録しません。")
                    .font(.lane(13))
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 12) {
                Step(number: 1, text: "下のボタンでシステム設定を開く")
                Step(number: 2, text: "「プライバシーとセキュリティ」→「アクセシビリティ」で LaneKeep をオン")
                Step(number: 3, text: "この画面に戻ると自動で次に進みます")
            }
            status
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                Button("システム設定を開く") {
                    model.requestAccessibilityPermission()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(model.isAccessibilityGranted)
                .keyboardShortcut(.defaultAction)
                Button("あとで") {
                    model.onboardingDismissed = true
                }
                .buttonStyle(PlainTextButtonStyle(color: Theme.ink2))
                .frame(height: 40)
                .disabled(model.isAccessibilityGranted)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(EdgeInsets(top: 24, leading: 20, bottom: 24, trailing: 20))
    }

    private var status: some View {
        let granted = model.isAccessibilityGranted
        return HStack(spacing: 10) {
            Circle()
                .fill(granted ? Theme.accent : Theme.display2)
                .frame(width: 10, height: 10)
            Text(granted ? "許可されました。一覧に進みます" : "まだ許可されていません")
                .font(.lane(13))
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .laneBox()
        .accessibilityElement(children: .combine)
    }

    private struct Step: View {
        let number: Int
        let text: String

        var body: some View {
            HStack(alignment: .top, spacing: 10) {
                Text("\(number)")
                    .font(.lane(12, .bold))
                    .foregroundStyle(Theme.accentInk)
                    .frame(width: 22, height: 22)
                    .background(Theme.accentSoft, in: Circle())
                Text(text)
                    .font(.lane(13))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
