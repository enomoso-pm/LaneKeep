import Foundation
import LaneKeepCore
import LaneKeepSystem
import Observation

/// The state of the "今の配置を保存" screen (spec §3.1), also used to overwrite an existing
/// workspace from the settings window.
@MainActor
@Observable
final class CaptureSession: Identifiable {
    enum Mode: Equatable {
        case new
        case overwrite(UUID)
    }

    nonisolated let id = UUID()
    let mode: Mode
    var name: String
    var color: WorkspaceColor
    var launchIfClosed = true
    var autoRestoreOnConnect = true
    var selectedIDs: Set<String> = []

    private(set) var displays: [DisplaySnapshot] = []
    private(set) var candidates: [CaptureCandidate] = []
    private(set) var isLoading = true

    init(mode: Mode, name: String, color: WorkspaceColor) {
        self.mode = mode
        self.name = name
        self.color = color
    }

    var selectedCandidates: [CaptureCandidate] {
        candidates.filter { selectedIDs.contains($0.id) }
    }

    /// Reads the displays and windows. `preselect` decides which windows start checked; by default
    /// all of them (spec §3.1).
    func load(
        excludedBundleIDs: Set<String>,
        preselect: (([CaptureCandidate]) -> Set<String>)? = nil
    ) async {
        isLoading = true
        let displays = ScreenReader.currentDisplays()
        let windows = await WindowCatalog.snapshot()
        let candidates = CaptureBuilder.candidates(from: windows, displays: displays, excludedBundleIDs: excludedBundleIDs)
        self.displays = displays
        self.candidates = candidates
        selectedIDs = preselect?(candidates) ?? Set(candidates.map(\.id))
        isLoading = false
    }

    func isSelected(_ candidate: CaptureCandidate) -> Bool {
        selectedIDs.contains(candidate.id)
    }

    func setSelected(_ selected: Bool, for candidate: CaptureCandidate) {
        if selected {
            selectedIDs.insert(candidate.id)
        } else {
            selectedIDs.remove(candidate.id)
        }
    }

    /// Several windows of the same app are told apart by their title in the list.
    func needsTitle(_ candidate: CaptureCandidate) -> Bool {
        candidates.filter { $0.window.bundleID == candidate.window.bundleID }.count > 1
    }
}
