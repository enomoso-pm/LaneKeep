import LaneKeepCore
import SwiftUI

/// The colored square with the workspace glyph (".tile").
struct WorkspaceTile: View {
    let color: WorkspaceColor
    let icon: WorkspaceIcon
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size / 4, style: .continuous)
            .fill(Theme.tileColor(color))
            .frame(width: size, height: size)
            .overlay(LaneIconView(icon: .workspace(icon), size: size / 2, color: .white))
            .accessibilityHidden(true)
    }
}

/// The app's initial on a gray square (".app"), as the spec asks for instead of the app icon.
struct AppInitialBadge: View {
    let name: String

    var body: some View {
        Text(initial)
            .font(.lane(11, .bold))
            .foregroundStyle(Theme.ink2)
            .frame(width: 22, height: 22)
            .background(Theme.muted, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}

/// A small square in the display's color (".dot").
struct DisplayDot: View {
    let role: DisplayRole

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Theme.displayColor(role))
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }
}

/// Display name with its color dot, either plain or as a gray pill (".pill").
struct DisplayLabel: View {
    let name: String
    let role: DisplayRole
    var pill = false

    var body: some View {
        HStack(spacing: 6) {
            DisplayDot(role: role)
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.lane(12))
        .foregroundStyle(pill ? Theme.ink : Theme.sub)
        .padding(.horizontal, pill ? 8 : 0)
        .frame(height: pill ? 24 : nil)
        .background {
            if pill {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.muted)
            }
        }
    }
}

/// A keyboard shortcut drawn as a key cap (".kbd"). A placeholder ("なし") is drawn in gray.
struct KeyCap: View {
    let text: String
    var isPlaceholder = false
    var isHighlighted = false

    var body: some View {
        Text(text)
            .font(.lane(13, isPlaceholder ? .regular : .semibold))
            .foregroundStyle(isPlaceholder ? Theme.sub : Theme.ink)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                isHighlighted ? Theme.muted : Theme.panel,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.lineStrong, lineWidth: 1)
            )
    }
}

/// The thin progress bar of a restoring workspace (".bar").
struct LaneProgressBar: View {
    let fraction: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.muted)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: proxy.size.width * min(1, max(0, fraction)))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: fraction)
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityLabel("配置の進み具合")
        .accessibilityValue("\(Int((fraction * 100).rounded()))パーセント")
    }
}

/// The swatches of the four workspace colors.
struct ColorSwatches: View {
    @Binding var selection: WorkspaceColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(WorkspaceColor.allCases, id: \.self) { color in
                Button {
                    selection = color
                } label: {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Theme.tileColor(color))
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(selection == color ? Theme.ink : .clear, lineWidth: 2)
                        )
                }
                .buttonStyle(.plain)
                .help(color.displayName)
                .accessibilityLabel(color.displayName)
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
    }
}
