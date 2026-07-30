import AppKit
import Dispatch
import FanCtlCore
import FanCtlHelperXPC
import QuartzCore
import ServiceManagement

@main
enum FanCtlMenuBarApp {
    @MainActor
    private static var appDelegate: FanCtlAppDelegate?

    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = FanCtlAppDelegate()
        appDelegate = delegate
        app.delegate = delegate
        app.run()
    }
}

private enum FanCtlDefaults {
    static let didAskLaunchAtLoginKey = "didAskLaunchAtLogin"
    static let launchAtLoginEnabledKey = "launchAtLoginEnabled"
    static let menuBarTitleFormatKey = "menuBarTitleFormat"
    static let appLanguageCodeKey = "appLanguageCode"
    static let updateCheckAtLaunchEnabledKey = "updateCheckAtLaunchEnabled"
}

private enum AppLanguage: String, CaseIterable {
    case korean = "ko"
    case english = "en"

    static var current: AppLanguage {
        if let rawValue = UserDefaults.standard.string(forKey: FanCtlDefaults.appLanguageCodeKey),
           let language = AppLanguage(rawValue: rawValue) {
            return language
        }

        let preferredLanguage = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferredLanguage.hasPrefix("ko") ? .korean : .english
    }

    static func setCurrent(_ language: AppLanguage) {
        guard UserDefaults.standard.string(forKey: FanCtlDefaults.appLanguageCodeKey) != language.rawValue else {
            return
        }
        UserDefaults.standard.set(language.rawValue, forKey: FanCtlDefaults.appLanguageCodeKey)
        NotificationCenter.default.post(name: .fanCtlLanguageDidChange, object: nil)
    }

    var displayName: String {
        switch self {
        case .korean:
            "한국어"
        case .english:
            "English"
        }
    }
}

enum L10n {
    private static func text(_ korean: String, _ english: String) -> String {
        AppLanguage.current == .korean ? korean : english
    }

    static var quitApp: String { text("종료", "Quit") }
    static var windowMenu: String { text("윈도우", "Window") }
    static var closeWindow: String { text("닫기", "Close") }
    static var launchAtLoginPromptTitle: String { text("로그인 시 열기", "Open at Login") }
    static var launchAtLoginPromptMessage: String { text("mFanCtl을 로그인할 때 자동으로 열 수 있습니다.", "mFanCtl can open automatically when you log in.") }
    static var allow: String { text("허용", "Allow") }
    static var openSystemSettings: String { text("설정 열기", "Open Settings") }
    static var later: String { text("나중에", "Later") }
    static var fanPresetsHeader: String { text("팬 사전 설정:", "Fan Presets:") }
    static var createPreset: String { text("사전 설정 만들기", "Create Preset") }
    static var settings: String { text("설정...", "Settings...") }
    static var more: String { text("더보기", "More") }
    static var checkForUpdates: String { text("업데이트 확인...", "Check for Updates...") }
    static var openGitHub: String { text("GitHub 바로가기", "Open GitHub") }
    static var general: String { text("일반", "General") }
    static var presets: String { text("사전 설정", "Presets") }
    static var name: String { text("이름", "Name") }
    static var add: String { text("추가", "Add") }
    static var remove: String { text("삭제", "Remove") }
    static var invalidRPMTitle: String { text("올바른 RPM을 입력하세요", "Enter a valid RPM") }
    static var ok: String { text("확인", "OK") }
    static var nameFieldLabel: String { text("이름:", "Name:") }
    static var addPresetTitle: String { text("사전 설정 추가", "Add Preset") }
    static var cancel: String { text("취소", "Cancel") }
    static var launchAtLoginSection: String { text("  자동 실행", "  Auto Launch") }
    static var launchAtLoginSetting: String { text("로그인 시 mFanCtl을 자동 실행", "Open mFanCtl at login") }
    static var checkForUpdatesAtLaunch: String { text("앱 시작 시 GitHub 릴리즈 확인", "Check GitHub Releases at launch") }
    static var languageSection: String { text("  언어", "  Language") }
    static var appLanguage: String { text("앱 언어", "App language") }
    static var menuBarDisplaySection: String { text("  메뉴바 표시", "  Menu Bar Display") }
    static var format: String { text("형식", "Format") }
    static var menuBarDisplay: String { text("메뉴바 표시", "Menu Bar Display") }
    static var automatic: String { text("자동", "Automatic") }
    static var maximumSpeed: String { text("최고 속도", "Maximum Speed") }
    static var presetBaseName: String { text("사전 설정", "Preset") }
    static var maximum: String { text("최대", "Max") }
    static var installingPermission: String { text("팬 제어 준비 중...", "Preparing fan control...") }
    static var applyingFanPreset: String {
        text(
            "팬 모드 전환 중...",
            "Switching fan mode..."
        )
    }
    static var fanPresetFailedAndRestoredAutomatic: String {
        text(
            "팬 설정을 적용하지 못해 자동 모드로 되돌렸습니다.",
            "The fan setting could not be applied, so Automatic mode was restored."
        )
    }
    static var automaticRecoveryInProgress: String {
        text(
            "팬 설정을 적용하지 못했습니다. 자동 모드 복구를 다시 시도 중입니다.",
            "The fan setting could not be applied. Retrying Automatic mode recovery."
        )
    }
    static var smcConnectionFailed: String { text("SMC 연결에 실패했습니다.", "SMC connection failed.") }
    static var noFansFound: String { text("팬을 찾을 수 없습니다.", "No fans found.") }
    static var missingPreset: String { text("사전 설정을 찾을 수 없습니다.", "Preset not found.") }
    static var helperUnavailable: String { text("팬 제어 helper가 설치되어 있지 않습니다.", "Fan control helper is not installed.") }
    static var helperRegistrationFailed: String { text("팬 제어 helper를 등록하지 못했습니다.", "Could not register the fan control helper.") }
    static var invalidHelperResponse: String { text("helper 응답이 올바르지 않습니다.", "Invalid helper response.") }
    static var incompatibleHelper: String {
        text(
            "팬 제어 helper 버전이 앱과 맞지 않습니다. 앱을 다시 실행하세요.",
            "The fan control helper version does not match the app. Restart the app."
        )
    }
    static var helperApprovalPromptTitle: String { text("백그라운드 앱 허용", "Allow Background App") }
    static var helperApprovalPromptMessage: String {
        text(
            "팬 제어를 사용하려면 시스템 설정에서 mFanCtl을 백그라운드 앱으로 허용해야 합니다.",
            "To control fans, allow mFanCtl as a background app in System Settings."
        )
    }
    static var helperRequiresApproval: String { text("백그라운드 앱에서 mFanCtl을 허용해주세요.", "Allow mFanCtl in Background Apps.") }
    static var presetDataUnreadable: String { text("저장된 사전 설정을 읽을 수 없습니다.", "Saved presets could not be read.") }
    static var manualFanModeDetected: String {
        text(
            "팬이 수동 상태입니다. 자동을 눌러 macOS 제어로 복귀하세요.",
            "Fans are in manual mode. Choose Automatic to return control to macOS."
        )
    }
    static var unknownFanModeDetected: String {
        text(
            "팬 제어 상태를 확인할 수 없습니다. 자동을 눌러 복구하세요.",
            "Fan control state could not be verified. Choose Automatic to recover."
        )
    }
    static var fanTestModeActive: String {
        text(
            "macOS 팬 제어 복귀가 완료되지 않았습니다. 자동을 다시 눌러주세요.",
            "Returning fan control to macOS is incomplete. Choose Automatic again."
        )
    }
    static var presetNoLongerApplied: String {
        text(
            "현재 팬 속도가 선택한 사전 설정과 다릅니다.",
            "Current fan speed no longer matches the selected preset."
        )
    }
    static var updateAvailableTitle: String { text("새 버전이 있습니다", "Update Available") }
    static var noUpdatesTitle: String { text("최신 버전입니다", "You're Up to Date") }
    static var updateCheckFailedTitle: String { text("업데이트 확인 실패", "Update Check Failed") }
    static var openGitHubButton: String { text("GitHub 열기", "Open GitHub") }
    static var invalidUpdateResponse: String { text("GitHub 응답이 올바르지 않습니다.", "Invalid GitHub response.") }
    static var releaseNotFound: String { text("GitHub 릴리즈 정보를 찾을 수 없습니다.", "GitHub release information could not be found.") }

    static func invalidRPMMessage(range: ClosedRange<Int>) -> String {
        text(
            "RPM은 \(range.lowerBound)~\(range.upperBound) 사이의 숫자만 사용할 수 있습니다.",
            "RPM must be a number from \(range.lowerBound) to \(range.upperBound)."
        )
    }

    static func addPresetValidationMessage(range: ClosedRange<Int>) -> String {
        text(
            "RPM은 \(range.lowerBound)~\(range.upperBound) 사이의 숫자만 가능합니다.",
            "RPM must be a number from \(range.lowerBound) to \(range.upperBound)."
        )
    }

    static func presetName(index: Int) -> String {
        text("사전 설정 \(index)", "Preset \(index)")
    }

    static func updateAvailableMessage(version: String) -> String {
        text(
            "mFanCtl \(version)을 사용할 수 있습니다.\nGitHub에서 최신 버전을 다운로드하세요.",
            "mFanCtl \(version) is available.\nDownload the latest version from GitHub."
        )
    }

    static func noUpdatesMessage(version: String) -> String {
        text(
            "현재 mFanCtl \(version)을 사용 중입니다.",
            "You're currently using mFanCtl \(version)."
        )
    }

    static func updateCheckFailedMessage(reason: String) -> String {
        text(
            "업데이트 정보를 확인할 수 없습니다.\n\(reason)",
            "Unable to check for updates.\n\(reason)"
        )
    }
}

private extension Notification.Name {
    static let fanCtlLanguageDidChange = Notification.Name("FanCtlLanguageDidChange")
}

private enum AppLinks {
    static let githubRepository = URL(string: "https://github.com/jinnyday0719/mfanctl")!
    static let githubLatestRelease = URL(string: "https://github.com/jinnyday0719/mfanctl/releases/latest")!
    static let githubLatestReleaseAPI = URL(string: "https://api.github.com/repos/jinnyday0719/mfanctl/releases/latest")!
}

private enum AppPreferences {
    static var isUpdateCheckAtLaunchEnabled: Bool {
        guard UserDefaults.standard.object(forKey: FanCtlDefaults.updateCheckAtLaunchEnabledKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: FanCtlDefaults.updateCheckAtLaunchEnabledKey)
    }

    static func setUpdateCheckAtLaunchEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: FanCtlDefaults.updateCheckAtLaunchEnabledKey)
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

private struct AppVersion: Comparable {
    let components: [Int]
    let rawValue: String

    init(_ rawValue: String) {
        let trimmedValue = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let numericPrefix = trimmedValue.split(separator: "-", maxSplits: 1).first.map(String.init) ?? trimmedValue
        components = numericPrefix
            .split(separator: ".")
            .map { Int($0) ?? 0 }
        self.rawValue = trimmedValue
    }

    static var current: AppVersion {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        return AppVersion(version)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

private enum UpdateCheckError: LocalizedError {
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            L10n.invalidUpdateResponse
        case .httpStatus(404):
            L10n.releaseNotFound
        case .httpStatus(let statusCode):
            "GitHub API returned HTTP \(statusCode)."
        }
    }
}

private enum UpdateChecker {
    static func latestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: AppLinks.githubLatestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("mFanCtl", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw UpdateCheckError.httpStatus(httpResponse.statusCode)
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}

@MainActor
private func centerWindowOnActiveScreen(_ window: NSWindow) {
    guard let screenFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
        window.center()
        return
    }

    let windowFrame = window.frame
    let verticalOffset = min(72, screenFrame.height * 0.08)
    let targetY = round(screenFrame.midY - (windowFrame.height / 2) + verticalOffset)
    let clampedY = min(max(targetY, screenFrame.minY), screenFrame.maxY - windowFrame.height)
    window.setFrameOrigin(NSPoint(
        x: round(screenFrame.midX - (windowFrame.width / 2)),
        y: clampedY
    ))
}

