import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Testing
@testable import LaneKeepCore

@Suite("Display map layout")
struct DisplayMapLayoutTests {
    let size = CGSize(width: 336, height: 150)

    @Test("Displays fit into the view and keep their proportions")
    func fitsAndKeepsProportions() {
        let displays = MapDisplay.from(Fixtures.homeDisplays)
        let layout = DisplayMapLayout(displays: displays, windows: [], size: size)
        #expect(layout.displays.count == 2)
        for placed in layout.displays {
            #expect(placed.rect.minX >= 0 && placed.rect.maxX <= size.width)
            #expect(placed.rect.minY >= 0 && placed.rect.maxY <= size.height - 16)
        }
        let external = layout.displays.first { $0.id == "EXT-27" }!.rect
        let builtin = layout.displays.first { $0.id == "BUILTIN" }!.rect
        // Wider than tall, like the real display (the gap inset changes the ratio a little).
        #expect(abs(external.width / external.height - 2560.0 / 1440.0) < 0.15)
        #expect(builtin.maxX <= external.minX)
        // The built-in display sits lower: its bottom edge lines up with the external one.
        #expect(abs(builtin.maxY - external.maxY) < 0.5)
    }

    @Test("Windows are drawn inside their display")
    func windowsInsideDisplays() {
        let workspace = Fixtures.homeWorkspace
        let windows = workspace.windows.map {
            MapWindow(id: $0.id.uuidString, displayID: $0.displayUUID, relativeFrame: $0.relativeFrame, label: $0.appName)
        }
        let layout = DisplayMapLayout(displays: MapDisplay.from(workspace.displays), windows: windows, size: size)
        #expect(layout.windows.count == 6)
        for window in layout.windows {
            let display = layout.displays.first { $0.id == window.window.displayID }!
            // Compare edges: swift-corelibs-foundation implements contains(_: CGRect) via union,
            // which is thrown off by rounding.
            #expect(window.rect.minX >= display.rect.minX && window.rect.maxX <= display.rect.maxX)
            #expect(window.rect.minY >= display.rect.minY && window.rect.maxY <= display.rect.maxY)
        }
        #expect(layout.windows.first { $0.window.label == "Slack" }?.role == .secondary)
    }

    @Test("Windows of unknown displays and empty inputs are dropped")
    func unknownDisplay() {
        let layout = DisplayMapLayout(
            displays: MapDisplay.from(Fixtures.homeDisplays),
            windows: [MapWindow(id: "x", displayID: "GONE", relativeFrame: CGRect(x: 0, y: 0, width: 1, height: 1), label: "x")],
            size: size
        )
        #expect(layout.windows.isEmpty)
        #expect(DisplayMapLayout(displays: [], windows: [], size: size).displays.isEmpty)
        #expect(DisplayMapLayout(displays: MapDisplay.from(Fixtures.homeDisplays), windows: [], size: .zero).displays.isEmpty)
    }

    @Test("Map displays come in role order with flipped coordinates")
    func mapDisplays() {
        let displays = MapDisplay.from(Fixtures.officeDisplays)
        #expect(displays.map(\.id) == ["OFFICE-27", "BUILTIN", "OFFICE-24"])
        #expect(displays.map(\.role) == [.primary, .secondary, .tertiary])
        // The built-in display (982 pt tall, bottom-aligned) starts 458 pt below the top.
        #expect(displays[1].frame.minY == 458)
    }
}

@Suite("Wording")
struct DisplayTextTests {
    @Test("Display names in role order")
    func displayNames() {
        #expect(DisplayText.displayNames(Fixtures.homeDisplays) == "外部 27インチ ＋ 内蔵ディスプレイ")
        #expect(DisplayText.displayNames([Fixtures.builtinAlone]) == "内蔵ディスプレイ")
    }

