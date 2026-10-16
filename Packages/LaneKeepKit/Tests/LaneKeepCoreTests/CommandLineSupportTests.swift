import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import LaneKeepCore

@Suite("Command-line arguments")
struct CommandLineSupportTests {
    @Test("Positional values, flags and options in any order")
    func parsing() throws {
        var arguments = CommandLineArguments(["--frame", "0,0,50%,100%", "Safari", "--json", "--index", "2"])
        let frame = try arguments.value(for: "--frame")
        let index = try arguments.integer(for: "--index")
        let json = arguments.flag("--json")
        let app = arguments.next()
        let nothing = arguments.next()
        #expect(frame == "0,0,50%,100%")
        #expect(index == 2)
        #expect(json)
        #expect(app == "Safari")
        #expect(nothing == nil)
        try arguments.rejectUnknownOptions()
    }

    @Test("Missing and malformed option values are errors")
    func errors() {
        #expect(throws: ArgumentError.missingValue(option: "--display")) {
            var arguments = CommandLineArguments(["move", "Safari", "--display"])
            _ = try arguments.value(for: "--display")
        }
        #expect(throws: ArgumentError.missingValue(option: "--index")) {
            var arguments = CommandLineArguments(["--index", "--title", "x"])
            _ = try arguments.integer(for: "--index")
        }
        #expect(throws: ArgumentError.notANumber(option: "--index", value: "abc")) {
            var arguments = CommandLineArguments(["--index", "abc"])
            _ = try arguments.integer(for: "--index")
        }
        #expect(throws: ArgumentError.unknownOptions(["--no-lauch"])) {
            try CommandLineArguments(["save", "Home", "--no-lauch"]).rejectUnknownOptions()
        }
    }

    @Test("Frames are fractions or percentages inside the visible area")
    func frames() {
        #expect(RelativeFrameArgument.parse("0,0,0.5,1") == .success(CGRect(x: 0, y: 0, width: 0.5, height: 1)))
        #expect(RelativeFrameArgument.parse("50%, 0%, 50%, 100%") == .success(CGRect(x: 0.5, y: 0, width: 0.5, height: 1)))
        #expect(RelativeFrameArgument.parse("0,0,0.5") == .failure(.format))
        #expect(RelativeFrameArgument.parse("0,0,nan,1") == .failure(.format))
        #expect(RelativeFrameArgument.parse("0,0,inf,1") == .failure(.format))
        #expect(RelativeFrameArgument.parse("0,0,50,100") == .failure(.outOfRange(looksLikePercent: true)))
        #expect(RelativeFrameArgument.parse("0.8,0,0.5,1") == .failure(.outOfRange(looksLikePercent: false)))
        #expect(RelativeFrameArgument.parse("-0.1,0,0.5,1") == .failure(.outOfRange(looksLikePercent: false)))
        #expect(RelativeFrameArgument.parse("0,0,0,1") == .failure(.outOfRange(looksLikePercent: false)))
    }

    @Test("Workspaces are found by name first, the most recently used of several, then by number")
    func lookup() {
        let old = Workspace(name: "自宅", displays: [], windows: [], lastUsedAt: Date(timeIntervalSince1970: 100))
        let new = Workspace(name: "自宅", displays: [], windows: [], lastUsedAt: Date(timeIntervalSince1970: 200))
        let two = Workspace(name: "2", displays: [], windows: [])
        let list = [old, new, two]
        #expect(WorkspaceLookup.find("自宅", in: list)?.id == new.id)
        #expect(WorkspaceLookup.find("2", in: list)?.id == two.id)
        #expect(WorkspaceLookup.find("1", in: list)?.id == old.id)
        #expect(WorkspaceLookup.find("9", in: list) == nil)
        #expect(WorkspaceLookup.named("自宅", in: list).map(\.id) == [new.id, old.id])
    }
}