@MainActor
final class FanCtlAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let model = FanCtlMenuBarModel()
    private let menu = NSMenu()
    private var statusItem: NSStatusItem?
    private var presetMenuItems: [FanPreset: NSMenuItem] = [:]
    private var errorItem: NSMenuItem?
    private var settingsWindowController: FanCtlSettingsWindowController?
    private var createPresetWindowController: FanCtlCreatePresetWindowController?
    private var isShowingFanHelperApprovalPrompt = false
    private var isRestoringAutomaticBeforeTermination = false
    private var lidStateObservation: LidStateObservation?
    private var lidStateTimer: Timer?
    private var lidStatePollTask: Task<Void, Never>?
    private var lidStatePollingGeneration = 0
    private var lidSafetyMonitoringWasRequired = false
    private var wasLidClosed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        NSApplication.shared.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(languageDidChange(_:)),
            name: .fanCtlLanguageDidChange,
            object: nil
        )
        installAutomaticFallbackObservers()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.menu = menu
        menu.delegate = self

        buildMenu()
        model.didChange = { [weak self] changes in
            self?.refreshMenu(changes)
        }
        model.didChangePresetList = { [weak self] in
            self?.buildMenu()
            self?.refreshMenu()
        }
        model.didChangeLidMonitoringRequirement = { [weak self] in
            self?.updateLidStateMonitoring()
        }
        model.didRequireHelperApproval = { [weak self] in
            self?.promptForFanHelperApprovalIfNeeded()
        }
        model.prepareHelper()
        refreshMenu()
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.promptForLaunchAtLoginIfNeeded()
            if AppPreferences.isUpdateCheckAtLaunchEnabled {
                self.checkForUpdates(presentsNoUpdate: false)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isRestoringAutomaticBeforeTermination else {
            return .terminateNow
        }

        isRestoringAutomaticBeforeTermination = true
        Task { [model] in
            await model.restoreAutomaticForAppTermination()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.recheckHelperApprovalIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopLidStateMonitoring()
        model.invalidateTimers()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
    }

    func windowWillClose(_ notification: Notification) {
        returnToMenuBarModeIfNoWindowsAreVisible()
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu(title: "mFanCtl")
        appMenuItem.submenu = appMenu

        let settingsItem = makePlainShortcutItem(
            title: L10n.settings,
            action: #selector(openSettings),
            keyEquivalent: ",",
            target: self
        )
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())

        let quitItem = makePlainShortcutItem(
            title: L10n.quitApp,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q",
            target: NSApplication.shared
        )
        appMenu.addItem(quitItem)

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)

        let windowMenu = NSMenu(title: L10n.windowMenu)
        windowMenuItem.submenu = windowMenu

        let closeItem = NSMenuItem(title: L10n.closeWindow, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeItem.target = nil
        windowMenu.addItem(closeItem)

        NSApplication.shared.mainMenu = mainMenu
        NSApplication.shared.windowsMenu = windowMenu
    }

    private func promptForLaunchAtLoginIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: FanCtlDefaults.didAskLaunchAtLoginKey) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.launchAtLoginPromptTitle
        alert.informativeText = L10n.launchAtLoginPromptMessage
        let enableButton = alert.addButton(withTitle: L10n.allow)
        enableButton.keyEquivalent = "\r"
        alert.addButton(withTitle: L10n.later)

        let response = runFrontmost(alert)
        UserDefaults.standard.set(true, forKey: FanCtlDefaults.didAskLaunchAtLoginKey)

        if response == .alertFirstButtonReturn {
            UserDefaults.standard.set(enableLaunchAtLogin(), forKey: FanCtlDefaults.launchAtLoginEnabledKey)
        } else {
            disableLaunchAtLogin()
            UserDefaults.standard.set(false, forKey: FanCtlDefaults.launchAtLoginEnabledKey)
        }
    }

    private func promptForFanHelperApprovalIfNeeded() {
        guard !isShowingFanHelperApprovalPrompt else {
            return
        }

        isShowingFanHelperApprovalPrompt = true

        let alert = NSAlert()
        alert.messageText = L10n.helperApprovalPromptTitle
        alert.informativeText = L10n.helperApprovalPromptMessage
        let openButton = alert.addButton(withTitle: L10n.openSystemSettings)
        openButton.keyEquivalent = "\r"
        alert.addButton(withTitle: L10n.later)

        if runFrontmost(alert) == .alertFirstButtonReturn {
            SMAppService.openSystemSettingsLoginItems()
        }

        isShowingFanHelperApprovalPrompt = false
    }

    private func enableLaunchAtLogin() -> Bool {
        let service = SMAppService.mainApp
        guard service.status != .enabled else {
            return true
        }

        do {
            try service.register()
            return true
        } catch {
            NSLog("mFanCtl failed to register launch at login: \(error.localizedDescription)")
            return false
        }
    }

    private func disableLaunchAtLogin() {
        let service = SMAppService.mainApp
        guard service.status != .notRegistered else {
            return
        }

        do {
            try service.unregister()
        } catch {
            NSLog("mFanCtl failed to unregister launch at login: \(error.localizedDescription)")
        }
    }

    private func runFrontmost(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.layout()
        alert.window.level = .floating
        alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        centerWindowOnActiveScreen(alert.window)
        alert.window.orderFrontRegardless()
        return alert.runModal()
    }

    private func installAutomaticFallbackObservers() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(
            self,
            selector: #selector(systemShouldRestoreAutomaticFanMode(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(systemShouldRestoreAutomaticFanMode(_:)),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(systemShouldRestoreAutomaticFanMode(_:)),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        workspaceCenter.addObserver(
            self,
            selector: #selector(systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        let distributedCenter = DistributedNotificationCenter.default()
        distributedCenter.addObserver(
            self,
            selector: #selector(systemShouldRestoreAutomaticFanMode(_:)),
            name: Notification.Name("com.apple.screenIsLocked"),
            object: nil
        )
        distributedCenter.addObserver(
            self,
            selector: #selector(systemShouldRestoreAutomaticFanMode(_:)),
            name: Notification.Name("com.apple.screensaver.didstart"),
            object: nil
        )

        updateLidStateMonitoring()
    }

    @objc private func systemShouldRestoreAutomaticFanMode(_ notification: Notification) {
        model.applyAutomaticForSleepOrLidClose()
    }

    @objc private func systemDidWake(_ notification: Notification) {
        restartLidStateObservation()
        model.refreshControlState()
    }

    @objc private func lidStateTimerDidFire() {
        pollLidState()
    }

    private func updateLidStateMonitoring() {
        let needsSafetyMonitoring = model.needsLidStateMonitoring
        defer {
            lidSafetyMonitoringWasRequired = needsSafetyMonitoring
        }

        guard LidStateReader.isSupported else {
            stopLidStateMonitoring()
            return
        }

        if lidStateObservation == nil {
            lidStateObservation = LidStateReader.observeChanges { [weak self] event in
                DispatchQueue.main.async { [weak self] in
                    switch event {
                    case .stateChanged(let isLidClosed):
                        self?.handleLidState(isLidClosed)
                    case .serviceTerminated:
                        self?.restartLidStateObservation()
                    }
                }
            }
        }

        if lidStateObservation != nil {
            lidStateTimer?.invalidate()
            lidStateTimer = nil
            if !needsSafetyMonitoring {
                stopLidStateFallbackPolling()
            } else if !lidSafetyMonitoringWasRequired {
                stopLidStateFallbackPolling()
                pollLidState()
            }
            return
        }

        guard needsSafetyMonitoring, lidStateTimer == nil else {
            if !needsSafetyMonitoring {
                stopLidStateFallbackPolling()
            }
            return
        }

        pollLidState()
        let timer = Timer(
            timeInterval: 2,
            target: self,
            selector: #selector(lidStateTimerDidFire),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 0.5
        lidStateTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopLidStateMonitoring() {
        lidStateObservation?.invalidate()
        lidStateObservation = nil
        stopLidStateFallbackPolling()
        lidSafetyMonitoringWasRequired = false
        wasLidClosed = false
    }

    private func stopLidStateFallbackPolling() {
        lidStatePollingGeneration &+= 1
        lidStateTimer?.invalidate()
        lidStateTimer = nil
        lidStatePollTask?.cancel()
        lidStatePollTask = nil
    }

    private func restartLidStateObservation() {
        lidStateObservation?.invalidate()
        lidStateObservation = nil
        lidSafetyMonitoringWasRequired = false
        updateLidStateMonitoring()
    }

    private func pollLidState() {
        guard lidStatePollTask == nil, model.needsLidStateMonitoring else {
            return
        }

        let generation = lidStatePollingGeneration
        lidStatePollTask = Task { [weak self] in
            let isLidClosed = await Task.detached {
                LidStateReader.isLidClosed()
            }.value
            guard !Task.isCancelled,
                  let self,
                  generation == lidStatePollingGeneration,
                  model.needsLidStateMonitoring else {
                return
            }
            if let isLidClosed {
                handleLidState(isLidClosed)
            }
            if generation == lidStatePollingGeneration {
                lidStatePollTask = nil
            }
        }
    }

    private func handleLidState(_ isLidClosed: Bool) {
        if isLidClosed {
            if model.needsLidStateMonitoring {
                if wasLidClosed {
                    model.ensureAutomaticWhileLidClosed()
                } else {
                    model.applyAutomaticForSleepOrLidClose()
                }
            } else {
                // A low-cost notification remains active even in Automatic mode.
                // Reconcile once on close so a manual state applied externally is
                // detected without restoring or probing the helper unnecessarily.
                model.refreshControlState()
            }
        }
        wasLidClosed = isLidClosed
    }

    private func buildMenu() {
        menu.removeAllItems()
        presetMenuItems.removeAll()
        menu.addItem(makeTitleItem())
        menu.addItem(.separator())

        let presetHeader = NSMenuItem(title: L10n.fanPresetsHeader, action: nil, keyEquivalent: "")
        presetHeader.isEnabled = false
        menu.addItem(presetHeader)

        for preset in model.presetEntries {
            let item = NSMenuItem(title: preset.name, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset.menuIdentifier
            menu.addItem(item)
            presetMenuItems[preset.preset] = item
        }

        let errorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        errorItem.isEnabled = false
        errorItem.isHidden = true
        menu.addItem(errorItem)
        self.errorItem = errorItem

        menu.addItem(.separator())

        let createPresetItem = NSMenuItem(title: L10n.createPreset, action: #selector(openCreatePreset), keyEquivalent: "")
        createPresetItem.target = self
        menu.addItem(createPresetItem)

        menu.addItem(.separator())

        let settingsItem = makePlainShortcutItem(
            title: L10n.settings,
            action: #selector(openSettings),
            keyEquivalent: ",",
            target: self
        )
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let moreItem = NSMenuItem(title: L10n.more, action: nil, keyEquivalent: "")
        let moreMenu = NSMenu(title: L10n.more)
        let checkForUpdatesItem = NSMenuItem(title: L10n.checkForUpdates, action: #selector(checkForUpdatesFromMenu), keyEquivalent: "")
        checkForUpdatesItem.target = self
        moreMenu.addItem(checkForUpdatesItem)
        moreMenu.addItem(.separator())
        let githubItem = NSMenuItem(title: L10n.openGitHub, action: #selector(openGitHub), keyEquivalent: "")
        githubItem.target = self
        moreMenu.addItem(githubItem)
        moreItem.submenu = moreMenu
        menu.addItem(moreItem)

        menu.addItem(.separator())

        let quitItem = makePlainShortcutItem(
            title: L10n.quitApp,
            action: #selector(quit),
            keyEquivalent: "q",
            target: self
        )
        menu.addItem(quitItem)
    }

    private func makePlainShortcutItem(
        title: String,
        action: Selector,
        keyEquivalent: String,
        target: AnyObject
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = target
        item.keyEquivalentModifierMask = [.command]
        item.image = nil
        item.onStateImage = nil
        item.offStateImage = nil
        item.mixedStateImage = nil
        item.indentationLevel = 0
        return item
    }

    @objc private func languageDidChange(_ notification: Notification) {
        installMainMenu()
        buildMenu()
        refreshMenu()
        settingsWindowController?.refreshLocalizedText()
        createPresetWindowController?.refreshLocalizedText()
    }

    private func makeTitleItem() -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 26))
        let label = NSTextField(labelWithString: "mFanCtl")
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.frame = NSRect(x: 18, y: 4, width: 144, height: 18)
        container.addSubview(label)
        item.view = container

        return item
    }

    private func refreshMenu(_ changes: FanCtlMenuBarModel.Change = .all) {
        if changes.contains(.statusTitle) {
            updateStatusTitle()
        }

        if changes.contains(.presets) {
            for preset in model.presetEntries {
                let item = presetMenuItems[preset.preset]
                item?.title = preset.name
                item?.state = model.selectedPreset == preset.preset ? .on : .off
                item?.isEnabled = !model.presetsDisabled
            }
        }

        if changes.contains(.error) {
            if let errorMessage = model.errorMessage {
                errorItem?.title = errorMessage
                errorItem?.attributedTitle = NSAttributedString(
                    string: errorMessage,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11),
                        .foregroundColor: NSColor.secondaryLabelColor
                    ]
                )
                errorItem?.isHidden = false
            } else {
                errorItem?.title = ""
                errorItem?.attributedTitle = NSAttributedString(string: "")
                errorItem?.isHidden = true
            }
        }
    }

    private func updateStatusTitle() {
        guard let button = statusItem?.button else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ]
        button.attributedTitle = NSAttributedString(string: model.menuBarTitle, attributes: attributes)
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let rawIdentifier = sender.representedObject as? String,
              let preset = FanPreset(menuIdentifier: rawIdentifier)
        else {
            return
        }

        if model.requiresHelperApproval {
            SMAppService.openSystemSettingsLoginItems()
            return
        }

        model.applyPresetSelection(preset)
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = FanCtlSettingsWindowController(model: model)
            settingsWindowController?.window?.delegate = self
        }
        settingsWindowController?.showGeneralTab()
        presentAppWindow(settingsWindowController)
    }

    @objc private func openCreatePreset() {
        if let settingsWindowController,
           settingsWindowController.window?.isVisible == true {
            settingsWindowController.showPresetList()
            presentAppWindow(settingsWindowController)
            return
        }

        if createPresetWindowController == nil {
            createPresetWindowController = FanCtlCreatePresetWindowController(model: model)
            createPresetWindowController?.window?.delegate = self
        }
        presentAppWindow(createPresetWindowController)
    }

    private func presentAppWindow(_ windowController: NSWindowController?) {
        NSApplication.shared.setActivationPolicy(.regular)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func returnToMenuBarModeIfNoWindowsAreVisible() {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            let hasVisibleWindow = [
                self.settingsWindowController?.window,
                self.createPresetWindowController?.window
            ].contains { $0?.isVisible == true }

            guard !hasVisibleWindow else {
                return
            }

            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    @objc private func openGitHub() {
        NSWorkspace.shared.open(AppLinks.githubRepository)
    }

    @objc private func checkForUpdatesFromMenu() {
        checkForUpdates(presentsNoUpdate: true)
    }

    private func checkForUpdates(presentsNoUpdate: Bool) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let release = try await UpdateChecker.latestRelease()
                let latestVersion = AppVersion(release.tagName)
                let currentVersion = AppVersion.current

                if latestVersion > currentVersion {
                    self.presentUpdateAvailable(version: latestVersion.rawValue, releaseURL: release.htmlURL ?? AppLinks.githubLatestRelease)
                } else if presentsNoUpdate {
                    self.presentNoUpdatesAvailable(version: currentVersion.rawValue)
                }
            } catch {
                if presentsNoUpdate {
                    self.presentUpdateCheckFailed(reason: error.localizedDescription)
                }
            }
        }
    }

    private func presentUpdateAvailable(version: String, releaseURL: URL) {
        let alert = NSAlert()
        alert.messageText = L10n.updateAvailableTitle
        alert.informativeText = L10n.updateAvailableMessage(version: version)
        let openButton = alert.addButton(withTitle: L10n.openGitHubButton)
        openButton.keyEquivalent = "\r"
        alert.addButton(withTitle: L10n.later)

        if runFrontmost(alert) == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    private func presentNoUpdatesAvailable(version: String) {
        let alert = NSAlert()
        alert.messageText = L10n.noUpdatesTitle
        alert.informativeText = L10n.noUpdatesMessage(version: version)
        alert.addButton(withTitle: L10n.ok)
        _ = runFrontmost(alert)
    }

    private func presentUpdateCheckFailed(reason: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.updateCheckFailedTitle
        alert.informativeText = L10n.updateCheckFailedMessage(reason: reason)
        alert.addButton(withTitle: L10n.ok)
        _ = runFrontmost(alert)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private enum FanCtlWindowLayout {
    static let settingsContentSize = NSSize(width: 450, height: 228)
    static let settingsMinimumSize = NSSize(width: 420, height: 212)
    static let menuBarDisplaySettingsContentSize = NSSize(width: settingsContentSize.width, height: 98)
    static let menuBarDisplaySettingsMinimumSize = NSSize(width: settingsMinimumSize.width, height: 98)
    static let presetContentSize = NSSize(width: settingsContentSize.width, height: 220)
    static let presetMinimumSize = NSSize(width: settingsMinimumSize.width, height: 200)
}

@MainActor
final class FanCtlSettingsWindowController: NSWindowController {
    private enum DisplayMode {
        case settings
        case presets
    }

    private enum SettingsTab {
        case general
        case menuBarDisplay
    }

    private let settingsViewController: FanCtlSettingsViewController
    private let presetListViewController: FanCtlPresetListViewController
    private let settingsToolbar = NSToolbar(identifier: "FanCtlSettingsToolbar")
    private let settingsFrameSize = FanCtlSettingsWindowController.measuredSettingsFrameSize(for: FanCtlWindowLayout.settingsContentSize)
    private let menuBarDisplaySettingsFrameSize = FanCtlSettingsWindowController.measuredSettingsFrameSize(for: FanCtlWindowLayout.menuBarDisplaySettingsContentSize)
    private let presetFrameSize = FanCtlSettingsWindowController.measuredFrameSize(for: FanCtlWindowLayout.presetContentSize)
    private var displayMode: DisplayMode = .settings
    private var transitionTask: Task<Void, Never>?

    init(model: FanCtlMenuBarModel) {
        settingsViewController = FanCtlSettingsViewController(model: model)
        presetListViewController = FanCtlPresetListViewController(model: model)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: FanCtlWindowLayout.settingsContentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = settingsViewController
        window.title = L10n.general
        window.backgroundColor = .windowBackgroundColor
        window.minSize = FanCtlWindowLayout.settingsMinimumSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.toolbarStyle = .preference
        window.titlebarSeparatorStyle = .line

        settingsToolbar.delegate = settingsViewController
        settingsToolbar.displayMode = .iconAndLabel
        settingsToolbar.allowsUserCustomization = false
        window.toolbar = settingsToolbar
        window.center()

        super.init(window: window)

        settingsViewController.didSelectGeneralTab = { [weak self] in
            self?.showSettingsTab(.general)
        }
        settingsViewController.didSelectMenuBarDisplayTab = { [weak self] in
            self?.showSettingsTab(.menuBarDisplay)
        }
    }

    func showGeneralTab() {
        transition(to: .settings)
    }

    func showPresetList() {
        transition(to: .presets)
    }

    func refreshLocalizedText() {
        settingsViewController.refreshLocalizedText(toolbar: settingsToolbar)
        presetListViewController.refreshLocalizedText()

        switch displayMode {
        case .settings:
            window?.title = settingsViewController.currentTitle
        case .presets:
            window?.title = L10n.presets
        }
    }

    private func transition(to mode: DisplayMode) {
        guard let window else {
            return
        }

        transitionTask?.cancel()
        let startFrame = window.frame
        let targetFrame = targetFrame(for: frameSize(for: mode), anchoredTo: startFrame)
        guard window.isVisible, displayMode != mode else {
            apply(mode, fadesIn: false)
            window.setFrame(targetFrame, display: true)
            return
        }

        transitionTask = Task { @MainActor [weak self] in
            self?.apply(mode, fadesIn: false)
            window.setFrame(startFrame, display: true)
            window.minSize = self?.minimumSize(for: mode) ?? window.minSize
            await self?.animateFrame(to: targetFrame, duration: 0.28)
        }
    }

    private func showSettingsTab(_ tab: SettingsTab) {
        guard let window else {
            return
        }

        transitionTask?.cancel()
        let startFrame = window.frame
        let targetFrame = targetFrame(for: settingsFrameSize(for: tab), anchoredTo: startFrame)
        let applyTab = { [weak self] in
            guard let self else {
                return
            }
            switch tab {
            case .general:
                self.settingsViewController.showGeneralTab()
                window.toolbar?.selectedItemIdentifier = FanCtlSettingsViewController.generalToolbarIdentifier
            case .menuBarDisplay:
                self.settingsViewController.showMenuBarDisplayTab()
                window.toolbar?.selectedItemIdentifier = FanCtlSettingsViewController.menuBarDisplayToolbarIdentifier
            }
            window.title = self.settingsViewController.currentTitle
            window.minSize = self.settingsMinimumSize(for: tab)
        }

        guard window.isVisible, displayMode == .settings else {
            applyTab()
            window.setFrame(targetFrame, display: true)
            return
        }

        guard abs(window.frame.height - targetFrame.height) > 0.5 else {
            applyTab()
            return
        }

        transitionTask = Task { @MainActor [weak self] in
            applyTab()
            window.setFrame(startFrame, display: true)
            await self?.animateFrame(to: targetFrame, duration: 0.22)
        }
    }

    private func apply(_ mode: DisplayMode, fadesIn: Bool) {
        guard let window else {
            return
        }

        switch mode {
        case .settings:
            settingsViewController.showGeneralTab()
            window.minSize = FanCtlWindowLayout.settingsMinimumSize
            window.toolbarStyle = .preference
            window.titlebarSeparatorStyle = .line
            window.toolbar = settingsToolbar
            window.contentViewController = settingsViewController
            window.toolbar?.selectedItemIdentifier = FanCtlSettingsViewController.generalToolbarIdentifier
            window.title = L10n.general
        case .presets:
            window.minSize = FanCtlWindowLayout.presetMinimumSize
            window.toolbar = nil
            window.titlebarSeparatorStyle = .line
            window.contentViewController = presetListViewController
            window.title = L10n.presets
        }

        displayMode = mode
        window.contentView?.alphaValue = fadesIn ? 0 : 1
        guard fadesIn else {
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.contentView?.animator().alphaValue = 1
        }
    }

    private func frameSize(for mode: DisplayMode) -> NSSize {
        switch mode {
        case .settings:
            settingsFrameSize
        case .presets:
            presetFrameSize
        }
    }

    private func settingsFrameSize(for tab: SettingsTab) -> NSSize {
        switch tab {
        case .general:
            settingsFrameSize
        case .menuBarDisplay:
            menuBarDisplaySettingsFrameSize
        }
    }

    private func minimumSize(for mode: DisplayMode) -> NSSize {
        switch mode {
        case .settings:
            FanCtlWindowLayout.settingsMinimumSize
        case .presets:
            FanCtlWindowLayout.presetMinimumSize
        }
    }

    private func settingsMinimumSize(for tab: SettingsTab) -> NSSize {
        switch tab {
        case .general:
            FanCtlWindowLayout.settingsMinimumSize
        case .menuBarDisplay:
            FanCtlWindowLayout.menuBarDisplaySettingsMinimumSize
        }
    }

    private func targetFrame(for frameSize: NSSize, anchoredTo currentFrame: NSRect) -> NSRect {
        return NSRect(
            x: currentFrame.minX,
            y: currentFrame.maxY - frameSize.height,
            width: frameSize.width,
            height: frameSize.height
        )
    }

    private func animateFrame(to targetFrame: NSRect, duration: TimeInterval) async {
        guard let window else {
            return
        }

        let startFrame = window.frame
        let frameInterval: UInt64 = 16_000_000
        let steps = max(1, Int(duration / 0.016))

        for step in 1...steps {
            guard !Task.isCancelled else {
                return
            }

            let progress = Double(step) / Double(steps)
            let easedProgress = progress * progress * (3 - 2 * progress)
            let nextFrame = interpolateFrame(from: startFrame, to: targetFrame, progress: easedProgress)
            window.setFrame(nextFrame, display: true)
            try? await Task.sleep(nanoseconds: frameInterval)
        }

        window.setFrame(targetFrame, display: true)
    }

    private func interpolateFrame(from startFrame: NSRect, to targetFrame: NSRect, progress: Double) -> NSRect {
        let value = { (start: CGFloat, end: CGFloat) -> CGFloat in
            start + ((end - start) * CGFloat(progress))
        }
        return NSRect(
            x: value(startFrame.minX, targetFrame.minX),
            y: value(startFrame.minY, targetFrame.minY),
            width: value(startFrame.width, targetFrame.width),
            height: value(startFrame.height, targetFrame.height)
        )
    }

    private static func measuredFrameSize(for contentSize: NSSize) -> NSSize {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: true
        )
        window.titlebarSeparatorStyle = .line
        return window.frame.size
    }

    private static func measuredSettingsFrameSize(for contentSize: NSSize) -> NSSize {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: true
        )
        window.toolbarStyle = .preference
        window.titlebarSeparatorStyle = .line

        let toolbar = NSToolbar(identifier: "FanCtlSettingsToolbarSizing")
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        return window.frame.size
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class FanCtlCreatePresetWindowController: NSWindowController {
    private let presetListViewController: FanCtlPresetListViewController

    init(model: FanCtlMenuBarModel) {
        presetListViewController = FanCtlPresetListViewController(model: model)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: FanCtlWindowLayout.presetContentSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = presetListViewController
        window.title = L10n.presets
        window.backgroundColor = .windowBackgroundColor
        window.minSize = FanCtlWindowLayout.presetMinimumSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.center()

        super.init(window: window)
    }

    func refreshLocalizedText() {
        window?.title = L10n.presets
        presetListViewController.refreshLocalizedText()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
private final class FanCtlPresetListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    private enum Column {
        static let name = NSUserInterfaceItemIdentifier("name")
        static let rpm = NSUserInterfaceItemIdentifier("rpm")
    }

    private let tableHorizontalInset: CGFloat = 22
    private let rpmColumnPreferredWidth: CGFloat = 128
    private let model: FanCtlMenuBarModel
    private let tableView = EditablePresetTableView()
    private let scrollView = VerticalOnlyPresetScrollView()
    private let footerView = PresetFooterView()
    private let addButton = NSButton()
    private let removeButton = NSButton()
    private var isShowingInvalidRPMAlert = false
    private var pendingTextFocus: (id: UUID, columnIdentifier: NSUserInterfaceItemIdentifier)?
    private var suppressNextEndEditingCommitID: UUID?
    private weak var addPresetNameField: NSTextField?
    private weak var addPresetRPMField: NSTextField?
    private weak var addPresetConfirmButton: NSButton?
    private weak var addPresetValidationLabel: NSTextField?
    private var addPresetRPMInputIsInvalid = false

    init(model: FanCtlMenuBarModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = PresetListContentView(frame: NSRect(origin: .zero, size: FanCtlWindowLayout.presetContentSize))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupFooter()
        setupTable()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        tableView.reloadData()
        fitTableToVisibleWidth()
        updateRemoveControl()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        fitTableToVisibleWidth()
    }

    func refreshLocalizedText() {
        if let nameColumn = tableView.tableColumn(withIdentifier: Column.name) {
            nameColumn.title = L10n.name
            nameColumn.headerCell = PaddedPresetHeaderCell(textCell: L10n.name)
        }
        addButton.setAccessibilityLabel(L10n.add)
        removeButton.setAccessibilityLabel(L10n.remove)
        tableView.reloadData()
        fitTableToVisibleWidth()
    }

    private func setupTable() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(editClickedCell)
        tableView.headerView = NSTableHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 26))
        tableView.rowHeight = 24
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.style = .plain
        tableView.intercellSpacing = NSSize(width: 0, height: tableView.intercellSpacing.height)
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none

        let nameColumn = NSTableColumn(identifier: Column.name)
        nameColumn.title = L10n.name
        nameColumn.width = 200
        nameColumn.minWidth = 150
        nameColumn.resizingMask = .autoresizingMask
        nameColumn.headerCell = PaddedPresetHeaderCell(textCell: nameColumn.title)

        let rpmColumn = NSTableColumn(identifier: Column.rpm)
        rpmColumn.title = "RPM"
        rpmColumn.width = rpmColumnPreferredWidth
        rpmColumn.minWidth = 110
        rpmColumn.resizingMask = []
        rpmColumn.headerCell = PaddedPresetHeaderCell(textCell: rpmColumn.title)

        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(rpmColumn)

        scrollView.contentView = LockedHorizontalClipView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.focusRingType = .none
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: tableHorizontalInset),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -tableHorizontalInset),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: footerView.topAnchor)
        ])
    }

    private func setupFooter() {
        footerView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(footerView)

        configureFooterButton(addButton, title: "+", accessibilityDescription: L10n.add, action: #selector(addPreset))
        configureFooterButton(removeButton, title: "-", accessibilityDescription: L10n.remove, action: #selector(removeSelectedPreset))
        footerView.addSubview(addButton)
        footerView.addSubview(removeButton)

        NSLayoutConstraint.activate([
            footerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: tableHorizontalInset),
            footerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -tableHorizontalInset),
            footerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            footerView.heightAnchor.constraint(equalToConstant: 30),

            addButton.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 10),
            addButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 26),
            addButton.heightAnchor.constraint(equalToConstant: 22),

            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 2),
            removeButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 26),
            removeButton.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    private func configureFooterButton(_ button: NSButton, title: String, accessibilityDescription: String, action: Selector) {
        button.title = title
        button.font = .systemFont(ofSize: 16, weight: .regular)
        button.setAccessibilityLabel(accessibilityDescription)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.controlSize = .small
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func fitTableToVisibleWidth() {
        let visibleWidth = floor(scrollView.contentSize.width)
        guard visibleWidth > 0,
              let nameColumn = tableView.tableColumn(withIdentifier: Column.name),
              let rpmColumn = tableView.tableColumn(withIdentifier: Column.rpm)
        else {
            return
        }

        if abs(tableView.frame.width - visibleWidth) > 0.5 {
            var frame = tableView.frame
            frame.size.width = visibleWidth
            tableView.frame = frame
        }
        if let headerView = tableView.headerView, abs(headerView.frame.width - visibleWidth) > 0.5 {
            var headerFrame = headerView.frame
            headerFrame.size.width = visibleWidth
            headerView.frame = headerFrame
        }

        rpmColumn.width = min(rpmColumnPreferredWidth, max(rpmColumn.minWidth, floor(visibleWidth * 0.38)))
        nameColumn.width = max(nameColumn.minWidth, visibleWidth - rpmColumn.width)
        tableView.sizeLastColumnToFit()
        tableView.tile()

        let clipView = scrollView.contentView
        if clipView.bounds.origin.x != 0 {
            clipView.scroll(to: NSPoint(x: 0, y: clipView.bounds.origin.y))
            scrollView.reflectScrolledClipView(clipView)
        }
    }

    private func updateRemoveControl() {
        let row = tableView.selectedRow
        removeButton.isEnabled = row >= 0
            && row < model.presetEntries.count
            && model.presetEntries[row].isDeletable
    }

    private func makePresetCellView(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cellView = NSTableCellView()
        cellView.identifier = identifier

        let textField = PresetTextField()
        textField.identifier = identifier
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 12, weight: .medium)
        textField.lineBreakMode = .byTruncatingTail
        textField.usesSingleLineMode = true
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        textField.delegate = self
        textField.translatesAutoresizingMaskIntoConstraints = false

        cellView.textField = textField
        cellView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
            textField.heightAnchor.constraint(lessThanOrEqualTo: cellView.heightAnchor, constant: -2)
        ])

        return cellView
    }

    @discardableResult
    private func commitPresetTextFieldIfValid(_ textField: NSTextField, reloadsTable: Bool = true) -> Bool {
        guard let presetTextField = textField as? PresetTextField,
              let id = presetTextField.presetID,
              let preset = model.userPresets.first(where: { $0.id == id })
        else {
            return true
        }

        switch presetTextField.columnIdentifier {
        case Column.name:
            model.updateUserPreset(id: id, name: presetTextField.stringValue, rpm: preset.rpm)
        case Column.rpm:
            guard let rpm = validatedRPM(from: presetTextField.stringValue) else {
                presetTextField.stringValue = "\(preset.rpm)"
                tableView.reloadData()
                showInvalidRPMAlert()
                updateRemoveControl()
                return false
            }
            model.updateUserPreset(id: id, name: preset.name, rpm: rpm)
        default:
            return true
        }

        if reloadsTable {
            tableView.reloadData()
            fitTableToVisibleWidth()
        }
        updateRemoveControl()
        return true
    }

    private func validatedRPM(from value: String) -> Int? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty,
              trimmedValue.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
              let rpm = Int(trimmedValue),
              model.validUserRPMRange.contains(rpm)
        else {
            return nil
        }
        return rpm
    }

    private func showInvalidRPMAlert() {
        guard !isShowingInvalidRPMAlert else {
            return
        }

        isShowingInvalidRPMAlert = true
        let validRange = model.validUserRPMRange
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.invalidRPMTitle
        alert.informativeText = L10n.invalidRPMMessage(range: validRange)
        alert.addButton(withTitle: L10n.ok)

        guard let window = view.window else {
            alert.runModal()
            isShowingInvalidRPMAlert = false
            return
        }

        alert.beginSheetModal(for: window) { [weak self] _ in
            self?.isShowingInvalidRPMAlert = false
        }
    }

    @objc private func addPreset() {
        showAddPresetSheet()
    }

    private func showAddPresetSheet() {
        let nameField = NSTextField(string: model.defaultNewUserPresetName)
        nameField.delegate = self

        let rpmField = NSTextField(string: "\(model.defaultNewUserPresetRPM)")
        rpmField.delegate = self

        addPresetNameField = nameField
        addPresetRPMField = rpmField
        addPresetRPMInputIsInvalid = false

        let nameLabel = NSTextField(labelWithString: L10n.nameFieldLabel)
        let rpmLabel = NSTextField(labelWithString: "RPM:")
        let validationLabel = NSTextField(labelWithString: addPresetValidationMessage)
        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: 11)
        validationLabel.isHidden = true
        nameLabel.alignment = .right
        rpmLabel.alignment = .right
        addPresetValidationLabel = validationLabel

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 310, height: 82))
        nameLabel.frame = NSRect(x: 0, y: 58, width: 56, height: 20)
        nameField.frame = NSRect(x: 66, y: 54, width: 230, height: 24)
        rpmLabel.frame = NSRect(x: 0, y: 28, width: 56, height: 20)
        rpmField.frame = NSRect(x: 66, y: 24, width: 230, height: 24)
        validationLabel.frame = NSRect(x: 66, y: 0, width: 230, height: 18)
        accessoryView.addSubview(nameLabel)
        accessoryView.addSubview(nameField)
        accessoryView.addSubview(rpmLabel)
        accessoryView.addSubview(rpmField)
        accessoryView.addSubview(validationLabel)

        let alert = NSAlert()
        alert.messageText = L10n.addPresetTitle
        alert.informativeText = ""
        alert.accessoryView = accessoryView
        let addButton = alert.addButton(withTitle: L10n.add)
        addButton.keyEquivalent = "\r"
        addPresetConfirmButton = addButton
        alert.addButton(withTitle: L10n.cancel)
        updateAddPresetValidationState(showsError: false)

        DispatchQueue.main.async {
            alert.window.initialFirstResponder = nameField
            alert.window.makeFirstResponder(nameField)
            nameField.selectText(nil)
        }

        guard let window = view.window else {
            return
        }

        alert.beginSheetModal(for: window) { [weak self, weak nameField, weak rpmField] response in
            guard let self,
                  response == .alertFirstButtonReturn,
                  let nameField,
                  let rpmField
            else {
                self?.clearAddPresetSheetReferences()
                return
            }

            guard let rpm = self.validatedRPM(from: rpmField.stringValue) else {
                self.clearAddPresetSheetReferences()
                return
            }

            let id = self.model.addUserPreset(name: nameField.stringValue, rpm: rpm)
            if let row = self.model.presetEntries.firstIndex(where: { $0.preset == .custom(id) }) {
                self.tableView.insertRows(at: IndexSet(integer: row), withAnimation: [])
                self.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                self.tableView.scrollRowToVisible(row)
            } else {
                self.tableView.reloadData()
            }
            self.updateRemoveControl()
            self.clearAddPresetSheetReferences()
        }
    }

    private var addPresetValidationMessage: String {
        let range = model.validUserRPMRange
        return L10n.addPresetValidationMessage(range: range)
    }

    private func updateAddPresetValidationState(showsError: Bool) {
        addPresetValidationLabel?.stringValue = addPresetValidationMessage
        addPresetValidationLabel?.isHidden = !showsError
        addPresetRPMField?.textColor = showsError ? .systemRed : .labelColor
        addPresetConfirmButton?.isEnabled = !showsError
        if !showsError {
            addPresetRPMInputIsInvalid = false
        }
    }

    private func rejectAddPresetRPM() {
        NSSound.beep()
        updateAddPresetValidationState(showsError: true)
        addPresetRPMInputIsInvalid = true
        addPresetRPMField?.selectText(nil)
    }

    private func commitAddPresetSheetFromKeyboard() {
        guard let rpmField = addPresetRPMField,
              validatedRPM(from: rpmField.stringValue) != nil
        else {
            rejectAddPresetRPM()
            return
        }

        updateAddPresetValidationState(showsError: false)
        addPresetConfirmButton?.performClick(nil)
    }

    private func clearAddPresetSheetReferences() {
        addPresetNameField = nil
        addPresetRPMField = nil
        addPresetConfirmButton = nil
        addPresetValidationLabel = nil
        addPresetRPMInputIsInvalid = false
    }

    @objc private func removeSelectedPreset() {
        let row = tableView.selectedRow
        guard row >= 0,
              row < model.presetEntries.count,
              case .custom(let id) = model.presetEntries[row].preset
        else {
            return
        }

        model.deleteUserPreset(id: id)
        tableView.reloadData()
        updateRemoveControl()
    }

    @objc private func editClickedCell() {
        let row = tableView.clickedRow
        let column = tableView.clickedColumn
        guard row >= 0,
              row < model.presetEntries.count,
              model.presetEntries[row].isEditable,
              column >= 0,
              let cellView = tableView.view(atColumn: column, row: row, makeIfNecessary: false) as? NSTableCellView,
              let textField = cellView.textField
        else {
            return
        }

        view.window?.makeFirstResponder(textField)
        textField.selectText(nil)
    }

    private func focusCell(row: Int, columnIdentifier: NSUserInterfaceItemIdentifier) {
        guard let column = tableView.tableColumn(withIdentifier: columnIdentifier) else {
            return
        }

        let columnIndex = tableView.column(withIdentifier: column.identifier)
        guard columnIndex >= 0 else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self,
                  row >= 0,
                  row < self.tableView.numberOfRows
            else {
                return
            }

            self.tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            NSApplication.shared.activate(ignoringOtherApps: true)
            self.view.window?.makeKeyAndOrderFront(nil)
            self.tableView.layoutSubtreeIfNeeded()
            guard let cellView = self.tableView.view(atColumn: columnIndex, row: row, makeIfNecessary: true) as? NSTableCellView,
                  let textField = cellView.textField
            else {
                return
            }

            _ = self.view.window?.makeFirstResponder(nil)
            self.view.window?.makeFirstResponder(self.tableView)
            self.tableView.editColumn(columnIndex, row: row, with: NSApplication.shared.currentEvent, select: true)
            _ = self.view.window?.makeFirstResponder(textField)
            textField.selectText(nil)
        }
    }

    private func focusPreset(id: UUID, columnIdentifier: NSUserInterfaceItemIdentifier, reloadsTable: Bool) {
        pendingTextFocus = (id, columnIdentifier)
        if reloadsTable {
            tableView.reloadData()
        }

        if let row = model.presetEntries.firstIndex(where: { $0.preset == .custom(id) }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            focusCell(row: row, columnIdentifier: columnIdentifier)
        }
    }

    private func focusRPMForTextField(_ textField: NSTextField) {
        guard let presetTextField = textField as? PresetTextField,
              presetTextField.columnIdentifier == Column.name,
              let id = presetTextField.presetID
        else {
            return
        }

        focusPreset(id: id, columnIdentifier: Column.rpm, reloadsTable: false)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        model.presetEntries.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0,
              row < model.presetEntries.count,
              let tableColumn
        else {
            return nil
        }

        let cellIdentifier = NSUserInterfaceItemIdentifier("preset-\(tableColumn.identifier.rawValue)")
        let cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
            ?? makePresetCellView(identifier: cellIdentifier)
        guard let textField = cellView.textField as? PresetTextField else {
            return cellView
        }

        let preset = model.presetEntries[row]
        switch tableColumn.identifier {
        case Column.name:
            textField.stringValue = preset.name
        case Column.rpm:
            textField.stringValue = preset.rpmText
        default:
            textField.stringValue = ""
        }

        if case .custom(let id) = preset.preset {
            textField.presetID = id
            if let pendingTextFocus,
               pendingTextFocus.id == id,
               pendingTextFocus.columnIdentifier == tableColumn.identifier {
                self.pendingTextFocus = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self, weak textField] in
                    guard let self, let textField else {
                        return
                    }
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    self.view.window?.makeKeyAndOrderFront(nil)
                    _ = self.view.window?.makeFirstResponder(nil)
                    self.view.window?.makeFirstResponder(self.tableView)
                    self.view.window?.makeFirstResponder(textField)
                    textField.selectText(nil)
                }
            }
        } else {
            textField.presetID = nil
        }
        textField.columnIdentifier = tableColumn.identifier
        textField.isEditable = preset.isEditable
        textField.isSelectable = preset.isEditable
        textField.textColor = .labelColor

        return cellView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRemoveControl()
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SquarePresetTableRowView()
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else {
            return
        }
        if textField === addPresetNameField || textField === addPresetRPMField {
            return
        }
        if let presetTextField = textField as? PresetTextField,
           let id = presetTextField.presetID,
           suppressNextEndEditingCommitID == id {
            suppressNextEndEditingCommitID = nil
            return
        }
        commitPresetTextFieldIfValid(textField)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.insertNewline(_:)),
              let textField = control as? NSTextField
        else {
            return false
        }

        if textField === addPresetNameField {
            textField.window?.makeFirstResponder(addPresetRPMField)
            addPresetRPMField?.selectText(nil)
            return true
        }
        if textField === addPresetRPMField {
            commitAddPresetSheetFromKeyboard()
            return true
        }

        let presetTextField = textField as? PresetTextField
        guard commitPresetTextFieldIfValid(textField, reloadsTable: presetTextField?.columnIdentifier != Column.name) else {
            return true
        }

        if presetTextField?.columnIdentifier == Column.name,
           let id = presetTextField?.presetID {
            suppressNextEndEditingCommitID = id
        }
        focusRPMForTextField(textField)
        return true
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField,
              textField === addPresetRPMField
        else {
            return
        }

        let value = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let isInvalid = validatedRPM(from: value) == nil
        if isInvalid && !value.isEmpty && !addPresetRPMInputIsInvalid {
            NSSound.beep()
        }
        updateAddPresetValidationState(showsError: isInvalid)
        addPresetRPMInputIsInvalid = isInvalid && !value.isEmpty
    }
}

