import Foundation

/// The contents of `workspaces.json`.
public struct WorkspaceDocument: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var workspaces: [Workspace]
    /// Entries that could not be decoded and were left out (not written back).
    public var unreadableEntries: Int = 0

    public init(workspaces: [Workspace]) {
        self.version = Self.currentVersion
        self.workspaces = workspaces
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case workspaces
    }

    /// Accepts `{"version": 1, "workspaces": [...]}` as well as a bare array. A broken entry does
    /// not make the other workspaces unreadable; it is counted in `unreadableEntries`.
    public init(from decoder: any Decoder) throws {
        let list: LossyList<Workspace>
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
            list = try container.decodeIfPresent(LossyList<Workspace>.self, forKey: .workspaces) ?? LossyList()
        } else {
            version = Self.currentVersion
            list = try LossyList<Workspace>(from: decoder)
        }
        workspaces = list.elements
        unreadableEntries = list.failures
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(workspaces, forKey: .workspaces)
    }
}

/// An array whose broken elements are skipped instead of failing the whole array.
struct LossyList<Element: Decodable>: Decodable {
    var elements: [Element] = []
    var failures = 0

    init() {}

    init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                elements.append(element)
            } else {
                // A failed decode does not advance the container; step over the element.
                _ = try container.decode(Skip.self)
                failures += 1
            }
        }
    }

    private struct Skip: Decodable {
        init(from decoder: any Decoder) throws {}
    }
}

/// The result of reading a file.
public struct StoreLoad<Value: Sendable>: Sendable {
    public var value: Value
    /// Set when (part of) the file could not be read. The original file was kept at this location.
    public var backupOfUnreadableFile: URL?

    public init(value: Value, backupOfUnreadableFile: URL? = nil) {
        self.value = value
        self.backupOfUnreadableFile = backupOfUnreadableFile
    }
}

/// Reads and writes `~/Library/Application Support/LaneKeep/workspaces.json` and
/// `preferences.json` (spec §5).
public struct LaneKeepStore: Sendable {
    public let directory: URL

    public init(directory: URL = LaneKeepStore.defaultDirectory) {
        self.directory = directory
    }

    /// `~/Library/Application Support/LaneKeep`.
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("LaneKeep", isDirectory: true)
    }

    public var workspacesURL: URL {
        directory.appendingPathComponent("workspaces.json", isDirectory: false)
    }

    public var preferencesURL: URL {
        directory.appendingPathComponent("preferences.json", isDirectory: false)
    }

    public func loadWorkspaces() -> StoreLoad<[Workspace]> {
        guard let data = try? Data(contentsOf: workspacesURL) else {
            // A missing file is the normal first-launch case.
            return StoreLoad(value: [])
        }
        do {
            let document = try Self.makeDecoder().decode(WorkspaceDocument.self, from: data)
            let backup = document.unreadableEntries > 0 ? backUp(workspacesURL, move: false) : nil
            return StoreLoad(value: document.workspaces, backupOfUnreadableFile: backup)
        } catch {
            return StoreLoad(value: [], backupOfUnreadableFile: backUp(workspacesURL, move: true))
        }
    }

    public func saveWorkspaces(_ workspaces: [Workspace]) throws {
        try save(WorkspaceDocument(workspaces: workspaces), to: workspacesURL)
    }

    public func loadPreferences() -> StoreLoad<Preferences> {
        guard let data = try? Data(contentsOf: preferencesURL) else {
            return StoreLoad(value: Preferences())
        }
        do {
            return StoreLoad(value: try Self.makeDecoder().decode(Preferences.self, from: data))
        } catch {
            return StoreLoad(value: Preferences(), backupOfUnreadableFile: backUp(preferencesURL, move: true))
        }
    }

    public func savePreferences(_ preferences: Preferences) throws {
        try save(preferences, to: preferencesURL)
    }

    // MARK: - Coding

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func save<Value: Encodable>(_ value: Value, to url: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    /// Keeps an unreadable file next to the original as `<name>.unreadable-<timestamp>.json` so
    /// that nothing the user saved is lost when the defaults are written back.
    private func backUp(_ url: URL, move: Bool) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = url.deletingPathExtension().lastPathComponent
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent("\(stem).unreadable-\(formatter.string(from: Date())).json", isDirectory: false)
        do {
            if move {
                try FileManager.default.moveItem(at: url, to: destination)
            } else {
                try FileManager.default.copyItem(at: url, to: destination)
            }
            return destination
        } catch {
            return nil
        }
    }
}
