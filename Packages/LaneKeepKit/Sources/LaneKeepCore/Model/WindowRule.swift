import Foundation

/// Where one window should go (spec §5).
public struct WindowRule: Codable, Equatable, Sendable, Identifiable {
    /// Stable identity for the settings table. Not part of the matching.
    public var id: UUID
    public var bundleID: String
    public var appName: String
    /// Optional text the window title must contain. Takes precedence over `index`.
    public var titleContains: String?
    /// Position of the window among the app's windows when it was saved.
    public var index: Int
    public var displayUUID: String
    /// Position and size relative to the display's visible frame (0…1, origin at the top-left).
    public var relativeFrame: CGRect
    public var launchIfClosed: Bool

    public init(
        id: UUID = UUID(),
        bundleID: String,
        appName: String,
        titleContains: String? = nil,
        index: Int,
        displayUUID: String,
        relativeFrame: CGRect,
        launchIfClosed: Bool
    ) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.titleContains = titleContains
        self.index = index
        self.displayUUID = displayUUID
        self.relativeFrame = relativeFrame
        self.launchIfClosed = launchIfClosed
    }

    /// `titleContains` without surrounding whitespace, or `nil` when there is nothing to match.
    public var titleMarker: String? {
        guard let trimmed = titleContains?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case bundleID
        case appName
        case titleContains
        case index
        case displayUUID
        case relativeFrame
        case launchIfClosed
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        bundleID = try container.decode(String.self, forKey: .bundleID)
        appName = try container.decodeIfPresent(String.self, forKey: .appName) ?? bundleID
        titleContains = try container.decodeIfPresent(String.self, forKey: .titleContains)
        index = max(0, try container.decodeIfPresent(Int.self, forKey: .index) ?? 0)
        displayUUID = try container.decode(String.self, forKey: .displayUUID)
        relativeFrame = try container.decodeRect(forKey: .relativeFrame)
        launchIfClosed = try container.decodeIfPresent(Bool.self, forKey: .launchIfClosed) ?? true
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(bundleID, forKey: .bundleID)
        try container.encode(appName, forKey: .appName)
        try container.encodeIfPresent(titleContains, forKey: .titleContains)
        try container.encode(index, forKey: .index)
        try container.encode(displayUUID, forKey: .displayUUID)
        try container.encodeRect(relativeFrame, forKey: .relativeFrame)
        try container.encode(launchIfClosed, forKey: .launchIfClosed)
    }
}