private final class PresetTextField: NSTextField {
    var presetID: UUID?
    var columnIdentifier: NSUserInterfaceItemIdentifier?

    override var acceptsFirstResponder: Bool {
        isEditable
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            currentEditor()?.selectAll(nil)
        }
        return becameFirstResponder
    }
}

private final class EditablePresetTableView: NSTableView {
    override func drawBackground(inClipRect clipRect: NSRect) {
        let colors = NSColor.alternatingContentBackgroundColors
        guard !colors.isEmpty else {
            super.drawBackground(inClipRect: clipRect)
            return
        }

        let rowStride = rowHeight + intercellSpacing.height
        guard rowStride > 0 else {
            super.drawBackground(inClipRect: clipRect)
            return
        }

        let startRow = max(0, Int(floor(clipRect.minY / rowStride)))
        var row = startRow
        var rowY = CGFloat(startRow) * rowStride

        while rowY < clipRect.maxY {
            colors[row % colors.count].setFill()
            NSRect(x: 0, y: rowY, width: bounds.width, height: rowStride).fill()
            row += 1
            rowY += rowStride
        }
    }

    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if responder is NSTextField || responder is NSTextView {
            return true
        }
        return super.validateProposedFirstResponder(responder, for: event)
    }
}

private final class LockedHorizontalClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        bounds.origin.x = 0
        return bounds
    }
}

