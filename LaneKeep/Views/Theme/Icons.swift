import LaneKeepCore
import SwiftUI

/// The stroked icons of the UI mock, redrawn from its SVG paths.
enum LaneIcon: Sendable {
    case brand
    case gear
    case back
    case plus
    case check
    case permission
    case workspace(WorkspaceIcon)

    /// Size of the SVG viewBox the path coordinates refer to.
    var viewBox: CGFloat {
        switch self {
        case .brand: 22
        case .permission: 48
        default: 24
        }
    }

    /// Stroke width in viewBox units (scaled with the icon, like SVG).
    var strokeWidth: CGFloat {
        switch self {
        case .brand: 1.6
        case .gear, .workspace: 1.8
        case .back, .plus, .permission: 2
        case .check: 2.2
        }
    }

    func path() -> Path {
        var path = Path()
        switch self {
        case .brand:
            path.addRoundedRect(in: CGRect(x: 2, y: 5, width: 11, height: 8), cornerSize: CGSize(width: 1.5, height: 1.5))
            path.addRoundedRect(in: CGRect(x: 14.5, y: 3, width: 5.5, height: 12), cornerSize: CGSize(width: 1.2, height: 1.2))
            path.line(6, 17, 9, 17)
        case .gear:
            path.addEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))
            path.line(12, 2, 12, 5)
            path.line(12, 19, 12, 22)
            path.line(4.2, 4.2, 6.3, 6.3)
            path.line(17.7, 17.7, 19.8, 19.8)
            path.line(2, 12, 5, 12)
            path.line(19, 12, 22, 12)
            path.line(4.2, 19.8, 6.3, 17.7)
            path.line(17.7, 6.3, 19.8, 4.2)
        case .back:
            path.move(to: CGPoint(x: 15, y: 5))
            path.addLine(to: CGPoint(x: 8, y: 12))
            path.addLine(to: CGPoint(x: 15, y: 19))
        case .plus:
            path.line(12, 5, 12, 19)
            path.line(5, 12, 19, 12)
        case .check:
            path.move(to: CGPoint(x: 5, y: 12))
            path.addLine(to: CGPoint(x: 9, y: 16))
            path.addLine(to: CGPoint(x: 19, y: 6))
        case .permission:
            path.addRoundedRect(in: CGRect(x: 4, y: 12, width: 24, height: 17), cornerSize: CGSize(width: 3, height: 3))
            path.addRoundedRect(in: CGRect(x: 31, y: 7, width: 13, height: 27), cornerSize: CGSize(width: 2.5, height: 2.5))
            path.line(12, 37, 20, 37)
            path.line(16, 29, 16, 37)
        case .workspace(let icon):
            Self.addWorkspaceIcon(icon, to: &path)
        }
        return path
    }

    private static func addWorkspaceIcon(_ icon: WorkspaceIcon, to path: inout Path) {
        switch icon {
        case .home:
            path.move(to: CGPoint(x: 4, y: 11))
            path.addLine(to: CGPoint(x: 12, y: 5))
            path.addLine(to: CGPoint(x: 20, y: 11))
            path.addLine(to: CGPoint(x: 20, y: 19))
            path.addLine(to: CGPoint(x: 4, y: 19))
            path.closeSubpath()
            path.move(to: CGPoint(x: 10, y: 19))
            path.addLine(to: CGPoint(x: 10, y: 14))
            path.addLine(to: CGPoint(x: 14, y: 14))
            path.addLine(to: CGPoint(x: 14, y: 19))
        case .office:
            path.addRoundedRect(in: CGRect(x: 5, y: 3, width: 14, height: 18), cornerSize: CGSize(width: 1, height: 1))
            path.line(9, 7, 11, 7)
            path.line(13, 7, 15, 7)
            path.line(9, 11, 11, 11)
            path.line(13, 11, 15, 11)
            path.move(to: CGPoint(x: 10, y: 21))
            path.addLine(to: CGPoint(x: 10, y: 17))
            path.addLine(to: CGPoint(x: 14, y: 17))
            path.addLine(to: CGPoint(x: 14, y: 21))
        case .laptop:
            path.addRoundedRect(in: CGRect(x: 5, y: 5, width: 14, height: 10), cornerSize: CGSize(width: 1, height: 1))
            path.line(3, 19, 21, 19)
        case .display:
            path.addRoundedRect(in: CGRect(x: 3, y: 4, width: 18, height: 12), cornerSize: CGSize(width: 1.5, height: 1.5))
            path.line(12, 16, 12, 20)
            path.line(8.5, 20, 15.5, 20)
        case .cafe:
            path.move(to: CGPoint(x: 5, y: 9))
            path.addLine(to: CGPoint(x: 16, y: 9))
            path.addLine(to: CGPoint(x: 16, y: 13))
            path.addQuadCurve(to: CGPoint(x: 10.5, y: 18.5), control: CGPoint(x: 16, y: 18.5))
            path.addQuadCurve(to: CGPoint(x: 5, y: 13), control: CGPoint(x: 5, y: 18.5))
            path.closeSubpath()
            path.move(to: CGPoint(x: 16, y: 10.5))
            path.addCurve(to: CGPoint(x: 16, y: 15), control1: CGPoint(x: 20, y: 10.5), control2: CGPoint(x: 20, y: 15))
            path.line(8.5, 3.5, 8.5, 6)
            path.line(12.5, 3.5, 12.5, 6)
            path.line(4, 21.5, 17, 21.5)
        }
    }
}

private extension Path {
    mutating func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
        move(to: CGPoint(x: x1, y: y1))
        addLine(to: CGPoint(x: x2, y: y2))
    }
}

/// A `LaneIcon` scaled into its frame.
struct LaneIconShape: Shape {
    let icon: LaneIcon

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / icon.viewBox
        let offset = CGPoint(
            x: rect.minX + (rect.width - icon.viewBox * scale) / 2,
            y: rect.minY + (rect.height - icon.viewBox * scale) / 2
        )
        return icon.path().applying(
            CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)
        )
    }
}

/// Draws an icon at a given size with the stroke width scaled like the SVG original. Without a
/// color it uses the current foreground style.
struct LaneIconView: View {
    let icon: LaneIcon
    var size: CGFloat = 18
    var color: Color?

    var body: some View {
        stroked
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var stroked: some View {
        let shape = LaneIconShape(icon: icon).stroke(
            style: StrokeStyle(lineWidth: icon.strokeWidth * size / icon.viewBox, lineCap: .round, lineJoin: .round)
        )
        if let color {
            shape.foregroundStyle(color)
        } else {
            shape
        }
    }
}
