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
                                        N は windows の「#N」。省略時は #0
      workspaces                        保存済みのワークスペース
      save <名前> [--replace] [--no-launch] [--no-auto-restore]
                                        今の配置をワークスペースとして保存
                                        同じ名前があるときは --replace で上書き
      restore <名前|番号>               ワークスペースを復元
      permission [--prompt]             アクセシビリティの許可を確認（--prompt で許可を求める）

    LaneKeep アプリの起動中に保存した内容は、次にアプリのメニューを開いたときに一覧に出ます。
    """

    static func run(_ arguments: [String]) async -> Int32 {
        AccessibilityTuning.configureMessagingTimeout()
        var arguments = CommandLineArguments(Array(arguments.dropFirst()))
        guard let command = arguments.next() else {
            print(usage)
            return 0
        }
        do {
            switch command {
            case "displays":
                let json = arguments.flag("--json")
                try finishParsing(arguments)
                return displays(json: json)
            case "windows":
                let all = arguments.flag("--all")
                let json = arguments.flag("--json")
                try finishParsing(arguments)
                return await windows(all: all, json: json)
            case "move":
                return try await move(&arguments)
            case "workspaces":
                try finishParsing(arguments)
                return workspaces()
            case "save":
                return try await save(&arguments)
            case "restore":
                return try await restore(&arguments)
            case "permission":
                let prompt = arguments.flag("--prompt")
                try finishParsing(arguments)
                return permission(prompt: prompt)
            case "help", "-h", "--help":
                print(usage)
                return 0
            default:
                fail("不明なコマンドです: \(command)\n\n\(usage)")
                return 64
            }
        } catch let error as ArgumentError {
            fail("\(error.message)\nlanekeep help で使い方を表示します。")
            return 64
        } catch let error as UsageError {
            fail(error.message)
            return 64
        } catch {
            fail(error.localizedDescription)
            return 1
        }
    }

    /// Fails on options or values that no part of the command used.
    static func finishParsing(_ arguments: CommandLineArguments) throws {
        var rest = arguments
        try rest.rejectUnknownOptions()
        if let extra = rest.next() {
            throw UsageError("余分な引数です: \(extra)")
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
        let names = Dictionary(displays.map { ($0.uuid, $0.name) }, uniquingKeysWith: { first, _ in first })
        let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
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

    static func move(_ arguments: inout CommandLineArguments) async throws -> Int32 {
        // Options first, so that their values are not taken for the app name.
        let frameText = try arguments.value(for: "--frame")
        let displayQuery = try arguments.value(for: "--display")
        let index = try arguments.integer(for: "--index")
        let title = try arguments.value(for: "--title")
        guard let appQuery = arguments.next() else {
            throw UsageError("動かすアプリを指定してください（例: lanekeep move Safari --frame 0,0,0.5,1）")
        }
        try finishParsing(arguments)
        guard let frameText else {
            throw UsageError("--frame x,y,w,h を指定してください（可視領域に対する割合。例: 0,0,0.5,1 または 0,0,50%,100%）")
        }
        let relative: CGRect
        switch RelativeFrameArgument.parse(frameText) {
        case .success(let frame):
            relative = frame
        case .failure(.format):
            throw UsageError("--frame は x,y,w,h の4つの数で指定してください（例: 0,0,0.5,1 または 0,0,50%,100%）")
        case .failure(.outOfRange(let looksLikePercent)):
            throw UsageError(looksLikePercent
                ? "--frame の値は 0〜1 の割合か、% を付けて指定してください（例: 0,0,50%,100%）"
                : "--frame の範囲が画面からはみ出しています（x + w と y + h は 1 以下）")
        }
        if let index, index < 0 {
            throw UsageError("--index は 0 以上の番号で指定してください。")
        }
        if index != nil, title != nil {
            throw UsageError("--index と --title はどちらか一方だけ指定してください。")
        }
        guard requirePermission() else { return 2 }

        let displays = DisplayRoles.ordered(ScreenReader.currentDisplays())
        guard let display = selectDisplay(displayQuery, among: displays) else {
            fail("ディスプレイが見つかりません。lanekeep displays で番号か UUID を確認してください。")
            return 1
        }
        guard let app = findApp(appQuery) else {
            fail("起動中のアプリ「\(appQuery)」が見つかりません。")
            return 1
        }
        // Make sure the window that was asked for exists, rather than moving another one.
        guard let windows = await Task.detached(operation: { WindowCatalog.windows(of: app) }).value else {
            fail("\(app.name) が応答しません。少し待ってからもう一度試してください。")
            return 1
        }
        if let title {
            guard windows.contains(where: { $0.title.localizedCaseInsensitiveContains(title) }) else {
                fail("\(app.name) にタイトルに「\(title)」を含むウィンドウはありません。lanekeep windows で確認してください。")
                return 1
            }
        } else {
            let wanted = index ?? 0
            guard windows.contains(where: { $0.indexInApp == wanted }) else {
                fail(windows.isEmpty
                    ? "\(app.name) にはウィンドウがありません。"
                    : "\(app.name) のウィンドウ #\(wanted) はありません（#0〜#\(windows.count - 1)）。lanekeep windows で確認してください。")
                return 1
            }
        }

        let rule = WindowRule(
            bundleID: app.bundleID,
            appName: app.name,
            titleContains: title,
            index: index ?? 0,
            displayUUID: display.uuid,
            relativeFrame: relative,
            launchIfClosed: false
        )
        let workspace = Workspace(name: "move", displays: displays.map(DisplayInfo.init), windows: [rule])
        let request = RestoreRequest(workspace: workspace, displays: displays, fallback: .mainDisplay, matching: .exactIndex)
        let report = await LiveRestore.run(request)
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
        let load = LaneKeepStore().loadWorkspaces(unreadableFile: .leave)
        warnAbout(load, file: "workspaces.json")
        let workspaces = load.value
        guard !workspaces.isEmpty else {
            print("保存済みのワークスペースはありません。")
            return load.problem == nil ? 0 : 1
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

    static func save(_ arguments: inout CommandLineArguments) async throws -> Int32 {
        let replace = arguments.flag("--replace")
        let launch = !arguments.flag("--no-launch")
        let autoRestore = !arguments.flag("--no-auto-restore")
        guard let rawName = arguments.next() else {
            throw UsageError("ワークスペースの名前を指定してください。")
        }
        try finishParsing(arguments)
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw UsageError("ワークスペースの名前を指定してください。")
        }
        guard requirePermission() else { return 2 }

        let store = LaneKeepStore()
        let load = store.loadWorkspaces(unreadableFile: .leave)
        guard load.problem == nil else {
            warnAbout(load, file: "workspaces.json")
            fail("読めない部分を消してしまわないよう、保存しませんでした。LaneKeep アプリを起動すると、読めないファイルを残したうえで読み直します。")
            return 1
        }
        var workspaces = load.value
        let existing = WorkspaceLookup.named(name, in: workspaces).first
        if existing != nil, !replace {
            fail("「\(name)」はすでにあります。今の配置で上書きするには --replace を付けてください。")
            return 1
        }
        let preferences = store.loadPreferences(unreadableFile: .leave)
        warnAbout(preferences, file: "preferences.json")
        let displays = ScreenReader.currentDisplays()
        let candidates = CaptureBuilder.candidates(
            from: await WindowCatalog.snapshot(),
            displays: displays,
            excludedBundleIDs: preferences.value.excludedBundleIDs
        )
        guard !candidates.isEmpty else {
            fail("保存できるウィンドウがありません。")
            return 1
        }

        let saved: Workspace
        if let existing, let position = workspaces.firstIndex(where: { $0.id == existing.id }) {
            // Like "今の配置で上書き" in the app: the workspace keeps its name, color, shortcut and
            // the title markers of its windows.
            var workspace = existing
            workspace.windows = CaptureBuilder.rules(from: candidates, replacing: existing.windows, launchIfClosedForNewWindows: launch)
            workspace.setDisplays(DisplayRoles.ordered(displays).map(DisplayInfo.init))
            if !autoRestore {
                workspace.autoRestoreOnConnect = false
            }
            workspace.lastUsedAt = Date()
            workspaces[position] = workspace
            saved = workspace
        } else {
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
            saved = workspace
        }
        do {
            try store.saveWorkspaces(workspaces)
        } catch {
            fail("保存できませんでした: \(error.localizedDescription)")
            return 1
        }
        print("「\(saved.name)」に\(saved.windows.count)件のウィンドウを\(existing == nil ? "保存" : "上書き")しました。")
        return 0
    }

    static func restore(_ arguments: inout CommandLineArguments) async throws -> Int32 {
        guard let query = arguments.next() else {
            throw UsageError("復元するワークスペースの名前か番号を指定してください。")
        }
        try finishParsing(arguments)
        guard requirePermission() else { return 2 }

        let store = LaneKeepStore()
        let load = store.loadWorkspaces(unreadableFile: .leave)
        warnAbout(load, file: "workspaces.json")
        guard let workspace = WorkspaceLookup.find(query, in: load.value) else {
            fail("ワークスペース「\(query)」が見つかりません。lanekeep workspaces で確認してください。")
            return 1
        }
        if WorkspaceLookup.named(query, in: load.value).count > 1 {
            fail("「\(query)」という名前が複数あるので、最後に使ったものを復元します。")
        }
        let preferences = store.loadPreferences(unreadableFile: .leave)
        warnAbout(preferences, file: "preferences.json")
        let request = RestoreRequest(
            workspace: workspace,
            displays: ScreenReader.currentDisplays(),
            fallback: preferences.value.missingDisplayFallback
        )
        let report = await LiveRestore.run(request) { progress in
            print("配置中… \(progress.completed) / \(progress.total)")
        }
        print(report.summary)
        if report.placedCount > 0 {
            recordUse(of: workspace.id, at: report.finishedAt, in: store)
        }
        return report.results.allSatisfy(\.outcome.isPlaced) ? 0 : 1
    }

    /// Records when the workspace was used, which decides between workspaces for automatic
    /// restores, as the app does. Skipped when the file cannot be read completely.
    static func recordUse(of id: UUID, at date: Date, in store: LaneKeepStore) {
        let load = store.loadWorkspaces(unreadableFile: .leave)
        guard load.problem == nil, let position = load.value.firstIndex(where: { $0.id == id }) else { return }
        var workspaces = load.value
        workspaces[position].lastUsedAt = date
        _ = try? store.saveWorkspaces(workspaces)
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

    /// Tells about a data file that could not be read completely. The file itself is left alone.
    static func warnAbout<Value>(_ load: StoreLoad<Value>, file: String) {
        switch load.problem {
        case .unreadable:
            fail("\(file) を読み込めませんでした（ファイルはそのままです）。")
        case .partlyUnreadable(let entries):
            fail("\(file) のうち\(entries)件を読み込めませんでした（ファイルはそのままです）。")
        case nil:
            break
        }
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
        if let number = Int(value) {
            return displays.indices.contains(number - 1) ? displays[number - 1] : nil
        }
        return displays.first { $0.uuid.caseInsensitiveCompare(value) == .orderedSame }
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

/// A usage mistake that is not about a single option.
struct UsageError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
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
