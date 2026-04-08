import Foundation

enum SelfCheck {
    static func run() throws {
        try customDateRangeIncludesEntireEndDay()
        try comparisonBaselineMatchesEquivalentWindow()
        try enumerateDaysDoesNotIncludeExclusiveEndDay()
        try averageTrackedMinutesByHourAveragesAcrossDays()
        try buildAnalysisSummaryUsesAveragedHourlyPattern()
        try buildAnalysisSummaryIncludesFocusSignalsAndKeystrokes()
        try buildComparisonSummaryIncludesBaselineDeltas()
        try analysisPromptsAddressYouDirectly()
        try analysisResponseFormattingRestoresSecondPersonAndSections()
        try parseClassificationHandlesWrappedResponse()
        try parseClassificationFallsBackToUnknownForInvalidJSON()
        try inMemoryDatabaseSavesAndFetchesSessionsAndAnalyses()
    }

    private static func customDateRangeIncludesEntireEndDay() throws {
        var selection = DateRangeSelection()
        selection.preset = .custom
        selection.customStart = date(2026, 4, 1, 0, 0)
        selection.customEnd = date(2026, 4, 1, 0, 0)

        let interval = selection.resolve(calendar: calendar)
        try expect(interval.start == date(2026, 4, 1, 0, 0), "Custom range start mismatch")
        try expect(interval.end == date(2026, 4, 2, 0, 0), "Custom range end should include the full end day")
    }

    private static func comparisonBaselineMatchesEquivalentWindow() throws {
        var today = DateRangeSelection()
        today.preset = .today

        let todayCurrent = DateInterval(start: date(2026, 4, 8, 0, 0), end: date(2026, 4, 8, 15, 30))
        let todayBaseline = today.comparisonBaseline(for: todayCurrent, calendar: calendar)
        try expect(todayBaseline.start == date(2026, 4, 7, 0, 0), "Today baseline should shift start by one day")
        try expect(todayBaseline.end == date(2026, 4, 7, 15, 30), "Today baseline should preserve elapsed time of day")

        var custom = DateRangeSelection()
        custom.preset = .custom
        let customCurrent = DateInterval(start: date(2026, 4, 8, 9, 0), end: date(2026, 4, 10, 9, 0))
        let customBaseline = custom.comparisonBaseline(for: customCurrent, calendar: calendar)
        try expect(customBaseline.start == date(2026, 4, 6, 9, 0), "Custom baseline should use the immediately preceding equal-length interval")
        try expect(customBaseline.end == date(2026, 4, 8, 9, 0), "Custom baseline should end at the current interval start")
    }

    private static func enumerateDaysDoesNotIncludeExclusiveEndDay() throws {
        let interval = DateInterval(start: date(2026, 4, 1, 0, 0), end: date(2026, 4, 3, 0, 0))
        let days = AnalysisAggregator.enumerateDays(in: interval, calendar: calendar)

        try expect(days == [
            date(2026, 4, 1, 0, 0),
            date(2026, 4, 2, 0, 0)
        ], "Exclusive end day was incorrectly included")
    }

    private static func averageTrackedMinutesByHourAveragesAcrossDays() throws {
        let sessions = [
            SessionRecord(timestamp: date(2026, 4, 1, 9, 0), app: "Xcode", category: .coding, task: "Code", confidence: 0.9),
            SessionRecord(timestamp: date(2026, 4, 1, 9, 30), app: "Safari", category: .browsing, task: "Docs", confidence: 0.7),
            SessionRecord(timestamp: date(2026, 4, 2, 9, 0), app: "Xcode", category: .coding, task: "Code", confidence: 0.9),
            SessionRecord(timestamp: date(2026, 4, 2, 10, 0), app: "Mail", category: .communication, task: "Email", confidence: 0.6)
        ]
        let blocks = AnalysisAggregator.blocks(from: sessions, fallbackInterval: 60)
        let interval = DateInterval(start: date(2026, 4, 1, 0, 0), end: date(2026, 4, 3, 0, 0))
        let hourly = AnalysisAggregator.averageTrackedMinutesByHour(blocks: blocks, interval: interval, calendar: calendar)

        try expect(hourly[9] == 1.5, "Expected 1.5 average tracked minutes at 09:00")
        try expect(hourly[10] == 0.5, "Expected 0.5 average tracked minutes at 10:00")
    }

