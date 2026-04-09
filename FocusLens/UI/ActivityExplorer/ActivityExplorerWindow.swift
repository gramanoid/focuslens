import AppKit
import Quartz
import SwiftUI

enum ActivityExplorerTab: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case insights = "Insights"
    case patterns = "Patterns"
    case keystrokes = "Keystrokes"
    case aiAnalysis = "AI Analysis"

    var id: String { rawValue }
}

enum TimelineViewMode: String, CaseIterable, Identifiable {
    case cards = "Timeline"
    case blocks = "Session Blocks"

    var id: String { rawValue }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case json = "JSON"
    case markdown = "Markdown"

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .csv: "csv"
        case .json: "json"
        case .markdown: "md"
        }
    }
}

@MainActor
final class ActivityExplorerViewModel: ObservableObject {
    @Published var selectedTab: ActivityExplorerTab = .timeline
    @Published var selectedDay = Calendar.current.startOfDay(for: .now)
    @Published var selectedHour: Int?
    @Published var timelineViewMode: TimelineViewMode = .cards
    @Published var selectedDateRange = DateRangeSelection()
    @Published var selectedCategories = Set(ActivityCategory.allCases.filter { $0 != .unknown })
    @Published var appSearchText = ""
    @Published var selectedApp = ""
    @Published var minimumConfidence = 0.0
    @Published var showOnlyFocusSessions = false
    @Published var daySessions: [SessionRecord] = []
    @Published var rangeSessions: [SessionRecord] = []
    @Published var analyses: [AnalysisRecord] = []
    @Published var analysisType: AnalysisType = .dailyRecap
    @Published var customPrompt = ""
    @Published var analysisResponse = ""
    @Published var isGeneratingAnalysis = false
    @Published var exportError: String?

    private var analysisTask: Task<Void, Never>?

    // Cached derived data — updated in reloadRange()/reloadDay(), not on every render.
    @Published private(set) var cachedRangeBlocks: [SessionBlock] = []
    @Published private(set) var cachedCategorySummaries: [CategorySummary] = []
    @Published private(set) var cachedAppUsage: [AppUsageSummary] = []
    @Published private(set) var cachedFocusTrend: [FocusScorePoint] = []
    @Published private(set) var cachedHourlyHeatmap: [HourlyHeatCell] = []
    @Published private(set) var cachedSwitchTrend: [HourlySwitchPoint] = []
    @Published private(set) var cachedAllApps: [String] = []
    @Published private(set) var rangeKeystrokes: [KeystrokeRecord] = []
    @Published var globalSearchResults: [SearchResult] = []
    @Published private(set) var cachedWeeklyHeatmap: [WeeklyHeatCell] = []
    @Published private(set) var cachedDayOfWeekSummaries: [DayOfWeekSummary] = []
    @Published private(set) var cachedPatternInsights: [PatternInsight] = []
    @Published private(set) var cachedOptimalSessionLength: TimeInterval = 0
    @Published private(set) var cachedAppFocusCorrelation: [(app: String, focusRatio: Double)] = []
    @Published private(set) var hasEnoughDataForPatterns = false
    var debouncedSearchTask: Task<Void, Never>?