private final class VerticalOnlyPresetScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event)
        if contentView.bounds.origin.x != 0 {
            contentView.scroll(to: NSPoint(x: 0, y: contentView.bounds.origin.y))
            reflectScrolledClipView(contentView)
        }
    }
}

private final class PaddedPresetHeaderCell: NSTableHeaderCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: rect).insetBy(dx: 8, dy: 0)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        super.titleRect(forBounds: rect).insetBy(dx: 8, dy: 0)
    }
}

private final class SquarePresetTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else {
            return
        }

        let selectionColor = isEmphasized
            ? NSColor.selectedContentBackgroundColor
            : NSColor.unemphasizedSelectedContentBackgroundColor
        selectionColor.setFill()
        bounds.fill()
    }
}

private final class PresetListContentView: NSView {
    override var isOpaque: Bool {
        true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()

        let cardRect = bounds.insetBy(dx: 22, dy: 16)
        let path = NSBezierPath(roundedRect: cardRect, xRadius: 14, yRadius: 14)
        cardBackgroundColor.setFill()
        path.fill()
    }

    private var cardBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(calibratedWhite: 1.0, alpha: 0.055)
                : NSColor(calibratedWhite: 0.0, alpha: 0.045)
        }
    }
}

private final class PresetFooterView: NSView {
    override var isOpaque: Bool {
        false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 0, y: bounds.height - 0.5))
        line.line(to: NSPoint(x: bounds.width, y: bounds.height - 0.5))
        line.lineWidth = 1
        line.stroke()
    }
}

@MainActor
private final class FanCtlSettingsViewController: NSViewController, NSToolbarDelegate, NSTextFieldDelegate {
    fileprivate static let generalToolbarIdentifier = NSToolbarItem.Identifier("general")
    fileprivate static let menuBarDisplayToolbarIdentifier = NSToolbarItem.Identifier("menuBarDisplay")

    private enum SettingsTab {
        case general
        case menuBarDisplay
    }

