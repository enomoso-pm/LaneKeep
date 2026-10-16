import SwiftUI

/// The large blue button ("今の配置を保存…", "システム設定を開く"): 44 pt high, full width.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButton(configuration: configuration)
    }

    private struct PrimaryButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.lane(14, .semibold))
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Size.primaryButtonHeight)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.accent)
                        .brightness(configuration.isPressed ? -0.06 : (isHovering && isEnabled ? 0.05 : 0))
                )
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .onHover { isHovering = $0 }
        }
    }
}

/// The regular bordered button (".btn"): 32 pt high. `prominent` is the blue variant used for
/// "復元" in the settings window.
struct LaneButtonStyle: ButtonStyle {
    var prominent = false
    var height: CGFloat = Theme.Size.buttonHeight

    func makeBody(configuration: Configuration) -> some View {
        LaneButton(configuration: configuration, prominent: prominent, height: height)
    }

    private struct LaneButton: View {
        let configuration: ButtonStyleConfiguration
        let prominent: Bool
        let height: CGFloat
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.lane(13, .semibold))
                .lineLimit(1)
                .foregroundStyle(prominent ? Theme.onAccent : Theme.ink)
                .padding(.horizontal, 12)
                .frame(height: height)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(prominent ? Theme.accent : Theme.lineStrong, lineWidth: 1)
                )
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .onHover { isHovering = $0 }
        }

        private var background: some View {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
            return Group {
                if prominent {
                    shape.fill(Theme.accent)
                        .brightness(configuration.isPressed ? -0.06 : (isHovering && isEnabled ? 0.05 : 0))
                } else {
                    shape.fill(configuration.isPressed || (isHovering && isEnabled) ? Theme.muted : Theme.panel)
                }
            }
        }
    }
}

/// A borderless text button ("終了", "あとで"). `height` gives it the height of a regular button
/// (".btn" without a border); otherwise it hugs the text.
struct PlainTextButtonStyle: ButtonStyle {
    var color: Color = Theme.sub
    var weight: Font.Weight = .medium
    var size: CGFloat = 13
    var height: CGFloat?
    var horizontalPadding: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        PlainTextButton(
            configuration: configuration,
            color: color,
            weight: weight,
            size: size,
            height: height,
            horizontalPadding: horizontalPadding
        )
    }

    private struct PlainTextButton: View {
        let configuration: ButtonStyleConfiguration
        let color: Color
        let weight: Font.Weight
        let size: CGFloat
        let height: CGFloat?
        let horizontalPadding: CGFloat
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.lane(size, weight))
                .foregroundStyle(color)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, height == nil ? 4 : 0)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovering || configuration.isPressed ? Theme.muted : .clear)
                )
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
        }
    }
}

/// 36 × 36 icon button with a hover background (".icon-btn").
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButton(configuration: configuration)
    }

    private struct IconButton: View {
        let configuration: ButtonStyleConfiguration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(Theme.ink2)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(isHovering || configuration.isPressed ? Theme.muted : .clear)
                )
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
        }
    }
}

/// The mock's 44 × 26 switch: the label on the left, the switch on the right.
///
/// Only the switch reacts to clicks, like the system switch; to VoiceOver the whole row is one
/// standard toggle.
struct LaneSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            LaneSwitch(isOn: configuration.$isOn)
        }
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
        }
    }
}

/// The switch itself, usable without a label.
struct LaneSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? Theme.accent : Theme.lineStrong)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    .frame(width: 20, height: 20)
                    .padding(3)
            }
            .frame(width: Theme.Size.toggle.width, height: Theme.Size.toggle.height)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
