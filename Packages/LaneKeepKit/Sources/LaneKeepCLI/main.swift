// lanekeep — a command-line companion to LaneKeep (spec §11, step 1).
//
// Lists displays and windows, moves a window to a place on a display, and saves or restores
// workspaces in the same workspaces.json the app uses.

#if canImport(AppKit)
import AppKit
import LaneKeepCore
import LaneKeepSystem

@MainActor
enum CLI {
    static let usage = """
    使い方: lanekeep <コマンド> [オプション]

    コマンド:
      displays [--json]                 接続中のディスプレイと画面構成の署名を表示
      windows [--all] [--json]          ウィンドウの一覧（アプリ、タイトル、位置、大きさ、所属画面）
      move <アプリ> --frame x,y,w,h      ウィンドウを画面の指定位置へ動かす
           [--display 番号|UUID]         x,y,w,h は可視領域に対する割合（0.5 または 50%）
           [--index N | --title 文字]    番号は displays の表示順。省略時はメイン画面
      workspaces                        保存済みのワークスペース
      save <名前> [--no-launch] [--no-auto-restore]
                                        今の配置を新しいワークスペースとして保存
      restore <名前|番号>               ワークスペースを復元
      permission [--prompt]             アクセシビリティの許可を確認（--prompt で許可を求める）

    LaneKeep アプリの起動中に save した内容は、アプリを再起動すると一覧に出ます。
    """

    static func run(_ arguments: [String]) async -> Int32 {
        AccessibilityTuning.configureMessagingTimeout()
        var arguments = Arguments(Array(arguments.dropFirst()))
        guard let command = arguments.next() else {
            print(usage)
            return 0
        }
        switch command {
        case "displays":
            return displays(json: arguments.flag("--json"))
        case "windows":
            return await windows(all: arguments.flag("--all"), json: arguments.flag("--json"))
        case "move":
            return await move(&arguments)
        case "workspaces":
            return workspaces()
        case "save":
            return await save(&arguments)
        case "restore":
            return await restore(&arguments)
        case "permission":
            return permission(prompt: arguments.flag("--prompt"))
        case "help", "-h", "--help":
            print(usage)
            return 0
        default:
            fail("不明なコマンドです: \(command)\n\n\(usage)")
            return 64
        }
    }

    // MARK: - Commands

    static func displays(json: Bool) -> Int32 {
        let displays = DisplayRoles.ordered(ScreenReader.currentDisplays())
        let signature = DisplaySignature.make(displays.map(\.uuid))
        if json {
            let output = DisplaysOutput(
                signature: signature,
                displays: displays.map {
                    DisplayOutput(uuid: $0.uuid, name: $0.name, frame: $0.frame, visibleFrame: $0.visibleFrame, isMain: $0.isMain, isBuiltin: $0.isBuiltin)
                }
            )
            printJSON(output)
            return 0
        }
        for (number, display) in displays.enumerated() {
            var flags: [String] = []
            if display.isMain { flags.append("メイン") }
            if display.isBuiltin { flags.append("内蔵") }
            print("[\(number + 1)] \(display.name)\(flags.isEmpty ? "" : "（\(flags.joined(separator: "・"))）")")
            print("    UUID      \(display.uuid)")
            print("    frame     \(describe(display.frame))")
            print("    visible   \(describe(display.visibleFrame))")
        }
        print("署名: \(signature.isEmpty ? "（なし）" : signature)")
        return 0
    }

