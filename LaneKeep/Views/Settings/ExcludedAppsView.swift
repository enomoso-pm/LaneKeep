import AppKit
import LaneKeepCore
import LaneKeepSystem
import SwiftUI
import UniformTypeIdentifiers

/// "除外するアプリ" (spec §3.5): apps whose windows are left out of the save list.
struct ExcludedAppsView: View {
    @Environment(AppModel.self) private var model
    @State private var runningApps: [RunningAppInfo] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("除外するアプリ")
                        .font(.lane(20, .bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    HintText("ここにあるアプリのウィンドウは「今の配置を保存」の一覧に出ません。保存済みのワークスペースはそのままです。")
                }
                VStack(spacing: 0) {
                    if model.preferences.excludedApps.isEmpty {
                        Text("除外しているアプリはありません")
                            .font(.lane(13))
                            .foregroundStyle(Theme.sub)
                            .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    ForEach(Array(model.preferences.excludedApps.enumerated()), id: \.element.id) { index, app in
                        if index > 0 {
                            Rectangle().fill(Theme.line).frame(height: 1)
                        }
                        ExcludedAppRow(app: app) {
                            model.removeExcludedApp(bundleID: app.bundleID)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .laneBox()
                Menu {
                    let candidates = addableApps
                    if candidates.isEmpty {
                        Text("追加できる起動中のアプリはありません")
                    }
                    ForEach(candidates) { app in
                        Button(app.name) {
                            model.addExcludedApp(bundleID: app.bundleID, name: app.name)
                        }
                    }
                    Divider()
                    Button("その他のアプリを選ぶ…") { chooseApplications() }
                } label: {
                    Text("アプリを追加")
                }
                .fixedSize()
                .help("起動中のアプリから選ぶか、アプリケーションフォルダから選びます")
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(EdgeInsets(top: 20, leading: 24, bottom: 28, trailing: 24))
        }
        .scrollBounceBehavior(.basedOnSize)
        .onAppear { reloadRunningApps() }
    }

    private var addableApps: [RunningAppInfo] {
        let excluded = model.preferences.excludedBundleIDs
        return runningApps.filter { !excluded.contains($0.bundleID) }
    }

    private func reloadRunningApps() {
        var seen = Set<String>()
        runningApps = RunningApps.regularApps()
            .filter { seen.insert($0.bundleID).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func chooseApplications() {
        let panel = NSOpenPanel()
        panel.title = "除外するアプリを選ぶ"
        panel.prompt = "除外する"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
            model.addExcludedApp(bundleID: bundleID, name: Self.displayName(of: bundle, at: url))
        }
    }

    private static func displayName(of bundle: Bundle, at url: URL) -> String {
        let keys = ["CFBundleDisplayName", "CFBundleName"]
        for key in keys {
            if let name = bundle.localizedInfoDictionary?[key] as? String ?? bundle.infoDictionary?[key] as? String,
               !name.isEmpty {
                return name
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }
}

private struct ExcludedAppRow: View {
    let app: ExcludedApp
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            AppInitialBadge(name: app.name)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.name)
                    .font(.lane(13))
                    .foregroundStyle(Theme.ink)
                Text(app.bundleID)
                    .font(.lane(11))
                    .foregroundStyle(Theme.sub)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Button("外す", action: onRemove)
                .buttonStyle(LaneButtonStyle(height: 28))
                .accessibilityLabel("\(app.name)を除外から外す")
        }
        .frame(minHeight: 48)
    }
}
