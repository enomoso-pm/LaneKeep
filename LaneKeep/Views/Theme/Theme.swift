import LaneKeepCore
import SwiftUI

/// Design tokens from SPEC.md §9 and the UI mock. Colors live in the asset catalog with light and
/// dark variants.
enum Theme {
    static let window = Color("Window")
    static let panel = Color("Panel")
    static let line = Color("Line")
    static let lineStrong = Color("LineStrong")
    static let ink = Color("Ink")
    static let ink2 = Color("Ink2")
    static let sub = Color("Sub")
    static let muted = Color("Muted")
    static let accent = Color("Accent")
    static let accentInk = Color("AccentInk")
    static let accentSoft = Color("AccentSoft")
    static let display2 = Color("Display2")
    static let display2Soft = Color("Display2Soft")
    static let displayGray = Color("DisplayGray")
    static let warn = Color("Warn")
    static let onAccent = Color("OnAccent")

    enum Radius {
        static let popover: CGFloat = 14
        static let card: CGFloat = 10
        static let button: CGFloat = 8
    }

    enum Size {
        static let popoverWidth: CGFloat = 360
        static let primaryButtonHeight: CGFloat = 44
        static let buttonHeight: CGFloat = 32
        static let toggle = CGSize(width: 44, height: 26)
    }

    /// Display colors: blue for the first display, orange for the second (always the built-in
    /// one), gray for the rest.
    static func displayColor(_ role: DisplayRole) -> Color {
        switch role {
        case .primary: accent
        case .secondary: display2
        case .tertiary: displayGray
        }
    }

    static func displaySoftColor(_ role: DisplayRole) -> Color {
        switch role {
        case .primary: accentSoft
        case .secondary: display2Soft
        case .tertiary: muted
        }
    }

    static func tileColor(_ color: WorkspaceColor) -> Color {
        Color(hex: color.hex)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Font {
    /// The mock's type scale: 10, 11, 12, 13, 14, 15, 18 and 20 pt in the system font (Hiragino
    /// Sans for Japanese).
    static func lane(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension View {
    /// The white "box" used for cards and grouped content: panel background, 1 pt line border,
    /// 10 pt corners.
    func laneBox(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        background(Theme.panel, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
    }
}