    private static func buildAnalysisSummaryUsesAveragedHourlyPattern() throws {
        let sessions = [
            SessionRecord(timestamp: date(2026, 4, 1, 9, 0), app: "Xcode", category: .coding, task: "Code", confidence: 0.9),
            SessionRecord(timestamp: date(2026, 4, 1, 10, 0), app: "Mail", category: .communication, task: "Email", confidence: 0.6),
            SessionRecord(timestamp: date(2026, 4, 2, 9, 0), app: "Xcode", category: .coding, task: "Code", confidence: 0.9),
            SessionRecord(timestamp: date(2026, 4, 2, 9, 30), app: "Safari", category: .browsing, task: "Research", confidence: 0.7)
        ]
        let interval = DateInterval(start: date(2026, 4, 1, 0, 0), end: date(2026, 4, 3, 0, 0))
        let summary = AnalysisAggregator.buildAnalysisSummary(sessions: sessions, interval: interval, calendar: calendar)

        try expect(summary.contains("09:00 — 2m"), "Summary should report averaged 09:00 activity")
        try expect(summary.contains("10:00 — 1m"), "Summary should report averaged 10:00 activity")
    }

    private static func buildAnalysisSummaryIncludesFocusSignalsAndKeystrokes() throws {
        let sessions = [
            SessionRecord(timestamp: date(2026, 4, 1, 9, 0), app: "Xcode", category: .coding, task: "Implement activity analysis", confidence: 0.95),
            SessionRecord(timestamp: date(2026, 4, 1, 9, 30), app: "Mail", category: .communication, task: "Reply to project updates", confidence: 0.7),
            SessionRecord(timestamp: date(2026, 4, 1, 10, 0), app: "Xcode", category: .coding, task: "Implement activity analysis", confidence: 0.95)
        ]
        let keystrokes = [
            KeystrokeRecord(
                sessionID: 1,
                timestamp: date(2026, 4, 1, 9, 5),
                app: "Xcode",
                typedText: "Refine the analysis summary output",
                keystrokeCount: 120
            )
        ]
        let interval = DateInterval(start: date(2026, 4, 1, 0, 0), end: date(2026, 4, 2, 0, 0))
        let summary = AnalysisAggregator.buildAnalysisSummary(
            sessions: sessions,
            interval: interval,
            calendar: calendar,
            keystrokeRecords: keystrokes
        )

        try expect(summary.contains("Focus profile:"), "Summary should include focus-profile metrics")
        try expect(summary.contains("Notable session blocks:"), "Summary should include concrete block highlights")
        try expect(summary.contains("Recurring task themes:"), "Summary should include recurring task themes")
        try expect(summary.contains("Keystroke activity:"), "Summary should include keystroke activity when present")
        try expect(summary.contains("Top typing apps: Xcode (120 keys)"), "Summary should list top typing apps")
    }

    private static func buildComparisonSummaryIncludesBaselineDeltas() throws {
        let currentSessions = [
            SessionRecord(timestamp: date(2026, 4, 8, 9, 0), app: "Xcode", category: .coding, task: "Implement comparison summary", confidence: 0.95),
            SessionRecord(timestamp: date(2026, 4, 8, 10, 0), app: "Xcode", category: .coding, task: "Implement comparison summary", confidence: 0.95),
            SessionRecord(timestamp: date(2026, 4, 8, 11, 0), app: "Mail", category: .communication, task: "Reply to reviews", confidence: 0.7)
        ]
        let previousSessions = [
            SessionRecord(timestamp: date(2026, 4, 7, 9, 0), app: "Mail", category: .communication, task: "Reply to reviews", confidence: 0.7),
            SessionRecord(timestamp: date(2026, 4, 7, 10, 0), app: "Safari", category: .browsing, task: "Research", confidence: 0.7)
        ]
        let currentKeystrokes = [
            KeystrokeRecord(sessionID: 1, timestamp: date(2026, 4, 8, 9, 5), app: "Xcode", typedText: "Implement comparison summary", keystrokeCount: 180)
        ]
        let previousKeystrokes = [
            KeystrokeRecord(sessionID: 1, timestamp: date(2026, 4, 7, 9, 5), app: "Mail", typedText: "Reply to reviews", keystrokeCount: 60)
        ]

        let summary = AnalysisAggregator.buildComparisonSummary(
            currentSessions: currentSessions,
            currentInterval: DateInterval(start: date(2026, 4, 8, 0, 0), end: date(2026, 4, 9, 0, 0)),
            previousSessions: previousSessions,
            previousInterval: DateInterval(start: date(2026, 4, 7, 0, 0), end: date(2026, 4, 8, 0, 0)),
            calendar: calendar,
            currentKeystrokeRecords: currentKeystrokes,
            previousKeystrokeRecords: previousKeystrokes
        )

        try expect(summary.contains("Tracked time delta:"), "Comparison summary should include tracked time delta")
        try expect(summary.contains("Biggest category shifts:"), "Comparison summary should include category shifts")
        try expect(summary.contains("Biggest app shifts:"), "Comparison summary should include app shifts")
        try expect(summary.contains("Typing shifts:"), "Comparison summary should include typing shifts")
    }

