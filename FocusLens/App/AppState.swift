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
    @Published var screenshotRetentionDays: Int
    @Published var idleThresholdMinutes: Int
    @Published var isUserIdle = false
    @Published var journalDirectoryPath: String
    @Published var autoJournalEnabled: Bool

    let database: AppDatabase
    let llamaClient: LlamaCppClient
    let downloadManager = ModelDownloadManager()
    let serverProcess = ServerProcessManager()
    let keystrokeMonitor = KeystrokeMonitor()
    let updater = AppUpdater()

    // Intelligence engines
    let embeddingClient: GeminiEmbeddingClient
    lazy var clusteringEngine = ProjectClusteringEngine(database: database, embeddingClient: embeddingClient)
    lazy var anomalyEngine = AnomalyDetectionEngine(database: database)
    lazy var briefingGenerator = MorningBriefingGenerator(database: database)
    lazy var semanticSearch = SemanticSearchEngine(database: database, embeddingClient: embeddingClient)

    private let defaults: UserDefaults
    private var healthTask: Task<Void, Never>?
    private var screenshotCleanupTask: Task<Void, Never>?
    private var autoExportTask: Task<Void, Never>?
    private var intelligenceTask: Task<Void, Never>?
    private var embeddingBackfillTask: Task<Void, Never>?
    private var lastScreenshotHash: UInt64?
    private var hasVerifiedScreenCaptureAccess = false
    private var sleepStartedAt: Date?
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
        self.embeddingClient = GeminiEmbeddingClient(apiKey: Self.geminiAPIKey)
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
        screenshotRetentionDays = defaults.object(forKey: Keys.screenshotRetentionDays) as? Int ?? 1
        idleThresholdMinutes = defaults.object(forKey: Keys.idleThresholdMinutes) as? Int ?? 2
        journalDirectoryPath = defaults.string(forKey: Keys.journalDirectory) ?? "~/Documents/FocusLens/journals"
        autoJournalEnabled = defaults.object(forKey: Keys.autoJournalEnabled) as? Bool ?? false

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
        // Never auto-show permission sheet on boot — the setup steps in the
        // menu bar popover handle permission granting without modal interruption.
        await checkServerHealth()

        // Auto-start server if model is ready and server isn't already running externally
        if !serverReachable && selectedModel.isDownloaded && serverProcess.isLlamaServerInstalled {
            serverProcess.start(model: selectedModel)
        }

        // Auto-start keystroke monitor if enabled and permitted
        if keystrokeTrackingEnabled && accessibilityPermissionGranted {
            keystrokeMonitor.start(excludedBundleIDs: excludedBundleIDs)
        }

        cleanupOldScreenshots()
        startScreenshotCleanupTimer()
        startAutoExportTimer()
        startIntelligencePipeline()
        startHealthChecks()
        updateScheduler()
        startSleepWakeObserver()
        startQuitObserver()
        startReanalysisTimer()
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
        ScreenCapture.openPrivacySettings()
        // Refresh after delay in case permission was already granted
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            refreshPermissionState()
        }
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
        let preflightGranted = ScreenCapture.hasPermission()
        if preflightGranted {
            hasVerifiedScreenCaptureAccess = true
        }
        screenPermissionGranted = hasVerifiedScreenCaptureAccess || preflightGranted
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
        KeystrokeMonitor.openAccessibilitySettings()
        // Refresh after a delay to catch if permission was already granted
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            refreshPermissionState()
        }
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

    /// Maps well-known bundle ID prefixes to their definitive category.
    /// Used for blank captures and as a fallback when the model misclassifies.
    private static let knownAppCategories: [(prefix: String, category: ActivityCategory)] = [
        // Communication — messaging, video calls
        ("ru.keepcoder.Telegram", .communication),
        ("net.whatsapp", .communication),
        ("com.facebook.messenger", .communication),
        ("com.tinyspeck.slackmacgap", .communication),
        ("us.zoom", .communication),
        ("com.apple.MobileSMS", .communication),
        ("com.apple.FaceTime", .communication),
        ("com.skype", .communication),
        ("com.hnc.Discord", .communication),
        ("com.viber", .communication),
        ("com.apple.mail", .communication),
        ("com.apple.mobilephone", .communication),

        // Work — office apps, email, enterprise tools
        ("com.microsoft.teams", .work),
        ("com.microsoft.Outlook", .work),
        ("com.microsoft.Excel", .work),
        ("com.microsoft.Powerpoint", .work),

        // Coding — editors, terminals, dev tools
        ("com.microsoft.VSCode", .coding),
        ("com.apple.dt.Xcode", .coding),
        ("com.sublimetext", .coding),
        ("com.jetbrains", .coding),
        ("com.googlecode.iterm2", .coding),
        ("com.mitchellh.ghostty", .coding),
        ("net.kovidgoyal.kitty", .coding),
        ("co.zeit.hyper", .coding),
        ("com.apple.Terminal", .coding),
        ("dev.warp.Warp", .coding),
        ("com.github.GitHubClient", .coding),
        ("abnerworks.Typora", .coding),
        ("com.openai.codex", .coding),
        ("tonyapp.devutils", .coding),
        ("com.apple.ScriptEditor2", .coding),
        ("com.pvncher.repoprompt", .coding),
        ("com.apple.Automator", .coding),
        ("com.apple.shortcuts", .coding),

        // Browsing — web browsers
        ("com.google.Chrome", .browsing),
        ("com.apple.Safari", .browsing),
        ("org.mozilla.firefox", .browsing),
        ("com.brave.Browser", .browsing),
        ("company.thebrowser.Browser", .browsing),
        ("com.operasoftware.Opera", .browsing),
        ("com.microsoft.edgemac", .browsing),

        // Design — creative tools
        ("com.figma.Desktop", .design),
        ("com.bohemiancoding.sketch3", .design),
        ("com.adobe.Photoshop", .design),
        ("com.adobe.illustrator", .design),
        ("com.apple.freeform", .design),
        ("cc.ffitch.shottr", .other),

        // Media — music, video, podcasts, photos
        ("com.spotify.client", .media),
        ("com.apple.Music", .media),
        ("com.apple.TV", .media),
        ("com.google.android.youtube", .media),
        ("org.videolan.vlc", .media),
        ("com.apple.QuickTimePlayerX", .media),
        ("com.apple.Photos", .media),
        ("com.apple.PhotoBooth", .media),
        ("com.apple.podcasts", .media),
        ("com.apple.VoiceMemos", .media),
        ("com.obsproject.obs-studio", .media),
        ("com.apple.Image_Capture", .media),

        // Writing — documents, text editing
        ("com.microsoft.Word", .writing),
        ("com.apple.iWork.Pages", .writing),
        ("com.apple.iWork.Numbers", .writing),
        ("com.apple.iWork.Keynote", .writing),
        ("com.apple.TextEdit", .writing),
        ("org.libreoffice", .writing),
        ("com.apple.Stickies", .writing),
        ("com.benjitaylor.Readout", .writing),
        ("ai.plaud.desktop", .writing),

        // Note Taking — knowledge management
        ("md.obsidian", .noteTaking),
        ("com.apple.Notes", .noteTaking),
        ("com.notion.Notion", .noteTaking),

        // Productivity — task management, scheduling, file sync
        ("com.apple.reminders", .productivity),
        ("com.apple.iCal", .productivity),
        ("com.google.drivefs", .productivity),

        // AI — AI assistants and local model tools
        ("com.anthropic.claudefordesktop", .ai),
        ("com.openai.chat", .ai),
        ("ai.elementlabs.lmstudio", .ai),
        ("im.manus.desktop", .ai),
        ("computer.pinokio", .ai),

        // Other — system utilities (genuinely miscellaneous)
        ("com.apple.systempreferences", .other),
        ("com.apple.SystemPreferences", .other),
        ("com.apple.finder", .other),
        ("com.apple.ActivityMonitor", .other),
        ("com.apple.Preview", .other),
        ("com.apple.DiskUtility", .other),
        ("com.apple.Passwords", .other),
        ("com.apple.SystemProfiler", .other),
        ("com.apple.Console", .other),
        ("com.apple.AppStore", .other),
        ("com.binarynights.ForkLift", .other),
        ("net.freemacsoft.AppCleaner", .other),
        ("com.raycast.macos", .other),
        ("com.bitwarden.desktop", .other),
        ("eu.exelban.Stats", .other),
        ("com.lwouis.alt-tab-macos", .other),
        ("com.knollsoft.Rectangle", .other),
        ("com.if.Amphetamine", .other),
        ("io.tailscale.ipn", .other),
        ("com.express.vpn", .other),
        ("com.aone.keka", .other),
        ("io.ganeshrvel.openmtp", .other),
        ("pro.betterdisplay", .other),
        ("com.apple.calculator", .other),
        ("com.apple.Maps", .other),
        ("com.apple.weather", .other),
        ("com.apple.stocks", .other),
        ("com.apple.news", .browsing),
        ("com.apple.Home", .other),
        ("com.apple.findmy", .other),
        ("com.apple.ScreenSharing", .communication),

        // Library — ebook management, reading
        ("net.kovidgoyal.calibre", .library),
        ("com.calibre-ebook", .library),
        ("com.apple.iBooksX", .library),
    ]

    private func knownCategory(for bundleID: String?) -> ActivityCategory? {
        guard let bundleID = bundleID else { return nil }
        return Self.knownAppCategories.first(where: { bundleID.hasPrefix($0.prefix) })?.category
    }

    private func guessCategoryForBlankCapture(bundleID: String?) -> ActivityCategory {
        knownCategory(for: bundleID) ?? .other
    }

    private func runCaptureCycle(manual: Bool = false) async {
        guard !isCaptureInFlight else { return }
        guard manual || isRunning else { return }
        refreshPermissionState()
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

        // Skip capture when user is idle (no keyboard/mouse activity).
        // This prevents duplicate screenshots when caffeine apps keep the screen on.
        let idleSeconds = Self.userIdleSeconds()
        let threshold = Double(idleThresholdMinutes) * 60
        if !manual && threshold > 0 && idleSeconds >= threshold {
            isUserIdle = true
            captureStatus = .idle
            return
        }
        isUserIdle = false

        do {
            captureStatus = .capturing

            // Flush keystroke buffer before capture
            let keystrokeSegments = keystrokeMonitor.flush()
            let keystrokeContext = Self.buildKeystrokeContext(from: keystrokeSegments)

            let customDir = screenshotDirectoryPath.isEmpty ? nil : screenshotDirectoryPath
            let payload = try ScreenCapture.capture(screenshotDirectory: customDir)
            hasVerifiedScreenCaptureAccess = true
            screenPermissionGranted = true
            if showPermissionSheet {
                showPermissionSheet = false
            }

            // Skip system processes that should never be tracked
            let systemSkipList: Set<String> = [
                "com.apple.loginwindow",
                "com.apple.SecurityAgent",
                "com.apple.screensaver",
                "com.apple.ScreenSaver.Engine",
                "com.apple.UserNotificationCenter"
            ]
            let shouldSkip = {
                if let bundleID = payload.activeBundleID {
                    return excludedBundleIDs.contains(bundleID) || systemSkipList.contains(bundleID)
                }
                // loginwindow has no bundle ID in some contexts — check app name
                return payload.activeAppName.lowercased() == "loginwindow"
            }()

            if shouldSkip {
                if !keepScreenshots {
                    try? FileManager.default.removeItem(at: payload.screenshotURL)
                }
                captureStatus = .idle
                return
            }

            // pHash deduplication: skip classification if screenshot is near-identical to previous
            if !manual, let currentHash = PerceptualHash.hash(from: payload.resizedPNGData) {
                if let lastHash = lastScreenshotHash,
                   PerceptualHash.distance(currentHash, lastHash) < 5 {
                    if !keepScreenshots {
                        try? FileManager.default.removeItem(at: payload.screenshotURL)
                    }
                    captureStatus = .idle
                    return
                }
                lastScreenshotHash = currentHash
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
                // Use known-app category if available, otherwise trust the model
                let finalCategory = knownCategory(for: payload.activeBundleID) ?? result.category
                session = SessionRecord(
                    timestamp: payload.timestamp,
                    app: AppIconResolver.displayName(for: payload.activeBundleID, fallback: payload.activeAppName),
                    bundleID: payload.activeBundleID,
                    category: finalCategory,
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

            if !defaults.bool(forKey: Keys.hasCompletedFirstCapture) {
                defaults.set(true, forKey: Keys.hasCompletedFirstCapture)
            }
            refreshRecentEntries()
            refreshTodaySummary()
            captureStatus = .idle
            lastErrorMessage = nil
        } catch {
            if case ScreenCaptureError.permissionDenied = error {
                hasVerifiedScreenCaptureAccess = false
                screenPermissionGranted = false
                showPermissionSheet = true
                captureStatus = .warning
                lastErrorMessage = error.localizedDescription
                return
            }
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

    func updateScreenshotRetention(_ days: Int) {
        screenshotRetentionDays = days
        defaults.set(days, forKey: Keys.screenshotRetentionDays)
    }

    func updateIdleThreshold(_ minutes: Int) {
        idleThresholdMinutes = minutes
        defaults.set(minutes, forKey: Keys.idleThresholdMinutes)
    }

    func updateJournalDirectory(_ path: String) {
        journalDirectoryPath = path
        defaults.set(path, forKey: Keys.journalDirectory)
    }

    func updateAutoJournal(_ enabled: Bool) {
        autoJournalEnabled = enabled
        defaults.set(enabled, forKey: Keys.autoJournalEnabled)
        if enabled {
            startAutoExportTimer()
        } else {
            autoExportTask?.cancel()
            autoExportTask = nil
        }
    }

    func preparedJournalDirectoryURL() -> URL? {
        let trimmedPath = journalDirectoryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return nil }
        let fileManager = FileManager.default

        let directory = URL(
            fileURLWithPath: NSString(string: trimmedPath).expandingTildeInPath,
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  fileManager.isWritableFile(atPath: directory.path) else {
                return nil
            }
            return directory
        }
    }

    func generateJournalOnQuit() {
        guard autoJournalEnabled, let dir = preparedJournalDirectoryURL() else { return }
        let generator = WorkJournalGenerator(database: database)
        _ = try? generator.writeJournal(for: .now, to: dir, captureInterval: captureInterval.rawValue)
        runAutoDataExport()
    }

    func cleanupOldScreenshots() {
        guard keepScreenshots, screenshotRetentionDays > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(screenshotRetentionDays) * 86400)
        let fm = FileManager.default
        guard let dir = try? ImageHelpers.screenshotsDirectory(customPath: screenshotDirectoryPath.isEmpty ? nil : screenshotDirectoryPath) else { return }
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else { return }
        var deletedCount = 0
        for file in files where file.pathExtension == "png" {
            guard let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
                  let created = attrs.creationDate,
                  created < cutoff else { continue }
            try? fm.removeItem(at: file)
            deletedCount += 1
        }
        if deletedCount > 0 {
            // Clear screenshot_path references in old sessions
            try? database.dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE sessions SET screenshot_path = NULL WHERE timestamp < ?",
                    arguments: [cutoff.timeIntervalSince1970]
                )
            }
        }
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
        // Poll health quickly after start so the UI updates without waiting 30s
        Task {
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await checkServerHealth()
                if serverReachable { break }
            }
        }
    }

    func stopServer() {
        serverProcess.stop()
    }

    // MARK: - Periodic Screenshot Cleanup

    private func startScreenshotCleanupTimer() {
        screenshotCleanupTask?.cancel()
        screenshotCleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 24 * 3600 * 1_000_000_000)
                } catch { break }
                await self?.cleanupOldScreenshots()
            }
        }
    }

    // MARK: - Auto JSON Export

    private func startAutoExportTimer() {
        autoExportTask?.cancel()
        autoExportTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 24 * 3600 * 1_000_000_000)
                } catch { break }
                await self?.runAutoDataExport()
            }
        }
    }

    @MainActor
    func runAutoDataExport() {
        guard autoJournalEnabled, let dir = preparedJournalDirectoryURL() else { return }

        let calendar = Calendar.current
        let now = Date()
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let interval = DateInterval(start: dayStart, end: dayEnd)

        let sessions = (try? database.fetchSessions(in: interval)) ?? []
        let keystrokes = (try? database.fetchKeystrokes(in: interval)) ?? []
        let analyses = (try? database.fetchAnalyses(limit: 100)) ?? []
        let relevantAnalyses = analyses.filter { $0.dateRangeStart <= dayEnd && $0.dateRangeEnd >= dayStart }

        // Intelligence data
        let projects = (try? database.fetchProjects(in: interval)) ?? []
        let snapshots = (try? database.fetchDailySnapshots(limit: 30)) ?? []
        let anomalies = (try? database.fetchAnomalyEvents(since: calendar.date(byAdding: .day, value: -7, to: now) ?? now)) ?? []

        guard !sessions.isEmpty else { return }

        // Build session-project assignments for today's sessions
        var sessionProjectMap: [Int64: [Int64]] = [:]
        for session in sessions {
            if let sessionID = session.id {
                let projectIDs = (try? database.fetchProjectIDsForSession(sessionID: sessionID)) ?? []
                if !projectIDs.isEmpty {
                    sessionProjectMap[sessionID] = projectIDs
                }
            }
        }

        let iso = ISO8601DateFormatter()

        let payload: [String: Any] = [
            "date": Self.dateOnlyFormatter.string(from: now),
            "generated_at": iso.string(from: now),
            "schema_version": 2,

            "sessions": sessions.map { session -> [String: Any] in
                var dict: [String: Any] = [
                    "id": session.id as Any,
                    "timestamp": iso.string(from: session.timestamp),
                    "app": session.app,
                    "bundle_id": session.bundleID as Any,
                    "category": session.category.rawValue,
                    "task": session.task,
                    "confidence": session.confidence,
                    "screenshot_path": session.screenshotPath as Any
                ]
                if let sessionID = session.id, let projectIDs = sessionProjectMap[sessionID] {
                    dict["project_ids"] = projectIDs
                }
                return dict
            },

            "keystrokes": keystrokes.map { [
                "id": $0.id as Any,
                "session_id": $0.sessionID,
                "timestamp": iso.string(from: $0.timestamp),
                "app": $0.app,
                "bundle_id": $0.bundleID as Any,
                "typed_text": $0.typedText,
                "keystroke_count": $0.keystrokeCount
            ] },

            "analyses": relevantAnalyses.map { [
                "id": $0.id as Any,
                "timestamp": iso.string(from: $0.timestamp),
                "type": $0.type.rawValue,
                "date_range_start": iso.string(from: $0.dateRangeStart),
                "date_range_end": iso.string(from: $0.dateRangeEnd),
                "prompt": $0.prompt,
                "response": $0.response
            ] },

            "projects": projects.map { [
                "id": $0.id as Any,
                "name": $0.name,
                "first_seen": iso.string(from: $0.firstSeen),
                "last_seen": iso.string(from: $0.lastSeen),
                "total_duration_seconds": $0.totalDuration,
                "dominant_apps": $0.dominantApps,
                "category_distribution": $0.categoryDistribution,
                "session_count": $0.sessionCount
            ] },

            "daily_snapshots": snapshots.map { [
                "date": Self.dateOnlyFormatter.string(from: $0.date),
                "focus_score": $0.focusScore,
                "deep_work_minutes": $0.deepWorkMinutes,
                "reactive_minutes": $0.reactiveMinutes,
                "context_switches": $0.contextSwitches,
                "top_app": $0.topApp as Any,
                "top_category": $0.topCategory as Any,
                "session_count": $0.sessionCount,
                "keystroke_count": $0.keystrokeCount
            ] },

            "anomalies": anomalies.map { [
                "id": $0.id as Any,
                "timestamp": iso.string(from: $0.timestamp),
                "metric": $0.metric,
                "value": $0.value,
                "baseline_mean": $0.baselineMean,
                "baseline_stddev": $0.baselineStddev,
                "sigma": $0.sigma,
                "severity": $0.severity,
                "message": $0.message
            ] }
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }
        let filename = Self.dateOnlyFormatter.string(from: now) + ".json"
        let fileURL = dir.appendingPathComponent(filename)
        try? jsonData.write(to: fileURL, options: .atomic)
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Re-analysis of Low-Quality Sessions

    func runReanalysis() {
        guard serverReachable, let baseURL = serverBaseURL else { return }
        Task {
            guard let sessions = try? database.fetchLowQualitySessions(limit: 10) else { return }
            for session in sessions {
                guard let path = session.screenshotPath,
                      FileManager.default.fileExists(atPath: path),
                      let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                      let resized = ImageHelpers.resizedPNGData(from: image) else { continue }

                do {
                    let result = try await llamaClient.classifyImage(
                        resized,
                        baseURL: baseURL,
                        frontmostAppName: session.app,
                        frontmostBundleID: session.bundleID
                    )
                    let finalCategory = knownCategory(for: session.bundleID) ?? result.category
                    guard let sessionID = session.id else { continue }
                    try database.updateSession(
                        id: sessionID,
                        category: finalCategory.rawValue,
                        task: result.task,
                        confidence: result.confidence,
                        rawResponse: result.rawResponse
                    )
                } catch {
                    continue
                }
            }
            refreshRecentEntries()
            refreshTodaySummary()
        }
    }

    // MARK: - Intelligence Pipeline

    private func startIntelligencePipeline() {
        // Backfill daily snapshots for all historical days
        try? anomalyEngine.backfillSnapshots()
        // Run project clustering on existing data
        try? clusteringEngine.clusterAll()
        // Backfill embeddings for sessions that don't have them yet
        startEmbeddingBackfill()

        // Run intelligence cycle every 6 hours:
        // - Re-cluster projects
        // - Compute today's snapshot
        // - Check for anomalies
        intelligenceTask?.cancel()
        intelligenceTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 6 * 3600 * 1_000_000_000)
                } catch { break }
                guard let self else { break }
                try? self.clusteringEngine.clusterAll()
                try? self.anomalyEngine.computeAndStoreSnapshot(for: .now)
                try? self.anomalyEngine.checkForAnomalies()
            }
        }
    }

    private func startEmbeddingBackfill() {
        embeddingBackfillTask?.cancel()
        embeddingBackfillTask = Task { [weak self] in
            guard let self else { return }
            // Process embeddings in batches of 20 to avoid API rate limits
            while !Task.isCancelled {
                guard let sessions = try? self.database.fetchSessionsWithoutEmbeddings(limit: 20),
                      !sessions.isEmpty else { break }

                let texts = sessions.map { "\($0.app): \($0.task)" }
                do {
                    let embeddings = try await self.embeddingClient.embedBatch(texts: texts)
                    for (session, embedding) in zip(sessions, embeddings) where embedding.count > 0 {
                        if let sessionID = session.id {
                            let data = GeminiEmbeddingClient.serialize(embedding)
                            try self.database.saveEmbedding(sessionID: sessionID, embedding: data, dimensions: embedding.count)
                        }
                    }
                } catch {
                    // Rate limited or API error — wait and retry
                    try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                }
                // Small delay between batches
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// Generate and store a morning briefing using the AI pipeline.
    func generateMorningBriefing() {
        guard let baseURL = serverBaseURL, serverReachable else { return }

        Task {
            do {
                let context = try briefingGenerator.buildBriefingPrompt()
                guard !context.isEmpty else { return }

                let systemPrompt = briefingGenerator.systemPrompt
                let now = Date()
                let calendar = Calendar.current
                let todayStart = calendar.startOfDay(for: now)
                let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart

                var collected = ""
                for try await token in llamaClient.streamAnalysis(
                    systemPrompt: systemPrompt,
                    userPrompt: context,
                    baseURL: baseURL
                ) {
                    collected += token
                }

                if !collected.isEmpty {
                    let formatted = AnalysisResponseFormatter.sanitize(collected)
                    let record = AnalysisRecord(
                        type: .morningBriefing,
                        dateRangeStart: todayStart,
                        dateRangeEnd: todayEnd,
                        prompt: context,
                        response: formatted
                    )
                    _ = try database.saveAnalysis(record)
                }
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }

    private func startReanalysisTimer() {
        Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 3 * 3600 * 1_000_000_000) // Every 3 hours
                } catch { break }
                runReanalysis()
            }
        }
    }

    // MARK: - Quit Observer (Journal)

    private func startQuitObserver() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.generateJournalOnQuit()
        }
    }

    // MARK: - Sleep / Wake Detection

    private func startSleepWakeObserver() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sleepStartedAt = Date()
            }
        }
        center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWake()
            }
        }
    }

    private func handleWake() {
        guard let sleepStart = sleepStartedAt else { return }
        sleepStartedAt = nil

        let wakeTime = Date()
        let duration = wakeTime.timeIntervalSince(sleepStart)

        // Only record sleep sessions longer than 1 minute
        guard duration > 60 else { return }

        let session = SessionRecord(
            timestamp: sleepStart,
            app: "System",
            bundleID: nil,
            category: .sleeping,
            task: "Device sleeping (\(AnalysisAggregator.format(duration: duration)))",
            confidence: 1.0,
            screenshotPath: nil,
            rawResponse: nil
        )
        _ = try? database.saveSession(session)
        refreshRecentEntries()
        refreshTodaySummary()
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

    nonisolated static func resolveScreenPermission(preflightGranted: Bool, verifiedByCapture: Bool) -> Bool {
        preflightGranted || verifiedByCapture
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
        static let hasCompletedFirstCapture = "focuslens.hasCompletedFirstCapture"
        static let screenshotRetentionDays = "focuslens.screenshotRetentionDays"
        static let idleThresholdMinutes = "focuslens.idleThresholdMinutes"
        static let journalDirectory = "focuslens.journalDirectory"
        static let autoJournalEnabled = "focuslens.autoJournalEnabled"
        static let geminiAPIKey = "focuslens.geminiAPIKey"
    }

    private static let geminiAPIKey: String = {
        UserDefaults.standard.string(forKey: Keys.geminiAPIKey) ?? ""
    }()

    /// Returns seconds since last keyboard or mouse event (HID-level, unaffected by caffeine apps).
    static func userIdleSeconds() -> Double {
        let keyboard = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        let mouse = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
        let click = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .leftMouseDown)
        return min(keyboard, mouse, click)
    }
}
