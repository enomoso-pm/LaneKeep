import Testing
@testable import LaneKeepCore

@Suite("Where LaneKeep runs from, and whether to ask to move it first")
struct InstallLocationTests {
    private func location(_ path: String, readOnly: Bool = false, home: String = "/Users/someone") -> InstallLocation {
        InstallLocation.classify(bundlePath: path, homeDirectory: home, isOnReadOnlyVolume: readOnly)
    }

    @Test("In /Applications there is nothing to do")
    func applications() {
        #expect(location("/Applications/LaneKeep.app") == .applications)
        #expect(!location("/Applications/LaneKeep.app").needsMove)
    }

    @Test("~/Applications counts as an Applications folder too, with or without a trailing slash")
    func homeApplications() {
        #expect(location("/Users/someone/Applications/LaneKeep.app") == .applications)
        #expect(location("/Users/someone/Applications/LaneKeep.app", home: "/Users/someone/") == .applications)
    }

    @Test("Opened where it was downloaded, macOS runs a random read-only copy")
    func translocated() {
        // The form of the path macOS uses for such a copy: …/AppTranslocation/<UUID>/d/<app>.
        let path = "/private/var/folders/xy/abc123/T/AppTranslocation/6D1E2A0C-1F7B-4C55-9F0E-3A2B1C0D9E8F/d/LaneKeep.app"
        #expect(location(path, readOnly: true) == .translocated)
        #expect(location(path, readOnly: true).needsMove)
    }

    @Test("Opened straight from a disk image that macOS does not translocate")
    func diskImage() {
        #expect(location("/Volumes/LaneKeep 1.1.0/LaneKeep.app", readOnly: true) == .diskImage)
        #expect(location("/Volumes/LaneKeep 1.1.0/LaneKeep.app", readOnly: true).needsMove)
    }

    @Test("Elsewhere on a writable disk it works, so the app does not insist")
    func elsewhere() {
        #expect(location("/Users/someone/Downloads/LaneKeep.app") == .elsewhere)
        #expect(location("/Volumes/External/Apps/LaneKeep.app") == .elsewhere)
        #expect(!location("/Users/someone/Downloads/LaneKeep.app").needsMove)
    }

    @Test("A folder whose name only starts like Applications is not one")
    func lookalike() {
        #expect(location("/Applications Old/LaneKeep.app") == .elsewhere)
        #expect(location("/Users/someone/ApplicationsBackup/LaneKeep.app") == .elsewhere)
    }
}
