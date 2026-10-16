import Foundation
import Observation
import os
import ServiceManagement

/// "ログイン時に起動" through `SMAppService.mainApp` (spec §8).
@MainActor
@Observable
final class LoginItemController {
    private(set) var status: SMAppService.Status = .notRegistered
    private(set) var errorMessage: String?

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    var requiresApproval: Bool {
        status == .requiresApproval
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            Logger(subsystem: "LaneKeep", category: "login-item").error("SMAppService failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "ログイン項目を変更できませんでした（\(error.localizedDescription)）"
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
