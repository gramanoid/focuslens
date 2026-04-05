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
    @Published var showPreferences = false
    @Published var showPermissionSheet = false
    @Published var showServerHelp = false
    @Published private(set) var isCaptureInFlight = false

    let database: AppDatabase
    let llamaClient: LlamaCppClient

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

    var serverStartCommand: String {
        "llama-server -m ~/models/Qwen2-VL-2B-Instruct-Q4_K_M.gguf --mmproj ~/models/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf --port 8080 -ngl 99"
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
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        defaults.set(enabled, forKey: Keys.launchAtLogin)
        configureLaunchAtLogin(enabled)
    }

    func openDashboard() {
        ActivityExplorerWindowController.shared.show(appState: self)
    }

    func refreshRecentEntries() {
        recentEntries = (try? database.fetchRecentSessions(limit: 5)) ?? []
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
            await runCaptureCycle()
        }
    }

    func refreshPermissionState() {
        screenPermissionGranted = ScreenCapture.hasPermission()
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
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
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

    private func runCaptureCycle() async {
        guard !isCaptureInFlight else { return }
        guard isRunning else { return }
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
            let payload = try ScreenCapture.capture()
            if let bundleID = payload.activeBundleID, excludedBundleIDs.contains(bundleID) {
                if !keepScreenshots {
                    try? FileManager.default.removeItem(at: payload.screenshotURL)
                }
                captureStatus = .idle
                return
            }

            captureStatus = .classifying
            let result = try await llamaClient.classifyImage(payload.resizedPNGData, baseURL: baseURL)
            var screenshotPath: String? = payload.screenshotURL.path
            if !keepScreenshots {
                try? FileManager.default.removeItem(at: payload.screenshotURL)
                screenshotPath = nil
            }

            let session = SessionRecord(
                timestamp: payload.timestamp,
                app: result.app.isEmpty ? payload.activeAppName : result.app,
                bundleID: payload.activeBundleID,
                category: result.category,
                task: result.task,
                confidence: result.confidence,
                screenshotPath: screenshotPath,
                rawResponse: result.rawResponse
            )
            _ = try database.saveSession(session)
            refreshRecentEntries()
            refreshTodaySummary()
            captureStatus = .idle
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
            captureStatus = serverReachable ? .idle : .warning
        }
    }

    private enum Keys {
        static let isRunning = "focuslens.isRunning"
        static let captureInterval = "focuslens.captureInterval"
        static let serverBaseURL = "focuslens.serverBaseURL"
        static let keepScreenshots = "focuslens.keepScreenshots"
        static let launchAtLogin = "focuslens.launchAtLogin"
        static let excludedApps = "focuslens.excludedApps"
    }
}