    private static func analysisPromptsAddressYouDirectly() throws {
        let prompts = AnalysisType.allCases
            .filter { $0 != .customPrompt }
            .map { $0.defaultPrompt.lowercased() }

        try expect(prompts.allSatisfy { !$0.contains("the user") }, "Default prompts should not refer to 'the user'")
        try expect(prompts.allSatisfy { $0.contains("you") || $0.contains("your") }, "Default prompts should address the person directly")
    }

    private static func analysisResponseFormattingRestoresSecondPersonAndSections() throws {
        let malformed = """
        What You DidI worked on coding and writing. Patterns That MatterMy focus score dropped by 18 points. Recommended AdjustmentI could protect the afternoon for deeper work.
        """

        let sanitized = AnalysisResponseFormatter.sanitize(malformed)
        let sections = AnalysisResponseFormatter.sections(from: malformed)
        let sanitizedSections = AnalysisResponseFormatter.sections(from: sanitized)

        try expect(sanitized.contains("## What You Did"), "Sanitizer should restore the What You Did heading")
        try expect(sanitized.contains("## Patterns That Matter"), "Sanitizer should restore the Patterns That Matter heading")
        try expect(sanitized.contains("## Recommended Adjustment"), "Sanitizer should restore the Recommended Adjustment heading")
        try expect(!sanitized.contains("I worked"), "Sanitizer should rewrite first-person phrasing")
        try expect(sanitized.contains("You worked"), "Sanitizer should rewrite output into second person")
        try expect(sections.count >= 3, "Section parser should recover the three required sections")
        try expect(sanitizedSections.count >= 3, "Section parser should parse sanitized output correctly")
    }

    private static func parseClassificationHandlesWrappedResponse() throws {
        let content = """
        Result:
        ```json
        {
          "app": "Safari",
          "category": "browsing",
          "task": "Reading documentation",
          "confidence": 1.2
        }
        ```
        """

        let result = LlamaCppClient.parseClassification(from: content)
        try expect(result.app == "Safari", "Wrapped response should parse app name")
        try expect(result.category == .browsing, "Wrapped response should parse category")
        try expect(result.task == "Reading documentation", "Wrapped response should parse task")
        try expect(result.confidence == 1, "Confidence should be clamped to 1")
    }

    private static func parseClassificationFallsBackToUnknownForInvalidJSON() throws {
        let content = "No JSON here."
        let result = LlamaCppClient.parseClassification(from: content)

        try expect(result.category == .unknown, "Invalid JSON should map to unknown classification")
        try expect(result.rawResponse == content, "Invalid JSON should preserve raw response")
    }

    private static func inMemoryDatabaseSavesAndFetchesSessionsAndAnalyses() throws {
        let database = try AppDatabase(storageMode: .inMemory)
        _ = try database.saveSession(
            SessionRecord(
                timestamp: Date(timeIntervalSince1970: 10),
                app: "Xcode",
                bundleID: "com.apple.dt.Xcode",
                category: .coding,
                task: "Editing project files",
                confidence: 0.95,
                screenshotPath: "/tmp/1.png",
                rawResponse: "{\"app\":\"Xcode\"}"
            )
        )
        _ = try database.saveAnalysis(
            AnalysisRecord(
                type: .dailyRecap,
                dateRangeStart: Date(timeIntervalSince1970: 0),
                dateRangeEnd: Date(timeIntervalSince1970: 100),
                prompt: "Summarize",
                response: "Done"
            )
        )

        let sessions = try database.fetchRecentSessions(limit: 5)
        let analyses = try database.fetchAnalyses(limit: 5)

        try expect(sessions.count == 1, "Expected one stored session")
        try expect(sessions.first?.app == "Xcode", "Stored session app mismatch")
        try expect(analyses.count == 1, "Expected one stored analysis")
        try expect(analyses.first?.type == .dailyRecap, "Stored analysis type mismatch")
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw SelfCheckError(message)
        }
    }
}

private struct SelfCheckError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
