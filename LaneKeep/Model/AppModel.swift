import AppKit
import KeyboardShortcuts
import LaneKeepCore
import LaneKeepSystem
import Observation
import os

/// Which screen the menu bar window shows.
enum PopoverRoute: Equatable {
    case list
    case capture
}

/// Which page the settings window shows.
enum SettingsPane: Hashable {
    case workspace(UUID)
    case general
    case excludedApps
}

/// What started a restore.
enum RestoreTrigger: Equatable {
    case manual
    case shortcut
    case automatic
}

struct ActiveRestore: Equatable {
    var workspaceID: UUID
    var trigger: RestoreTrigger
    var progress: RestoreProgress
}

/// The state shown under a workspace in the list.
enum WorkspaceCardState: Equatable {
    case restoring(RestoreProgress)
    case note(String)
    case matchesCurrent
    case missingDisplays(Int)
    case plain
}

/// The app's state and everything the UI can ask it to do.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: - State

    private(set) var workspaces: [Workspace] = []
    private(set) var preferences = Preferences()
    /// The displays connected right now.
    private(set) var displays: [DisplaySnapshot] = []
    private(set) var isAccessibilityGranted = false
    private(set) var activeRestore: ActiveRestore?
    /// The one-line result per workspace (spec §3.2), also used for "saved" confirmations.
    private(set) var notes: [UUID: String] = [:]
    /// A problem with the data files that the user should know about.
    private(set) var storageProblem: String?
    /// Set after a shortcut was recorded that another action already used.
    private(set) var shortcutNotice: String?
    /// Bumped whenever a keyboard shortcut changes, so views that show shortcuts update.
    private(set) var shortcutRevision = 0

    var popoverRoute: PopoverRoute = .list
    private(set) var captureSession: CaptureSession?
    /// "あとで" on the permission screen, for this session.
    var onboardingDismissed = false
    /// Shows the permission screen a moment longer after the permission was granted.
    private(set) var isCelebratingPermission = false
    /// The usable height of the screen the menu bar window is on.
    private(set) var availableScreenHeight: CGFloat = 900

    var settingsPane: SettingsPane = .general

    let loginItem = LoginItemController()

    private let store = LaneKeepStore()
    private let shortcuts = ShortcutCenter()
    @ObservationIgnored private var displayMonitor: DisplayMonitor?
    @ObservationIgnored private var saveWorkspacesTask: Task<Void, Never>?
    @ObservationIgnored private var savePreferencesTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    @ObservationIgnored private var shortcutNoticeTask: Task<Void, Never>?
    @ObservationIgnored private var pendingAutoTrigger: AutoRestoreTrigger?
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    /// When the set of connected displays last changed, and the last restore the user started
    /// (with its displays): a restore the user picked for new displays is not overridden by the
    /// automatic one that follows once the displays have settled.
    @ObservationIgnored private var displaysChangedAt: Date?
    @ObservationIgnored private var lastUserRestore: (signature: String, startedAt: Date)?
    /// The version of workspaces.json the app last read or wrote, and what the app changed since:
    /// the `lanekeep` command writes the same file while the app runs.
    @ObservationIgnored private var workspacesStamp: FileStamp?
    @ObservationIgnored private var changedWorkspaceIDs: Set<UUID> = []
    @ObservationIgnored private var deletedWorkspaceIDs: Set<UUID> = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var distributedObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var isStarted = false
    /// Set on the sample models of previews and UI snapshots, which are not in the menu bar.
    @ObservationIgnored private var isPreview = false
    private let log = Logger(subsystem: "LaneKeep", category: "app")

    private init() {}

    // MARK: - Derived state

    var currentSignature: String {
        DisplaySignature.make(displays.map(\.uuid))
    }

    var isRestoring: Bool {
        activeRestore != nil
    }

    var showsOnboarding: Bool {
        (!isAccessibilityGranted && !onboardingDismissed) || isCelebratingPermission
    }

    var currentDisplaysText: String {
        displays.isEmpty ? "ディスプレイが見つかりません" : DisplayText.displayNames(displays)
    }

    func workspace(_ id: UUID) -> Workspace? {
        workspaces.first { $0.id == id }
    }

    func cardState(for workspace: Workspace) -> WorkspaceCardState {
        if let activeRestore, activeRestore.workspaceID == workspace.id {
            return .restoring(activeRestore.progress)
        }
        if let note = notes[workspace.id] {
            return .note(note)
        }
        switch workspace.availability(for: displays) {
        case .matchesCurrent:
            return .matchesCurrent
        case .missingDisplays(let count):
            return .missingDisplays(count)
        case .available:
            return .plain
        }
    }

    func isMatchingCurrentDisplays(_ workspace: Workspace) -> Bool {
        workspace.availability(for: displays) == .matchesCurrent
    }

    func shortcutText(for workspace: Workspace) -> String? {
        _ = shortcutRevision
        #if DEBUG
        if let text = PreviewData.shortcutTexts[workspace.id] {
            return text
        }
        #endif
        return shortcuts.text(for: workspace)
    }

    var menuShortcutText: String? {
        _ = shortcutRevision
        #if DEBUG
        if let text = PreviewData.menuShortcutText {
            return text
        }
        #endif
        return shortcuts.menuShortcutText
    }

    // MARK: - Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        AccessibilityTuning.configureMessagingTimeout()
        loadData()
        refreshDisplays()
        refreshPermission()
        loginItem.refresh()

        shortcuts.prepareMenuShortcut()
        shortcuts.onToggleMenu = { StatusItemBridge.toggleMenu() }
        shortcuts.onRestore = { [weak self] id in
            self?.restore(id, trigger: .shortcut)
        }
        assignMissingShortcuts()
        shortcuts.registerHandlers(for: workspaces)
        observers.append(
            NotificationCenter.default.addObserver(forName: ShortcutCenter.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.shortcutRevision += 1
                }
            }
        )
        // Coming back from System Settings: the login item may have been approved, the
        // permission granted or taken away.
        observers.append(
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.loginItem.refresh()
                    self?.refreshPermission()
                }
            }
        )
        // Posted by the system when the list of apps allowed to use accessibility changes.
        distributedObservers.append(
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.accessibility.api"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.recheckPermissionSoon()
                }
            }
        )

        let monitor = DisplayMonitor(initialSignature: currentSignature)
        monitor.onDisplaysChanged = { [weak self] in
            self?.displaysDidChange()
        }
        monitor.onSettled = { [weak self] trigger in
            self?.handleAutoRestore(trigger)
        }
        monitor.start()
        displayMonitor = monitor

        // Without the permission LaneKeep can do nothing, and a menu bar app shows no window on
        // its own: open the menu so that the permission screen is the first thing the user sees.
        if !isAccessibilityGranted {
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                StatusItemBridge.openMenu()
            }
        }
    }

    /// Writes pending changes immediately (on quit).
    func flushPendingSaves() {
        if saveWorkspacesTask != nil {
            saveWorkspacesNow()
        }
        if savePreferencesTask != nil {
            savePreferencesNow()
        }
    }

    func quit() {
        flushPendingSaves()
        NSApp.terminate(nil)
    }

    // MARK: - Environment

    func refreshDisplays() {
        let current = ScreenReader.currentDisplays()
        if current != displays {
            displays = current
        }
    }

    func refreshPermission() {
        let granted = AccessibilityPermission.isGranted
        guard granted != isAccessibilityGranted else {
            if !granted {
                startPermissionPolling()
            }
            return
        }
        let wasShowingOnboarding = showsOnboarding
        isAccessibilityGranted = granted
        if granted {
            log.info("Accessibility permission granted")
            popoverRoute = .list
            if wasShowingOnboarding {
                celebratePermission()
            }
        } else {
            log.info("Accessibility permission missing")
            startPermissionPolling()
        }
    }

    /// "システム設定を開く": adds LaneKeep to the list in System Settings (through the system
    /// prompt) and opens the Accessibility pane.
    func requestAccessibilityPermission() {
        AccessibilityPermission.requestWithSystemPrompt()
        AccessibilityPermission.openSystemSettings()
        startPermissionPolling()
    }

    /// Checks the permission every second until it is granted (spec §3.6).
    private func startPermissionPolling() {
        guard permissionTask == nil else { return }
        permissionTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.refreshPermission()
                if self.isAccessibilityGranted {
                    break
                }
            }
            self?.permissionTask = nil
        }
    }

    /// Checks the permission again once a change has had a moment to apply.
    private func recheckPermissionSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.refreshPermission()
        }
    }

    private func celebratePermission() {
        isCelebratingPermission = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            self?.isCelebratingPermission = false
        }
    }

    private func displaysDidChange() {
        let previousSignature = currentSignature
        refreshDisplays()
        if currentSignature != previousSignature {
            displaysChangedAt = Date()
            // Results describe the previous arrangement; the cards show the new state instead.
            notes.removeAll()
        }
    }

    // MARK: - Menu bar window

    func popoverVisibilityChanged(_ visibility: WindowVisibility, window: NSWindow) {
        guard !isPreview else { return }
        StatusItemBridge.menuWindow = window
        switch visibility {
        case .shown:
            refreshDisplays()
            refreshPermission()
            syncWorkspacesWithFile()
            if let height = window.screen?.visibleFrame.height {
                availableScreenHeight = height
            }
        case .hidden:
            // Closing the menu abandons a save in progress. A menu that is merely covered (the
            // display went to sleep) keeps it.
            if popoverRoute == .capture {
                cancelCapture()
            }
        case .covered:
            break
        }
    }

    func openSettings(_ pane: SettingsPane? = nil) {
        if let pane {
            settingsPane = pane
        } else if case .workspace(let id) = settingsPane, workspace(id) == nil {
            settingsPane = .general
        }
        StatusItemBridge.closeMenu()
        loginItem.refresh()
        syncWorkspacesWithFile()
        SettingsWindowController.shared.show(model: self)
    }

    // MARK: - Restoring

    func restore(_ id: UUID, trigger: RestoreTrigger) {
        guard activeRestore == nil, let workspace = workspace(id) else { return }
        refreshPermission()
        guard isAccessibilityGranted else {
            log.info("Restore of \(workspace.name, privacy: .public) needs the accessibility permission")
            if trigger != .automatic {
                onboardingDismissed = false
                StatusItemBridge.openMenu()
            }
            return
        }
        guard !workspace.windows.isEmpty else {
            notes[id] = "このワークスペースには配置するウィンドウがありません"
            return
        }
        refreshDisplays()
        let request = RestoreRequest(workspace: workspace, displays: displays, fallback: preferences.missingDisplayFallback)
        notes[id] = nil
        activeRestore = ActiveRestore(
            workspaceID: id,
            trigger: trigger,
            progress: RestoreProgress(completed: 0, total: workspace.windows.count)
        )
        if trigger != .automatic {
            lastUserRestore = (signature: currentSignature, startedAt: Date())
        }
        log.info("Restoring \(workspace.name, privacy: .public) (\(String(describing: trigger), privacy: .public))")

        let started = ContinuousClock.now
        restoreTask = Task {
            let report = await LiveRestore.run(request) { progress in
                await MainActor.run {
                    self.updateProgress(progress, for: id)
                }
            }
            if trigger == .manual {
                // Keep the progress visible for a moment even when every window was already in place.
                let minimum = Duration.milliseconds(500)
                let elapsed = ContinuousClock.now - started
                if elapsed < minimum {
                    try? await Task.sleep(for: minimum - elapsed)
                }
            }
            self.finishRestore(report)
        }
    }

    /// Reads the result out to VoiceOver users, who would not notice the card changing.
    private func announce(_ text: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ]
        )
    }

    private func updateProgress(_ progress: RestoreProgress, for id: UUID) {
        guard activeRestore?.workspaceID == id else { return }
        activeRestore?.progress = progress
    }

    private func finishRestore(_ report: RestoreReport) {
        activeRestore = nil
        restoreTask = nil
        log.info("Restore finished: \(report.summary, privacy: .public)")
        if let index = workspaces.firstIndex(where: { $0.id == report.workspaceID }) {
            notes[report.workspaceID] = report.summary
            if report.placedCount > 0 {
                workspaces[index].lastUsedAt = report.finishedAt
                changedWorkspaceIDs.insert(report.workspaceID)
                scheduleWorkspacesSave()
            }
            announce("「\(workspaces[index].name)」：\(report.summary)")
        }
        if let pending = pendingAutoTrigger {
            pendingAutoTrigger = nil
            handleAutoRestore(pending)
        }
    }

    /// Spec §3.3: restore the matching workspace when displays change (or the Mac wakes up).
    private func handleAutoRestore(_ trigger: AutoRestoreTrigger) {
        refreshDisplays()
        guard preferences.autoRestoreEnabled else { return }
        if isRestoring {
            pendingAutoTrigger = (pendingAutoTrigger ?? []).union(trigger)
            return
        }
        var trigger = trigger
        if trigger.contains(.displaysChanged),
           let userRestore = lastUserRestore,
           userRestore.signature == currentSignature,
           let changedAt = displaysChangedAt,
           userRestore.startedAt >= changedAt {
            // The user already restored a workspace for these displays.
            trigger.remove(.displaysChanged)
        }
        guard !trigger.isEmpty else { return }
        syncWorkspacesWithFile()
        guard let workspace = AutoRestorePolicy.workspaceToRestore(
            among: workspaces,
            currentSignature: currentSignature,
            trigger: trigger,
            masterSwitch: preferences.autoRestoreEnabled
        ) else {
            return
        }
        restore(workspace.id, trigger: .automatic)
    }

    // MARK: - Saving the current layout

    func beginCapture() {
        refreshPermission()
        guard isAccessibilityGranted else {
            onboardingDismissed = false
            return
        }
        refreshDisplays()
        let session = CaptureSession(
            mode: .new,
            name: CaptureBuilder.suggestedName(for: displays, existingNames: workspaces.map(\.name)),
            color: CaptureBuilder.suggestedColor(existing: workspaces.map(\.color))
        )
        captureSession = session
        popoverRoute = .capture
        let excluded = preferences.excludedBundleIDs
        Task {
            await session.load(excludedBundleIDs: excluded)
        }
    }

    func cancelCapture() {
        popoverRoute = .list
        captureSession = nil
    }

    func saveCapture(_ session: CaptureSession) {
        // Return and the save button can both fire; only the current session is saved, once.
        guard captureSession === session else { return }
        let selected = session.selectedCandidates
        guard !selected.isEmpty else { return }
        let fallbackName = CaptureBuilder.suggestedName(for: session.displays, existingNames: workspaces.map(\.name))
        var workspace = CaptureBuilder.workspace(
            name: CaptureBuilder.normalizedName(session.name, fallback: fallbackName),
            color: session.color,
            icon: CaptureBuilder.suggestedIcon(for: session.displays),
            candidates: selected,
            displays: session.displays,
            launchIfClosed: session.launchIfClosed,
            autoRestoreOnConnect: session.autoRestoreOnConnect
        )
        shortcuts.assignDefaultShortcut(to: &workspace, others: workspaces)
        workspaces.append(workspace)
        changedWorkspaceIDs.insert(workspace.id)
        shortcuts.registerHandlers(for: workspaces)
        scheduleWorkspacesSave()
        notes[workspace.id] = "\(selected.count)件のウィンドウを保存しました"
        if case .general = settingsPane {
            settingsPane = .workspace(workspace.id)
        }
        cancelCapture()
    }

    /// A capture session for "今の配置で上書き", with the windows of the existing rules checked.
    func makeOverwriteSession(for id: UUID) -> CaptureSession? {
        guard let workspace = workspace(id) else { return nil }
        refreshDisplays()
        let session = CaptureSession(mode: .overwrite(id), name: workspace.name, color: workspace.color)
        session.autoRestoreOnConnect = workspace.autoRestoreOnConnect
        session.launchIfClosed = workspace.windows.isEmpty || workspace.windows.contains(where: \.launchIfClosed)
        let rules = workspace.windows
        let excluded = preferences.excludedBundleIDs
        Task {
            await session.load(excludedBundleIDs: excluded) { candidates in
                let matched = Set(CaptureBuilder.matchPrevious(rules, to: candidates).keys)
                return matched.isEmpty ? Set(candidates.map(\.id)) : matched
            }
        }
        return session
    }

    func applyOverwrite(_ session: CaptureSession) {
        guard case .overwrite(let id) = session.mode else { return }
        let selected = session.selectedCandidates
        guard !selected.isEmpty else { return }
        update(id) { workspace in
            workspace.windows = CaptureBuilder.rules(
                from: selected,
                replacing: workspace.windows,
                launchIfClosedForNewWindows: session.launchIfClosed
            )
            workspace.setDisplays(DisplayRoles.ordered(session.displays).map(DisplayInfo.init))
            workspace.autoRestoreOnConnect = session.autoRestoreOnConnect
            workspace.lastUsedAt = Date()
        }
        notes[id] = "\(selected.count)件のウィンドウで上書きしました"
    }

    // MARK: - Editing workspaces

    func update(_ id: UUID, _ change: (inout Workspace) -> Void) {
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        change(&workspaces[index])
        changedWorkspaceIDs.insert(id)
        scheduleWorkspacesSave()
    }

    func updateRule(_ ruleID: UUID, in workspaceID: UUID, _ change: (inout WindowRule) -> Void) {
        update(workspaceID) { workspace in
            if let index = workspace.windows.firstIndex(where: { $0.id == ruleID }) {
                change(&workspace.windows[index])
            }
        }
    }

    func deleteRule(_ ruleID: UUID, in workspaceID: UUID) {
        update(workspaceID) { workspace in
            workspace.windows.removeAll { $0.id == ruleID }
        }
    }

    func deleteWorkspace(_ id: UUID) {
        guard let workspace = workspace(id) else { return }
        shortcuts.removeShortcut(of: workspace)
        workspaces.removeAll { $0.id == id }
        changedWorkspaceIDs.remove(id)
        deletedWorkspaceIDs.insert(id)
        notes[id] = nil
        shortcuts.registerHandlers(for: workspaces)
        scheduleWorkspacesSave()
        if settingsPane == .workspace(id) {
            settingsPane = workspaces.first.map { .workspace($0.id) } ?? .general
        }
    }

    // MARK: - Shortcuts

    func shortcutName(for workspace: Workspace) -> KeyboardShortcuts.Name? {
        ShortcutCenter.name(for: workspace)
    }

    /// Called by the recorders after the user changed a shortcut.
    func shortcutRecorded(for name: KeyboardShortcuts.Name) {
        shortcutRevision += 1
        let notice = shortcuts.resolveConflicts(after: name, workspaces: workspaces)
        // Removing a key combination from one action can unregister it for the action that just
        // got it (KeyboardShortcuts 2.x); registering all handlers again keeps it working.
        shortcuts.registerHandlers(for: workspaces)
        guard let notice else { return }
        shortcutNotice = notice
        shortcutNoticeTask?.cancel()
        shortcutNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.shortcutNotice = nil
        }
    }

    func resetMenuShortcut() {
        KeyboardShortcuts.setShortcut(ShortcutCenter.defaultMenuShortcut, for: ShortcutCenter.toggleMenu)
        shortcutRecorded(for: ShortcutCenter.toggleMenu)
    }

    /// Workspaces written by the command-line tool have no shortcut yet.
    private func assignMissingShortcuts() {
        var changed = false
        for index in workspaces.indices where workspaces[index].shortcut == nil {
            var workspace = workspaces[index]
            shortcuts.assignDefaultShortcut(to: &workspace, others: workspaces)
            workspaces[index] = workspace
            changedWorkspaceIDs.insert(workspace.id)
            changed = true
        }
        if changed {
            scheduleWorkspacesSave()
        }
    }

    // MARK: - Preferences

    func updatePreferences(_ change: (inout Preferences) -> Void) {
        change(&preferences)
        schedulePreferencesSave()
    }

    func setAutoRestoreEnabled(_ enabled: Bool) {
        updatePreferences { $0.autoRestoreEnabled = enabled }
        if !enabled {
            pendingAutoTrigger = nil
            if activeRestore?.trigger == .automatic {
                log.info("Automatic restore stopped by the master switch")
                restoreTask?.cancel()
            }
        }
    }

    func addExcludedApp(bundleID: String, name: String) {
        guard !preferences.excludedApps.contains(where: { $0.bundleID == bundleID }) else { return }
        updatePreferences { preferences in
            preferences.excludedApps.append(ExcludedApp(bundleID: bundleID, name: name))
            preferences.excludedApps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func removeExcludedApp(bundleID: String) {
        updatePreferences { $0.excludedApps.removeAll { $0.bundleID == bundleID } }
    }

    var dataDirectory: URL {
        store.directory
    }

    // MARK: - Persistence

    private func loadData() {
        let workspaceLoad = store.loadWorkspaces()
        let preferencesLoad = store.loadPreferences()
        workspaces = workspaceLoad.value
        workspacesStamp = workspaceLoad.stamp
        preferences = preferencesLoad.value
        var backups: [URL?] = []
        if workspaceLoad.problem != nil {
            backups.append(workspaceLoad.backupOfUnreadableFile)
        }
        if preferencesLoad.problem != nil {
            backups.append(preferencesLoad.backupOfUnreadableFile)
        }
        reportLoadProblems(backups: backups)
        if case .general = settingsPane, let first = workspaces.first {
            settingsPane = .workspace(first.id)
        }
    }

    /// Shows a notice about data files that could not be read completely: one entry per file,
    /// with the copy that was kept (`nil` when none could be made).
    private func reportLoadProblems(backups files: [URL?]) {
        guard !files.isEmpty else { return }
        let backups = files.compactMap { $0?.lastPathComponent }
        if backups.isEmpty {
            storageProblem = "保存データの一部を読み込めませんでした。"
        } else {
            storageProblem = "保存データの一部を読み込めませんでした。元のファイルは \(backups.joined(separator: "、")) として残してあります。"
        }
        log.error("Data files could not be read completely; backups: \(backups.joined(separator: ", "), privacy: .public)")
    }

    /// Picks up changes another program made to workspaces.json since the app last read or wrote
    /// it: workspaces saved with the `lanekeep` command, or a hand edit.
    private func syncWorkspacesWithFile() {
        guard isStarted, !isPreview, store.workspacesStamp != workspacesStamp else { return }
        let load = store.loadWorkspaces()
        workspacesStamp = load.stamp
        if let problem = load.problem {
            reportLoadProblems(backups: [load.backupOfUnreadableFile])
            // Nothing usable in the file: keep what the app has; it is written back on the next save.
            if problem == .unreadable {
                return
            }
        }
        let merged = WorkspaceMerge.merge(
            local: workspaces,
            file: load.value,
            changedLocally: changedWorkspaceIDs,
            deletedLocally: deletedWorkspaceIDs
        )
        guard merged != workspaces else { return }
        log.info("workspaces.json was changed by another program; \(merged.count) workspaces now")
        workspaces = merged
        assignMissingShortcuts()
        shortcuts.registerHandlers(for: workspaces)
        if case .workspace(let id) = settingsPane, workspace(id) == nil {
            settingsPane = workspaces.first.map { .workspace($0.id) } ?? .general
        }
    }

    func dismissStorageProblem() {
        storageProblem = nil
    }

    private func scheduleWorkspacesSave() {
        saveWorkspacesTask?.cancel()
        saveWorkspacesTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveWorkspacesNow()
        }
    }

    private func saveWorkspacesNow() {
        saveWorkspacesTask?.cancel()
        saveWorkspacesTask = nil
        // Do not write over what another program saved in the meantime.
        syncWorkspacesWithFile()
        do {
            workspacesStamp = try store.saveWorkspaces(workspaces)
            changedWorkspaceIDs.removeAll()
            deletedWorkspaceIDs.removeAll()
        } catch {
            log.error("Saving workspaces failed: \(error.localizedDescription, privacy: .public)")
            storageProblem = "ワークスペースを保存できませんでした（\(error.localizedDescription)）"
        }
    }

    private func schedulePreferencesSave() {
        savePreferencesTask?.cancel()
        savePreferencesTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.savePreferencesNow()
        }
    }

    private func savePreferencesNow() {
        savePreferencesTask?.cancel()
        savePreferencesTask = nil
        do {
            try store.savePreferences(preferences)
        } catch {
            log.error("Saving preferences failed: \(error.localizedDescription, privacy: .public)")
            storageProblem = "設定を保存できませんでした（\(error.localizedDescription)）"
        }
    }
}

