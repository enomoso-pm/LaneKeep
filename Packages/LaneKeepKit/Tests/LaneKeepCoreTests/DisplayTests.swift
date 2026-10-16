import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import LaneKeepCore

@Suite("Display signature and identity (spec §6.2)")
struct DisplaySignatureTests {
    func external(_ uuid: String, x: CGFloat = 0) -> DisplaySnapshot {
        DisplaySnapshot(
            uuid: uuid,
            name: uuid,
            frame: CGRect(x: x, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: x, y: 0, width: 1920, height: 1055),
            isMain: x == 0
        )
    }

    @Test("The signature is the sorted UUIDs joined with |")
    func signature() {
        #expect(DisplaySignature.make(for: [external("B"), external("C", x: 1920), external("A", x: 3840)]) == "A|B|C")
        #expect(DisplaySignature.make(for: [external("B"), external("A", x: 1920)]) == DisplaySignature.make(for: [external("A"), external("B", x: 1920)]))
        #expect(DisplaySignature.make(for: [DisplaySnapshot]()) == "")
    }

    @Test("Closing the lid does not change the signature")
    func lidClosed() {
        let lidOpen = DisplaySignature.make(for: [Fixtures.external27, Fixtures.builtin])
        let lidClosed = DisplaySignature.make(for: [Fixtures.external27])
        #expect(lidOpen == "EXT-27")
        #expect(lidOpen == lidClosed)
        // Also for the displays recorded in a workspace.
        #expect(DisplaySignature.make(for: Fixtures.homeWorkspace.displays) == lidClosed)
        // Several external displays: only the built-in one is left out.
        #expect(DisplaySignature.make(for: Fixtures.officeDisplays) == "OFFICE-24|OFFICE-27")
    }

    @Test("With the built-in display alone, it is the signature (never empty)")
    func builtinOnly() {
        let signature = DisplaySignature.make(for: [Fixtures.builtinAlone])
        #expect(signature == "BUILTIN")
        #expect(!signature.isEmpty)
        #expect(Fixtures.laptopWorkspace.displaySignature == "BUILTIN")
        // So a laptop-only workspace still restores automatically.
        var tracker = AutoRestoreTracker(initialSignature: "EXT-27")
        #expect(tracker.evaluate(currentSignature: signature) == .displaysChanged)
    }

    @Test("Components round-trip")
    func components() {
        #expect(DisplaySignature.components(of: "A|B|C") == ["A", "B", "C"])
        #expect(DisplaySignature.components(of: "").isEmpty)
    }

    @Test("Unique UUIDs are kept as they are")
    func uniqueUUIDs() {
        let ids = DisplayIdentity.uniqueIdentifiers(
            rawUUIDs: ["A", "B"],
            frames: [CGRect(x: 0, y: 0, width: 10, height: 10), CGRect(x: 10, y: 0, width: 10, height: 10)]
        )
        #expect(ids == ["A", "B"])
    }

    @Test("Identical monitors are numbered from left to right")
    func identicalMonitors() {
        let ids = DisplayIdentity.uniqueIdentifiers(
            rawUUIDs: ["SAME", "MAIN", "SAME", "SAME"],
            frames: [
                CGRect(x: 2560, y: 0, width: 1920, height: 1080),
                CGRect(x: 0, y: 0, width: 2560, height: 1440),
                CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                CGRect(x: 2560, y: 1080, width: 1920, height: 1080)
            ]
        )
        #expect(ids == ["SAME#3", "MAIN", "SAME", "SAME#2"])
    }
}

@Suite("Display colors (spec §9)")
struct DisplayRoleTests {
    @Test("Home: the external display is blue, the built-in one orange")
    func home() {
        let roles = DisplayRoles.assign(Fixtures.homeDisplays)
        #expect(roles["EXT-27"] == .primary)
        #expect(roles["BUILTIN"] == .secondary)
    }

    @Test("Office: main display blue, built-in orange, the other gray")
    func office() {
        let roles = DisplayRoles.assign(Fixtures.officeDisplays)
        #expect(roles["OFFICE-27"] == .primary)
        #expect(roles["BUILTIN"] == .secondary)
        #expect(roles["OFFICE-24"] == .tertiary)
    }

    @Test("Laptop only: the built-in display stays orange")
    func laptop() {
        #expect(DisplayRoles.assign([Fixtures.builtinAlone])["BUILTIN"] == .secondary)
    }

