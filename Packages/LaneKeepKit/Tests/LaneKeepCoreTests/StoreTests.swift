import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import LaneKeepCore

@Suite("Saving to workspaces.json (spec §5)")
struct StoreTests {
    /// A fresh, empty directory for each test.
    func makeStore() throws -> LaneKeepStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LaneKeepTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return LaneKeepStore(directory: directory)
    }

    func files(in store: LaneKeepStore) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: store.directory.path).sorted()
    }

    @Test("Workspaces survive a round trip")
    func roundTrip() throws {
        let store = try makeStore()
        var home = Fixtures.homeWorkspace
        home.shortcut = "restoreWorkspace-1"
        home.lastUsedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let workspaces = [home, Fixtures.officeWorkspace, Fixtures.laptopWorkspace]

        try store.saveWorkspaces(workspaces)
        let load = store.loadWorkspaces()

        #expect(load.value == workspaces)
        #expect(load.backupOfUnreadableFile == nil)
    }

    @Test("A missing file means no workspaces")
    func missingFile() throws {
        let store = try makeStore()
        let load = store.loadWorkspaces()
        #expect(load.value.isEmpty)
        #expect(load.backupOfUnreadableFile == nil)
    }

    @Test("The file is readable JSON with a version")
    func format() throws {
        let store = try makeStore()
        try store.saveWorkspaces([Fixtures.laptopWorkspace])
        let text = try String(contentsOf: store.workspacesURL, encoding: .utf8)
        #expect(text.contains("\"version\" : 1"))
        #expect(text.contains("\"relativeFrame\" : {"))
        #expect(text.contains("\"displaySignature\" : \"BUILTIN\""))
    }

    @Test("An unreadable file is kept as a backup")
    func corruptFile() throws {
        let store = try makeStore()
        try Data("{ not json".utf8).write(to: store.workspacesURL)

        let load = store.loadWorkspaces()

        #expect(load.value.isEmpty)
        let backup = try #require(load.backupOfUnreadableFile)
        #expect(try String(contentsOf: backup, encoding: .utf8) == "{ not json")
        #expect(!FileManager.default.fileExists(atPath: store.workspacesURL.path))
    }

    @Test("One broken workspace does not take the others with it")
    func partiallyBroken() throws {
        let store = try makeStore()
        try store.saveWorkspaces([Fixtures.laptopWorkspace])
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: store.workspacesURL)) as! [String: Any]
        var list = json["workspaces"] as! [Any]
        list.append(["name": "broken", "windows": [["bundleID": 42]]])
        json["workspaces"] = list
        try JSONSerialization.data(withJSONObject: json).write(to: store.workspacesURL)

        let load = store.loadWorkspaces()

        #expect(load.value.map(\.name) == ["ノートPCのみ"])
        #expect(load.backupOfUnreadableFile != nil)
        // The original stays in place until the app saves again.
        #expect(FileManager.default.fileExists(atPath: store.workspacesURL.path))
    }

    @Test("Older or hand-written files fill in defaults")
    func lenientDecoding() throws {
        let store = try makeStore()
        let json = """
        [
          {
            "name": "最小",
            "color": "purple",
            "displays": [{ "uuid": "A", "frame": [[0, 0], [1440, 900]] }],
            "windows": [
              { "bundleID": "com.apple.Safari", "displayUUID": "A", "relativeFrame": [[0, 0], [0.5, 1]] }
            ]
          }
        ]
        """
        try Data(json.utf8).write(to: store.workspacesURL)

        let load = store.loadWorkspaces()
        let workspace = try #require(load.value.first)

        #expect(load.backupOfUnreadableFile == nil)
        #expect(workspace.name == "最小")
        #expect(workspace.color == .blue)
        #expect(workspace.icon == .display)
        #expect(workspace.displaySignature == "A")
        #expect(workspace.autoRestoreOnConnect)
        #expect(!workspace.autoRestoreOnWake)
        #expect(workspace.displays[0].frame == CGRect(x: 0, y: 0, width: 1440, height: 900))
        let rule = try #require(workspace.windows.first)
        #expect(rule.appName == "com.apple.Safari")
        #expect(rule.index == 0)
        #expect(rule.launchIfClosed)
        #expect(rule.relativeFrame == CGRect(x: 0, y: 0, width: 0.5, height: 1))
    }

    @Test("Signatures saved before the built-in display was left out are made again")
    func migratesSignatures() throws {
        let store = try makeStore()
        let json = """
        {"version": 1, "workspaces": [
          {"name": "自宅", "displaySignature": "BUILTIN|EXT-27",
           "displays": [{"uuid": "EXT-27", "isMain": true}, {"uuid": "BUILTIN", "isBuiltin": true}],
           "windows": []},
          {"name": "ノートPCのみ", "displaySignature": "BUILTIN",
           "displays": [{"uuid": "BUILTIN", "isMain": true, "isBuiltin": true}],
           "windows": []},
          {"name": "画面の記録なし", "displaySignature": "X|Y", "windows": []}
        ]}
        """
        try Data(json.utf8).write(to: store.workspacesURL)

        let workspaces = store.loadWorkspaces().value

        #expect(workspaces.map(\.displaySignature) == ["EXT-27", "BUILTIN", "X|Y"])
        // The next save writes the new signature.
        try store.saveWorkspaces(workspaces)
        let text = try String(contentsOf: store.workspacesURL, encoding: .utf8)
        #expect(text.contains("\"displaySignature\" : \"EXT-27\""))
        #expect(!text.contains("BUILTIN|EXT-27"))
    }

    @Test("Preferences survive a round trip")
    func preferences() throws {
        let store = try makeStore()
        #expect(store.loadPreferences().value == Preferences())

        let preferences = Preferences(
            autoRestoreEnabled: false,
            missingDisplayFallback: .largestDisplay,
            excludedApps: [ExcludedApp(bundleID: "com.apple.finder", name: "Finder")]
        )
        try store.savePreferences(preferences)
        #expect(store.loadPreferences().value == preferences)
    }

    @Test("Unreadable preferences fall back to the defaults")
    func corruptPreferences() throws {
        let store = try makeStore()
        try Data("[]".utf8).write(to: store.preferencesURL)
        let load = store.loadPreferences()
        #expect(load.value == Preferences())
        #expect(load.backupOfUnreadableFile != nil)
    }

    @Test("Saving creates the directory")
    func createsDirectory() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("LaneKeepTests-\(UUID().uuidString)", isDirectory: true)
        let store = LaneKeepStore(directory: base.appendingPathComponent("nested/LaneKeep", isDirectory: true))
        try store.saveWorkspaces([])
        #expect(FileManager.default.fileExists(atPath: store.workspacesURL.path))
    }

    @Test("The default location is Application Support/LaneKeep")
    func defaultDirectory() {
        #expect(LaneKeepStore.defaultDirectory.lastPathComponent == "LaneKeep")
    }

    @Test("Problems are reported, and read-only loads leave the file where it is")
    func readOnlyLoad() throws {
        let store = try makeStore()
        try Data("{ not json".utf8).write(to: store.workspacesURL)

        let load = store.loadWorkspaces(unreadableFile: .leave)

        #expect(load.value.isEmpty)
        #expect(load.problem == .unreadable)
        #expect(load.backupOfUnreadableFile == nil)
        #expect(try files(in: store) == ["workspaces.json"])
    }

    @Test("Partly readable files report how many entries were left out")
    func partlyReadableProblem() throws {
        let store = try makeStore()
        let json = """
        {"version": 1, "workspaces": [{"name": "broken", "windows": [{"bundleID": 42}]}, {"name": "ok", "displays": [], "windows": []}]}
        """
        try Data(json.utf8).write(to: store.workspacesURL)

        let load = store.loadWorkspaces(unreadableFile: .leave)

        #expect(load.value.map(\.name) == ["ok"])
        #expect(load.problem == .partlyUnreadable(entries: 1))
        #expect(try files(in: store) == ["workspaces.json"])
    }

    @Test("An object without a workspaces list is unreadable, not empty")
    func missingWorkspacesKey() throws {
        let store = try makeStore()
        try Data(#"{"version": 1, "Workspaces": []}"#.utf8).write(to: store.workspacesURL)

        let load = store.loadWorkspaces()

        #expect(load.problem == .unreadable)
        #expect(load.backupOfUnreadableFile != nil)
    }

    @Test("Reads and writes report the version of the file")
    func stamps() throws {
        let store = try makeStore()
        #expect(store.workspacesStamp == nil)

        let written = try store.saveWorkspaces([Fixtures.laptopWorkspace])
        #expect(written != nil)
        #expect(written == store.workspacesStamp)
        #expect(store.loadWorkspaces().stamp == written)

        try store.saveWorkspaces([Fixtures.laptopWorkspace, Fixtures.homeWorkspace])
        #expect(store.workspacesStamp != written)
    }

    @Test("A display listed twice in a file is read once")
    func duplicateDisplays() throws {
        let store = try makeStore()
        let json = """
        [{"name": "dup", "displays": [{"uuid": "A", "name": "first"}, {"uuid": "A", "name": "second"}], "windows": []}]
        """
        try Data(json.utf8).write(to: store.workspacesURL)

        let workspace = try #require(store.loadWorkspaces().value.first)

        #expect(workspace.displays.map(\.name) == ["first"])
        // Drawing it does not trip over the duplicate either.
        let layout = DisplayMapLayout(displays: MapDisplay.from(workspace.displays), windows: [], size: CGSize(width: 300, height: 150))
        #expect(layout.displays.count == 1)
    }
}
