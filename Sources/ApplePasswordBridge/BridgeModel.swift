import AppKit
import Combine
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class BridgeModel: ObservableObject {
    @Published var monitoringEnabled: Bool {
        didSet { UserDefaults.standard.set(monitoringEnabled, forKey: Keys.monitoring) }
    }
    @Published var automaticFillEnabled: Bool {
        didSet { UserDefaults.standard.set(automaticFillEnabled, forKey: Keys.automaticFill) }
    }
    @Published var ocrFallbackEnabled: Bool {
        didSet { UserDefaults.standard.set(ocrFallbackEnabled, forKey: Keys.ocrFallback) }
    }
    @Published var fillSpeed: FillSpeed {
        didSet { UserDefaults.standard.set(fillSpeed.rawValue, forKey: Keys.fillSpeed) }
    }
    @Published var applicationRuleMode: ApplicationRuleMode {
        didSet { UserDefaults.standard.set(applicationRuleMode.rawValue, forKey: Keys.applicationRuleMode) }
    }
    @Published private(set) var allowlistedApplications: [TargetApplication]
    @Published private(set) var denylistedApplications: [TargetApplication]
    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    @Published private(set) var launchAtLogin = false
    @Published private(set) var statusText = "正在启动"
    @Published private(set) var isWorking = false

    private enum Keys {
        static let monitoring = "monitoringEnabled"
        static let automaticFill = "automaticFillEnabled"
        static let ocrFallback = "ocrFallbackEnabled"
        static let fillSpeed = "fillSpeed"
        static let applicationRuleMode = "applicationRuleMode"
        static let allowlistedApplications = "allowlistedApplications"
        static let denylistedApplications = "denylistedApplications"
    }

    private let codeReader = PasswordCodeReader()
    private let browserAutofill = BrowserAutofill()
    private var timer: Timer?
    private var hotKey: GlobalHotKey?
    private var currentCode: CapturedCode?
    private var lastSuccessfulCode: String?
    private var lastVisionAttempt = Date.distantPast
    private var scanInProgress = false
    private var manualRequestPending = false
    private var started = false

    init() {
        UserDefaults.standard.register(defaults: [
            Keys.monitoring: true,
            Keys.automaticFill: true,
            Keys.ocrFallback: true,
            Keys.fillSpeed: FillSpeed.reliable.rawValue,
            Keys.applicationRuleMode: ApplicationRuleMode.allowlist.rawValue
        ])
        monitoringEnabled = UserDefaults.standard.bool(forKey: Keys.monitoring)
        automaticFillEnabled = UserDefaults.standard.bool(forKey: Keys.automaticFill)
        ocrFallbackEnabled = UserDefaults.standard.bool(forKey: Keys.ocrFallback)
        fillSpeed = FillSpeed(
            rawValue: UserDefaults.standard.string(forKey: Keys.fillSpeed) ?? ""
        ) ?? .reliable
        applicationRuleMode = ApplicationRuleMode(
            rawValue: UserDefaults.standard.string(forKey: Keys.applicationRuleMode) ?? ""
        ) ?? .allowlist
        allowlistedApplications = Self.loadApplications(
            key: Keys.allowlistedApplications,
            fallback: [.firefox]
        )
        denylistedApplications = Self.loadApplications(
            key: Keys.denylistedApplications,
            fallback: []
        )
        Task { @MainActor [weak self] in
            self?.start()
        }
    }

    func start() {
        guard !started else { return }
        started = true
        refreshPermissions()
        if !accessibilityGranted {
            PermissionManager.requestAccessibility()
        }
        if !screenRecordingGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                PermissionManager.requestScreenRecording()
            }
        }
        refreshLaunchAtLogin()
        hotKey = GlobalHotKey { [weak self] in
            Task { @MainActor in
                await self?.fillNow()
            }
        }
        let hotKeyReady = hotKey?.start() == true
        statusText = hotKeyReady ? "等待 Apple 密码授权窗口" : "快捷键注册失败"

        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refreshPermissions()
                if self.monitoringEnabled && self.automaticFillEnabled {
                    await self.scanAndFill(manual: false)
                }
            }
        }
    }

    func fillNow() async {
        await scanAndFill(manual: true)
    }

    func requestAccessibility() {
        PermissionManager.requestAccessibility()
        statusText = "请在系统设置中允许辅助功能权限"
    }

    func requestScreenRecording() {
        PermissionManager.requestScreenRecording()
        refreshPermissions()
        statusText = screenRecordingGranted
            ? "录屏权限已允许"
            : "请在系统设置中允许屏幕与系统录音权限"
    }

    func openAccessibilitySettings() {
        PermissionManager.openAccessibilitySettings()
    }

    func openScreenRecordingSettings() {
        PermissionManager.openScreenRecordingSettings()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLaunchAtLogin()
        } catch {
            statusText = "登录启动设置失败：\(error.localizedDescription)"
            refreshLaunchAtLogin()
        }
    }

    var activeApplicationRules: [TargetApplication] {
        applicationRuleMode == .allowlist ? allowlistedApplications : denylistedApplications
    }

    func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "添加"
        panel.message = applicationRuleMode == .allowlist
            ? "选择允许自动填入的应用"
            : "选择禁止自动填入的应用"
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addApplication(at: url)
    }

    func removeApplication(_ application: TargetApplication) {
        if applicationRuleMode == .allowlist {
            allowlistedApplications.removeAll { $0.bundleIdentifier == application.bundleIdentifier }
            saveApplications(allowlistedApplications, key: Keys.allowlistedApplications)
        } else {
            denylistedApplications.removeAll { $0.bundleIdentifier == application.bundleIdentifier }
            saveApplications(denylistedApplications, key: Keys.denylistedApplications)
        }
    }

    private func scanAndFill(manual: Bool) async {
        guard !scanInProgress else {
            if manual { manualRequestPending = true }
            return
        }
        guard accessibilityGranted else {
            if manual { statusText = "需要辅助功能权限" }
            return
        }

        scanInProgress = true
        isWorking = true
        defer {
            scanInProgress = false
            isWorking = false
            if manualRequestPending {
                manualRequestPending = false
                Task { @MainActor [weak self] in
                    await self?.scanAndFill(manual: true)
                }
            }
        }

        let target: BrowserAutofill.Target
        do {
            target = try browserAutofill.locateTarget(policy: applicationPolicy)
        } catch {
            if manual { statusText = error.localizedDescription }
            return
        }

        var captured = codeReader.readUsingAccessibility()
        if captured == nil,
           ocrFallbackEnabled,
           screenRecordingGranted,
           manual || Date().timeIntervalSince(lastVisionAttempt) >= 0.25 {
            lastVisionAttempt = Date()
            captured = await codeReader.readUsingVision()
        }

        if let captured {
            currentCode = captured
        }
        guard let code = currentCode, code.isFresh() else {
            currentCode = nil
            if manual { statusText = "未发现有效的 Apple 密码验证码窗口" }
            return
        }
        guard manual || code.value != lastSuccessfulCode else { return }

        do {
            statusText = "已识别验证码，正在激活 \(target.application.localizedName ?? "目标应用")"
            try await browserAutofill.fill(code: code.value, target: target, speed: fillSpeed)
            lastSuccessfulCode = code.value
            currentCode = nil
            statusText = "已填入 \(target.application.localizedName ?? "目标应用")（\(code.source.rawValue)）"
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func refreshPermissions() {
        accessibilityGranted = PermissionManager.accessibilityGranted
        screenRecordingGranted = PermissionManager.screenRecordingGranted
    }

    private func refreshLaunchAtLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private var applicationPolicy: ApplicationRulePolicy {
        ApplicationRulePolicy(
            mode: applicationRuleMode,
            allowlist: Set(allowlistedApplications.map(\.bundleIdentifier)),
            denylist: Set(denylistedApplications.map(\.bundleIdentifier))
        )
    }

    private func addApplication(at url: URL) {
        guard let bundle = Bundle(url: url),
              let bundleIdentifier = bundle.bundleIdentifier,
              bundleIdentifier != "com.anti.ApplePasswordBridge" else {
            statusText = "所选项目不是有效的 macOS 应用"
            return
        }
        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let application = TargetApplication(
            bundleIdentifier: bundleIdentifier,
            displayName: displayName
        )

        if applicationRuleMode == .allowlist {
            allowlistedApplications.removeAll { $0.bundleIdentifier == bundleIdentifier }
            allowlistedApplications.append(application)
            allowlistedApplications.sort { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
            saveApplications(allowlistedApplications, key: Keys.allowlistedApplications)
        } else {
            denylistedApplications.removeAll { $0.bundleIdentifier == bundleIdentifier }
            denylistedApplications.append(application)
            denylistedApplications.sort { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
            saveApplications(denylistedApplications, key: Keys.denylistedApplications)
        }
    }

    private func saveApplications(_ applications: [TargetApplication], key: String) {
        guard let data = try? JSONEncoder().encode(applications) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func loadApplications(
        key: String,
        fallback: [TargetApplication]
    ) -> [TargetApplication] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let applications = try? JSONDecoder().decode([TargetApplication].self, from: data) else {
            return fallback
        }
        return applications
    }
}
