import Foundation

/// Generates structured markdown work journals from FocusLens session data.
final class WorkJournalGenerator {
    let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    /// Generate a complete markdown journal for a given day.
    func generate(for date: Date, captureInterval: Double = 60, calendar: Calendar = .current) throws -> String {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let interval = DateInterval(start: dayStart, end: dayEnd)

        let sessions = try database.fetchSessions(in: interval)
        let keystrokes = try database.fetchKeystrokes(in: interval)
        let blocks = AnalysisAggregator.blocks(from: sessions, fallbackInterval: captureInterval)
        let merged = AnalysisAggregator.mergedBlocks(from: blocks)

        guard !sessions.isEmpty else {
            return "---\ndate: \(Self.dateFormatter.string(from: date))\ntotal_tracked: \"0m\"\n---\n\nNo activity recorded for this day.\n"
        }

        let catSummaries = AnalysisAggregator.categorySummaries(for: blocks)
        let appUsage = AnalysisAggregator.appUsage(for: blocks)
        let totalDuration = AnalysisAggregator.totalDuration(of: blocks)
        let focusScore = AnalysisAggregator.focusScore(for: blocks)
        let switches = AnalysisAggregator.contextSwitchCount(in: blocks)
        let topApps = appUsage.prefix(5).map(\.app)

        // Find the latest analysis covering this date
        let analyses = (try? database.fetchAnalyses(limit: 20)) ?? []
        let matchingAnalysis = analyses.first { a in
            a.dateRangeStart <= dayEnd && a.dateRangeEnd >= dayStart
        }

        var md = ""

        // YAML frontmatter
        md += "---\n"
        md += "date: \(Self.dateFormatter.string(from: date))\n"
        md += "total_tracked: \"\(AnalysisAggregator.format(duration: totalDuration))\"\n"
        md += "dominant_category: \(catSummaries.first?.category.rawValue ?? "unknown")\n"
        md += "productivity_score: \(Int(focusScore))\n"
        md += "top_apps: [\(topApps.map { "\"\($0)\"" }.joined(separator: ", "))]\n"
        md += "context_switches: \(switches)\n"
        md += "sessions: \(sessions.count)\n"
        md += "generated_at: \"\(ISO8601DateFormatter().string(from: .now))\"\n"
        md += "---\n\n"

        // Header
        md += "# Work Journal — \(Self.longDateFormatter.string(from: date))\n\n"

        // Summary
        md += "## Summary\n\n"
        md += "- **Total tracked:** \(AnalysisAggregator.format(duration: totalDuration))\n"
        md += "- **Productivity score:** \(Int(focusScore))%\n"
        md += "- **Sessions:** \(sessions.count)\n"
        md += "- **Context switches:** \(switches)\n\n"

        // Category breakdown
        md += "## Categories\n\n"
        md += "| Category | Duration | % |\n"
        md += "|----------|----------|---|\n"
        for summary in catSummaries {
            md += "| \(summary.category.title) | \(AnalysisAggregator.format(duration: summary.duration)) | \(Int(summary.percentage * 100))% |\n"
        }
        md += "\n"

        // Top apps
        md += "## Top Apps\n\n"
        for (i, app) in appUsage.prefix(10).enumerated() {
            md += "\(i + 1). **\(app.app)** — \(AnalysisAggregator.format(duration: app.duration)) (\(app.dominantCategory.title))\n"
        }
        md += "\n"

        // Timeline
        md += "## Timeline\n\n"
        for block in merged.prefix(30) {
            let start = block.start.formatted(date: .omitted, time: .shortened)
            let end = block.end.formatted(date: .omitted, time: .shortened)
            md += "- **\(start)–\(end)** \(block.app) — \(block.task) (\(block.category.title))\n"
        }
        if merged.count > 30 {
            md += "- *...and \(merged.count - 30) more sessions*\n"
        }
        md += "\n"

        // Keystroke highlights
        if !keystrokes.isEmpty {
            let totalKeys = keystrokes.reduce(0) { $0 + $1.keystrokeCount }
            let byApp = Dictionary(grouping: keystrokes, by: \.app)
                .map { ($0.key, $0.value.reduce(0) { $0 + $1.keystrokeCount }, $0.value) }
                .sorted { $0.1 > $1.1 }

            md += "## Keystroke Activity\n\n"
            md += "**Total:** \(totalKeys.formatted()) keystrokes across \(byApp.count) apps\n\n"
            for (app, count, records) in byApp.prefix(5) {
                md += "### \(app) (\(count) keys)\n\n"
                let sample = records
                    .sorted { $0.timestamp < $1.timestamp }
                    .compactMap { $0.typedText.isEmpty ? nil : $0.typedText }
                    .prefix(3)
                for text in sample {
                    let trimmed = String(text.prefix(200))
                    md += "> \(trimmed)\n\n"
                }
            }
        }

        // AI Analysis
        if let analysis = matchingAnalysis {
            md += "## AI Analysis\n\n"
            md += "*Generated: \(analysis.timestamp.formatted(date: .abbreviated, time: .shortened))*\n\n"
            md += analysis.response
            md += "\n"
        }

        return md
    }

    /// Write journal to disk. Returns the URL of the written file.
    @discardableResult
    func writeJournal(for date: Date, to directory: URL, captureInterval: Double = 60) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let filename = Self.dateFormatter.string(from: date) + ".md"
        let fileURL = directory.appendingPathComponent(filename)
        let content = try generate(for: date, captureInterval: captureInterval)
        try Data(content.utf8).write(to: fileURL, options: .atomic)
        return fileURL
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let longDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .full
        return f
    }()
}