    private let model: FanCtlMenuBarModel
    private let generalContentView = NSView()
    private let menuBarDisplayContentView = NSView()
    private let launchAtLoginSectionLabel = NSTextField(labelWithString: L10n.launchAtLoginSection)
    private let launchAtLoginRow = SettingsRowView()
    private let launchAtLoginLabel = NSTextField(labelWithString: L10n.launchAtLoginSetting)
    private let launchAtLoginSwitch = NSSwitch()
    private let updateCheckRow = SettingsRowView()
    private let updateCheckLabel = NSTextField(labelWithString: L10n.checkForUpdatesAtLaunch)
    private let updateCheckSwitch = NSSwitch()
    private let languageSectionLabel = NSTextField(labelWithString: L10n.languageSection)
    private let languageRow = SettingsRowView()
    private let languageLabel = NSTextField(labelWithString: L10n.appLanguage)
    private let languagePopUpButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let menuBarDisplaySectionLabel = NSTextField(labelWithString: L10n.menuBarDisplaySection)
    private let menuBarFormatRow = SettingsRowView()
    private let menuBarFormatLabel = NSTextField(labelWithString: L10n.format)
    private let menuBarFormatField = NSTextField()
    private var menuBarFormatLabelWidthConstraint: NSLayoutConstraint?
    private var selectedTab: SettingsTab = .general
    fileprivate var didSelectGeneralTab: (() -> Void)?
    fileprivate var didSelectMenuBarDisplayTab: (() -> Void)?

    init(model: FanCtlMenuBarModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = SettingsContentView(frame: NSRect(origin: .zero, size: FanCtlWindowLayout.settingsContentSize))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContent()
        refreshLaunchAtLoginState()
        refreshUpdateCheckState()
        refreshMenuBarFormat()
        showGeneralSettings()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshLaunchAtLoginState()
        refreshUpdateCheckState()
        refreshMenuBarFormat()
        reloadLanguagePopUpButton()
    }

    fileprivate var currentTitle: String {
        switch selectedTab {
        case .general:
            L10n.general
        case .menuBarDisplay:
            L10n.menuBarDisplay
        }
    }

    fileprivate func refreshLocalizedText(toolbar: NSToolbar?) {
        launchAtLoginSectionLabel.stringValue = L10n.launchAtLoginSection
        launchAtLoginLabel.stringValue = L10n.launchAtLoginSetting
        updateCheckLabel.stringValue = L10n.checkForUpdatesAtLaunch
        languageSectionLabel.stringValue = L10n.languageSection
        languageLabel.stringValue = L10n.appLanguage
        menuBarDisplaySectionLabel.stringValue = L10n.menuBarDisplaySection
        menuBarFormatLabel.stringValue = L10n.format
        updateMenuBarFormatLabelWidth()
        menuBarFormatField.placeholderString = FanCtlMenuBarModel.defaultMenuBarTitleFormat
        reloadLanguagePopUpButton()
        refreshToolbarItems(toolbar)
        view.window?.title = currentTitle
    }

    private func setupContent() {
        generalContentView.translatesAutoresizingMaskIntoConstraints = false
        menuBarDisplayContentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(generalContentView)
        view.addSubview(menuBarDisplayContentView)

        NSLayoutConstraint.activate([
            generalContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            generalContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            generalContentView.topAnchor.constraint(equalTo: view.topAnchor),
            generalContentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            menuBarDisplayContentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            menuBarDisplayContentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            menuBarDisplayContentView.topAnchor.constraint(equalTo: view.topAnchor),
            menuBarDisplayContentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        setupGeneralContent()
        setupMenuBarDisplayContent()
    }

    private func setupGeneralContent() {
        launchAtLoginSectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        launchAtLoginSectionLabel.textColor = .labelColor
        launchAtLoginSectionLabel.translatesAutoresizingMaskIntoConstraints = false

        launchAtLoginRow.translatesAutoresizingMaskIntoConstraints = false

        launchAtLoginLabel.font = .systemFont(ofSize: 13, weight: .medium)
        launchAtLoginLabel.textColor = .labelColor
        launchAtLoginLabel.translatesAutoresizingMaskIntoConstraints = false

        launchAtLoginSwitch.target = self
        launchAtLoginSwitch.action = #selector(toggleLaunchAtLogin(_:))
        launchAtLoginSwitch.controlSize = .small
        launchAtLoginSwitch.translatesAutoresizingMaskIntoConstraints = false

        updateCheckRow.translatesAutoresizingMaskIntoConstraints = false

        updateCheckLabel.font = .systemFont(ofSize: 13, weight: .medium)
        updateCheckLabel.textColor = .labelColor
        updateCheckLabel.translatesAutoresizingMaskIntoConstraints = false

        updateCheckSwitch.target = self
        updateCheckSwitch.action = #selector(toggleUpdateCheckAtLaunch(_:))
        updateCheckSwitch.controlSize = .small
        updateCheckSwitch.translatesAutoresizingMaskIntoConstraints = false

        languageSectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        languageSectionLabel.textColor = .labelColor
        languageSectionLabel.translatesAutoresizingMaskIntoConstraints = false

        languageRow.translatesAutoresizingMaskIntoConstraints = false

        languageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        languageLabel.textColor = .labelColor
        languageLabel.translatesAutoresizingMaskIntoConstraints = false

        languagePopUpButton.target = self
        languagePopUpButton.action = #selector(selectLanguage(_:))
        languagePopUpButton.controlSize = .small
        languagePopUpButton.font = .systemFont(ofSize: 13)
        languagePopUpButton.translatesAutoresizingMaskIntoConstraints = false
        reloadLanguagePopUpButton()

        generalContentView.addSubview(launchAtLoginSectionLabel)
        generalContentView.addSubview(launchAtLoginRow)
        generalContentView.addSubview(updateCheckRow)
        generalContentView.addSubview(languageSectionLabel)
        generalContentView.addSubview(languageRow)
        launchAtLoginRow.addSubview(launchAtLoginLabel)
        launchAtLoginRow.addSubview(launchAtLoginSwitch)
        updateCheckRow.addSubview(updateCheckLabel)
        updateCheckRow.addSubview(updateCheckSwitch)
        languageRow.addSubview(languageLabel)
        languageRow.addSubview(languagePopUpButton)

        NSLayoutConstraint.activate([
            launchAtLoginSectionLabel.leadingAnchor.constraint(equalTo: generalContentView.leadingAnchor, constant: 22),
            launchAtLoginSectionLabel.topAnchor.constraint(equalTo: generalContentView.topAnchor, constant: 16),

            launchAtLoginRow.leadingAnchor.constraint(equalTo: generalContentView.leadingAnchor, constant: 22),
            launchAtLoginRow.trailingAnchor.constraint(equalTo: generalContentView.trailingAnchor, constant: -22),
            launchAtLoginRow.topAnchor.constraint(equalTo: launchAtLoginSectionLabel.bottomAnchor, constant: 12),
            launchAtLoginRow.heightAnchor.constraint(equalToConstant: 38),

            launchAtLoginLabel.leadingAnchor.constraint(equalTo: launchAtLoginRow.leadingAnchor, constant: 12),
            launchAtLoginLabel.centerYAnchor.constraint(equalTo: launchAtLoginRow.centerYAnchor),
            launchAtLoginLabel.trailingAnchor.constraint(lessThanOrEqualTo: launchAtLoginSwitch.leadingAnchor, constant: -10),

            launchAtLoginSwitch.trailingAnchor.constraint(equalTo: launchAtLoginRow.trailingAnchor, constant: -10),
            launchAtLoginSwitch.centerYAnchor.constraint(equalTo: launchAtLoginRow.centerYAnchor),

            updateCheckRow.leadingAnchor.constraint(equalTo: generalContentView.leadingAnchor, constant: 22),
            updateCheckRow.trailingAnchor.constraint(equalTo: generalContentView.trailingAnchor, constant: -22),
            updateCheckRow.topAnchor.constraint(equalTo: launchAtLoginRow.bottomAnchor, constant: 8),
            updateCheckRow.heightAnchor.constraint(equalToConstant: 38),

            updateCheckLabel.leadingAnchor.constraint(equalTo: updateCheckRow.leadingAnchor, constant: 12),
            updateCheckLabel.centerYAnchor.constraint(equalTo: updateCheckRow.centerYAnchor),
            updateCheckLabel.trailingAnchor.constraint(lessThanOrEqualTo: updateCheckSwitch.leadingAnchor, constant: -10),

            updateCheckSwitch.trailingAnchor.constraint(equalTo: updateCheckRow.trailingAnchor, constant: -10),
            updateCheckSwitch.centerYAnchor.constraint(equalTo: updateCheckRow.centerYAnchor),

            languageSectionLabel.leadingAnchor.constraint(equalTo: generalContentView.leadingAnchor, constant: 22),
            languageSectionLabel.topAnchor.constraint(equalTo: updateCheckRow.bottomAnchor, constant: 18),

            languageRow.leadingAnchor.constraint(equalTo: generalContentView.leadingAnchor, constant: 22),
            languageRow.trailingAnchor.constraint(equalTo: generalContentView.trailingAnchor, constant: -22),
            languageRow.topAnchor.constraint(equalTo: languageSectionLabel.bottomAnchor, constant: 12),
            languageRow.heightAnchor.constraint(equalToConstant: 38),

            languageLabel.leadingAnchor.constraint(equalTo: languageRow.leadingAnchor, constant: 12),
            languageLabel.centerYAnchor.constraint(equalTo: languageRow.centerYAnchor),
            languageLabel.trailingAnchor.constraint(lessThanOrEqualTo: languagePopUpButton.leadingAnchor, constant: -10),

            languagePopUpButton.trailingAnchor.constraint(equalTo: languageRow.trailingAnchor, constant: -10),
            languagePopUpButton.centerYAnchor.constraint(equalTo: languageRow.centerYAnchor),
            languagePopUpButton.widthAnchor.constraint(equalToConstant: 122)
        ])
    }

    private func setupMenuBarDisplayContent() {
        menuBarDisplaySectionLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        menuBarDisplaySectionLabel.textColor = .labelColor
        menuBarDisplaySectionLabel.translatesAutoresizingMaskIntoConstraints = false

        menuBarFormatRow.translatesAutoresizingMaskIntoConstraints = false

        menuBarFormatLabel.font = .systemFont(ofSize: 13, weight: .medium)
        menuBarFormatLabel.textColor = .labelColor
        menuBarFormatLabel.translatesAutoresizingMaskIntoConstraints = false

        menuBarFormatField.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        menuBarFormatField.placeholderString = FanCtlMenuBarModel.defaultMenuBarTitleFormat
        menuBarFormatField.delegate = self
        menuBarFormatField.target = self
        menuBarFormatField.action = #selector(commitMenuBarFormatField(_:))
        menuBarFormatField.usesSingleLineMode = true
        menuBarFormatField.lineBreakMode = .byTruncatingTail
        menuBarFormatField.translatesAutoresizingMaskIntoConstraints = false

        menuBarDisplayContentView.addSubview(menuBarDisplaySectionLabel)
        menuBarDisplayContentView.addSubview(menuBarFormatRow)
        menuBarFormatRow.addSubview(menuBarFormatLabel)
        menuBarFormatRow.addSubview(menuBarFormatField)

        let formatLabelWidthConstraint = menuBarFormatLabel.widthAnchor.constraint(equalToConstant: menuBarFormatLabelWidth)
        menuBarFormatLabelWidthConstraint = formatLabelWidthConstraint

        NSLayoutConstraint.activate([
            menuBarDisplaySectionLabel.leadingAnchor.constraint(equalTo: menuBarDisplayContentView.leadingAnchor, constant: 22),
            menuBarDisplaySectionLabel.topAnchor.constraint(equalTo: menuBarDisplayContentView.topAnchor, constant: 16),

            menuBarFormatRow.leadingAnchor.constraint(equalTo: menuBarDisplayContentView.leadingAnchor, constant: 22),
            menuBarFormatRow.trailingAnchor.constraint(equalTo: menuBarDisplayContentView.trailingAnchor, constant: -22),
            menuBarFormatRow.topAnchor.constraint(equalTo: menuBarDisplaySectionLabel.bottomAnchor, constant: 12),
            menuBarFormatRow.heightAnchor.constraint(equalToConstant: 38),

            menuBarFormatLabel.leadingAnchor.constraint(equalTo: menuBarFormatRow.leadingAnchor, constant: 12),
            menuBarFormatLabel.centerYAnchor.constraint(equalTo: menuBarFormatRow.centerYAnchor),
            formatLabelWidthConstraint,

            menuBarFormatField.leadingAnchor.constraint(equalTo: menuBarFormatLabel.trailingAnchor, constant: 10),
            menuBarFormatField.trailingAnchor.constraint(equalTo: menuBarFormatRow.trailingAnchor, constant: -12),
            menuBarFormatField.centerYAnchor.constraint(equalTo: menuBarFormatRow.centerYAnchor),
            menuBarFormatField.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    private var menuBarFormatLabelWidth: CGFloat {
        AppLanguage.current == .korean ? 34 : 54
    }

    private func updateMenuBarFormatLabelWidth() {
        menuBarFormatLabelWidthConstraint?.constant = menuBarFormatLabelWidth
        menuBarDisplayContentView.layoutSubtreeIfNeeded()
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginSwitch.state = isLaunchAtLoginSelected ? .on : .off
    }

    private func refreshUpdateCheckState() {
        updateCheckSwitch.state = AppPreferences.isUpdateCheckAtLaunchEnabled ? .on : .off
    }

    private func reloadLanguagePopUpButton() {
        let selectedLanguage = AppLanguage.current
        languagePopUpButton.removeAllItems()

        for language in AppLanguage.allCases {
            languagePopUpButton.addItem(withTitle: language.displayName)
            languagePopUpButton.lastItem?.representedObject = language.rawValue
        }

        if let selectedIndex = AppLanguage.allCases.firstIndex(of: selectedLanguage) {
            languagePopUpButton.selectItem(at: selectedIndex)
        }
    }

    @objc private func selectLanguage(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let language = AppLanguage(rawValue: rawValue)
        else {
            reloadLanguagePopUpButton()
            return
        }

        AppLanguage.setCurrent(language)
    }

    private var isLaunchAtLoginSelected: Bool {
        switch SMAppService.mainApp.status {
        case .enabled:
            return true
        case .notRegistered, .notFound:
            return false
        case .requiresApproval:
            return UserDefaults.standard.bool(forKey: FanCtlDefaults.launchAtLoginEnabledKey)
        @unknown default:
            return UserDefaults.standard.bool(forKey: FanCtlDefaults.launchAtLoginEnabledKey)
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSSwitch) {
        let shouldEnable = sender.state == .on
        let previousValue = UserDefaults.standard.bool(forKey: FanCtlDefaults.launchAtLoginEnabledKey)

        do {
            if shouldEnable {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered,
                      SMAppService.mainApp.status != .notFound {
                try SMAppService.mainApp.unregister()
            }
            UserDefaults.standard.set(shouldEnable, forKey: FanCtlDefaults.launchAtLoginEnabledKey)
        } catch {
            NSLog("mFanCtl failed to update launch at login: \(error.localizedDescription)")
            UserDefaults.standard.set(previousValue, forKey: FanCtlDefaults.launchAtLoginEnabledKey)
            sender.state = previousValue ? .on : .off
        }
    }

    @objc private func toggleUpdateCheckAtLaunch(_ sender: NSSwitch) {
        AppPreferences.setUpdateCheckAtLaunchEnabled(sender.state == .on)
    }

    private func refreshMenuBarFormat() {
        guard menuBarFormatField.currentEditor() == nil else {
            return
        }
        menuBarFormatField.stringValue = model.menuBarTitleFormat
    }

    @objc private func commitMenuBarFormatField(_ sender: NSTextField) {
        model.updateMenuBarTitleFormat(sender.stringValue)
        sender.stringValue = model.menuBarTitleFormat
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField,
              textField === menuBarFormatField
        else {
            return
        }
        model.updateMenuBarTitleFormat(textField.stringValue)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField,
              textField === menuBarFormatField
        else {
            return
        }
        model.updateMenuBarTitleFormat(textField.stringValue)
        textField.stringValue = model.menuBarTitleFormat
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.generalToolbarIdentifier, Self.menuBarDisplayToolbarIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.generalToolbarIdentifier, Self.menuBarDisplayToolbarIdentifier]
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.generalToolbarIdentifier, Self.menuBarDisplayToolbarIdentifier]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.generalToolbarIdentifier:
            let item = makeToolbarItem(
                identifier: itemIdentifier,
                label: L10n.general,
                symbolName: "gearshape",
                action: #selector(selectGeneralToolbarItem(_:))
            )
            toolbar.selectedItemIdentifier = Self.generalToolbarIdentifier
            return item
        case Self.menuBarDisplayToolbarIdentifier:
            return makeToolbarItem(
                identifier: itemIdentifier,
                label: L10n.menuBarDisplay,
                symbolName: "menubar.rectangle",
                action: #selector(selectMenuBarDisplayToolbarItem(_:))
            )
        default:
            return nil
        }
    }

    private func makeToolbarItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.target = self
        item.action = action
        updateToolbarItem(item, label: label, symbolName: symbolName)
        return item
    }

    private func refreshToolbarItems(_ toolbar: NSToolbar?) {
        for item in toolbar?.items ?? [] {
            switch item.itemIdentifier {
            case Self.generalToolbarIdentifier:
                updateToolbarItem(item, label: L10n.general, symbolName: "gearshape")
            case Self.menuBarDisplayToolbarIdentifier:
                updateToolbarItem(item, label: L10n.menuBarDisplay, symbolName: "menubar.rectangle")
            default:
                continue
            }
        }
    }

    private func updateToolbarItem(_ item: NSToolbarItem, label: String, symbolName: String) {
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
            ?? NSImage(systemSymbolName: "textformat", accessibilityDescription: label)
        if let image {
            image.isTemplate = true
            item.image = image
        }
    }

    @objc private func selectGeneralToolbarItem(_ sender: NSToolbarItem) {
        sender.toolbar?.selectedItemIdentifier = Self.generalToolbarIdentifier
        if let didSelectGeneralTab {
            didSelectGeneralTab()
        } else {
            showGeneralSettings()
        }
    }

    @objc private func selectMenuBarDisplayToolbarItem(_ sender: NSToolbarItem) {
        sender.toolbar?.selectedItemIdentifier = Self.menuBarDisplayToolbarIdentifier
        if let didSelectMenuBarDisplayTab {
            didSelectMenuBarDisplayTab()
        } else {
            showMenuBarDisplaySettings()
        }
    }

    func showGeneralTab() {
        showGeneralSettings()
    }

    func showMenuBarDisplayTab() {
        showMenuBarDisplaySettings()
    }

    private func showGeneralSettings() {
        selectedTab = .general
        generalContentView.isHidden = false
        menuBarDisplayContentView.isHidden = true
        view.window?.title = currentTitle
    }

    private func showMenuBarDisplaySettings() {
        selectedTab = .menuBarDisplay
        generalContentView.isHidden = true
        menuBarDisplayContentView.isHidden = false
        view.window?.title = currentTitle
    }
}

private final class SettingsRowView: NSView {
    override var isOpaque: Bool {
        false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = 14
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)

        cardBackgroundColor.setFill()
        path.fill()
    }

    private var cardBackgroundColor: NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark
                ? NSColor(calibratedWhite: 1.0, alpha: 0.055)
                : NSColor(calibratedWhite: 0.0, alpha: 0.045)
        }
    }
}

