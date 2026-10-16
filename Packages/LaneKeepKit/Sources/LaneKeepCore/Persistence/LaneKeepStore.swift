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
    /// not make the other workspaces unreadable; it is counted in `unreadableEntries`. An object
    /// without a `workspaces` list is not a workspace file (e.g. a misspelled key in a hand edit)
    /// and fails, so that it is kept instead of being overwritten with an empty list.
    public init(from decoder: any Decoder) throws {
        let list: LossyList<Workspace>
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            version = try container.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
            list = try container.decode(LossyList<Workspace>.self, forKey: .workspaces)
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

/// What was wrong with a file that was read.
public enum StoreProblem: Equatable, Sendable {
    /// Nothing in the file could be used (not JSON, wrong structure, or not readable at all).
    case unreadable
    /// This many entries could not be read and were left out.
    case partlyUnreadable(entries: Int)
}

/// What to do with a file that cannot be read completely.
public enum UnreadableFileHandling: Sendable {
    /// Keep a copy next to it (`<name>.unreadable-<date>.json`) before the program writes the file
    /// again. A file that cannot be used at all is moved aside. For the app, which saves often.
    case backUp
    /// Leave the file alone, for programs that only read, or refuse to write after a problem.
    case leave
}

/// One version of a file on disk, to notice when another program changed it.
public struct FileStamp: Equatable, Sendable {
    public var modificationDate: Date
    public var size: Int

    public init(modificationDate: Date, size: Int) {
        self.modificationDate = modificationDate
        self.size = size
    }
}

/// The result of reading a file.
public struct StoreLoad<Value: Sendable>: Sendable {
    public var value: Value
    public var problem: StoreProblem?
    /// Where the unreadable file was kept, with `.backUp`.
    public var backupOfUnreadableFile: URL?
    /// The version of the file that was read; `nil` when there was no file.
    public var stamp: FileStamp?

    public init(value: Value, problem: StoreProblem? = nil, backupOfUnreadableFile: URL? = nil, stamp: FileStamp? = nil) {
        self.value = value
        self.problem = problem
        self.backupOfUnreadableFile = backupOfUnreadableFile
        self.stamp = stamp
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

    public func loadWorkspaces(unreadableFile handling: UnreadableFileHandling = .backUp) -> StoreLoad<[Workspace]> {
        let url = workspacesURL
        let fileStamp = stamp(of: url)
        guard FileManager.default.fileExists(atPath: url.path) else {
            // A missing file is the normal first-launch case.
            return StoreLoad(value: [])
        }
        guard let data = try? Data(contentsOf: url),
              let document = try? Self.makeDecoder().decode(WorkspaceDocument.self, from: data)
        else {
            let backup = handling == .backUp ? backUp(url, move: true) : nil
            // A file that was moved aside is no longer there.
            return StoreLoad(value: [], problem: .unreadable, backupOfUnreadableFile: backup, stamp: backup == nil ? fileStamp : nil)
        }
        guard document.unreadableEntries == 0 else {
            let backup = handling == .backUp ? backUp(url, move: false) : nil
            return StoreLoad(
                value: document.workspaces,
                problem: .partlyUnreadable(entries: document.unreadableEntries),
                backupOfUnreadableFile: backup,
                stamp: fileStamp
            )
        }
        return StoreLoad(value: document.workspaces, stamp: fileStamp)
    }

    /// Writes the workspaces and returns the version of the file that was written.
    @discardableResult
    public func saveWorkspaces(_ workspaces: [Workspace]) throws -> FileStamp? {
        try save(WorkspaceDocument(workspaces: workspaces), to: workspacesURL)
        return stamp(of: workspacesURL)
    }

    public func loadPreferences(unreadableFile handling: UnreadableFileHandling = .backUp) -> StoreLoad<Preferences> {
        let url = preferencesURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return StoreLoad(value: Preferences())
        }
        guard let data = try? Data(contentsOf: url),
              let preferences = try? Self.makeDecoder().decode(Preferences.self, from: data)
        else {
            let backup = handling == .backUp ? backUp(url, move: true) : nil
            return StoreLoad(value: Preferences(), problem: .unreadable, backupOfUnreadableFile: backup, stamp: stamp(of: url))
        }
        return StoreLoad(value: preferences, stamp: stamp(of: url))
    }

    public func savePreferences(_ preferences: Preferences) throws {
        try save(preferences, to: preferencesURL)
    }

    /// The current version of the workspaces file, or `nil` when there is none.
    public var workspacesStamp: FileStamp? {
        stamp(of: workspacesURL)
    }

    func stamp(of url: URL) -> FileStamp? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        let size = (attributes[.size] as? NSNumber)?.intValue
            ?? (attributes[.size] as? UInt64).map { Int($0) }
            ?? (attributes[.size] as? Int)
            ?? 0
        return FileStamp(modificationDate: attributes[.modificationDate] as? Date ?? .distantPast, size: size)
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
