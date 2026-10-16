import Foundation
import Testing
@testable import LaneKeepCore

@Suite("Changes made by other programs")
struct WorkspaceMergeTests {
    func workspace(_ name: String, lastUsed: TimeInterval? = nil) -> Workspace {
        Workspace(name: name, displays: [], windows: [], lastUsedAt: lastUsed.map { Date(timeIntervalSince1970: $0) })
    }

    @Test("Workspaces saved by the command appear in the app")
    func addedInFile() {
        let a = workspace("A"), b = workspace("B"), c = workspace("C")
        let merged = WorkspaceMerge.merge(local: [a, b], file: [a, b, c], changedLocally: [], deletedLocally: [])
        #expect(merged == [a, b, c])
    }

    @Test("The app's own changes win; untouched workspaces take the file's version")
    func changes() {
        var a = workspace("A"), b = workspace("B")
        var aInFile = a
        aInFile.name = "A (file)"
        var bInFile = b
        bInFile.name = "B (file)"
        a.name = "A (app)"
        b.lastUsedAt = nil
        let merged = WorkspaceMerge.merge(local: [a, b], file: [aInFile, bInFile], changedLocally: [a.id], deletedLocally: [])
        #expect(merged.map(\.name) == ["A (app)", "B (file)"])
    }

    @Test("Deleted in the app stays deleted; deleted in the file is dropped unless changed in the app")
    func deletions() {
        let a = workspace("A"), b = workspace("B"), c = workspace("C"), d = workspace("D")
        let merged = WorkspaceMerge.merge(
            local: [a, b, d],          // C was deleted in the app
            file: [a, c],              // B and D were removed from the file
            changedLocally: [d.id],    // D is new in the app
            deletedLocally: [c.id]
        )
        #expect(merged == [a, d])
    }
}
