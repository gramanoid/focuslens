import AppKit
import Foundation
import ServiceManagement
import SwiftUI

enum CaptureIntervalOption: Double, CaseIterable, Identifiable {
    case thirtySeconds = 30
    case oneMinute = 60
    case twoMinutes = 120
    case fiveMinutes = 300

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .thirtySeconds: "30s"
        case .oneMinute: "1m"
        case .twoMinutes: "2m"
        case .fiveMinutes: "5m"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    enum CaptureStatus {
        case idle
        case capturing
        case classifying
        case warning
    }

    @Published var captureStatus: CaptureStatus = .idle
    @Published var serverReachable = false
    @Published var screenPermissionGranted = false
    @Published var healthCheckedAt: Date?
    @Published var isRunning: Bool
    @Published var captureInterval: CaptureIntervalOption
    @Published var serverBaseURLString: String
    @Published var keepScreenshots: Bool
    @Published var launchAtLogin: Bool
    @Published var excludedAppsText: String
    @Published var lastErrorMessage: String?
    @Published var recentEntries: [SessionRecord] = []
    @Published var todaySummary: [CategorySummary] = []
    @Published var todaySessionCount = 0
    @Published var showPermissionSheet = false
    @Published var showServerHelp = false
    @Published private(set) var isCaptureInFlight = false
    @Published var accessibilityPermissionGranted = false
    @Published var keystrokeTrackingEnabled: Bool
    @Published var selectedModel: ModelDefinition
    @Published var customModelPath: String
    @Published var customMmprojPath: String
    @Published var screenshotDirectoryPath: String

    let database: AppDatabase
    let llamaClient: LlamaCppClient
    let downloadManager = ModelDownloadManager()
    let serverProcess = ServerProcessManager()
    let keystrokeMonitor = KeystrokeMonitor()

    private let defaults: UserDefaults
    private var healthTask: Task<Void, Never>?
    private lazy var scheduler = CaptureScheduler(
        intervalProvider: { [weak self] in
            self?.captureInterval.rawValue ?? CaptureIntervalOption.oneMinute.rawValue
        },
        action: { [weak self] in
            await self?.runCaptureCycle()
        }
    )

    init(
        database: AppDatabase? = nil,
        llamaClient: LlamaCppClient = LlamaCppClient()
    ) {
        self.database = database ?? AppDatabase.makeDefault()
        self.llamaClient = llamaClient
        defaults = UserDefaults.standard
        isRunning = defaults.object(forKey: Keys.isRunning) as? Bool ?? true
        captureInterval = CaptureIntervalOption(rawValue: defaults.double(forKey: Keys.captureInterval)).map { $0 } ?? .oneMinute
        serverBaseURLString = defaults.string(forKey: Keys.serverBaseURL) ?? "http://localhost:8080"
        keepScreenshots = defaults.object(forKey: Keys.keepScreenshots) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        excludedAppsText = defaults.string(forKey: Keys.excludedApps) ?? ""

        keystrokeTrackingEnabled = defaults.object(forKey: Keys.keystrokeTrackingEnabled) as? Bool ?? true

        let savedModelID = defaults.string(forKey: Keys.selectedModelID) ?? "qwen2-vl-2b"
        selectedModel = ModelDefinition.find(id: savedModelID) ?? ModelDefinition.recommended[0]
        customModelPath = defaults.string(forKey: Keys.customModelPath) ?? ""
        customMmprojPath = defaults.string(forKey: Keys.customMmprojPath) ?? ""
        screenshotDirectoryPath = defaults.string(forKey: Keys.screenshotDirectory) ?? ""

        Task {
            await bootstrap()
        }
    }

    var serverBaseURL: URL? {
        URL(string: serverBaseURLString)
    }