    static func windows(all: Bool, json: Bool) async -> Int32 {
        guard requirePermission() else { return 2 }
        let displays = ScreenReader.currentDisplays()
        let snapshots = await WindowCatalog.snapshot()
        let candidates = CaptureBuilder.candidates(from: snapshots, displays: displays)
        let names = Dictionary(uniqueKeysWithValues: displays.map { ($0.uuid, $0.name) })
        let byID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0) })
        let listed = all ? snapshots : candidates.map(\.window)

        if json {
            printJSON(listed.map { window in
                let candidate = byID[window.id]
                return WindowOutput(
                    app: window.appName,
                    bundleID: window.bundleID,
                    index: window.indexInApp,
                    title: window.title,
                    frame: window.frame,
                    display: candidate.flatMap { names[$0.displayUUID] },
                    displayUUID: candidate?.displayUUID,
                    relativeFrame: candidate?.relativeFrame,
                    isMinimized: window.isMinimized
                )
            })
            return 0
        }
        if listed.isEmpty {
            print("ウィンドウが見つかりません。")
            return 0
        }
        for window in listed {
            let title = window.title.isEmpty ? "" : "「\(truncate(window.title, to: 40))」"
            print("\(window.appName) #\(window.indexInApp) \(title)")
            print("    bundle    \(window.bundleID)")
            print("    frame     \(describe(window.frame))（左上原点）")
            if let candidate = byID[window.id] {
                print("    画面      \(names[candidate.displayUUID] ?? candidate.displayUUID)  \(DisplayText.relativeFrame(candidate.relativeFrame))")
            } else {
                print("    画面      －（\(window.isMinimized ? "しまわれています" : "保存の対象外")）")
            }
        }
        return 0
    }

    static func move(_ arguments: inout Arguments) async -> Int32 {
        guard requirePermission() else { return 2 }
        // Options first, so that their values are not taken for the app name.
        let frameText = arguments.value(for: "--frame")
        let displayQuery = arguments.value(for: "--display")
        let index = arguments.value(for: "--index").flatMap { Int($0) } ?? 0
        let title = arguments.value(for: "--title")
        guard let appQuery = arguments.next() else {
            fail("動かすアプリを指定してください（例: lanekeep move Safari --frame 0,0,0.5,1）")
            return 64
        }
        guard let frameText, let relative = parseFrame(frameText) else {
            fail("--frame x,y,w,h を指定してください（可視領域に対する割合。例: 0,0,0.5,1 または 0,0,50%,100%）")
            return 64
        }
        let displays = DisplayRoles.ordered(ScreenReader.currentDisplays())
        guard let display = selectDisplay(displayQuery, among: displays) else {
            fail("ディスプレイが見つかりません。lanekeep displays で番号か UUID を確認してください。")
            return 1
        }
        guard let app = findApp(appQuery) else {
            fail("起動中のアプリ「\(appQuery)」が見つかりません。")
            return 1
        }
        let rule = WindowRule(
            bundleID: app.bundleID,
            appName: app.name,
            titleContains: title,
            index: max(0, index),
            displayUUID: display.uuid,
            relativeFrame: relative,
            launchIfClosed: false
        )
        let workspace = Workspace(name: "move", displays: displays.map(DisplayInfo.init), windows: [rule])
        let report = await LiveRestore.run(RestoreRequest(workspace: workspace, displays: displays, fallback: .mainDisplay))
        guard let outcome = report.results.first?.outcome else { return 1 }
        switch outcome {
        case .placed(let frame, _):
            print("\(app.name) を \(display.name) の \(DisplayText.relativeFrame(relative)) に動かしました: \(describe(frame))")
            return 0
        default:
            fail(report.summary)
            return 1
        }
    }

    static func workspaces() -> Int32 {
        let workspaces = LaneKeepStore().loadWorkspaces().value
        guard !workspaces.isEmpty else {
            print("保存済みのワークスペースはありません。")
            return 0
        }
        let displays = ScreenReader.currentDisplays()
        for (number, workspace) in workspaces.enumerated() {
            let state: String
            switch workspace.availability(for: displays) {
            case .matchesCurrent:
                state = "今の構成と一致"
            case .missingDisplays(let count):
                state = "未接続の画面 \(count)台"
            case .available:
                state = "復元できます"
            }
            print("[\(number + 1)] \(workspace.name) — \(DisplayText.workspaceMeta(workspace))（\(state)）")
            for rule in workspace.windows {
                let displayName = workspace.display(withUUID: rule.displayUUID)?.name ?? rule.displayUUID
                print("    \(rule.appName)  \(DisplayText.marker(for: rule))  \(displayName)  \(DisplayText.relativeFrame(rule.relativeFrame))")
            }
        }
        return 0
    }

    static func save(_ arguments: inout Arguments) async -> Int32 {
        guard requirePermission() else { return 2 }
        let launch = !arguments.flag("--no-launch")
        let autoRestore = !arguments.flag("--no-auto-restore")
        guard let name = arguments.next() else {
            fail("ワークスペースの名前を指定してください。")
            return 64
        }
        let store = LaneKeepStore()
        var workspaces = store.loadWorkspaces().value
        let displays = ScreenReader.currentDisplays()
        let candidates = CaptureBuilder.candidates(
            from: await WindowCatalog.snapshot(),
            displays: displays,
            excludedBundleIDs: store.loadPreferences().value.excludedBundleIDs
        )
        guard !candidates.isEmpty else {
            fail("保存できるウィンドウがありません。")
            return 1
        }
        let workspace = CaptureBuilder.workspace(
            name: name,
            color: CaptureBuilder.suggestedColor(existing: workspaces.map(\.color)),
            icon: CaptureBuilder.suggestedIcon(for: displays),
            candidates: candidates,
            displays: displays,
            launchIfClosed: launch,
            autoRestoreOnConnect: autoRestore
        )
        workspaces.append(workspace)
        do {
            try store.saveWorkspaces(workspaces)
        } catch {
            fail("保存できませんでした: \(error.localizedDescription)")
            return 1
        }
        print("「\(workspace.name)」に\(workspace.windows.count)件のウィンドウを保存しました。")
        return 0
    }

    static func restore(_ arguments: inout Arguments) async -> Int32 {
        guard requirePermission() else { return 2 }
        guard let query = arguments.next() else {
            fail("復元するワークスペースの名前か番号を指定してください。")
            return 64
        }
        let store = LaneKeepStore()
        let workspaces = store.loadWorkspaces().value
        let match = Int(query).flatMap { workspaces.indices.contains($0 - 1) ? workspaces[$0 - 1] : nil }
            ?? workspaces.first { $0.name == query }
        guard let workspace = match else {
            fail("ワークスペース「\(query)」が見つかりません。lanekeep workspaces で確認してください。")
            return 1
        }
        let request = RestoreRequest(
            workspace: workspace,
            displays: ScreenReader.currentDisplays(),
            fallback: store.loadPreferences().value.missingDisplayFallback
        )
        let report = await LiveRestore.run(request) { progress in
            print("配置中… \(progress.completed) / \(progress.total)")
        }
        print(report.summary)
        return report.results.allSatisfy(\.outcome.isPlaced) ? 0 : 1
    }

    static func permission(prompt: Bool) -> Int32 {
        if AccessibilityPermission.isGranted {
            print("アクセシビリティの許可があります。")
            return 0
        }
        if prompt {
            AccessibilityPermission.requestWithSystemPrompt()
        }
        print(permissionHelp)
        return 2
    }

    // MARK: - Helpers

    static let permissionHelp = """
    アクセシビリティの許可がありません。
    「システム設定」→「プライバシーとセキュリティ」→「アクセシビリティ」で、このコマンドを
    実行しているアプリ（ターミナルなど）をオンにしてください。
    """

    static func requirePermission() -> Bool {
        guard AccessibilityPermission.isGranted else {
            fail(permissionHelp)
            return false
        }
        return true
    }

    static func findApp(_ query: String) -> RunningAppInfo? {
        let apps = RunningApps.regularApps()
        return apps.first { $0.bundleID == query }
            ?? apps.first { $0.name.localizedCaseInsensitiveCompare(query) == .orderedSame }
            ?? apps.first { $0.name.localizedCaseInsensitiveContains(query) }
    }

    static func selectDisplay(_ value: String?, among displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        guard let value else {
            return displays.first(where: \.isMain) ?? displays.first
        }
        if let number = Int(value), displays.indices.contains(number - 1) {
            return displays[number - 1]
        }
        return displays.first { $0.uuid.caseInsensitiveCompare(value) == .orderedSame }
    }

    /// "0,0,0.5,1" or "0,0,50%,100%".
    static func parseFrame(_ text: String) -> CGRect? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 4 else { return nil }
        let values: [CGFloat] = parts.compactMap { part in
            if part.hasSuffix("%") {
                return Double(part.dropLast()).map { CGFloat($0) / 100 }
            }
            return Double(part).map { CGFloat($0) }
        }
        guard values.count == 4, values[2] > 0, values[3] > 0 else { return nil }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }

    static func describe(_ rect: CGRect) -> String {
        "x \(Int(rect.minX.rounded())), y \(Int(rect.minY.rounded())), 幅 \(Int(rect.width.rounded())), 高さ \(Int(rect.height.rounded()))"
    }

    static func truncate(_ text: String, to length: Int) -> String {
        text.count > length ? String(text.prefix(length - 1)) + "…" : text
    }

    static func fail(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    static func printJSON<Value: Encodable>(_ value: Value) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }
}

