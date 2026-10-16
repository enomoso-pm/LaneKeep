import AppKit
import LaneKeepCore
import LaneKeepSystem
import SwiftUI
import UniformTypeIdentifiers

/// "除外するアプリ" (spec §3.5): apps whose windows are left out of the save list.
struct ExcludedAppsView: View {
    @Environment(AppModel.self) private var model
    @State private var runningApps: [RunningAppInfo] = []
    @State private var isChoosingApp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("除外するアプリ")
                        .laneText(20, .bold)
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    HintText("ここにあるアプリのウィンドウは「今の配置を保存」の一覧に出ません。保存済みのワークスペースはそのままです。")
                }
                VStack(spacing: 0) {
                    if model.preferences.excludedApps.isEmpty {
                        Text("除外しているアプリはありません")
                            .laneText(13)
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
                Button("アプリを追加…") {
                    reloadRunningApps()
                    isChoosingApp = true
                }
                .buttonStyle(LaneButtonStyle())
                .help("起動中のアプリから選ぶか、アプリケーションフォルダから選びます")
                .popover(isPresented: $isChoosingApp, arrowEdge: .bottom) {
                    AppChooser(
                        apps: addableApps,
                        onChoose: { app in
                            model.addExcludedApp(bundleID: app.bundleID, name: app.name)
                            isChoosingApp = false
                        },
                        onChooseOther: {
                            isChoosingApp = false
                            // Let the popover close before the panel takes over.
                            Task { @MainActor in
                                chooseApplications()
                            }
                        }
                    )
                }
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
                    .laneText(13)
                    .foregroundStyle(Theme.ink)
                Text(app.bundleID)
                    .laneText(11)
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

/// The running apps that can be excluded, and a way to pick any other app.
private struct AppChooser: View {
    let apps: [RunningAppInfo]
    let onChoose: (RunningAppInfo) -> Void
    let onChooseOther: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel("起動中のアプリ")
                .padding(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
            if apps.isEmpty {
                Text("追加できる起動中のアプリはありません")
                    .laneText(13)
                    .foregroundStyle(Theme.sub)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(apps) { app in
                            AppChooserRow(app: app) { onChoose(app) }
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: 320)
                .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(Theme.line).frame(height: 1)
                .padding(.top, 6)
            Button("その他のアプリを選ぶ…", action: onChooseOther)
                .buttonStyle(PlainTextButtonStyle(color: Theme.accentInk, weight: .medium, size: 13, height: 36, horizontalPadding: 10))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
        }
        .frame(width: 280)
    }
}

private struct AppChooserRow: View {
    let app: RunningAppInfo
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AppInitialBadge(name: app.name)
                Text(app.name)
                    .font(.lane(13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Theme.muted : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(app.bundleID)
    }
}
