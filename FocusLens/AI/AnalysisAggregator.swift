import Foundation

enum DateRangePreset: String, CaseIterable, Identifiable {
    case today
    case yesterday
    case thisWeek
    case last7Days
    case thisMonth
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This Week"
        case .last7Days: "Last 7 Days"
        case .thisMonth: "This Month"
        case .custom: "Custom"
        }
    }
}

struct DateRangeSelection: Hashable {
    var preset: DateRangePreset = .today
    var customStart: Date = Calendar.current.startOfDay(for: .now)
    var customEnd: Date = .now

    func resolve(calendar: Calendar = .current) -> DateInterval {
        let now = Date()
        switch preset {
        case .today:
            let start = calendar.startOfDay(for: now)
            return DateInterval(start: start, end: min(now, calendar.date(byAdding: .day, value: 1, to: start) ?? now))
        case .yesterday:
            let todayStart = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
            return DateInterval(start: start, end: todayStart)
        case .thisWeek:
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        case .last7Days:
            let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
            return DateInterval(start: start, end: now)
        case .thisMonth:
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
            return DateInterval(start: start, end: now)
        case .custom:
            let startDay = calendar.startOfDay(for: min(customStart, customEnd))
            let endDay = calendar.startOfDay(for: max(customStart, customEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return DateInterval(start: startDay, end: end)
        }
    }

    func comparisonBaseline(for currentInterval: DateInterval, calendar: Calendar = .current) -> DateInterval {
        switch preset {
        case .today, .yesterday:
            return shifted(currentInterval, by: .day, value: -1, calendar: calendar)
        case .thisWeek:
            return shifted(currentInterval, by: .weekOfYear, value: -1, calendar: calendar)
        case .last7Days:
            return shifted(currentInterval, by: .day, value: -7, calendar: calendar)
        case .thisMonth:
            return shifted(currentInterval, by: .month, value: -1, calendar: calendar)
        case .custom:
            return DateInterval(
                start: currentInterval.start.addingTimeInterval(-currentInterval.duration),
                end: currentInterval.start
            )
        }
    }

    private func shifted(
        _ interval: DateInterval,
        by component: Calendar.Component,
        value: Int,
        calendar: Calendar
    ) -> DateInterval {
        let start = calendar.date(byAdding: component, value: value, to: interval.start) ?? interval.start
        let end = calendar.date(byAdding: component, value: value, to: interval.end) ?? interval.end
        return DateInterval(start: start, end: end)
    }
}

struct SessionBlock: Identifiable, Hashable {
    let id: String
    let start: Date
    let end: Date
    let app: String
    let bundleID: String?
    let category: ActivityCategory
    let task: String
    let confidence: Double
    let screenshotPath: String?
    let rawResponse: String?

    var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

struct CategorySummary: Identifiable, Hashable {
    var id: String { category.rawValue }
    let category: ActivityCategory
    let duration: TimeInterval
    let percentage: Double
}

struct AppUsageSummary: Identifiable, Hashable {
    var id: String { app }
    let app: String
    let duration: TimeInterval
    let dominantCategory: ActivityCategory
}

struct FocusScorePoint: Identifiable, Hashable {
    var id: Date { date }
    let date: Date
    let score: Double
}

struct HourlySwitchPoint: Identifiable, Hashable {
    var id: Int { hour }
    let hour: Int
    let averageSwitches: Double
}

struct HourlyHeatCell: Identifiable, Hashable {
    let day: Date
    let hour: Int
    let minutes: Double

    var id: String {
        "\(day.timeIntervalSince1970)-\(hour)"
    }
}

struct WeeklyHeatCell: Identifiable, Hashable {
    let dayOfWeek: Int  // 1=Sunday ... 7=Saturday
    let hour: Int
    let averageMinutes: Double
    var id: String { "\(dayOfWeek)-\(hour)" }
    var dayName: String { Calendar.current.shortWeekdaySymbols[dayOfWeek - 1] }
}

struct DayOfWeekSummary: Identifiable, Hashable {
    let dayOfWeek: Int
    let averageProductivityScore: Double
    let averageTrackedMinutes: Double
    let averageContextSwitches: Double
    var id: Int { dayOfWeek }
    var dayName: String { Calendar.current.weekdaySymbols[dayOfWeek - 1] }
}

struct PatternInsight: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

enum AnalysisAggregator {
    private static let productiveCategories: Set<ActivityCategory> = [.coding, .writing, .design, .work, .noteTaking]
    private static let reactiveCategories: Set<ActivityCategory> = [.communication, .browsing, .productivity, .ai]
    private struct ComparisonSnapshot {
        let sessionCount: Int
        let dayCount: Int
        let totalTracked: TimeInterval
        let focusScore: Double
        let deepWorkDuration: TimeInterval
        let reactiveDuration: TimeInterval
        let contextSwitches: Int
        let averageConfidence: Double
        let categoryDurations: [String: TimeInterval]
        let appDurations: [String: TimeInterval]
        let peakTrackedHour: (hour: Int, minutes: Double)?
        let peakDeepWorkHour: (hour: Int, minutes: Double)?
        let totalKeystrokes: Int
        let typingByApp: [String: Int]
    }

    static func blocks(from sessions: [SessionRecord], fallbackInterval: TimeInterval = 60) -> [SessionBlock] {
        guard !sessions.isEmpty else { return [] }
        let sorted = sessions.sorted { $0.timestamp < $1.timestamp }
        return sorted.enumerated().map { index, session in
            let fallbackEnd = session.timestamp.addingTimeInterval(fallbackInterval)
            let minimumEnd = session.timestamp.addingTimeInterval(1)
            let end: Date
            if index < sorted.count - 1 {
                let nextTimestamp = sorted[index + 1].timestamp
                end = max(min(nextTimestamp, fallbackEnd), minimumEnd)
            } else {
                end = fallbackEnd
            }

            return SessionBlock(
                id: "\(session.id ?? Int64(index))",
                start: session.timestamp,
                end: end,
                app: session.app,
                bundleID: session.bundleID,
                category: session.category,
                task: session.task,
                confidence: session.confidence,
                screenshotPath: session.screenshotPath,
                rawResponse: session.rawResponse
            )
        }
    }

    static func mergedBlocks(from blocks: [SessionBlock]) -> [SessionBlock] {
        guard var current = blocks.first else { return [] }
        var merged: [SessionBlock] = []

        for block in blocks.dropFirst() {
            if block.app == current.app, block.task == current.task, block.category == current.category {
                current = SessionBlock(
                    id: current.id,
                    start: current.start,
                    end: block.end,
                    app: current.app,
                    bundleID: current.bundleID ?? block.bundleID,
                    category: current.category,
                    task: current.task,
                    confidence: max(current.confidence, block.confidence),
                    screenshotPath: current.screenshotPath ?? block.screenshotPath,
                    rawResponse: current.rawResponse ?? block.rawResponse
                )
            } else {
                merged.append(current)
                current = block
            }
        }

        merged.append(current)
        return merged
    }

    static func totalDuration(of blocks: [SessionBlock]) -> TimeInterval {
        blocks.reduce(0) { $0 + $1.duration }
    }

    static func categorySummaries(for blocks: [SessionBlock]) -> [CategorySummary] {
        let total = max(totalDuration(of: blocks), 1)
        let grouped = Dictionary(grouping: blocks, by: \.category)
        return grouped.map { category, blocks in
            let duration = blocks.reduce(0) { $0 + $1.duration }
            return CategorySummary(category: category, duration: duration, percentage: duration / total)
        }
        .sorted { $0.duration > $1.duration }
    }

    static func appUsage(for blocks: [SessionBlock], limit: Int = 10) -> [AppUsageSummary] {
        let grouped = Dictionary(grouping: blocks, by: \.app)
        return grouped.map { app, blocks in
            let duration = blocks.reduce(0) { $0 + $1.duration }
            let categoryBuckets = Dictionary(grouping: blocks, by: \.category)
            let dominantCategory = categoryBuckets
                .map { category, blocks -> (ActivityCategory, TimeInterval) in
                    (category, blocks.reduce(0) { $0 + $1.duration })
                }
                .max { lhs, rhs in lhs.1 < rhs.1 }?.0 ?? .other
            return AppUsageSummary(app: app, duration: duration, dominantCategory: dominantCategory)
        }
        .sorted { $0.duration > $1.duration }
        .prefix(limit)
        .map { $0 }
    }

    static func longestFocusBlock(in blocks: [SessionBlock]) -> SessionBlock? {
        mergedBlocks(from: blocks)
            .filter { productiveCategories.contains($0.category) }
            .max(by: { $0.duration < $1.duration })
    }

    static func contextSwitchCount(in blocks: [SessionBlock]) -> Int {
        zip(blocks, blocks.dropFirst()).reduce(0) { partialResult, pair in
            partialResult + (pair.0.category == pair.1.category ? 0 : 1)
        }
    }

    static func focusScore(for blocks: [SessionBlock]) -> Double {
        let total = totalDuration(of: blocks)
        guard total > 0 else { return 0 }
        let weightedDuration = blocks.reduce(0.0) { sum, block in
            let weight: Double
            switch block.category {
            case .coding, .writing, .design, .work, .noteTaking: weight = 1.0
            case .ai, .browsing, .productivity: weight = 0.5
            case .communication: weight = 0.25
            case .media, .library, .other, .sleeping, .unknown: weight = 0
            }
            return sum + block.duration * weight
        }
        return (weightedDuration / total) * 100
    }

    static func focusScoreTrend(blocks: [SessionBlock], interval: DateInterval, calendar: Calendar = .current) -> [FocusScorePoint] {
        let days = enumerateDays(in: interval, calendar: calendar)
        return days.map { day in
            let dayInterval = DateInterval(start: day, end: calendar.date(byAdding: .day, value: 1, to: day) ?? day)
            let dayBlocks = blocks.filter { dayInterval.intersects(DateInterval(start: $0.start, end: $0.end)) }
            return FocusScorePoint(date: day, score: focusScore(for: dayBlocks))
        }
    }

    static func hourlyHeatmap(blocks: [SessionBlock], interval: DateInterval, calendar: Calendar = .current) -> [HourlyHeatCell] {
        enumerateDays(in: interval, calendar: calendar).flatMap { day in
            (0 ..< 24).map { hour in
                let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
                let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
                let hourInterval = DateInterval(start: start, end: end)
                let minutes = blocks.reduce(0.0) { partialResult, block in
                    partialResult + overlapMinutes(block: block, with: hourInterval)
                }
                return HourlyHeatCell(day: day, hour: hour, minutes: minutes)
            }
        }
    }

    static func hourlyDensity(for blocks: [SessionBlock], on day: Date, calendar: Calendar = .current) -> [Int: Double] {
        let dayStart = calendar.startOfDay(for: day)
        return Dictionary(uniqueKeysWithValues: (0 ..< 24).map { hour in
            let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart) ?? dayStart
            let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
            let interval = DateInterval(start: start, end: end)
            let trackedMinutes = blocks.reduce(0.0) { $0 + overlapMinutes(block: $1, with: interval) }
            return (hour, trackedMinutes / 60)
        })
    }

    static func averageSwitchesByHour(blocks: [SessionBlock], interval: DateInterval, calendar: Calendar = .current) -> [HourlySwitchPoint] {
        let days = enumerateDays(in: interval, calendar: calendar)
        return (0 ..< 24).map { hour in
            let switchTotal = days.reduce(0) { total, day in
                let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
                let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
                let hourBlocks = blocks.filter { DateInterval(start: $0.start, end: $0.end).intersects(DateInterval(start: start, end: end)) }
                return total + contextSwitchCount(in: hourBlocks)
            }
            return HourlySwitchPoint(hour: hour, averageSwitches: days.isEmpty ? 0 : Double(switchTotal) / Double(days.count))
        }
    }

    static func format(duration: TimeInterval) -> String {
        let rounded = Int(duration.rounded())
        let hours = rounded / 3600
        let minutes = (rounded % 3600) / 60
        if hours == 0 {
            return "\(minutes)m"
        }
        return "\(hours)h \(minutes)m"
    }

    static func buildAnalysisSummary(
        sessions: [SessionRecord],
        interval: DateInterval,
        calendar: Calendar = .current,
        fallbackInterval: TimeInterval = 60,
        keystrokeRecords: [KeystrokeRecord] = []
    ) -> String {
        let blocks = blocks(from: sessions, fallbackInterval: fallbackInterval)
        let merged = mergedBlocks(from: blocks)
        let summaries = categorySummaries(for: blocks)
        let apps = appUsage(for: blocks)
        let hourly = averageTrackedMinutesByHour(blocks: blocks, interval: interval, calendar: calendar)
        let switches = averageSwitchesByHour(blocks: blocks, interval: interval, calendar: calendar)
        let longest = longestFocusBlock(in: blocks)
        let mostFragmented = switches.max(by: { $0.averageSwitches < $1.averageSwitches })
        let totalTracked = totalDuration(of: blocks)
        let focusScoreValue = focusScore(for: blocks)
        let deepWorkDuration = duration(of: blocks, in: productiveCategories)
        let reactiveDuration = duration(of: blocks, in: reactiveCategories)
        let passiveDuration = max(0, totalTracked - deepWorkDuration - reactiveDuration)
        let averageConfidence = blocks.isEmpty ? 0 : blocks.reduce(0.0) { $0 + $1.confidence } / Double(blocks.count)
        let dayCount = enumerateDays(in: interval, calendar: calendar).count
        let peakTrackedHour = hourly.max(by: { $0.value < $1.value })
        let deepWorkHourly = averageTrackedMinutesByHour(
            blocks: blocks.filter { productiveCategories.contains($0.category) },
            interval: interval,
            calendar: calendar
        )
        let peakDeepWorkHour = deepWorkHourly.max(by: { $0.value < $1.value })
        let focusApps = focusHeavyApps(for: blocks, limit: 3)
        let notableBlocks = merged
            .sorted {
                if $0.duration == $1.duration {
                    return $0.start < $1.start
                }
                return $0.duration > $1.duration
            }
            .prefix(5)
        let taskThemes = topTaskThemes(in: merged, limit: 5)
        let browsingHighlights = detailHighlights(in: merged, categories: [.browsing], limit: 4)
        let communicationHighlights = detailHighlights(in: merged, categories: [.communication], limit: 4)
        let communicationSamples = keystrokeSamples(
            from: keystrokeRecords,
            apps: Set(communicationHighlights.map(\.app)),
            limit: 3
        )
        let transitions = topCategoryTransitions(in: merged, limit: 3)
        let switchHotspots = switches
            .filter { $0.averageSwitches > 0 }
            .sorted { $0.averageSwitches > $1.averageSwitches }
            .prefix(3)

        var lines: [String] = []
        lines.append("Date range: \(format(date: interval.start)) to \(format(date: interval.end))")
        lines.append("Days covered: \(dayCount)")
        lines.append("Total sessions: \(sessions.count)")
        lines.append("Total tracked time: \(format(duration: totalTracked))")
        lines.append("Average classifier confidence: \(Int((averageConfidence * 100).rounded()))%")
        lines.append("")
        lines.append("Focus profile:")
        lines.append("- Focus score: \(Int(focusScoreValue.rounded()))/100")
        lines.append("- Deep work (coding, writing, design, note-taking): \(format(duration: deepWorkDuration)) (\(percentageString(deepWorkDuration, total: totalTracked)))")
        lines.append("- Reactive work (communication, browsing, productivity, AI): \(format(duration: reactiveDuration)) (\(percentageString(reactiveDuration, total: totalTracked)))")
        lines.append("- Passive or low-signal time: \(format(duration: passiveDuration)) (\(percentageString(passiveDuration, total: totalTracked)))")
        lines.append("")
        lines.append("Category breakdown:")
        summaries.forEach { summary in
            lines.append("- \(summary.category.title): \(format(duration: summary.duration)) (\(Int(summary.percentage * 100))%)")
        }
        lines.append("")
        lines.append("Top apps by time:")
        for (index, app) in apps.prefix(5).enumerated() {
            lines.append("\(index + 1). \(app.app) - \(format(duration: app.duration)) in \(app.dominantCategory.title)")
        }
        if !focusApps.isEmpty {
            lines.append("")
            lines.append("Focus-heavy apps:")
            for app in focusApps {
                lines.append("- \(app.app): \(Int((app.focusRatio * 100).rounded()))% deep work across \(format(duration: app.duration))")
            }
        }
        if !notableBlocks.isEmpty {
            lines.append("")
            lines.append("Notable session blocks:")
            for block in notableBlocks {
                lines.append("- \(format(time: block.start)) to \(format(time: block.end)) | \(block.app) | \(block.category.title) | \(compactTask(block.task))")
            }
        }
        if !taskThemes.isEmpty {
            lines.append("")
            lines.append("Recurring task themes:")
            for theme in taskThemes {
                lines.append("- \(theme.task) - \(theme.occurrences)x for \(format(duration: theme.duration))")
            }
        }
        if !browsingHighlights.isEmpty {
            lines.append("")
            lines.append("Browsing details:")
            for block in browsingHighlights {
                lines.append("- \(block.app): \(compactTask(block.task)) (\(format(duration: block.duration)))")
            }
        }
        if !communicationHighlights.isEmpty {
            lines.append("")
            lines.append("Communication details:")
            for block in communicationHighlights {
                lines.append("- \(block.app): \(compactTask(block.task)) (\(format(duration: block.duration)))")
            }
            for sample in communicationSamples {
                lines.append("- Typed sample [\(sample.app)]: \"\(sample.text)\"")
            }
        }
        lines.append("")
        lines.append("Hourly pattern (avg minutes tracked per hour):")
        let hourlyText = (0 ..< 24).map { hour in
            "\(String(format: "%02d", hour)):00 — \(Int((hourly[hour] ?? 0).rounded()))m"
        }.joined(separator: ", ")
        lines.append(hourlyText)
        lines.append("")
        lines.append("Context switches per hour (avg): \(String(format: "%.2f", switches.reduce(0) { $0 + $1.averageSwitches } / Double(max(switches.count, 1))))")
        if let peakTrackedHour {
            lines.append("Peak tracked hour: \(hourLabel(peakTrackedHour.key)) with \(Int(peakTrackedHour.value.rounded()))m average tracked")
        }
        if let peakDeepWorkHour, peakDeepWorkHour.value > 0 {
            lines.append("Peak deep-work hour: \(hourLabel(peakDeepWorkHour.key)) with \(Int(peakDeepWorkHour.value.rounded()))m average deep work")
        }
        if let longest {
            lines.append("Longest focus block: \(format(duration: longest.duration)) in \(longest.category.title) at \(format(date: longest.start))")
        }
        if let mostFragmented {
            lines.append("Most fragmented hour: \(hourLabel(mostFragmented.hour)) with \(String(format: "%.2f", mostFragmented.averageSwitches)) switches")
        }
        if !switchHotspots.isEmpty {
            lines.append("Switch-heavy hours: \(switchHotspots.map { "\(hourLabel($0.hour)) (\(String(format: "%.2f", $0.averageSwitches)))" }.joined(separator: ", "))")
        }
        if !transitions.isEmpty {
            lines.append("Common category handoffs: \(transitions.map { "\($0.from.title) -> \($0.to.title) (\($0.count))" }.joined(separator: ", "))")
        }

        // Keystroke data
        if !keystrokeRecords.isEmpty {
            lines.append("")
            lines.append("Keystroke activity:")
            let totalKeys = keystrokeRecords.reduce(0) { $0 + $1.keystrokeCount }
            lines.append("- Total keystrokes: \(totalKeys)")
            let byApp = Dictionary(grouping: keystrokeRecords, by: \.app)
            let topApps = byApp.map { app, records in
                (app, records.reduce(0) { $0 + $1.keystrokeCount })
            }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            lines.append("- Top typing apps: \(topApps.map { "\($0.0) (\($0.1) keys)" }.joined(separator: ", "))")

            // Sample text per top app (first 200 chars)
            for (app, _) in topApps.prefix(3) {
                let combinedText = byApp[app]?
                    .map(\.typedText)
                    .joined()
                    .prefix(200) ?? ""
                if !combinedText.isEmpty {
                    lines.append("- [\(app)] sample: \"\(combinedText)\"")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    static func buildComparisonSummary(
        currentSessions: [SessionRecord],
        currentInterval: DateInterval,
        previousSessions: [SessionRecord],
        previousInterval: DateInterval,
        calendar: Calendar = .current,
        fallbackInterval: TimeInterval = 60,
        currentKeystrokeRecords: [KeystrokeRecord] = [],
        previousKeystrokeRecords: [KeystrokeRecord] = []
    ) -> String {
        let current = comparisonSnapshot(
            sessions: currentSessions,
            interval: currentInterval,
            calendar: calendar,
            fallbackInterval: fallbackInterval,
            keystrokeRecords: currentKeystrokeRecords
        )
        let previous = comparisonSnapshot(
            sessions: previousSessions,
            interval: previousInterval,
            calendar: calendar,
            fallbackInterval: fallbackInterval,
            keystrokeRecords: previousKeystrokeRecords
        )

        var lines: [String] = []
        lines.append("Previous equivalent period: \(format(date: previousInterval.start)) to \(format(date: previousInterval.end))")

        guard previous.sessionCount > 0 || previous.totalTracked > 0 || previous.totalKeystrokes > 0 else {
            lines.append("No tracked baseline exists for the previous equivalent period.")
            return lines.joined(separator: "\n")
        }

        lines.append("Baseline coverage: \(format(duration: previous.totalTracked)) across \(previous.sessionCount) sessions over \(previous.dayCount) day(s)")
        lines.append("Tracked time delta: \(format(deltaDuration: current.totalTracked - previous.totalTracked))\(percentDeltaSuffix(current: current.totalTracked, previous: previous.totalTracked))")
        lines.append("Focus score delta: \(format(deltaPoints: current.focusScore - previous.focusScore))")
        lines.append("Deep work delta: \(format(deltaDuration: current.deepWorkDuration - previous.deepWorkDuration))\(percentDeltaSuffix(current: current.deepWorkDuration, previous: previous.deepWorkDuration))")
        lines.append("Reactive work delta: \(format(deltaDuration: current.reactiveDuration - previous.reactiveDuration))\(percentDeltaSuffix(current: current.reactiveDuration, previous: previous.reactiveDuration))")
        lines.append("Context switch delta: \(format(deltaCount: current.contextSwitches - previous.contextSwitches))")
        lines.append("Confidence delta: \(format(deltaPoints: (current.averageConfidence - previous.averageConfidence) * 100))")

        if current.totalKeystrokes > 0 || previous.totalKeystrokes > 0 {
            lines.append("Keystroke delta: \(format(deltaCount: current.totalKeystrokes - previous.totalKeystrokes))\(percentDeltaSuffix(current: Double(current.totalKeystrokes), previous: Double(previous.totalKeystrokes)))")
        }

        let categoryShifts = topDurationDeltas(
            current: current.categoryDurations,
            previous: previous.categoryDurations,
            limit: 4
        )
        if !categoryShifts.isEmpty {
            lines.append("Biggest category shifts: \(categoryShifts.joined(separator: ", "))")
        }

        let appShifts = topDurationDeltas(
            current: current.appDurations,
            previous: previous.appDurations,
            limit: 4
        )
        if !appShifts.isEmpty {
            lines.append("Biggest app shifts: \(appShifts.joined(separator: ", "))")
        }

        let typingShifts = topCountDeltas(
            current: current.typingByApp,
            previous: previous.typingByApp,
            limit: 3
        )
        if !typingShifts.isEmpty {
            lines.append("Typing shifts: \(typingShifts.joined(separator: ", "))")
        }

        if let currentPeak = current.peakTrackedHour, let previousPeak = previous.peakTrackedHour, currentPeak.hour != previousPeak.hour {
            lines.append("Peak tracked hour shift: \(hourLabel(previousPeak.hour)) -> \(hourLabel(currentPeak.hour))")
        }

        if let currentDeepPeak = current.peakDeepWorkHour, let previousDeepPeak = previous.peakDeepWorkHour, currentDeepPeak.hour != previousDeepPeak.hour {
            lines.append("Peak deep-work hour shift: \(hourLabel(previousDeepPeak.hour)) -> \(hourLabel(currentDeepPeak.hour))")
        }

        return lines.joined(separator: "\n")
    }

    static func enumerateDays(in interval: DateInterval, calendar: Calendar) -> [Date] {
        guard interval.end > interval.start else { return [calendar.startOfDay(for: interval.start)] }
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: interval.start)
        let inclusiveEnd = interval.end.addingTimeInterval(-1)
        let end = calendar.startOfDay(for: inclusiveEnd)

        while cursor <= end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return days
    }

    static func averageTrackedMinutesByHour(
        blocks: [SessionBlock],
        interval: DateInterval,
        calendar: Calendar = .current
    ) -> [Int: Double] {
        let days = enumerateDays(in: interval, calendar: calendar)
        guard !days.isEmpty else { return Dictionary(uniqueKeysWithValues: (0 ..< 24).map { ($0, 0) }) }

        return Dictionary(uniqueKeysWithValues: (0 ..< 24).map { hour in
            let totalMinutes = days.reduce(0.0) { partialResult, day in
                let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
                let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
                let interval = DateInterval(start: start, end: end)
                return partialResult + blocks.reduce(0) { $0 + overlapMinutes(block: $1, with: interval) }
            }
            return (hour, totalMinutes / Double(days.count))
        })
    }

    private static func overlapMinutes(block: SessionBlock, with interval: DateInterval) -> Double {
        let start = max(block.start, interval.start)
        let end = min(block.end, interval.end)
        guard end > start else { return 0 }
        return end.timeIntervalSince(start) / 60
    }

    private static func format(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Cross-Day Pattern Analysis

    /// 7×24 heatmap of average tracked minutes per weekday × hour.
    static func weeklyHeatmap(blocks: [SessionBlock], calendar: Calendar = .current) -> [WeeklyHeatCell] {
        // Group blocks by weekday
        var minutesByWeekdayHour = [Int: [Int: [Double]]]() // weekday -> hour -> [minutes per day]
        let dayBlocks = Dictionary(grouping: blocks, by: { calendar.startOfDay(for: $0.start) })

        for (day, dayBlockList) in dayBlocks {
            let weekday = calendar.component(.weekday, from: day)
            for hour in 0 ..< 24 {
                let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
                let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
                let interval = DateInterval(start: start, end: end)
                let mins = dayBlockList.reduce(0.0) { $0 + overlapMinutes(block: $1, with: interval) }
                minutesByWeekdayHour[weekday, default: [:]][hour, default: []].append(mins)
            }
        }

        return (1...7).flatMap { weekday in
            (0 ..< 24).map { hour in
                let values = minutesByWeekdayHour[weekday]?[hour] ?? []
                let avg = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
                return WeeklyHeatCell(dayOfWeek: weekday, hour: hour, averageMinutes: avg)
            }
        }
    }

    /// Per-day-of-week averages for productivity, tracked time, and context switches.
    static func dayOfWeekSummaries(blocks: [SessionBlock], calendar: Calendar = .current) -> [DayOfWeekSummary] {
        let dayBlocks = Dictionary(grouping: blocks, by: { calendar.startOfDay(for: $0.start) })

        var byWeekday = [Int: [(score: Double, minutes: Double, switches: Int)]]()
        for (day, dayBlockList) in dayBlocks {
            let weekday = calendar.component(.weekday, from: day)
            let score = focusScore(for: dayBlockList)
            let minutes = totalDuration(of: dayBlockList) / 60
            let switches = contextSwitchCount(in: dayBlockList)
            byWeekday[weekday, default: []].append((score, minutes, switches))
        }

        return (1...7).compactMap { weekday in
            guard let entries = byWeekday[weekday], !entries.isEmpty else {
                return DayOfWeekSummary(dayOfWeek: weekday, averageProductivityScore: 0, averageTrackedMinutes: 0, averageContextSwitches: 0)
            }
            let count = Double(entries.count)
            return DayOfWeekSummary(
                dayOfWeek: weekday,
                averageProductivityScore: entries.reduce(0) { $0 + $1.score } / count,
                averageTrackedMinutes: entries.reduce(0) { $0 + $1.minutes } / count,
                averageContextSwitches: entries.reduce(0) { $0 + Double($1.switches) } / count
            )
        }
    }

    /// Median duration of productive merged blocks.
    static func optimalSessionLength(blocks: [SessionBlock]) -> TimeInterval {
        let productive = mergedBlocks(from: blocks).filter { productiveCategories.contains($0.category) }
        guard !productive.isEmpty else { return 0 }
        let sorted = productive.map(\.duration).sorted()
        return sorted[sorted.count / 2]
    }

    /// Apps ranked by their ratio of focus time to total time.
    static func appFocusCorrelation(blocks: [SessionBlock]) -> [(app: String, focusRatio: Double)] {
        let byApp = Dictionary(grouping: blocks, by: \.app)
        return byApp.compactMap { app, appBlocks in
            let total = totalDuration(of: appBlocks)
            guard total > 60 else { return nil } // ignore trivial usage
            let focusDuration = appBlocks.filter { productiveCategories.contains($0.category) }.reduce(0) { $0 + $1.duration }
            return (app: app, focusRatio: focusDuration / total)
        }
        .sorted { $0.focusRatio > $1.focusRatio }
    }

    /// Generate text insight cards from cross-day pattern data.
    static func generatePatternInsights(
        daySummaries: [DayOfWeekSummary],
        weeklyHeatmap: [WeeklyHeatCell],
        blocks: [SessionBlock]
    ) -> [PatternInsight] {
        var insights: [PatternInsight] = []

        // Best day of the week
        if let best = daySummaries.max(by: { $0.averageProductivityScore < $1.averageProductivityScore }),
           best.averageProductivityScore > 0 {
            insights.append(PatternInsight(
                icon: "star.fill",
                title: "Most Productive Day",
                description: "\(best.dayName) averages \(Int(best.averageProductivityScore))% productivity with \(Int(best.averageTrackedMinutes))m tracked."
            ))
        }

        // Peak focus hours
        let topHours = weeklyHeatmap
            .filter { $0.averageMinutes > 0 }
            .sorted { $0.averageMinutes > $1.averageMinutes }
            .prefix(3)
        if let peak = topHours.first {
            insights.append(PatternInsight(
                icon: "flame.fill",
                title: "Peak Focus Hour",
                description: "\(String(format: "%02d", peak.hour)):00 on \(peak.dayName) is your most active hour (\(Int(peak.averageMinutes))m avg)."
            ))
        }

        // Context switch comparison
        if let calmest = daySummaries.filter({ $0.averageTrackedMinutes > 30 }).min(by: { $0.averageContextSwitches < $1.averageContextSwitches }),
           let busiest = daySummaries.max(by: { $0.averageContextSwitches < $1.averageContextSwitches }),
           calmest.dayOfWeek != busiest.dayOfWeek {
            insights.append(PatternInsight(
                icon: "arrow.triangle.swap",
                title: "Focus vs Fragmentation",
                description: "\(calmest.dayName) is your calmest (\(Int(calmest.averageContextSwitches)) switches), \(busiest.dayName) is most fragmented (\(Int(busiest.averageContextSwitches)) switches)."
            ))
        }

        // Optimal session length
        let optimal = optimalSessionLength(blocks: blocks)
        if optimal > 0 {
            insights.append(PatternInsight(
                icon: "timer",
                title: "Optimal Session Length",
                description: "Your median deep-work block is \(format(duration: optimal)). Plan focus sessions around this length."
            ))
        }

        // Top focus apps
        let focusApps = appFocusCorrelation(blocks: blocks).prefix(2)
        if let top = focusApps.first, top.focusRatio > 0 {
            insights.append(PatternInsight(
                icon: "app.badge.checkmark",
                title: "Focus App",
                description: "\(top.app) has the highest focus ratio (\(Int(top.focusRatio * 100))% deep work)."
            ))
        }

        return insights
    }

    private static func duration(of blocks: [SessionBlock], in categories: Set<ActivityCategory>) -> TimeInterval {
        blocks
            .filter { categories.contains($0.category) }
            .reduce(0) { $0 + $1.duration }
    }

    private static func comparisonSnapshot(
        sessions: [SessionRecord],
        interval: DateInterval,
        calendar: Calendar,
        fallbackInterval: TimeInterval,
        keystrokeRecords: [KeystrokeRecord]
    ) -> ComparisonSnapshot {
        let blocks = blocks(from: sessions, fallbackInterval: fallbackInterval)
        let groupedApps = Dictionary(grouping: blocks, by: \.app)
        let hourly = averageTrackedMinutesByHour(blocks: blocks, interval: interval, calendar: calendar)
        let deepWorkHourly = averageTrackedMinutesByHour(
            blocks: blocks.filter { productiveCategories.contains($0.category) },
            interval: interval,
            calendar: calendar
        )
        let typingByApp = Dictionary(
            grouping: keystrokeRecords,
            by: \.app
        ).mapValues { records in
            records.reduce(0) { $0 + $1.keystrokeCount }
        }

        return ComparisonSnapshot(
            sessionCount: sessions.count,
            dayCount: enumerateDays(in: interval, calendar: calendar).count,
            totalTracked: totalDuration(of: blocks),
            focusScore: focusScore(for: blocks),
            deepWorkDuration: duration(of: blocks, in: productiveCategories),
            reactiveDuration: duration(of: blocks, in: reactiveCategories),
            contextSwitches: contextSwitchCount(in: blocks),
            averageConfidence: blocks.isEmpty ? 0 : blocks.reduce(0.0) { $0 + $1.confidence } / Double(blocks.count),
            categoryDurations: Dictionary(uniqueKeysWithValues: categorySummaries(for: blocks).map { ($0.category.title, $0.duration) }),
            appDurations: groupedApps.mapValues { totalDuration(of: $0) },
            peakTrackedHour: hourly.max(by: { $0.value < $1.value }).flatMap { $0.value > 0 ? ($0.key, $0.value) : nil },
            peakDeepWorkHour: deepWorkHourly.max(by: { $0.value < $1.value }).flatMap { $0.value > 0 ? ($0.key, $0.value) : nil },
            totalKeystrokes: keystrokeRecords.reduce(0) { $0 + $1.keystrokeCount },
            typingByApp: typingByApp
        )
    }

    private static func percentageString(_ duration: TimeInterval, total: TimeInterval) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int(((duration / total) * 100).rounded()))%"
    }

    private static func percentDeltaSuffix(current: Double, previous: Double) -> String {
        guard previous > 0 else { return "" }
        let delta = ((current - previous) / previous) * 100
        return " (\(format(signedNumber: delta))%)"
    }

    private static func focusHeavyApps(for blocks: [SessionBlock], limit: Int) -> [(app: String, focusRatio: Double, duration: TimeInterval)] {
        let byApp = Dictionary(grouping: blocks, by: \.app)
        return byApp.compactMap { app, appBlocks in
            let total = totalDuration(of: appBlocks)
            guard total >= 180 else { return nil }
            let focusDuration = duration(of: appBlocks, in: productiveCategories)
            guard focusDuration > 0 else { return nil }
            return (app: app, focusRatio: focusDuration / total, duration: total)
        }
        .sorted {
            if $0.focusRatio == $1.focusRatio {
                return $0.duration > $1.duration
            }
            return $0.focusRatio > $1.focusRatio
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func detailHighlights(
        in blocks: [SessionBlock],
        categories: Set<ActivityCategory>,
        limit: Int
    ) -> [SessionBlock] {
        blocks
            .filter { categories.contains($0.category) && !compactTask($0.task).isEmpty }
            .sorted {
                if $0.duration == $1.duration {
                    return $0.start < $1.start
                }
                return $0.duration > $1.duration
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func keystrokeSamples(
        from records: [KeystrokeRecord],
        apps: Set<String>,
        limit: Int
    ) -> [(app: String, text: String)] {
        guard !apps.isEmpty else { return [] }

        let grouped = Dictionary(grouping: records.filter { apps.contains($0.app) }, by: \.app)
        return grouped.compactMap { app, appRecords in
            let sample = appRecords
                .map(\.typedText)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sample.isEmpty else { return nil }
            return (app: app, text: compactTask(sample, maxLength: 140))
        }
        .sorted { $0.text.count > $1.text.count }
        .prefix(limit)
        .map { $0 }
    }

    private static func topTaskThemes(in blocks: [SessionBlock], limit: Int) -> [(task: String, occurrences: Int, duration: TimeInterval)] {
        var buckets: [String: (task: String, occurrences: Int, duration: TimeInterval)] = [:]

        for block in blocks {
            let task = compactTask(block.task)
            guard !task.isEmpty else { continue }

            let key = task.lowercased()
            var bucket = buckets[key] ?? (task: task, occurrences: 0, duration: 0)
            bucket.occurrences += 1
            bucket.duration += block.duration
            if task.count > bucket.task.count {
                bucket.task = task
            }
            buckets[key] = bucket
        }

        return buckets.values
            .sorted {
                if $0.duration == $1.duration {
                    return $0.occurrences > $1.occurrences
                }
                return $0.duration > $1.duration
            }
            .prefix(limit)
            .map { $0 }
    }

    private static func topCategoryTransitions(in blocks: [SessionBlock], limit: Int) -> [(from: ActivityCategory, to: ActivityCategory, count: Int)] {
        var counts: [String: (from: ActivityCategory, to: ActivityCategory, count: Int)] = [:]

        for (lhs, rhs) in zip(blocks, blocks.dropFirst()) {
            guard lhs.category != rhs.category else { continue }

            let key = "\(lhs.category.rawValue)->\(rhs.category.rawValue)"
            var bucket = counts[key] ?? (from: lhs.category, to: rhs.category, count: 0)
            bucket.count += 1
            counts[key] = bucket
        }

        return counts.values
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }

    private static func compactTask(_ task: String, maxLength: Int = 96) -> String {
        let collapsed = task
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !collapsed.isEmpty else { return "" }
        guard collapsed.count > maxLength else { return collapsed }
        let index = collapsed.index(collapsed.startIndex, offsetBy: maxLength - 3)
        return String(collapsed[..<index]) + "..."
    }

    private static func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private static func format(time: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: time)
    }

    private static func format(deltaDuration: TimeInterval) -> String {
        let sign = deltaDuration >= 0 ? "+" : "-"
        return "\(sign)\(format(duration: abs(deltaDuration)))"
    }

    private static func format(deltaCount: Int) -> String {
        let sign = deltaCount >= 0 ? "+" : ""
        return "\(sign)\(deltaCount)"
    }

    private static func format(deltaPoints: Double) -> String {
        let rounded = Int(deltaPoints.rounded())
        let sign = rounded >= 0 ? "+" : ""
        return "\(sign)\(rounded) pts"
    }

    private static func format(signedNumber: Double) -> String {
        let rounded = Int(deltaRounded(delta: signedNumber))
        let sign = rounded >= 0 ? "+" : ""
        return "\(sign)\(rounded)"
    }

    private static func topDurationDeltas<Key: Hashable>(
        current: [Key: TimeInterval],
        previous: [Key: TimeInterval],
        limit: Int
    ) -> [String] where Key: CustomStringConvertible {
        let keys = Set(current.keys).union(previous.keys)
        return keys.compactMap { key -> (String, TimeInterval)? in
            let delta = (current[key] ?? 0) - (previous[key] ?? 0)
            guard abs(delta) >= 60 else { return nil }
            return ("\(key.description) \(format(deltaDuration: delta))", abs(delta))
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
    }

    private static func topCountDeltas<Key: Hashable>(
        current: [Key: Int],
        previous: [Key: Int],
        limit: Int
    ) -> [String] where Key: CustomStringConvertible {
        let keys = Set(current.keys).union(previous.keys)
        return keys.compactMap { key -> (String, Int)? in
            let delta = (current[key] ?? 0) - (previous[key] ?? 0)
            guard abs(delta) >= 25 else { return nil }
            return ("\(key.description) \(format(deltaCount: delta))", abs(delta))
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        .map(\.0)
    }

    private static func deltaRounded(delta: Double) -> Double {
        if delta.isNaN || delta.isInfinite {
            return 0
        }
        return delta.rounded()
    }
}