private final class SettingsContentView: NSView {
    override var isOpaque: Bool {
        true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

private actor SensorSampler {
    private var reader: SensorReader?
    private var cadence = SensorSamplingCadence(completeSnapshotInterval: 20)

    func snapshot(forceComplete: Bool = false) throws -> SensorSnapshot {
        if reader == nil {
            reader = try SensorReader()
        }
        guard let reader else {
            throw FanCtlMenuError.smcUnavailable
        }

        let now = ProcessInfo.processInfo.systemUptime
        let scope = cadence.scope(at: now, forceComplete: forceComplete)

        do {
            let snapshot = try reader.snapshotStrict(scope: scope)
            cadence.recordSuccessfulSnapshot(scope: scope, at: now)
            return snapshot
        } catch {
            if smcConnectionRecoveryDisposition(for: error) == .reopenConnection {
                // IOKit connections can become stale across sleep or a service restart.
                // Data-shape and firmware errors retain the connection to avoid churn.
                self.reader = nil
                cadence.invalidateControlState()
            }
            throw error
        }
    }

    func invalidateControlStateCache() {
        reader?.invalidateControlStateCache()
        cadence.invalidateControlState()
    }
}

@MainActor
final class FanCtlMenuBarModel: NSObject {
    static let defaultMenuBarTitleFormat = "{RPM}rpm | {TEMP}℃"

    struct Change: OptionSet, Sendable {
        let rawValue: Int

        static let statusTitle = Change(rawValue: 1 << 0)
        static let presets = Change(rawValue: 1 << 1)
        static let error = Change(rawValue: 1 << 2)
        static let all: Change = [.statusTitle, .presets, .error]
    }

    private enum NoticeSource: Int, CaseIterable {
        case control
        case lease
        case permission
        case mode
        case helper
        case presets
        case sensor
    }

    private enum StoredPresetLoadResult {
        case loaded([UserFanPreset])
        case unreadable
    }

    var didChange: (@MainActor (Change) -> Void)?
    var didChangePresetList: (@MainActor () -> Void)?
    var didChangeLidMonitoringRequirement: (@MainActor () -> Void)?
    var didRequireHelperApproval: (@MainActor () -> Void)?

    private(set) var menuBarTitle = "--rpm | --℃" {
        didSet {
            guard oldValue != menuBarTitle else {
                return
            }
            notifyChange(.statusTitle)
        }
    }
    private(set) var snapshot: SensorSnapshot?
    private(set) var errorMessage: String? {
        didSet {
            guard oldValue != errorMessage else {
                return
            }
            notifyChange(.error)
        }
    }
    private(set) var menuBarTitleFormat = FanCtlMenuBarModel.loadMenuBarTitleFormat()
    private(set) var selectedPreset: FanPreset? {
        didSet {
            guard oldValue != selectedPreset else {
                return
            }
            if let selectedPreset, selectedPreset != .automatic {
                startManualControlMaintenance()
            } else {
                stopManualControlMaintenance()
            }
            notifyChange(.presets)
            didChangeLidMonitoringRequirement?()
        }
    }
    private var helperState: HelperState = .unknown {
        didSet {
            guard oldValue != helperState else {
                return
            }
            if (oldValue == .installing) != (helperState == .installing) {
                notifyChange(.presets)
            }
        }
    }
    private(set) var requiresHelperApproval = false {
        didSet {
            guard oldValue != requiresHelperApproval else {
                return
            }
            if requiresHelperApproval {
                helperProbeTask?.cancel()
                helperProbeTask = nil
            }
        }
    }
    private(set) var userPresets: [UserFanPreset] = [] {
        didSet {
            guard !isLoadingUserPresets, oldValue != userPresets else {
                return
            }
            saveUserPresets()
            didChangePresetList?()
        }
    }

    private let refreshInterval: TimeInterval = 2
    private static let maximumStaleTemperatureAge: TimeInterval = 30
    private static let userPresetsKey = "userFanPresets"
    private static let absoluteUserRPMRange =
        FanCtlHelperConstants.minimumRPM...FanCtlHelperConstants.maximumEncodedRPM
    private var lastValidGPUTemperature: Int?
    private var lastValidGPUTemperatureDate: Date?
    private let sensorSampler = SensorSampler()
    private var sensorRefreshTask: Task<Void, Never>?
    private var controlStateInvalidationTask: Task<Void, Never>?
    private var controlStateInvalidationGeneration: UInt = 0
    private var controlStateRefreshPending = false
    private var helperProbeTask: Task<Void, Never>?
    private var helperPreparationTask: Task<Void, Never>?
    private var controlTask: Task<Void, Never>?
    private var safetyRecoveryTask: Task<Void, Never>?
    private var manualLeaseRenewalTask: Task<Void, Never>?
    private var manualLeaseTimer: Timer?
    private var manualControlActivity: (any NSObjectProtocol)?
    private var controlGeneration = 0
    private var pendingPreset: FanPreset? {
        didSet {
            guard oldValue != pendingPreset else {
                return
            }
            didChangeLidMonitoringRequirement?()
        }
    }
    private var safetyRecoveryPending = false
    private var helperProbeFailureCount = 0
    private var nextHelperProbeDate: Date?
    private var nextHelperApprovalStatusCheckDate: Date?
    private var manualLeaseFailureCount = 0
    private var manualLeaseRenewalGeneration = 0
    private var automaticRecoveryNoticePending = false
    private var observedFanNeedsSafetyMonitoring = false {
        didSet {
            guard oldValue != observedFanNeedsSafetyMonitoring else {
                return
            }
            didChangeLidMonitoringRequirement?()
        }
    }
    private var notices: [NoticeSource: String] = [:]
    private var isLoadingUserPresets = true
    private var timer: Timer?
    private var pendingChanges: Change = []
    private var changeNotificationScheduled = false
    private var isInvalidated = false

    var needsLidStateMonitoring: Bool {
        if let pendingPreset, pendingPreset != .automatic {
            return true
        }
        if let selectedPreset, selectedPreset != .automatic {
            return true
        }
        return observedFanNeedsSafetyMonitoring
    }

    var presetEntries: [FanPresetEntry] {
        [
            FanPresetEntry(
                preset: .automatic,
                name: L10n.automatic,
                rpmText: L10n.automatic,
                isEditable: false,
                isDeletable: false
            ),
            FanPresetEntry(
                preset: .maximum,
                name: L10n.maximumSpeed,
                rpmText: maximumPresetRPMText,
                isEditable: false,
                isDeletable: false
            )
        ] + userPresets.map {
            FanPresetEntry(
                preset: .custom($0.id),
                name: $0.name,
                rpmText: "\($0.rpm)",
                isEditable: true,
                isDeletable: true
            )
        }
    }

    var presetsDisabled: Bool {
        helperState == .installing
    }

    var validUserRPMRange: ClosedRange<Int> {
        guard let snapshot, !snapshot.fans.isEmpty else {
            return Self.absoluteUserRPMRange
        }

        let minimums = snapshot.fans.compactMap(\.minimumRPM).filter { $0.isFinite && $0 >= 0 }
        let maximums = snapshot.fans.compactMap(\.maximumRPM).filter { $0.isFinite && $0 >= 1 }
        guard maximums.count == snapshot.fans.count,
              let smallestMaximum = maximums.min(),
              smallestMaximum <= Double(Int.max)
        else {
            return Self.absoluteUserRPMRange
        }

        let greatestMinimum = minimums.max() ?? Double(Self.absoluteUserRPMRange.lowerBound)
        guard greatestMinimum <= Double(Int.max) else {
            return Self.absoluteUserRPMRange
        }

        let lowerBound = max(Self.absoluteUserRPMRange.lowerBound, Int(greatestMinimum.rounded(.up)))
        let upperBound = min(Self.absoluteUserRPMRange.upperBound, Int(smallestMaximum.rounded(.down)))
        guard lowerBound <= upperBound else {
            return Self.absoluteUserRPMRange
        }
        return lowerBound...upperBound
    }

    override init() {
        super.init()
        switch Self.loadUserPresets() {
        case .loaded(let presets):
            userPresets = presets
        case .unreadable:
            userPresets = []
            setNotice(L10n.presetDataUnreadable, source: .presets)
        }
        isLoadingUserPresets = false

        refresh()
        timer = Timer.scheduledTimer(
            timeInterval: refreshInterval,
            target: self,
            selector: #selector(timerDidFire),
            userInfo: nil,
            repeats: true
        )
        timer?.tolerance = 0.4
        RunLoop.main.add(timer!, forMode: .common)
        refreshHelperState()
    }

    func invalidateTimers() {
        isInvalidated = true
        timer?.invalidate()
        timer = nil
        sensorRefreshTask?.cancel()
        sensorRefreshTask = nil
        controlStateInvalidationTask?.cancel()
        controlStateInvalidationTask = nil
        controlStateRefreshPending = false
        helperProbeTask?.cancel()
        helperProbeTask = nil
        helperPreparationTask?.cancel()
        helperPreparationTask = nil
        FanCtlHelperClient.invalidateConnection()
        controlTask?.cancel()
        controlTask = nil
        safetyRecoveryTask?.cancel()
        safetyRecoveryTask = nil
        stopManualControlMaintenance()
    }

    func prepareHelper() {
        prepareHelperSilently()
    }

    func recheckHelperApprovalIfNeeded() {
        guard requiresHelperApproval else {
            return
        }
        nextHelperApprovalStatusCheckDate = nil
        refreshHelperState()
    }

    func refresh() {
        guard !isInvalidated, sensorRefreshTask == nil else {
            return
        }

        let sampler = sensorSampler
        let observationGeneration = controlGeneration
        let canReconcileObservedState = controlTask == nil &&
            safetyRecoveryTask == nil &&
            helperPreparationTask == nil
        sensorRefreshTask = Task { [weak self] in
            do {
                let nextSnapshot = try await sampler.snapshot()
                try Task.checkCancellation()
                guard let self else {
                    return
                }
                snapshot = nextSnapshot
                menuBarTitle = title(for: nextSnapshot, format: menuBarTitleFormat)
                if nextSnapshot.fans.isEmpty {
                    setNotice(L10n.noFansFound, source: .sensor)
                } else {
                    setNotice(nil, source: .sensor)
                    if canReconcileObservedState,
                       observationGeneration == controlGeneration {
                        reconcileObservedFanState(nextSnapshot)
                    }
                }
            } catch is CancellationError {
                // App shutdown or a superseded refresh.
            } catch {
                guard let self else {
                    return
                }
                setNotice(error.localizedDescription, source: .sensor)
                if snapshot == nil {
                    menuBarTitle = "mFanCtl -"
                }
            }
            self?.completeSensorRefresh()
        }
    }

    func refreshControlState() {
        guard !isInvalidated else {
            return
        }
        controlStateRefreshPending = true
        controlStateInvalidationGeneration &+= 1
        guard controlStateInvalidationTask == nil else {
            return
        }

        let sampler = sensorSampler
        controlStateInvalidationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                let requestedGeneration = controlStateInvalidationGeneration
                await sampler.invalidateControlStateCache()
                guard !Task.isCancelled else {
                    return
                }
                guard requestedGeneration != controlStateInvalidationGeneration else {
                    controlStateInvalidationTask = nil
                    startPendingControlStateRefreshIfPossible()
                    return
                }
            }
        }
    }