    @Test("Two external displays with the lid closed: blue and orange")
    func clamshell() {
        let side = DisplaySnapshot(
            uuid: "SIDE", name: "Side",
            frame: CGRect(x: 2560, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 2560, y: 0, width: 1920, height: 1055),
            isMain: false
        )
        let roles = DisplayRoles.assign([side, Fixtures.external27])
        #expect(roles["EXT-27"] == .primary)
        #expect(roles["SIDE"] == .secondary)
    }

    @Test("Role order: blue first, then orange, then gray")
    func ordering() {
        let ordered = DisplayRoles.ordered(Fixtures.officeDisplays).map(\.uuid)
        #expect(ordered == ["OFFICE-27", "BUILTIN", "OFFICE-24"])
    }

    @Test("Spatial order: left to right")
    func spatial() {
        let ordered = DisplayGeometry.spatiallyOrdered(Fixtures.officeDisplays).map(\.uuid)
        #expect(ordered == ["OFFICE-24", "OFFICE-27", "BUILTIN"])
    }
}

@Suite("Display geometry")
struct DisplayGeometryTests {
    @Test("The main display's height is the reference for flipping")
    func primaryHeight() {
        #expect(DisplayGeometry.primaryHeight(of: Fixtures.homeDisplays) == 1440)
        #expect(DisplayGeometry.primaryHeight(of: [Fixtures.builtinAlone]) == 982)
        #expect(DisplayGeometry.primaryHeight(of: [DisplaySnapshot]()) == nil)
    }

    @Test("A window belongs to the display that contains its center")
    func centerPoint() {
        // In Accessibility coordinates the built-in display spans y 458…1440, x -1512…0.
        let window = CGRect(x: -400, y: 600, width: 500, height: 300) // center (-150, 750)
        let display = DisplayGeometry.display(forAccessibilityRect: window, among: Fixtures.homeDisplays, primaryHeight: 1440)
        #expect(display?.uuid == "BUILTIN")
    }

    @Test("A window whose center is off screen goes to the display it overlaps most")
    func mostlyOffScreen() {
        let window = CGRect(x: 2400, y: -400, width: 300, height: 500) // center (2550, -150)
        let display = DisplayGeometry.display(forAccessibilityRect: window, among: Fixtures.homeDisplays, primaryHeight: 1440)
        #expect(display?.uuid == "EXT-27")
    }

    @Test("A window on no display belongs nowhere")
    func nowhere() {
        let window = CGRect(x: 10_000, y: 10_000, width: 300, height: 300)
        #expect(DisplayGeometry.display(forAccessibilityRect: window, among: Fixtures.homeDisplays, primaryHeight: 1440) == nil)
    }
}

@Suite("Workspace availability")
struct WorkspaceAvailabilityTests {
    @Test("Exactly the saved displays → matches")
    func matches() {
        #expect(Fixtures.homeWorkspace.availability(for: Fixtures.homeDisplays) == .matchesCurrent)
    }

    @Test("A display with windows is missing")
    func missing() {
        let availability = Fixtures.officeWorkspace.availability(for: [Fixtures.office27, Fixtures.officeBuiltin])
        #expect(availability == .missingDisplays(count: 1))
    }

    @Test("More displays than saved → available but not matching")
    func extraDisplays() {
        #expect(Fixtures.laptopWorkspace.availability(for: Fixtures.homeDisplays) == .available)
    }

    @Test("A missing display without windows does not count")
    func missingWithoutWindows() {
        var workspace = Fixtures.officeWorkspace
        workspace.windows.removeAll { $0.displayUUID == "OFFICE-24" }
        #expect(workspace.availability(for: [Fixtures.office27, Fixtures.officeBuiltin]) == .available)
    }

    @Test("Saved with the lid open, docked with the lid closed → matches")
    func lidClosedMatches() {
        #expect(Fixtures.homeWorkspace.availability(for: [Fixtures.external27]) == .matchesCurrent)
        let chosen = AutoRestorePolicy.workspaceToRestore(
            among: [Fixtures.laptopWorkspace, Fixtures.homeWorkspace],
            currentSignature: DisplaySignature.make(for: [Fixtures.external27]),
            trigger: .displaysChanged,
            masterSwitch: true
        )
        #expect(chosen?.name == "自宅デスク")
    }

    @Test("Saved with the lid closed, docked with the lid open → matches")
    func lidOpenMatches() {
        let closed = Workspace(name: "クラムシェル", displays: [DisplayInfo(Fixtures.external27)], windows: Fixtures.homeWorkspace.windows)
        #expect(closed.availability(for: Fixtures.homeDisplays) == .matchesCurrent)
    }
}