    let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        reloadAll()
    }

    var selectedRangeInterval: DateInterval {
        selectedDateRange.resolve()
    }

    var timelineBlocks: [SessionBlock] {
        let blocks = AnalysisAggregator.mergedBlocks(
            from: AnalysisAggregator.blocks(from: daySessions, fallbackInterval: appState.captureInterval.rawValue)
        )
        return blocks.filter { block in
            let matchesCategory = selectedCategories.isEmpty || selectedCategories.contains(block.category)
            let matchesApp = selectedApp.isEmpty || block.app == selectedApp
            let matchesConfidence = block.confidence >= minimumConfidence
            let matchesFocus = !showOnlyFocusSessions || block.duration >= 180
            return matchesCategory && matchesApp && matchesConfidence && matchesFocus
        }.reversed()
    }

    var allApps: [String] {
        guard !appSearchText.isEmpty else { return cachedAllApps }
        return cachedAllApps.filter { $0.localizedCaseInsensitiveContains(appSearchText) }
    }

    var rangeBlocks: [SessionBlock] { cachedRangeBlocks }
    var categorySummaries: [CategorySummary] { cachedCategorySummaries }
    var appUsage: [AppUsageSummary] { cachedAppUsage }
    var focusTrend: [FocusScorePoint] { cachedFocusTrend }
    var hourlyHeatmap: [HourlyHeatCell] { cachedHourlyHeatmap }
    var switchTrend: [HourlySwitchPoint] { cachedSwitchTrend }

    var hourlyDensityForSelectedDay: [Int: Double] {
        AnalysisAggregator.hourlyDensity(for: timelineBlocks, on: selectedDay)
    }

    var totalTrackedTimeText: String {
        AnalysisAggregator.format(duration: AnalysisAggregator.totalDuration(of: cachedRangeBlocks))
    }

    var mostUsedAppText: String {
        cachedAppUsage.first?.app ?? "None"
    }

    var longestFocusSessionText: String {
        guard let block = AnalysisAggregator.longestFocusBlock(in: cachedRangeBlocks) else { return "None" }
        return "\(AnalysisAggregator.format(duration: block.duration)) in \(block.category.title)"
    }

    var contextSwitchesText: String {
        "\(AnalysisAggregator.contextSwitchCount(in: cachedRangeBlocks))"
    }

    func reloadAll() {
        reloadDay()
        reloadRange()
        reloadAnalyses()
        reloadPatterns()
    }

    func reloadDay() {
        let start = Calendar.current.startOfDay(for: selectedDay)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let interval = DateInterval(start: start, end: end)
        daySessions = (try? appState.database.fetchSessions(in: interval)) ?? []
        cachedAllApps = (try? appState.database.fetchDistinctApps()) ?? []
    }

    func reloadRange() {
        rangeSessions = (try? appState.database.fetchSessions(in: selectedRangeInterval)) ?? []
        let interval = selectedRangeInterval
        let blocks = AnalysisAggregator.blocks(from: rangeSessions, fallbackInterval: appState.captureInterval.rawValue)
        cachedRangeBlocks = blocks
        cachedCategorySummaries = AnalysisAggregator.categorySummaries(for: blocks)
        cachedAppUsage = AnalysisAggregator.appUsage(for: blocks)
        cachedFocusTrend = AnalysisAggregator.focusScoreTrend(blocks: blocks, interval: interval)
        cachedHourlyHeatmap = AnalysisAggregator.hourlyHeatmap(blocks: blocks, interval: interval)
        cachedSwitchTrend = AnalysisAggregator.averageSwitchesByHour(blocks: blocks, interval: interval)
        rangeKeystrokes = (try? appState.database.fetchKeystrokes(in: interval)) ?? []
    }

    func reloadPatterns() {
        let calendar = Calendar.current
        let end = Date()
        let start = calendar.date(byAdding: .day, value: -30, to: end) ?? end
        let interval = DateInterval(start: start, end: end)
        let sessions = (try? appState.database.fetchSessions(in: interval)) ?? []
        let blocks = AnalysisAggregator.blocks(from: sessions, fallbackInterval: appState.captureInterval.rawValue)

        let uniqueDays = Set(blocks.map { calendar.startOfDay(for: $0.start) })
        hasEnoughDataForPatterns = uniqueDays.count >= 7

        guard hasEnoughDataForPatterns else { return }

        cachedWeeklyHeatmap = AnalysisAggregator.weeklyHeatmap(blocks: blocks)
        cachedDayOfWeekSummaries = AnalysisAggregator.dayOfWeekSummaries(blocks: blocks)
        cachedOptimalSessionLength = AnalysisAggregator.optimalSessionLength(blocks: blocks)
        cachedAppFocusCorrelation = AnalysisAggregator.appFocusCorrelation(blocks: blocks)
        cachedPatternInsights = AnalysisAggregator.generatePatternInsights(
            daySummaries: cachedDayOfWeekSummaries,
            weeklyHeatmap: cachedWeeklyHeatmap,
            blocks: blocks
        )
    }

    func reloadAnalyses() {
        analyses = (try? appState.database.fetchAnalyses(limit: 100)) ?? []
    }

    func jumpTo(day: Date, hour: Int) {
        selectedDay = day
        selectedHour = hour
        selectedTab = .timeline
        reloadDay()
    }

    func triggerExport(_ format: ExportFormat) {
        do {
            let payload = try exportPayload(for: format)
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "FocusLens-\(format.rawValue.lowercased())-\(Int(Date().timeIntervalSince1970)).\(format.fileExtension)"
            if panel.runModal() == .OK, let url = panel.url {
                try payload.write(to: url, options: .atomic)
            }
        } catch {
            exportError = error.localizedDescription
        }
    }

    func generateAnalysis() {
        guard let baseURL = appState.serverBaseURL else {
            exportError = "Invalid llama.cpp URL."
            return
        }
        if analysisType == .customPrompt, customPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            exportError = "Enter a custom prompt before generating analysis."
            return
        }

        let currentInterval = selectedRangeInterval
        let comparisonInterval = selectedDateRange.comparisonBaseline(for: currentInterval)
        let currentSessions = rangeSessions
        let currentKeystrokes = rangeKeystrokes
        let comparisonSessions = (try? appState.database.fetchSessions(in: comparisonInterval)) ?? []
        let comparisonKeystrokes = (try? appState.database.fetchKeystrokes(in: comparisonInterval)) ?? []

        let summary = AnalysisAggregator.buildAnalysisSummary(
            sessions: currentSessions,
            interval: currentInterval,
            fallbackInterval: appState.captureInterval.rawValue,
            keystrokeRecords: currentKeystrokes
        )
        let comparisonSummary = AnalysisAggregator.buildComparisonSummary(
            currentSessions: currentSessions,
            currentInterval: currentInterval,
            previousSessions: comparisonSessions,
            previousInterval: comparisonInterval,
            fallbackInterval: appState.captureInterval.rawValue,
            currentKeystrokeRecords: currentKeystrokes,
            previousKeystrokeRecords: comparisonKeystrokes
        )
        let instruction = analysisType == .customPrompt ? customPrompt : analysisType.defaultPrompt
        let userPrompt = """
        Activity data:
        ## Selected period
        \(summary)

        ## Comparison vs Previous Equivalent Period
        \(comparisonSummary)

        Response contract:
        - Write directly to me using "you" and "your".
        - Never use first-person voice. Do not use "I", "me", "my", "mine", "we", or "our".
        - Never say "the user", "the person", or "they worked on".
        - Treat the data as evidence. Separate clear observations from lighter inferences.
        - Every major point must cite concrete support from the timeline, apps, categories, or keystrokes.
        - Prefer sharp insights over generic productivity advice.
        - When comparison data exists, explain what changed versus the previous equivalent period.
        - When browsing or communication details are available, name the specific site, page, thread, document, or person.
        - If the data does not support a specific site or person, say that it is unspecified instead of inventing one.
        - Use only these markdown headings, in this exact order:
          ## What You Did
          ## Patterns That Matter
          ## Recommended Adjustment
        - Put each heading on its own line and follow it with short bullet points.

        Task:
        \(instruction)
        """

        isGeneratingAnalysis = true
        analysisResponse = ""
        analysisTask?.cancel()

        analysisTask = Task {
            do {
                let systemPrompt = """
                You are writing a private work analysis for the owner of this Mac.
                Address them directly as "you" and "your."
                Never use first-person voice. Do not use "I", "me", "my", "mine", "we", or "our".
                Never say "the user", "the person", "they worked on", or similar third-person phrasing.
                The data was collected by periodically taking screenshots and classifying what they were working on.
                Be specific, data-driven, and concise. Reference actual times, apps, patterns, and keystroke signals from the data.
                Use the previous equivalent period as the baseline when comparison data is available. Call out what increased, decreased, or shifted materially.
                When browsing or communication details are available, name the specific site, page, thread, document, or person.
                If the provided data does not support a specific site or person, say that it is unspecified instead of inventing one.
                Do not be generic. If the data is sparse or ambiguous, say that plainly instead of inventing certainty.
                Use markdown with exactly these sections:
                ## What You Did
                ## Patterns That Matter
                ## Recommended Adjustment
                Under each section, use short bullets only. Keep recommendations realistic and prioritized.
                """
                var collected = ""
                for try await token in appState.llamaClient.streamAnalysis(systemPrompt: systemPrompt, userPrompt: userPrompt, baseURL: baseURL) {
                    collected += token
                    analysisResponse = collected
                }

                if !collected.isEmpty {
                    let formatted = AnalysisResponseFormatter.sanitize(collected)
                    analysisResponse = formatted
                    let record = AnalysisRecord(
                        type: analysisType,
                        dateRangeStart: currentInterval.start,
                        dateRangeEnd: currentInterval.end,
                        prompt: instruction,
                        response: formatted
                    )
                    _ = try appState.database.saveAnalysis(record)
                    reloadAnalyses()
                }
                isGeneratingAnalysis = false
            } catch {
                exportError = error.localizedDescription
                isGeneratingAnalysis = false
            }
        }
    }

    func autoLoadAnalysis() {
        // If there's already a response or generation in progress, skip.
        guard analysisResponse.isEmpty, !isGeneratingAnalysis else { return }

        // Try to load the most recent saved analysis first.
        if let latest = analyses.first {
            open(latest)
            return
        }

        // No saved analyses — auto-generate if server is reachable and data exists.
        guard appState.serverReachable, !rangeSessions.isEmpty else { return }
        generateAnalysis()
    }

    func open(_ analysis: AnalysisRecord) {
        analysisType = analysis.type
        if analysis.type == .customPrompt {
            customPrompt = analysis.prompt
        }
        analysisResponse = analysis.response
    }

    func delete(_ analysis: AnalysisRecord) {
        guard let id = analysis.id else { return }
        try? appState.database.deleteAnalysis(id: id)
        reloadAnalyses()
    }

    func exportJournalForSelectedDay() {
        let generator = WorkJournalGenerator(database: appState.database)
        do {
            let markdown = try generator.generate(for: selectedDay, captureInterval: appState.captureInterval.rawValue)
            let panel = NSSavePanel()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            panel.nameFieldStringValue = "\(formatter.string(from: selectedDay)).md"
            panel.canCreateDirectories = true
            if panel.runModal() == .OK, let url = panel.url {
                try Data(markdown.utf8).write(to: url, options: .atomic)
            }
        } catch {
            exportError = error.localizedDescription
        }
    }

    func performSearch(query: String) {
        let (cleanedQuery, dateRange) = NaturalDateParser.parse(query)
        guard !cleanedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            globalSearchResults = []
            return
        }
        let sessions = (try? appState.database.searchSessions(query: cleanedQuery, in: dateRange, limit: 25)) ?? []
        let keystrokes = (try? appState.database.searchKeystrokes(query: cleanedQuery, in: dateRange, limit: 25)) ?? []

        var results: [SearchResult] = []
        for s in sessions {
            results.append(SearchResult(
                id: "s-\(s.id ?? 0)",
                timestamp: s.timestamp,
                app: s.app,
                text: s.task,
                category: s.category,
                source: .session
            ))
        }
        for k in keystrokes {
            results.append(SearchResult(
                id: "k-\(k.id ?? 0)",
                timestamp: k.timestamp,
                app: k.app,
                text: String(k.typedText.prefix(120)),
                category: nil,
                source: .keystroke
            ))
        }
        globalSearchResults = results.sorted { $0.timestamp > $1.timestamp }
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private func exportPayload(for format: ExportFormat) throws -> Data {
        switch format {
        case .csv:
            let dateFormatter = Self.isoFormatter
            var lines = ["timestamp,app,bundle_id,category,task,confidence,screenshot_path"]
            for session in rangeSessions {
                lines.append(
                    [
                        dateFormatter.string(from: session.timestamp),
                        session.app,
                        session.bundleID ?? "",
                        session.category.rawValue,
                        session.task,
                        "\(session.confidence)",
                        session.screenshotPath ?? ""
                    ]
                    .map(Self.csvEscape(_:))
                    .joined(separator: ",")
                )
            }
            return Data(lines.joined(separator: "\n").utf8)
        case .json:
            return try JSONEncoder.pretty.encode(rangeSessions)
        case .markdown:
            let currentInterval = selectedRangeInterval
            let comparisonInterval = selectedDateRange.comparisonBaseline(for: currentInterval)
            let comparisonSessions = (try? appState.database.fetchSessions(in: comparisonInterval)) ?? []
            let comparisonKeystrokes = (try? appState.database.fetchKeystrokes(in: comparisonInterval)) ?? []
            let summary = AnalysisAggregator.buildAnalysisSummary(
                sessions: rangeSessions,
                interval: currentInterval,
                fallbackInterval: appState.captureInterval.rawValue,
                keystrokeRecords: rangeKeystrokes
            )
            let comparisonSummary = AnalysisAggregator.buildComparisonSummary(
                currentSessions: rangeSessions,
                currentInterval: currentInterval,
                previousSessions: comparisonSessions,
                previousInterval: comparisonInterval,
                fallbackInterval: appState.captureInterval.rawValue,
                currentKeystrokeRecords: rangeKeystrokes,
                previousKeystrokeRecords: comparisonKeystrokes
            )
            var markdown = "# FocusLens Report\n\n"
            markdown += "\(summary)\n\n"
            markdown += "## Comparison vs Previous Equivalent Period\n\n"
            markdown += "\(comparisonSummary)\n\n"
            markdown += "## Sessions\n"
            for session in rangeSessions {
                markdown += "- \(session.timestamp.formatted(date: .omitted, time: .shortened)) | \(session.app) | \(session.category.title) | \(session.task)\n"
            }
            return Data(markdown.utf8)
        }
    }

    private static func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