    private func completeSensorRefresh() {
        sensorRefreshTask = nil
        startPendingControlStateRefreshIfPossible()
    }

    private func startPendingControlStateRefreshIfPossible() {
        guard !isInvalidated,
              controlStateRefreshPending,
              controlStateInvalidationTask == nil,
              sensorRefreshTask == nil else {
            return
        }
        controlStateRefreshPending = false
        refresh()
    }

    func applyPresetSelection(_ preset: FanPreset) {
        safetyRecoveryPending = false
        safetyRecoveryTask?.cancel()
        safetyRecoveryTask = nil
        applyPreset(preset)
    }

    func applyAutomaticForSleepOrLidClose() {
        safetyRecoveryPending = true
        startSafetyRecoveryIfNeeded()
    }

    func ensureAutomaticWhileLidClosed() {
        guard safetyRecoveryPending || selectedPreset != .automatic || pendingPreset != nil else {
            return
        }
        applyAutomaticForSleepOrLidClose()
    }

    func restoreAutomaticForAppTermination() async {
        safetyRecoveryPending = false
        controlGeneration += 1
        pendingPreset = nil
        controlTask?.cancel()
        safetyRecoveryTask?.cancel()
        stopManualControlMaintenance()
        let mutationSequence = FanCtlHelperClient.nextMutationSequence()
        _ = await restoreAutomatic(
            reason: "app termination",
            showsFailure: false,
            expectedGeneration: controlGeneration,
            mutationSequence: mutationSequence,
            refreshesSensors: false
        )
    }

    @discardableResult
    private func restoreAutomatic(
        reason: String,
        showsFailure: Bool,
        expectedGeneration: Int,
        mutationSequence: Int64,
        refreshesSensors: Bool = true
    ) async -> Bool {
        let succeeded: Bool
        do {
            _ = try await FanCtlHelperClient.send(
                "SET_AUTOMATIC",
                timeout: FanCtlHelperClient.automaticFallbackTimeout,
                mutationSequence: mutationSequence
            )
            try Task.checkCancellation()
            if expectedGeneration == controlGeneration {
                helperState = .available
                requiresHelperApproval = false
                automaticRecoveryNoticePending = false
                setNotice(nil, source: .control)
                setNotice(nil, source: .mode)
                setNotice(nil, source: .lease)
                setNotice(nil, source: .helper)
                setNotice(nil, source: .permission)
                selectedPreset = .automatic
                manualLeaseFailureCount = 0
            }
            succeeded = true
        } catch {
            NSLog("mFanCtl failed to restore automatic fan mode for \(reason): \(error.localizedDescription)")
            if showsFailure, expectedGeneration == controlGeneration, !Task.isCancelled {
                setNotice(error.localizedDescription, source: .control)
                selectedPreset = nil
            }
            succeeded = false
        }

        if refreshesSensors {
            // The helper may have changed SMC state even when the reply reports
            // failure or the local Task was cancelled after sending.
            refreshControlState()
        }
        return succeeded
    }

    @discardableResult
    func addUserPreset() -> UUID {
        addUserPreset(name: nextUserPresetName(), rpm: defaultUserPresetRPM())
    }

    @discardableResult
    func addUserPreset(name: String, rpm: Int) -> UUID {
        let id = UUID()
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = UserFanPreset(
            id: id,
            name: trimmedName.isEmpty ? L10n.presetBaseName : trimmedName,
            rpm: max(validUserRPMRange.lowerBound, min(validUserRPMRange.upperBound, rpm))
        )
        userPresets.append(preset)
        return id
    }

    func deleteUserPreset(id: UUID) {
        let wasSelectedOrPending = selectedPreset == .custom(id) || pendingPreset == .custom(id)
        userPresets.removeAll { $0.id == id }
        if wasSelectedOrPending {
            selectedPreset = nil
            applyPreset(.automatic)
        }
    }

    func updateUserPreset(id: UUID, name: String, rpm: Int) {
        guard let index = userPresets.firstIndex(where: { $0.id == id }) else {
            return
        }

        let wasSelectedOrPending = selectedPreset == .custom(id) || pendingPreset == .custom(id)
        let previousRPM = userPresets[index].rpm
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedPreset = UserFanPreset(
            id: userPresets[index].id,
            name: trimmedName.isEmpty ? L10n.presetBaseName : trimmedName,
            rpm: max(validUserRPMRange.lowerBound, min(validUserRPMRange.upperBound, rpm))
        )
        userPresets[index] = updatedPreset
        if wasSelectedOrPending, updatedPreset.rpm != previousRPM {
            applyPreset(.custom(id))
        }
    }

    func updateMenuBarTitleFormat(_ format: String) {
        let nextFormat = Self.normalizedMenuBarTitleFormat(format)
        menuBarTitleFormat = nextFormat
        UserDefaults.standard.set(nextFormat, forKey: FanCtlDefaults.menuBarTitleFormatKey)

        if let snapshot {
            menuBarTitle = title(for: snapshot, format: nextFormat)
        }
    }

    private func title(for snapshot: SensorSnapshot, format: String) -> String {
        if let currentTemperature = Self.roundedGPUTemperature(snapshot.gpuTemperature) {
            lastValidGPUTemperature = currentTemperature
            lastValidGPUTemperatureDate = Date()
        }

        let temperature = recentGPUTemperatureText()
        let fanSummary = Self.fanSummary(snapshot.fans)
        return Self.formattedMenuBarTitle(rpm: fanSummary, temperature: temperature, format: format)
    }

    private func recentGPUTemperatureText(now: Date = Date()) -> String {
        guard let temperature = lastValidGPUTemperature,
              let date = lastValidGPUTemperatureDate,
              now.timeIntervalSince(date) <= Self.maximumStaleTemperatureAge
        else {
            lastValidGPUTemperature = nil
            lastValidGPUTemperatureDate = nil
            return "--"
        }
        return "\(temperature)"
    }

    private static func roundedGPUTemperature(_ gpuTemperature: GPUTemperatureSnapshot?) -> Int? {
        guard let average = gpuTemperature?.averageCelsius, average.isFinite else {
            return nil
        }
        return Int(average.rounded())
    }

    private static func formattedMenuBarTitle(rpm: String, temperature: String, format: String) -> String {
        normalizedMenuBarTitleFormat(format)
            .replacingOccurrences(of: "{RPM}", with: rpm)
            .replacingOccurrences(of: "{TEMP}", with: temperature)
    }

    private static func loadMenuBarTitleFormat() -> String {
        normalizedMenuBarTitleFormat(UserDefaults.standard.string(forKey: FanCtlDefaults.menuBarTitleFormatKey) ?? defaultMenuBarTitleFormat)
    }

