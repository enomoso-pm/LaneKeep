import Testing
@testable import LaneKeepCore

@Suite("Renaming a workspace in the settings or in the list")
struct WorkspaceNameTests {
    @Test("A new name is kept as typed")
    func newName() {
        #expect(Workspace.editedName("オフィス", current: "自宅デスク") == "オフィス")
        #expect(Workspace.editedName("自宅 デスク", current: "自宅デスク") == "自宅 デスク")
    }

    @Test("Spaces and line breaks around the name are dropped, full-width spaces too")
    func trimmed() {
        #expect(Workspace.editedName("  オフィス \n", current: "自宅デスク") == "オフィス")
        #expect(Workspace.editedName("\u{3000}オフィス\u{3000}", current: "自宅デスク") == "オフィス")
    }

    @Test("An empty name keeps the old one")
    func empty() {
        #expect(Workspace.editedName("", current: "自宅デスク") == nil)
        #expect(Workspace.editedName("   ", current: "自宅デスク") == nil)
        #expect(Workspace.editedName("\u{3000}", current: "自宅デスク") == nil)
    }

    @Test("The same name is no change, with or without spaces around it")
    func unchanged() {
        #expect(Workspace.editedName("自宅デスク", current: "自宅デスク") == nil)
        #expect(Workspace.editedName(" 自宅デスク ", current: "自宅デスク") == nil)
    }
}
