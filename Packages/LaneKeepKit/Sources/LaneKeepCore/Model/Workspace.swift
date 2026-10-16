import Foundation

/// A named "display configuration + window layout" (spec §2, §5).
public struct Workspace: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var color: WorkspaceColor
    public var icon: WorkspaceIcon
    /// Name of the KeyboardShortcuts entry that restores this workspace.
    public var shortcut: String?
    /// Sorted UUIDs of the displays that were connected when the workspace was saved.
    public var displaySignature: String
    public var displays: [DisplayInfo]
    public var windows: [WindowRule]
    public var autoRestoreOnConnect: Bool
    public var autoRestoreOnWake: Bool
    public var lastUsedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        color: WorkspaceColor = .blue,
        icon: WorkspaceIcon = .display,
        shortcut: String? = nil,
        displays: [DisplayInfo],
        windows: [WindowRule],
        autoRestoreOnConnect: Bool = true,
        autoRestoreOnWake: Bool = false,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.shortcut = shortcut
        self.displaySignature = DisplaySignature.make(displays.map(\.uuid))
        self.displays = displays
        self.windows = windows
        self.autoRestoreOnConnect = autoRestoreOnConnect
        self.autoRestoreOnWake = autoRestoreOnWake
        self.lastUsedAt = lastUsedAt
    }

    /// Number of different apps among the window rules.
    public var appCount: Int {
        Set(windows.map(\.bundleID)).count
    }

    public func display(withUUID uuid: String) -> DisplayInfo? {
        displays.first { $0.uuid == uuid }
    }

    /// Replaces the recorded display configuration (and its signature).
    public mutating func setDisplays(_ newDisplays: [DisplayInfo]) {
        displays = newDisplays
        displaySignature = DisplaySignature.make(newDisplays.map(\.uuid))
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case color
        case icon
        case shortcut
        case displaySignature
        case displays
        case windows
        case autoRestoreOnConnect
        case autoRestoreOnWake
        case lastUsedAt
    }

    /// Lenient decoding: missing optional fields get their defaults so that a hand-edited or older
    /// file still loads.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "名称未設定"
        color = try container.decodeIfPresent(WorkspaceColor.self, forKey: .color) ?? .blue
        icon = try container.decodeIfPresent(WorkspaceIcon.self, forKey: .icon) ?? .display
        shortcut = try container.decodeIfPresent(String.self, forKey: .shortcut)
        displays = try container.decodeIfPresent([DisplayInfo].self, forKey: .displays) ?? []
        displaySignature = try container.decodeIfPresent(String.self, forKey: .displaySignature)
            ?? DisplaySignature.make(displays.map(\.uuid))
        windows = try container.decodeIfPresent([WindowRule].self, forKey: .windows) ?? []
        autoRestoreOnConnect = try container.decodeIfPresent(Bool.self, forKey: .autoRestoreOnConnect) ?? true
        autoRestoreOnWake = try container.decodeIfPresent(Bool.self, forKey: .autoRestoreOnWake) ?? false
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(color, forKey: .color)
        try container.encode(icon, forKey: .icon)
        try container.encodeIfPresent(shortcut, forKey: .shortcut)
        try container.encode(displaySignature, forKey: .displaySignature)
        try container.encode(displays, forKey: .displays)
        try container.encode(windows, forKey: .windows)
        try container.encode(autoRestoreOnConnect, forKey: .autoRestoreOnConnect)
        try container.encode(autoRestoreOnWake, forKey: .autoRestoreOnWake)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
    }
}
