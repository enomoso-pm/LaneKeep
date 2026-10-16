import LaneKeepCore
import SwiftUI

/// The "配置図": which window sits on which display, and where (the signature element of the
/// mock). The geometry comes from `DisplayMapLayout`.
struct DisplayMapView: View {
    let displays: [MapDisplay]
    let windows: [MapWindow]
    var selectedWindowID: String?
    var onSelectWindow: ((String) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let layout = DisplayMapLayout(displays: displays, windows: windows, size: proxy.size, padding: 12, labelHeight: 18, gap: 10)
            ZStack(alignment: .topLeading) {
                ForEach(layout.displays) { placed in
                    displayBox(placed, windows: layout.windows.filter { $0.window.displayID == placed.id })
                }
                ForEach(layout.windows) { placed in
                    windowBox(placed)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: windows.map(\.id))
        }
        .background(Theme.muted, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            if displays.isEmpty {
                Text("ディスプレイの情報がありません")
                    .font(.lane(12))
                    .foregroundStyle(Theme.sub)
            }
        }
    }

    private func displayBox(_ placed: DisplayMapLayout.PlacedDisplay, windows: [DisplayMapLayout.PlacedWindow]) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return ZStack(alignment: .topLeading) {
            shape
                .fill(Theme.panel)
                .overlay(shape.strokeBorder(Theme.displayColor(placed.display.role), lineWidth: 2))
                .frame(width: placed.rect.width, height: placed.rect.height)
                .offset(x: placed.rect.minX, y: placed.rect.minY)
                .accessibilityElement()
                .accessibilityLabel(accessibilityLabel(placed.display, windows: windows))
            Text(placed.display.name)
                .font(.lane(11))
                .foregroundStyle(Theme.sub)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: max(48, placed.rect.width - 6), alignment: .leading)
                .offset(x: placed.rect.minX + 6, y: placed.rect.maxY + 3)
                .accessibilityHidden(true)
        }
    }

    private func windowBox(_ placed: DisplayMapLayout.PlacedWindow) -> some View {
        let isSelected = placed.id == selectedWindowID
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let showsLabel = placed.rect.width >= 22 && placed.rect.height >= 14
        return shape
            .fill(Theme.displaySoftColor(placed.role))
            .overlay(shape.strokeBorder(Theme.displayColor(placed.role), lineWidth: 1))
            .overlay(alignment: .topLeading) {
                if showsLabel {
                    Text(placed.window.label)
                        .font(.lane(10))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                }
            }
            .clipShape(shape)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Theme.ink, lineWidth: 2)
                        .padding(-3)
                }
            }
            .frame(width: placed.rect.width, height: placed.rect.height)
            .contentShape(Rectangle())
            .onTapGesture {
                onSelectWindow?(placed.id)
            }
            .help(placed.window.label)
            .offset(x: placed.rect.minX, y: placed.rect.minY)
            .zIndex(isSelected ? 1 : 0)
            .accessibilityHidden(true)
    }

    private func accessibilityLabel(_ display: MapDisplay, windows: [DisplayMapLayout.PlacedWindow]) -> String {
        guard !windows.isEmpty else {
            return "\(display.name)、ウィンドウなし"
        }
        return "\(display.name)、ウィンドウ\(windows.count)件：" + windows.map(\.window.label).joined(separator: "、")
    }
}

/// The small drawing of the connected displays in the popover header (44 × 30).
struct DisplayGlyph: View {
    let displays: [MapDisplay]

    var body: some View {
        Canvas { context, size in
            guard !displays.isEmpty else { return }
            let bounds = displays.map(\.frame).reduce(CGRect.null) { $0.union($1) }
            let standSpace: CGFloat = 4
            let scale = min((size.width - 2) / bounds.width, (size.height - 2 - standSpace) / bounds.height)
            let contentWidth = bounds.width * scale
            let contentHeight = bounds.height * scale
            let origin = CGPoint(x: (size.width - contentWidth) / 2, y: (size.height - standSpace - contentHeight) / 2)
            for display in displays {
                let rect = CGRect(
                    x: origin.x + (display.frame.minX - bounds.minX) * scale,
                    y: origin.y + (display.frame.minY - bounds.minY) * scale,
                    width: display.frame.width * scale,
                    height: display.frame.height * scale
                ).insetBy(dx: 1.2, dy: 1.2)
                let color = Theme.displayColor(display.role)
                context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(color), lineWidth: 1.6)
                if display.role != .secondary {
                    var stand = Path()
                    stand.move(to: CGPoint(x: rect.midX - 3, y: rect.maxY + 3))
                    stand.addLine(to: CGPoint(x: rect.midX + 3, y: rect.maxY + 3))
                    context.stroke(stand, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                }
            }
        }
        .frame(width: 44, height: 30)
        .accessibilityHidden(true)
    }
}