    @Test("Workspace meta line")
    func meta() {
        #expect(DisplayText.workspaceMeta(Fixtures.homeWorkspace) == "2画面、6アプリ")
        #expect(DisplayText.workspaceMeta(Fixtures.officeWorkspace) == "3画面、8アプリ")
        var workspace = Fixtures.laptopWorkspace
        workspace.windows.append(Fixtures.rule("Safari", index: 1, display: "BUILTIN", 0, 0, 10, 10))
        #expect(DisplayText.workspaceMeta(workspace) == "1画面、4アプリ・5ウィンドウ")
    }

    @Test("Window markers")
    func markers() {
        #expect(DisplayText.marker(for: Fixtures.rule("A", display: "D", 0, 0, 1, 1)) == "最初のウィンドウ")
        #expect(DisplayText.marker(for: Fixtures.rule("A", index: 2, display: "D", 0, 0, 1, 1)) == "3番目のウィンドウ")
        #expect(DisplayText.marker(for: Fixtures.rule("A", title: " lanekeep ", display: "D", 0, 0, 1, 1)) == "タイトルに「lanekeep」")
    }

    @Test("Relative frames as percentages")
    func percentages() {
        #expect(DisplayText.relativeFrame(CGRect(x: 0.02, y: 0.03, width: 0.48, height: 0.94)) == "左2% 上3%、幅48% 高さ94%")
        #expect(DisplayText.relativeFrame(CGRect(x: 0.505, y: -0.004, width: 1, height: 0.333)) == "左51% 上0%、幅100% 高さ33%")
    }

    @Test("Missing display notes")
    func missingNote() {
        #expect(DisplayText.missingDisplaysNote(count: 1, fallback: .mainDisplay) == "未接続の画面が1台あります。その分はメイン画面に寄せて配置します")
        #expect(DisplayText.missingDisplaysNote(count: 2, fallback: .skip) == "未接続の画面が2台あります。その画面のウィンドウは動かしません")
    }

    @Test("Launch option")
    func launchOption() {
        #expect(DisplayText.launchOption(true) == "起動する")
        #expect(DisplayText.launchOption(false) == "何もしない")
    }
}

@Suite("Default shortcuts")
struct ShortcutSlotsTests {
    @Test("The smallest free digit is used")
    func nextFree() {
        #expect(ShortcutSlots.nextFreeDigit(used: []) == 1)
        #expect(ShortcutSlots.nextFreeDigit(used: [1, 2, 4]) == 3)
        #expect(ShortcutSlots.nextFreeDigit(used: Set(1...9)) == nil)
    }

    @Test("Shortcut names contain no dots")
    func names() {
        let name = ShortcutSlots.shortcutName(for: UUID())
        #expect(!name.contains("."))
        #expect(name.hasPrefix("restoreWorkspace-"))
    }
}

@Suite("Model coding")
struct ModelCodingTests {
    @Test("Unknown enum values fall back to defaults")
    func unknownEnums() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode([WorkspaceColor].self, from: Data(#"["green","teal"]"#.utf8)) == [.green, .blue])
        #expect(try decoder.decode([WorkspaceIcon].self, from: Data(#"["home","rocket"]"#.utf8)) == [.home, .display])
        #expect(try decoder.decode([MissingDisplayFallback].self, from: Data(#"["skip","moon"]"#.utf8)) == [.skip, .mainDisplay])
    }

    @Test("Rects are written as named fields")
    func rectFormat() throws {
        let info = DisplayInfo(uuid: "A", name: "A", frame: CGRect(x: 1, y: 2, width: 3, height: 4), isMain: true)
        let json = String(data: try LaneKeepStore.makeEncoder().encode(info), encoding: .utf8) ?? ""
        #expect(json.contains("\"width\" : 3"))
        #expect(!json.contains("visibleFrame"))
    }

    @Test("Setting displays updates the signature")
    func setDisplays() {
        var workspace = Fixtures.homeWorkspace
        workspace.setDisplays([DisplayInfo(Fixtures.builtinAlone)])
        #expect(workspace.displaySignature == "BUILTIN")
    }
}
