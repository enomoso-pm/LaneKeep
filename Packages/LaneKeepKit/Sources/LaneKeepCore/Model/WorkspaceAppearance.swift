import Foundation

/// The tile color of a workspace (spec §3.1: blue, orange, green, gray).
public enum WorkspaceColor: String, CaseIterable, Codable, Sendable {
    case blue
    case orange
    case green
    case gray

    /// sRGB value of the tile. The same value is used in light and dark appearance (see the UI mock).
    public var hex: UInt32 {
        switch self {
        case .blue: 0x2457C5
        case .orange: 0xB4530A
        case .green: 0x1F6B52
        case .gray: 0x4A4A50
        }
    }

    /// Name read out by VoiceOver and shown in tooltips.
    public var displayName: String {
        switch self {
        case .blue: "青"
        case .orange: "オレンジ"
        case .green: "緑"
        case .gray: "グレー"
        }
    }

    /// Unknown values (for example from a newer version of the app) fall back to blue instead of
    /// making the whole file unreadable.
    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = WorkspaceColor(rawValue: rawValue) ?? .blue
    }
}

/// The glyph drawn on a workspace tile.
public enum WorkspaceIcon: String, CaseIterable, Codable, Sendable {
    case home
    case office
    case laptop
    case display
    case cafe

    public var displayName: String {
        switch self {
        case .home: "自宅"
        case .office: "オフィス"
        case .laptop: "ノートPC"
        case .display: "ディスプレイ"
        case .cafe: "カフェ"
        }
    }

    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = WorkspaceIcon(rawValue: rawValue) ?? .display
    }
}
