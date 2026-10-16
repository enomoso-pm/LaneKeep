#if DEBUG
import AppKit
import SwiftUI

/// Renders every screen with the sample data into PNG files, in light and dark appearance, and
/// quits. Debug builds only; used to check the UI against the mock without clicking through it:
///
///     LaneKeep.app/Contents/MacOS/LaneKeep --render-ui-snapshots [output directory]
///
/// Each image is also printed to standard output as base64 lines (`LKSNAP <name> <part> <data>`)
/// so that it can be recovered from a CI log.
@MainActor
enum SnapshotRenderer {
    static let argument = "--render-ui-snapshots"

    static var isRequested: Bool {
        CommandLine.arguments.contains(argument)
    }

    static func renderAndQuit() {
        Task {
            await renderAll()
            NSApp.terminate(nil)
        }
    }

    private struct Shot {
        let name: String
        let size: CGSize
        let makeView: @MainActor () -> AnyView
    }

    private static var shots: [Shot] {
        [
            Shot(name: "popover-list", size: CGSize(width: 360, height: 620)) {
                AnyView(PopoverRootView().environment(AppModel.preview()))
            },
            Shot(name: "popover-restoring", size: CGSize(width: 360, height: 620)) {
                AnyView(PopoverRootView().environment(AppModel.preview(.restoring)))
            },
            Shot(name: "popover-finished", size: CGSize(width: 360, height: 620)) {
                AnyView(PopoverRootView().environment(AppModel.preview(.finished)))
            },
            Shot(name: "popover-capture", size: CGSize(width: 360, height: 720)) {
                let session = CaptureSession.preview()
                return AnyView(
                    CaptureScreen(session: session, onCancel: {}, onSave: {})
                        .frame(width: 360, height: 720)
                        .background(Theme.window)
                )
            },
            Shot(name: "popover-onboarding", size: CGSize(width: 360, height: 560)) {
                AnyView(PopoverRootView().environment(AppModel.preview(.noPermission)))
            },
            Shot(name: "popover-empty", size: CGSize(width: 360, height: 620)) {
                AnyView(PopoverRootView().environment(AppModel.preview(.empty)))
            },
            Shot(name: "settings-workspace", size: CGSize(width: 1000, height: 820)) {
                AnyView(SettingsRootView().environment(AppModel.preview()))
            },
            Shot(name: "settings-office", size: CGSize(width: 1000, height: 820)) {
                let model = AppModel.preview()
                model.settingsPane = .workspace(PreviewData.office.id)
                return AnyView(SettingsRootView().environment(model))
            },
            Shot(name: "settings-general", size: CGSize(width: 1000, height: 820)) {
                let model = AppModel.preview()
                model.settingsPane = .general
                return AnyView(SettingsRootView().environment(model))
            },
            Shot(name: "settings-excluded", size: CGSize(width: 1000, height: 620)) {
                let model = AppModel.preview()
                model.settingsPane = .excludedApps
                return AnyView(SettingsRootView().environment(model))
            }
        ]
    }

    private static func renderAll() async {
        let arguments = CommandLine.arguments
        let directory: URL? = arguments.firstIndex(of: argument).flatMap { index in
            arguments.indices.contains(index + 1) ? URL(fileURLWithPath: arguments[index + 1], isDirectory: true) : nil
        }
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let appearances: [(suffix: String, name: NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        for appearance in appearances {
            for shot in shots {
                let name = "\(shot.name)-\(appearance.suffix)"
                guard let data = await render(shot.makeView(), size: shot.size, appearance: appearance.name) else {
                    print("LKSNAP-FAILED \(name)")
                    continue
                }
                if let directory {
                    try? data.write(to: directory.appendingPathComponent("\(name).png"))
                }
                emit(data, name: name)
            }
        }
        print("LKSNAP-DONE")
    }

    private static func render(_ view: AnyView, size: CGSize, appearance: NSAppearance.Name) async -> Data? {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }

        // Give SwiftUI a few run loop turns to lay out and draw.
        for _ in 0..<3 {
            hosting.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return nil
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        return representation.representation(using: .png, properties: [:])
    }

    private static func emit(_ data: Data, name: String) {
        let encoded = data.base64EncodedString()
        let chunkSize = 3_000
        var part = 0
        var start = encoded.startIndex
        while start < encoded.endIndex {
            let end = encoded.index(start, offsetBy: chunkSize, limitedBy: encoded.endIndex) ?? encoded.endIndex
            print("LKSNAP \(name) \(part) \(encoded[start..<end])")
            start = end
            part += 1
        }
        print("LKSNAP-END \(name) \(part)")
    }
}
#endif
