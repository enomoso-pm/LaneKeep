import Foundation

/// Where windows go when the display they were saved on is not connected (spec §3.4).
public enum MissingDisplayFallback: String, CaseIterable, Codable, Sendable {
    /// The display with the menu bar. The default.
    case mainDisplay
    /// The display with the largest area.
    case largestDisplay
    /// Leave those windows where they are.
    case skip

    /// Label for the setting.
    public var title: String {
        switch self {
        case .mainDisplay: "メイン画面に寄せる"
        case .largestDisplay: "いちばん大きい画面に寄せる"
        case .skip: "寄せずにそのままにする"
        }
    }

    /// The destination as used in sentences ("メイン画面に寄せています"), `nil` for `.skip`.
    public var destinationName: String? {
        switch self {
        case .mainDisplay: "メイン画面"
        case .largestDisplay: "いちばん大きい画面"
        case .skip: nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = MissingDisplayFallback(rawValue: rawValue) ?? .mainDisplay
    }
}

/// An app whose windows are hidden from the "save current layout" list (spec §3.5).
public struct ExcludedApp: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var bundleID: String
    public var name: String

    public var id: String { bundleID }

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// App-wide settings. Stored next to the workspaces in `preferences.json`.
public struct Preferences: Codable, Equatable, Sendable {
    /// The "つないだら自動で復元" master switch (spec §3.3).
    public var autoRestoreEnabled: Bool
    public var missingDisplayFallback: MissingDisplayFallback
    public var excludedApps: [ExcludedApp]

    public init(
        autoRestoreEnabled: Bool = true,
        missingDisplayFallback: MissingDisplayFallback = .mainDisplay,
        excludedApps: [ExcludedApp] = []
    ) {
        self.autoRestoreEnabled = autoRestoreEnabled
        self.missingDisplayFallback = missingDisplayFallback
        self.excludedApps = excludedApps
    }

    public var excludedBundleIDs: Set<String> {
        Set(excludedApps.map(\.bundleID))
    }

    private enum CodingKeys: String, CodingKey {
        case autoRestoreEnabled
        case missingDisplayFallback
        case excludedApps
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoRestoreEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoRestoreEnabled) ?? true
        missingDisplayFallback = try container.decodeIfPresent(MissingDisplayFallback.self, forKey: .missingDisplayFallback) ?? .mainDisplay
        excludedApps = try container.decodeIfPresent([ExcludedApp].self, forKey: .excludedApps) ?? []
    }
}
