import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import LaneKeepCore

@Suite("Detecting display changes (spec §6.2)")
struct AutoRestoreTrackerTests {
    @Test("A new signature is a display change")
    func change() {
        var tracker = AutoRestoreTracker(initialSignature: "A")
        #expect(tracker.evaluate(currentSignature: "A|B") == .displaysChanged)
        #expect(tracker.lastSignature == "A|B")
        #expect(tracker.evaluate(currentSignature: "A|B") == nil)
    }

    @Test("Resolution changes (same signature) are ignored")
    func sameSignature() {
        var tracker = AutoRestoreTracker(initialSignature: "A|B")
        #expect(tracker.evaluate(currentSignature: "A|B") == nil)
    }

    @Test("Unplugging and plugging back in before things settle is no change")
    func backAndForth() {
        var tracker = AutoRestoreTracker(initialSignature: "A|B")
        // Only the state after the debounce is evaluated.
        #expect(tracker.evaluate(currentSignature: "A|B") == nil)
    }

    @Test("An empty signature is ignored and not remembered")
    func emptySignature() {
        var tracker = AutoRestoreTracker(initialSignature: "A|B")
        #expect(tracker.evaluate(currentSignature: "") == nil)
        #expect(tracker.lastSignature == "A|B")
        #expect(tracker.evaluate(currentSignature: "A") == .displaysChanged)
    }

    @Test("Wake is reported once")
    func wake() {
        var tracker = AutoRestoreTracker(initialSignature: "A")
        tracker.noteWake()
        #expect(tracker.evaluate(currentSignature: "A") == .wake)
        #expect(tracker.evaluate(currentSignature: "A") == nil)
    }

    @Test("Waking up with other displays reports both")
    func wakeWithChange() {
        var tracker = AutoRestoreTracker(initialSignature: "A")
        tracker.noteWake()
        #expect(tracker.evaluate(currentSignature: "A|B") == [.displaysChanged, .wake])
    }

    @Test("A wake noted while no display is reported survives until displays are back")
    func wakeDuringEmptySignature() {
        var tracker = AutoRestoreTracker(initialSignature: "A")
        tracker.noteWake()
        #expect(tracker.evaluate(currentSignature: "") == nil)
        #expect(tracker.evaluate(currentSignature: "A") == .wake)
    }
}

@Suite("Choosing the workspace to restore (spec §3.3)")
struct AutoRestorePolicyTests {
    func workspace(_ name: String, signature: String, connect: Bool = true, wake: Bool = false, lastUsed: Date? = nil) -> Workspace {
        var workspace = Workspace(
            name: name,
            displays: DisplaySignature.components(of: signature).map {
                DisplayInfo(uuid: $0, name: $0, frame: .zero, isMain: false)
            },
            windows: [Fixtures.rule("Safari", display: "A", 0, 0, 50, 50)],
            autoRestoreOnConnect: connect,
            autoRestoreOnWake: wake,
            lastUsedAt: lastUsed
        )
        workspace.displaySignature = signature
        return workspace
    }

    @Test("The matching workspace is chosen")
    func match() {
        let workspaces = [workspace("home", signature: "A|B"), workspace("laptop", signature: "A")]
        let chosen = AutoRestorePolicy.workspaceToRestore(among: workspaces, currentSignature: "A", trigger: .displaysChanged, masterSwitch: true)
        #expect(chosen?.name == "laptop")
    }

    @Test("The master switch turns everything off")
    func masterSwitch() {
        let workspaces = [workspace("home", signature: "A|B", wake: true)]
        #expect(AutoRestorePolicy.workspaceToRestore(among: workspaces, currentSignature: "A|B", trigger: [.displaysChanged, .wake], masterSwitch: false) == nil)
    }

    @Test("Workspaces with auto-restore off are not restored")
    func perWorkspaceSwitch() {
        let workspaces = [workspace("home", signature: "A|B", connect: false)]
        #expect(AutoRestorePolicy.workspaceToRestore(among: workspaces, currentSignature: "A|B", trigger: .displaysChanged, masterSwitch: true) == nil)
    }

    @Test("Wake only restores workspaces that opted in")
    func wake() {
        let workspaces = [workspace("home", signature: "A|B"), workspace("home-wake", signature: "A|B", wake: true)]
        let chosen = AutoRestorePolicy.workspaceToRestore(among: workspaces, currentSignature: "A|B", trigger: .wake, masterSwitch: true)
        #expect(chosen?.name == "home-wake")
        let none = AutoRestorePolicy.workspaceToRestore(among: [workspaces[0]], currentSignature: "A|B", trigger: .wake, masterSwitch: true)
        #expect(none == nil)
    }

    @Test("Among several matches the most recently used wins")
    func lastUsed() {
        let workspaces = [
            workspace("never", signature: "A|B"),
            workspace("old", signature: "A|B", lastUsed: Date(timeIntervalSince1970: 100)),
            workspace("recent", signature: "A|B", lastUsed: Date(timeIntervalSince1970: 200))
        ]
        let chosen = AutoRestorePolicy.workspaceToRestore(among: workspaces, currentSignature: "A|B", trigger: .displaysChanged, masterSwitch: true)
        #expect(chosen?.name == "recent")
    }

    @Test("Ties keep the list order")
    func ties() {
        let workspaces = [workspace("first", signature: "A|B"), workspace("second", signature: "A|B")]
        let chosen = AutoRestorePolicy.workspaceToRestore(among: workspaces, currentSignature: "A|B", trigger: .displaysChanged, masterSwitch: true)
        #expect(chosen?.name == "first")
    }

    @Test("Empty workspaces are not restored")
    func emptyWorkspace() {
        var empty = workspace("empty", signature: "A")
        empty.windows = []
        #expect(AutoRestorePolicy.workspaceToRestore(among: [empty], currentSignature: "A", trigger: .displaysChanged, masterSwitch: true) == nil)
    }
}