/// Minimal argument handling: positional values in order, flags and `--name value` options
/// anywhere.
struct Arguments {
    private var items: [String]

    init(_ items: [String]) {
        self.items = items
    }

    /// The next positional argument.
    mutating func next() -> String? {
        guard let index = items.firstIndex(where: { !$0.hasPrefix("--") }) else { return nil }
        return items.remove(at: index)
    }

    mutating func flag(_ name: String) -> Bool {
        guard let index = items.firstIndex(of: name) else { return false }
        items.remove(at: index)
        return true
    }

    mutating func value(for name: String) -> String? {
        guard let index = items.firstIndex(of: name), items.indices.contains(index + 1) else { return nil }
        let value = items[index + 1]
        items.removeSubrange(index...(index + 1))
        return value
    }
}

struct DisplaysOutput: Encodable {
    var signature: String
    var displays: [DisplayOutput]
}

struct DisplayOutput: Encodable {
    var uuid: String
    var name: String
    var frame: CGRect
    var visibleFrame: CGRect
    var isMain: Bool
    var isBuiltin: Bool
}

struct WindowOutput: Encodable {
    var app: String
    var bundleID: String
    var index: Int
    var title: String
    var frame: CGRect
    var display: String?
    var displayUUID: String?
    var relativeFrame: CGRect?
    var isMinimized: Bool
}

let status = await CLI.run(CommandLine.arguments)
exit(status)
#else
print("lanekeep は macOS 専用です。")
#endif