    private static func normalizedMenuBarTitleFormat(_ format: String) -> String {
        let singleLineFormat = format
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        guard !singleLineFormat.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return defaultMenuBarTitleFormat
        }
        return singleLineFormat
    }

    private static func fanSummary(_ fans: [FanSnapshot]) -> String {
        guard !fans.isEmpty else {
            return "--"
        }

        let activeFans = fans.filter { $0.actualRPM > 1 }
        guard !activeFans.isEmpty else {
            return "0"
        }

        let average = activeFans.map(\.actualRPM).reduce(0, +) / Double(activeFans.count)
        return "\(Int(average.rounded()))"
    }

    private func nextUserPresetName() -> String {
        let existingNames = Set(presetEntries.map(\.name))
        var index = userPresets.count + 1
        while true {
            let name = L10n.presetName(index: index)
            if !existingNames.contains(name) {
                return name
            }
            index += 1
        }
    }

    private func defaultUserPresetRPM() -> Int {
        guard let snapshot, !snapshot.fans.isEmpty else {
            return 4000
        }

        let minimum = average(snapshot.fans.compactMap(\.minimumRPM)) ?? 2500
        let maximum = average(snapshot.fans.compactMap(\.maximumRPM)) ?? 6500
        return Int(((minimum + maximum) / 2).rounded())
    }

    var defaultNewUserPresetName: String {
        nextUserPresetName()
    }

    var defaultNewUserPresetRPM: Int {
        defaultUserPresetRPM()
    }

    private var maximumPresetRPMText: String {
        guard let snapshot,
              let maximum = average(snapshot.fans.compactMap(\.maximumRPM))
        else {
            return L10n.maximum
        }
        return "\(Int(maximum.rounded()))"
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else {
            return nil
        }
        return values.reduce(0, +) / Double(values.count)
    }

    private func saveUserPresets() {
        guard let data = try? JSONEncoder().encode(userPresets) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.userPresetsKey)
    }

    private static func loadUserPresets() -> StoredPresetLoadResult {
        guard let data = UserDefaults.standard.data(forKey: userPresetsKey) else {
            return .loaded([])
        }
        guard let presets = try? JSONDecoder().decode([UserFanPreset].self, from: data) else {
            return .unreadable
        }

        var identifiers = Set<UUID>()
        var validated: [UserFanPreset] = []
        validated.reserveCapacity(presets.count)
        for preset in presets {
            guard identifiers.insert(preset.id).inserted,
                  absoluteUserRPMRange.contains(preset.rpm)
            else {
                return .unreadable
            }
            let trimmedName = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            validated.append(UserFanPreset(
                id: preset.id,
                name: trimmedName.isEmpty ? L10n.presetBaseName : trimmedName,
                rpm: preset.rpm
            ))
        }
        return .loaded(validated)
    }

    @objc private func timerDidFire() {
        refresh()
        refreshHelperState()
        if safetyRecoveryPending {
            startSafetyRecoveryIfNeeded()
        }
    }

    private func applyPreset(_ preset: FanPreset) {
        automaticRecoveryNoticePending = false
        safetyRecoveryPending = false
        safetyRecoveryTask?.cancel()
        safetyRecoveryTask = nil
        if let selectedPreset, selectedPreset != .automatic {
            startManualControlMaintenance()
        }
        // Keep the current manual lease alive until Automatic is actually
        // verified. If the command fails, the checked preset still describes
        // the state we are maintaining.
        cancelManualLeaseRenewal()
        controlGeneration += 1
        let generation = controlGeneration
        let mutationSequence = FanCtlHelperClient.nextMutationSequence()
        pendingPreset = preset
        controlTask?.cancel()
        setNotice(L10n.applyingFanPreset, source: .control)
        setNotice(nil, source: .lease)
        setNotice(nil, source: .mode)

        controlTask = Task { [weak self] in
            guard let self else {
                return
            }
            var didAttemptMutation = false
            defer {
                if generation == controlGeneration {
                    pendingPreset = nil
                    controlTask = nil
                }
                if didAttemptMutation {
                    // A stale local generation does not cancel a mutation that
                    // was already delivered to the privileged helper.
                    refreshControlState()
                }
            }
            do {
                try await ensureHelperAvailableForControl()
                try Task.checkCancellation()
                didAttemptMutation = true
                try await sendHelperCommand(for: preset, mutationSequence: mutationSequence)
                try Task.checkCancellation()
                guard generation == controlGeneration else {
                    return
                }
                helperState = .available
                helperProbeFailureCount = 0
                requiresHelperApproval = false
                setNotice(nil, source: .permission)
                setNotice(nil, source: .helper)
                setNotice(nil, source: .control)
                selectedPreset = preset
                pendingPreset = nil
                manualLeaseFailureCount = 0
            } catch is CancellationError {
                // A newer preset or a safety fallback superseded this request.
            } catch InstallError.requiresApproval {
                guard generation == controlGeneration else {
                    return
                }
                setNotice(nil, source: .control)
                let shouldPrompt = !requiresHelperApproval
                helperState = .unavailable
                requiresHelperApproval = true
                setNotice(InstallError.requiresApproval.localizedDescription, source: .permission)
                if shouldPrompt {
                    didRequireHelperApproval?()
                }
                NSLog("mFanCtl fan helper requires approval")
            } catch {
                guard generation == controlGeneration else {
                    return
                }
                if case FanCtlHelperClient.Error.unavailable = error {
                    setNotice(nil, source: .control)
                    helperState = .unavailable
                    setNotice(error.localizedDescription, source: .helper)
                } else if case FanCtlHelperClient.Error.rejected(let code, _) = error,
                          code == "fan_control_failed",
                          preset != .automatic {
                    selectedPreset = .automatic
                    setNotice(L10n.fanPresetFailedAndRestoredAutomatic, source: .control)
                } else if case FanCtlHelperClient.Error.rejected(let code, _) = error,
                          code == "automatic_recovery_failed" ||
                              (code == "fan_control_failed" && preset == .automatic) {
                    selectedPreset = nil
                    automaticRecoveryNoticePending = true
                    setNotice(L10n.automaticRecoveryInProgress, source: .control)
                } else {
                    setNotice(error.localizedDescription, source: .control)
                }
                NSLog("mFanCtl failed to apply fan preset: \(error.localizedDescription)")
            }

        }
    }

    @objc private func manualLeaseTimerDidFire() {
        renewManualLeaseIfNeeded()
    }

    private func startManualControlMaintenance() {
        if manualControlActivity == nil {
            manualControlActivity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Maintain the user-selected manual fan mode"
            )
        }

        guard manualLeaseTimer == nil else {
            return
        }

        let timer = Timer(
            timeInterval: FanCtlHelperConstants.manualControlHeartbeatInterval,
            target: self,
            selector: #selector(manualLeaseTimerDidFire),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = min(0.5, FanCtlHelperConstants.manualControlHeartbeatInterval / 10)
        manualLeaseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopManualControlMaintenance() {
        manualLeaseTimer?.invalidate()
        manualLeaseTimer = nil
        cancelManualLeaseRenewal()

        if let manualControlActivity {
            ProcessInfo.processInfo.endActivity(manualControlActivity)
            self.manualControlActivity = nil
        }
    }

    private func cancelManualLeaseRenewal() {
        manualLeaseRenewalGeneration &+= 1
        manualLeaseRenewalTask?.cancel()
        manualLeaseRenewalTask = nil
    }

    private func sendHelperCommand(for preset: FanPreset, mutationSequence: Int64) async throws {
        let command: String
        switch preset {
        case .automatic:
            command = "SET_AUTOMATIC"
        case .maximum:
            command = "SET_MAXIMUM"
        case .custom(let id):
            if let preset = userPresets.first(where: { $0.id == id }) {
                guard validUserRPMRange.contains(preset.rpm) else {
                    throw FanCtlMenuError.invalidPresetRPM(validUserRPMRange)
                }
                command = "SET_RPM \(preset.rpm)"
            } else {
                throw FanCtlMenuError.missingPreset
            }
        }

        _ = try await FanCtlHelperClient.send(
            command,
            timeout: FanCtlHelperClient.fanCommandTimeout,
            mutationSequence: mutationSequence
        )
    }

    private func ensureHelperAvailableForControl() async throws {
        if let helperPreparationTask {
            setNotice(L10n.installingPermission, source: .helper)
            await helperPreparationTask.value
            try Task.checkCancellation()
        }

        let requiresReinstall: Bool
        do {
            try await FanCtlHelperClient.waitUntilAvailable(timeout: 1.0)
            helperState = .available
            helperProbeFailureCount = 0
            return
        } catch is CancellationError {
            throw CancellationError()
        } catch FanCtlHelperClient.Error.incompatibleHelper {
            requiresReinstall = true
        } catch {
            // Registration below also refreshes an outdated bundled helper.
            requiresReinstall = false
        }

        helperState = .installing
        requiresHelperApproval = false
        setNotice(nil, source: .permission)
        setNotice(L10n.installingPermission, source: .helper)

        try await Task.detached {
            if requiresReinstall {
                try FanCtlHelperInstaller.reinstall()
            } else {
                try FanCtlHelperInstaller.install()
            }
        }.value
        FanCtlHelperClient.invalidateConnection()
        try Task.checkCancellation()
        do {
            try await waitForHelperAvailability()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            guard !requiresReinstall else {
                throw error
            }
            try await Task.detached {
                try FanCtlHelperInstaller.reinstall()
            }.value
            FanCtlHelperClient.invalidateConnection()
            try Task.checkCancellation()
            try await waitForHelperAvailability()
        }
        helperState = .available
        helperProbeFailureCount = 0
        setNotice(nil, source: .helper)
    }

    private func renewManualLeaseIfNeeded() {
        guard !safetyRecoveryPending,
              controlTask == nil,
              safetyRecoveryTask == nil,
              manualLeaseRenewalTask == nil,
              let selectedPreset,
              selectedPreset != .automatic
        else {
            return
        }

        let expectedPreset = selectedPreset
        let expectedControlGeneration = controlGeneration
        let mutationSequence = FanCtlHelperClient.nextMutationSequence()
        manualLeaseRenewalGeneration &+= 1
        let renewalGeneration = manualLeaseRenewalGeneration
        manualLeaseRenewalTask = Task { [weak self] in
            guard let self else {
                return
            }
            defer {
                if renewalGeneration == manualLeaseRenewalGeneration {
                    manualLeaseRenewalTask = nil
                }
            }
            do {
                _ = try await FanCtlHelperClient.send(
                    "RENEW_MANUAL_LEASE",
                    timeout: 3.0,
                    mutationSequence: mutationSequence
                )
                try Task.checkCancellation()
                guard renewalGeneration == manualLeaseRenewalGeneration,
                      expectedControlGeneration == controlGeneration,
                      self.selectedPreset == expectedPreset else {
                    return
                }
                manualLeaseFailureCount = 0
                setNotice(nil, source: .lease)
            } catch is CancellationError {
                // Automatic mode or a newer command stopped the heartbeat.
            } catch {
                guard renewalGeneration == manualLeaseRenewalGeneration,
                      expectedControlGeneration == controlGeneration,
                      self.selectedPreset == expectedPreset else {
                    return
                }
                manualLeaseFailureCount += 1
                let leaseIsInactive: Bool
                if case FanCtlHelperClient.Error.rejected(let code, _) = error {
                    leaseIsInactive = code == "manual_lease_inactive"
                } else {
                    leaseIsInactive = false
                }

                if leaseIsInactive || manualLeaseFailureCount >= 2 {
                    self.selectedPreset = nil
                    setNotice(error.localizedDescription, source: .lease)
                    safetyRecoveryPending = true
                }
            }
            if safetyRecoveryPending {
                startSafetyRecoveryIfNeeded()
            }
        }
    }

    private func startSafetyRecoveryIfNeeded() {
        guard safetyRecoveryPending, safetyRecoveryTask == nil else {
            return
        }

        controlGeneration += 1
        let generation = controlGeneration
        let mutationSequence = FanCtlHelperClient.nextMutationSequence()
        pendingPreset = nil
        controlTask?.cancel()
        controlTask = nil
        stopManualControlMaintenance()

        safetyRecoveryTask = Task { [weak self] in
            guard let self else {
                return
            }
            let succeeded = await restoreAutomatic(
                reason: "sleep or lid close",
                showsFailure: true,
                expectedGeneration: generation,
                mutationSequence: mutationSequence
            )
            guard generation == controlGeneration else {
                return
            }
            safetyRecoveryPending = !succeeded
            safetyRecoveryTask = nil
        }
    }

    private func prepareHelperSilently() {
        guard helperPreparationTask == nil else {
            return
        }

        let generation = controlGeneration
        helperPreparationTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try await Task.detached {
                    try FanCtlHelperInstaller.install()
                }.value
                FanCtlHelperClient.invalidateConnection()
                try Task.checkCancellation()
                do {
                    try await waitForHelperAvailability()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try await Task.detached {
                        try FanCtlHelperInstaller.reinstall()
                    }.value
                    FanCtlHelperClient.invalidateConnection()
                    try Task.checkCancellation()
                    try await waitForHelperAvailability()
                }
                helperState = .available
                helperProbeFailureCount = 0
                requiresHelperApproval = false
                setNotice(nil, source: .permission)
                setNotice(nil, source: .helper)

                if generation == controlGeneration {
                    let mutationSequence = FanCtlHelperClient.nextMutationSequence()
                    _ = await restoreAutomatic(
                        reason: "app launch reconciliation",
                        showsFailure: true,
                        expectedGeneration: generation,
                        mutationSequence: mutationSequence
                    )
                }
            } catch is CancellationError {
                // App shutdown.
            } catch InstallError.requiresApproval {
                helperState = .unavailable
                requiresHelperApproval = true
                setNotice(InstallError.requiresApproval.localizedDescription, source: .permission)
                didRequireHelperApproval?()
                NSLog("mFanCtl fan helper requires approval")
            } catch {
                helperState = .unavailable
                requiresHelperApproval = false
                setNotice(error.localizedDescription, source: .helper)
                NSLog("mFanCtl silent fan helper preparation failed: \(error.localizedDescription)")
            }
            helperPreparationTask = nil
        }
    }

    private func refreshHelperState(now: Date = Date()) {
        guard helperProbeTask == nil,
              helperState == .unknown || helperState == .available || helperState == .unavailable
        else {
            return
        }

        if requiresHelperApproval {
            if let nextHelperApprovalStatusCheckDate, now < nextHelperApprovalStatusCheckDate {
                return
            }
            nextHelperApprovalStatusCheckDate = now.addingTimeInterval(10)
            guard FanCtlHelperInstaller.serviceStatus == .enabled else {
                return
            }

            requiresHelperApproval = false
            nextHelperApprovalStatusCheckDate = nil
            helperProbeFailureCount = 0
            helperState = .unknown
            nextHelperProbeDate = nil
            FanCtlHelperClient.invalidateConnection()
        }

        if let nextHelperProbeDate, now < nextHelperProbeDate {
            return
        }

        helperProbeTask = Task { [weak self] in
            guard let self else {
                return
            }
            do {
                try await FanCtlHelperClient.waitUntilAvailable(timeout: 0.75)
                try Task.checkCancellation()
                helperProbeFailureCount = 0
                if helperState != .installing {
                    helperState = .available
                }
                requiresHelperApproval = false
                setNotice(nil, source: .permission)
                setNotice(nil, source: .helper)
                nextHelperProbeDate = Date().addingTimeInterval(30)
            } catch is CancellationError {
                // App shutdown.
            } catch {
                helperProbeFailureCount += 1
                let exponent = min(max(helperProbeFailureCount - 1, 0), 4)
                let retryDelay = min(4 * pow(2, Double(exponent)), 60)
                nextHelperProbeDate = Date().addingTimeInterval(retryDelay)
                if helperProbeFailureCount >= 3, helperState != .installing {
                    helperState = .unavailable
                    if !requiresHelperApproval {
                        setNotice(error.localizedDescription, source: .helper)
                    }
                }
            }
            helperProbeTask = nil
        }
    }

    private func reconcileObservedFanState(_ snapshot: SensorSnapshot) {
        guard controlTask == nil,
              safetyRecoveryTask == nil,
              helperPreparationTask == nil
        else {
            return
        }

        let modes = snapshot.fans.compactMap(\.mode)
        observedFanNeedsSafetyMonitoring =
            (!snapshot.fans.isEmpty && modes.count != snapshot.fans.count) ||
            modes.contains { $0 != 0 && $0 != 3 } ||
            (snapshot.fanTestMode != nil && snapshot.fanTestMode != 0)
        guard modes.count == snapshot.fans.count else {
            selectedPreset = nil
            setNotice(L10n.unknownFanModeDetected, source: .mode)
            return
        }

        if modes.allSatisfy({ $0 == 0 || $0 == 3 }) {
            if let fanTestMode = snapshot.fanTestMode, fanTestMode != 0 {
                selectedPreset = nil
                setNotice(L10n.fanTestModeActive, source: .mode)
                return
            }
            selectedPreset = .automatic
            if automaticRecoveryNoticePending {
                automaticRecoveryNoticePending = false
                setNotice(nil, source: .control)
            }
            setNotice(nil, source: .mode)
            return
        }

        guard modes.allSatisfy({ $0 == 1 }) else {
            selectedPreset = nil
            setNotice(L10n.unknownFanModeDetected, source: .mode)
            return
        }

        guard let selectedPreset, selectedPreset != .automatic else {
            self.selectedPreset = nil
            setNotice(L10n.manualFanModeDetected, source: .mode)
            return
        }

        switch selectedManualPresetMatchesSnapshot(selectedPreset, fans: snapshot.fans) {
        case .some(true):
            setNotice(nil, source: .mode)
        case .some(false):
            self.selectedPreset = nil
            setNotice(L10n.presetNoLongerApplied, source: .mode)
        case .none:
            self.selectedPreset = nil
            setNotice(L10n.unknownFanModeDetected, source: .mode)
        }
    }

    private func selectedManualPresetMatchesSnapshot(_ preset: FanPreset, fans: [FanSnapshot]) -> Bool? {
        switch preset {
        case .automatic:
            return false
        case .maximum:
            guard fans.allSatisfy({ $0.targetRPM != nil && $0.maximumRPM != nil }) else {
                return nil
            }
            return fans.allSatisfy { fan in
                guard let target = fan.targetRPM, let maximum = fan.maximumRPM else {
                    return false
                }
                return Self.rpmValuesMatch(target, maximum)
            }
        case .custom(let id):
            guard let requestedRPM = userPresets.first(where: { $0.id == id })?.rpm,
                  fans.allSatisfy({ $0.targetRPM != nil })
            else {
                return nil
            }
            return fans.allSatisfy { fan in
                guard let target = fan.targetRPM else {
                    return false
                }
                return Self.rpmValuesMatch(target, Double(requestedRPM))
            }
        }
    }

    private static func rpmValuesMatch(_ lhs: Double, _ rhs: Double) -> Bool {
        guard lhs.isFinite, rhs.isFinite else {
            return false
        }
        return abs(lhs - rhs) <= max(25, abs(rhs) * 0.02)
    }

    private func notifyChange(_ change: Change) {
        pendingChanges.formUnion(change)
        guard !changeNotificationScheduled, didChange != nil else {
            return
        }

        changeNotificationScheduled = true
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            await Task.yield()
            let changes = pendingChanges
            pendingChanges = []
            changeNotificationScheduled = false
            if !changes.isEmpty {
                didChange?(changes)
            }
        }
    }

    private func setNotice(_ message: String?, source: NoticeSource) {
        let normalized = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalized, !normalized.isEmpty {
            notices[source] = normalized
        } else {
            notices.removeValue(forKey: source)
        }

        let nextMessage = NoticeSource.allCases.compactMap { notices[$0] }.first
        if nextMessage != errorMessage {
            errorMessage = nextMessage
        }
    }

    private func waitForHelperAvailability(timeout: TimeInterval = 10.0) async throws {
        try await FanCtlHelperClient.waitUntilAvailable(timeout: timeout)
    }
}

struct UserFanPreset: Codable, Equatable {
    let id: UUID
    var name: String
    var rpm: Int
}

struct FanPresetEntry: Equatable {
    let preset: FanPreset
    let name: String
    let rpmText: String
    let isEditable: Bool
    let isDeletable: Bool

    var menuIdentifier: String {
        preset.menuIdentifier
    }
}

enum FanPreset: Hashable {
    case automatic
    case maximum
    case custom(UUID)

    init?(menuIdentifier: String) {
        switch menuIdentifier {
        case "automatic":
            self = .automatic
        case "maximum":
            self = .maximum
        default:
            guard menuIdentifier.hasPrefix("custom:") else {
                return nil
            }

            let rawID = String(menuIdentifier.dropFirst("custom:".count))
            guard let id = UUID(uuidString: rawID) else {
                return nil
            }
            self = .custom(id)
        }
    }

    var menuIdentifier: String {
        switch self {
        case .automatic:
            "automatic"
        case .maximum:
            "maximum"
        case .custom(let id):
            "custom:\(id.uuidString)"
        }
    }
}

enum HelperState: Equatable {
    case unknown
    case unavailable
    case installing
    case available
}

private enum FanCtlMenuError: LocalizedError {
    case smcUnavailable
    case noFans
    case missingPreset
    case invalidPresetRPM(ClosedRange<Int>)

    var errorDescription: String? {
        switch self {
        case .smcUnavailable:
            L10n.smcConnectionFailed
        case .noFans:
            L10n.noFansFound
        case .missingPreset:
            L10n.missingPreset
        case .invalidPresetRPM(let range):
            L10n.invalidRPMMessage(range: range)
        }
    }
}