final class ActivityExplorerWindowController: NSWindowController {
    static let shared = ActivityExplorerWindowController()

    private var viewModel: ActivityExplorerViewModel?

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    func show(appState: AppState) {
        if window == nil {
            let viewModel = ActivityExplorerViewModel(appState: appState)
            self.viewModel = viewModel
            let contentView = ActivityExplorerView(viewModel: viewModel)
            let hostingController = NSHostingController(rootView: AnyView(contentView))
            let window = NSWindow(contentViewController: hostingController)
            window.title = "FocusLens"
            window.setContentSize(NSSize(width: 1280, height: 860))
            window.minSize = NSSize(width: 960, height: 680)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }

        viewModel?.reloadAll()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct ActivityExplorerView: View {
    @ObservedObject var viewModel: ActivityExplorerViewModel

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            GlobalSearchBar(viewModel: viewModel)

            Picker("Tab", selection: $viewModel.selectedTab) {
                ForEach(ActivityExplorerTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            Group {
                switch viewModel.selectedTab {
                case .timeline:
                    TimelineTabView(viewModel: viewModel)
                case .insights:
                    InsightsTabView(viewModel: viewModel)
                case .patterns:
                    PatternsTabView(viewModel: viewModel)
                case .keystrokes:
                    KeystrokesTabView(viewModel: viewModel)
                case .aiAnalysis:
                    AIAnalysisTabView(viewModel: viewModel)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .motionSafe(.easeInOut(duration: DS.Motion.fast), value: viewModel.selectedTab)
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.bottom, DS.Spacing.xl)
        .padding(.top, DS.Spacing.sm)
        .frame(minWidth: 960, minHeight: 680)
        .background(DS.Background.dashboard)
        .preferredColorScheme(.dark)
        .onChange(of: viewModel.selectedDay) { _ in
            viewModel.reloadDay()
        }
        .onChange(of: viewModel.selectedDateRange) { _ in
            viewModel.reloadRange()
        }
        .onChange(of: viewModel.selectedTab) { tab in
            if tab == .aiAnalysis {
                viewModel.autoLoadAnalysis()
            }
        }
        .alert("Export Error", isPresented: Binding(
            get: { viewModel.exportError != nil },
            set: { if !$0 { viewModel.exportError = nil } }
        )) {
            Button("Close", role: .cancel) { viewModel.exportError = nil }
        } message: {
            Text(viewModel.exportError ?? "")
        }
    }
}

struct DateRangeSelectorView: View {
    @Binding var selection: DateRangeSelection

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Picker("Range", selection: $selection.preset) {
                ForEach(DateRangePreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            if selection.preset == .custom {
                HStack {
                    DatePicker("Start", selection: $selection.customStart, displayedComponents: .date)
                    DatePicker("End", selection: $selection.customEnd, displayedComponents: .date)
                }
            }
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