    var excludedBundleIDs: Set<String> {
        Set(
            excludedAppsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    var activeModel: ModelDefinition {
        if selectedModel.id == "custom" {
            return ModelDefinition(
                id: "custom",
                displayName: "Custom",
                modelFileName: (customModelPath as NSString).lastPathComponent,
                mmprojFileName: (customMmprojPath as NSString).lastPathComponent,
                modelURL: selectedModel.modelURL,
                mmprojURL: selectedModel.mmprojURL,
                sizeDescription: "User-provided",
                qualityDescription: "User-provided",
                imageMinTokens: 1024,
                description: selectedModel.description,
                pros: selectedModel.pros,
                cons: selectedModel.cons
            )
        }
        return selectedModel
    }

    var serverStartCommand: String {
        let model = activeModel
        var cmd = "llama-server -m \(model.modelPath) --mmproj \(model.mmprojPath) --port 8080 -ngl 99"
        if model.imageMinTokens > 0 {
            cmd += " --image-min-tokens \(model.imageMinTokens)"
        }
        return cmd
    }

    var hasCapturedSessions: Bool {
        !recentEntries.isEmpty
    }

    var totalTrackedTimeToday: TimeInterval {
        todaySummary.reduce(0) { $0 + $1.duration }
    }

    var dominantCategoryToday: ActivityCategory? {
        todaySummary.max(by: { $0.duration < $1.duration })?.category
    }

    var lastCapturedAt: Date? {
        recentEntries.first?.timestamp
    }

    var setupCompletedSteps: Int {
        [screenPermissionGranted, serverReachable, hasCapturedSessions].filter { $0 }.count
    }

    var setupProgress: Double {
        Double(setupCompletedSteps) / 3.0
    }

    var needsOnboarding: Bool {
        !screenPermissionGranted || !serverReachable || !hasCapturedSessions
    }

    var isReadyForImmediateCapture: Bool {
        screenPermissionGranted && serverReachable && !isCaptureInFlight
    }

    var statusLabel: String {
        switch captureStatus {
        case .idle: "Idle"
        case .capturing: "Capturing"
        case .classifying: "Classifying"
        case .warning: "Warning"
        }
    }

    var statusSymbolName: String {
        switch captureStatus {
        case .idle: serverReachable ? "eye" : "exclamationmark.triangle.fill"
        case .capturing: "camera.circle.fill"
        case .classifying: "brain.head.profile"
        case .warning: "exclamationmark.triangle.fill"
        }
    }

    func bootstrap() async {
        refreshRecentEntries()
        refreshTodaySummary()
        refreshPermissionState()
        if let startupWarning = database.startupWarning {
            lastErrorMessage = startupWarning
        }
        showPermissionSheet = !screenPermissionGranted
        await checkServerHealth()

        // Auto-start server if model is ready and server isn't already running externally
        if !serverReachable && selectedModel.isDownloaded && serverProcess.isLlamaServerInstalled {
            serverProcess.start(model: selectedModel)
        }

        // Auto-start keystroke monitor if enabled and permitted
        if keystrokeTrackingEnabled && accessibilityPermissionGranted {
            keystrokeMonitor.start(excludedBundleIDs: excludedBundleIDs)
        }

        startHealthChecks()
        updateScheduler()
    }

    func toggleRunning() {
        isRunning.toggle()
        defaults.set(isRunning, forKey: Keys.isRunning)
        updateScheduler()
    }

    func updateCaptureInterval(_ option: CaptureIntervalOption) {
        captureInterval = option
        defaults.set(option.rawValue, forKey: Keys.captureInterval)
        updateScheduler()
    }

    func updateServerURL(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        serverBaseURLString = trimmed
        defaults.set(trimmed, forKey: Keys.serverBaseURL)
        Task { await checkServerHealth() }
    }

    func updateKeepScreenshots(_ enabled: Bool) {
        keepScreenshots = enabled
        defaults.set(enabled, forKey: Keys.keepScreenshots)
    }

    func updateExcludedApps(_ value: String) {
        excludedAppsText = value
        defaults.set(value, forKey: Keys.excludedApps)
        keystrokeMonitor.updateExcludedApps(excludedBundleIDs)
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        defaults.set(enabled, forKey: Keys.launchAtLogin)
        configureLaunchAtLogin(enabled)
    }

    func openDashboard() {
        dismissPopover()
        ActivityExplorerWindowController.shared.show(appState: self)
    }

    func openPreferences() {
        dismissPopover()
        PreferencesWindowController.shared.show(appState: self)
    }

    /// Closes the MenuBarExtra popover panel so the newly opened window takes focus.
    func dismissPopover() {
        // MenuBarExtra(.window) creates an NSPanel that becomes keyWindow.
        // Closing it collapses the menu bar popover.
        if let panel = NSApp.keyWindow, panel is NSPanel {
            panel.close()
        }
    }

    func refreshRecentEntries() {
        recentEntries = (try? database.fetchRecentSessions(limit: 3)) ?? []
    }

    func refreshTodaySummary() {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? .now
        let interval = DateInterval(start: start, end: end)
        let sessions = (try? database.fetchSessions(in: interval)) ?? []
        todaySessionCount = sessions.count
        todaySummary = AnalysisAggregator.categorySummaries(for: AnalysisAggregator.blocks(from: sessions))
    }

    func requestScreenPermission() {
        showPermissionSheet = !ScreenCapture.requestPermission()
        refreshPermissionState()
    }

    func dismissPermissionSheet() {
        showPermissionSheet = false
    }

    func copyServerCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(serverStartCommand, forType: .string)
    }

    func triggerCaptureNow() {
        Task {
            await runCaptureCycle(manual: true)
        }
    }

    func refreshPermissionState() {
        screenPermissionGranted = ScreenCapture.hasPermission()
        let wasAccessibilityGranted = accessibilityPermissionGranted
        accessibilityPermissionGranted = KeystrokeMonitor.hasAccessibilityPermission()
        if screenPermissionGranted && showPermissionSheet {
            showPermissionSheet = false
        }
        // Auto-start keystroke monitor when permission is newly granted
        if !wasAccessibilityGranted && accessibilityPermissionGranted && keystrokeTrackingEnabled && !keystrokeMonitor.isMonitoring {
            keystrokeMonitor.start(excludedBundleIDs: excludedBundleIDs)
        }
    }

    func requestAccessibilityPermission() {
        KeystrokeMonitor.requestAccessibilityPermission()
        refreshPermissionState()
    }

    func updateKeystrokeTracking(_ enabled: Bool) {
        keystrokeTrackingEnabled = enabled
        defaults.set(enabled, forKey: Keys.keystrokeTrackingEnabled)
        if enabled && accessibilityPermissionGranted {
            keystrokeMonitor.start(excludedBundleIDs: excludedBundleIDs)
        } else {
            keystrokeMonitor.stop()
        }
    }

    func checkServerHealth() async {
        guard let baseURL = serverBaseURL else {
            serverReachable = false
            captureStatus = .warning
            return
        }
        serverReachable = await llamaClient.health(baseURL: baseURL)
        healthCheckedAt = .now
        if !serverReachable {
            captureStatus = .warning
        } else if captureStatus == .warning {
            captureStatus = .idle
        }
    }

    private func startHealthChecks() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkServerHealth()
                do {
                    try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                } catch {
                    break // CancellationError — exit cleanly
                }
            }
        }
    }

    private func updateScheduler() {
        if isRunning {
            scheduler.start()
        } else {
            scheduler.stop()
            captureStatus = serverReachable ? .idle : .warning
        }
    }

    private func configureLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func guessCategoryForBlankCapture(bundleID: String?) -> ActivityCategory {
        guard let bundleID = bundleID?.lowercased() else { return .other }
        let communicationBundles = [
            "org.telegram", "net.whatsapp", "com.facebook.messenger",
            "com.tinyspeck.slackmacgap", "us.zoom", "com.microsoft.teams",
            "com.apple.MobileSMS", "com.apple.FaceTime", "com.skype",
            "com.discord", "com.viber"
        ]
        if communicationBundles.contains(where: { bundleID.hasPrefix($0) }) {
            return .communication
        }
        return .other
    }

    private func runCaptureCycle(manual: Bool = false) async {
        guard !isCaptureInFlight else { return }
        guard manual || isRunning else { return }
        refreshPermissionState()
        guard screenPermissionGranted else {
            showPermissionSheet = true
            captureStatus = .warning
            return
        }
        guard let baseURL = serverBaseURL else {
            captureStatus = .warning
            return
        }
        guard serverReachable else {
            captureStatus = .warning
            return
        }

        isCaptureInFlight = true
        defer { isCaptureInFlight = false }

        do {
            captureStatus = .capturing

            // Flush keystroke buffer before capture
            let keystrokeSegments = keystrokeMonitor.flush()
            let keystrokeContext = Self.buildKeystrokeContext(from: keystrokeSegments)

            let customDir = screenshotDirectoryPath.isEmpty ? nil : screenshotDirectoryPath
            let payload = try ScreenCapture.capture(screenshotDirectory: customDir)
            if let bundleID = payload.activeBundleID, excludedBundleIDs.contains(bundleID) {
                if !keepScreenshots {
                    try? FileManager.default.removeItem(at: payload.screenshotURL)
                }
                captureStatus = .idle
                return
            }

            var screenshotPath: String? = payload.screenshotURL.path
            if !keepScreenshots {
                try? FileManager.default.removeItem(at: payload.screenshotURL)
                screenshotPath = nil
            }

            let session: SessionRecord
            if payload.isBlankCapture {
                let appName = AppIconResolver.displayName(for: payload.activeBundleID, fallback: payload.activeAppName)
                let category = guessCategoryForBlankCapture(bundleID: payload.activeBundleID)
                session = SessionRecord(
                    timestamp: payload.timestamp,
                    app: appName,
                    bundleID: payload.activeBundleID,
                    category: category,
                    task: "Screen content obscured by \(appName)",
                    confidence: 0.7,
                    screenshotPath: screenshotPath,
                    rawResponse: nil
                )
            } else {
                captureStatus = .classifying
                let result = try await llamaClient.classifyImage(
                    payload.resizedPNGData,
                    baseURL: baseURL,
                    frontmostAppName: payload.activeAppName,
                    frontmostBundleID: payload.activeBundleID,
                    keystrokeContext: keystrokeContext
                )
                session = SessionRecord(
                    timestamp: payload.timestamp,
                    app: AppIconResolver.displayName(for: payload.activeBundleID, fallback: payload.activeAppName),
                    bundleID: payload.activeBundleID,
                    category: result.category,
                    task: result.task,
                    confidence: result.confidence,
                    screenshotPath: screenshotPath,
                    rawResponse: result.rawResponse
                )
            }
            let savedSession = try database.saveSession(session)

            // Save keystroke records linked to this session
            if let sessionID = savedSession.id, !keystrokeSegments.isEmpty {
                let records = keystrokeSegments.map { segment in
                    KeystrokeRecord(
                        sessionID: sessionID,
                        timestamp: segment.startTime,
                        app: segment.app,
                        bundleID: segment.bundleID,
                        typedText: segment.text,
                        keystrokeCount: segment.keystrokeCount
                    )
                }
                try? database.saveKeystrokes(records)
            }

            refreshRecentEntries()
            refreshTodaySummary()
            captureStatus = .idle
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            captureStatus = serverReachable ? .idle : .warning
        }
    }

    func selectModel(_ model: ModelDefinition) {
        selectedModel = model
        defaults.set(model.id, forKey: Keys.selectedModelID)
        if model.isDownloaded && serverProcess.isLlamaServerInstalled {
            serverProcess.restart(model: model)
        }
    }

    func updateCustomModelPath(_ path: String) {
        customModelPath = path
        defaults.set(path, forKey: Keys.customModelPath)
    }

    func updateCustomMmprojPath(_ path: String) {
        customMmprojPath = path
        defaults.set(path, forKey: Keys.customMmprojPath)
    }

    func updateScreenshotDirectory(_ path: String) {
        screenshotDirectoryPath = path
        defaults.set(path, forKey: Keys.screenshotDirectory)
    }

    func downloadAndStartModel(_ model: ModelDefinition) {
        Task {
            await downloadManager.download(model)
            if downloadManager.status == .complete && serverProcess.isLlamaServerInstalled {
                serverProcess.start(model: model)
            }
        }
    }

    func startServer() {
        serverProcess.start(model: activeModel)
    }

    func stopServer() {
        serverProcess.stop()
    }

    static func buildKeystrokeContext(from segments: [KeystrokeSegment]) -> String? {
        guard !segments.isEmpty else { return nil }
        var lines: [String] = ["Keystroke activity since last capture:"]
        for segment in segments {
            let preview = String(segment.text.prefix(500))
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: "")
            lines.append("- [\(segment.app)] \(segment.keystrokeCount) keystrokes: \"\(preview)\"")
        }
        lines.append("Use this typed text alongside the screenshot to determine what the user is doing.")
        return lines.joined(separator: "\n")
    }

    private enum Keys {
        static let isRunning = "focuslens.isRunning"
        static let captureInterval = "focuslens.captureInterval"
        static let serverBaseURL = "focuslens.serverBaseURL"
        static let keepScreenshots = "focuslens.keepScreenshots"
        static let launchAtLogin = "focuslens.launchAtLogin"
        static let excludedApps = "focuslens.excludedApps"
        static let selectedModelID = "focuslens.selectedModelID"
        static let customModelPath = "focuslens.customModelPath"
        static let customMmprojPath = "focuslens.customMmprojPath"
        static let screenshotDirectory = "focuslens.screenshotDirectory"
        static let keystrokeTrackingEnabled = "focuslens.keystrokeTrackingEnabled"
    }
}