#if DEBUG
extension AppModel {
    enum PreviewScenario {
        case standard
        case restoring
        case finished
        case capture
        case noPermission
        case empty
    }

    /// A model filled with the sample data of the UI mock, for previews and UI snapshots. It is
    /// not started: nothing is read from or written to disk.
    static func preview(_ scenario: PreviewScenario = .standard) -> AppModel {
        PreviewData.installShortcutTexts()
        let model = AppModel()
        model.isStarted = true
        model.isPreview = true
        model.displays = PreviewData.homeDisplays
        model.workspaces = scenario == .empty ? [] : PreviewData.workspaces
        model.isAccessibilityGranted = scenario != .noPermission
        model.preferences.excludedApps = [
            ExcludedApp(bundleID: "com.apple.finder", name: "Finder"),
            ExcludedApp(bundleID: "com.apple.systempreferences", name: "システム設定")
        ]
        model.settingsPane = scenario == .empty ? .general : .workspace(PreviewData.home.id)
        switch scenario {
        case .restoring:
            model.activeRestore = ActiveRestore(
                workspaceID: PreviewData.home.id,
                trigger: .manual,
                progress: RestoreProgress(completed: 3, total: 6)
            )
        case .finished:
            model.notes = [
                PreviewData.home.id: "6件すべて配置しました",
                PreviewData.office.id: "8件を配置しました。うち2件はメイン画面に寄せています",
                PreviewData.laptop.id: "3件を配置しました。Slackのウィンドウが見つからなかったので起動しています"
            ]
        case .capture:
            model.captureSession = CaptureSession.preview()
            model.popoverRoute = .capture
        case .standard, .noPermission, .empty:
            break
        }
        return model
    }
}
#endif
