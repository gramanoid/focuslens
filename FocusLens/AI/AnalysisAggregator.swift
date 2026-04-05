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

enum AnalysisAggregator {
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
            .filter { [.coding, .writing, .design].contains($0.category) }
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
        let focusDuration = blocks
            .filter { [.coding, .writing, .design].contains($0.category) }
            .reduce(0) { $0 + $1.duration }
        return (focusDuration / total) * 100
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
        calendar: Calendar = .current
    ) -> String {
        let blocks = blocks(from: sessions)
        let summaries = categorySummaries(for: blocks)
        let apps = appUsage(for: blocks)
        let hourly = averageTrackedMinutesByHour(blocks: blocks, interval: interval, calendar: calendar)
        let switches = averageSwitchesByHour(blocks: blocks, interval: interval, calendar: calendar)
        let longest = longestFocusBlock(in: blocks)
        let mostFragmented = switches.max(by: { $0.averageSwitches < $1.averageSwitches })

        var lines: [String] = []
        lines.append("Date range: \(format(date: interval.start)) to \(format(date: interval.end))")
        lines.append("Total sessions: \(sessions.count)")
        lines.append("Total tracked time: \(format(duration: totalDuration(of: blocks)))")
        lines.append("")
        lines.append("Category breakdown:")
        summaries.forEach { summary in
            lines.append("- \(summary.category.rawValue): \(format(duration: summary.duration)) (\(Int(summary.percentage * 100))%)")
        }
        lines.append("")
        lines.append("Top apps by time:")
        for (index, app) in apps.enumerated() {
            lines.append("\(index + 1). \(app.app) — \(format(duration: app.duration))")
        }
        lines.append("")
        lines.append("Hourly pattern (avg minutes tracked per hour):")
        let hourlyText = (0 ..< 24).map { hour in
            "\(String(format: "%02d", hour)):00 — \(Int((hourly[hour] ?? 0).rounded()))m"
        }.joined(separator: ", ")
        lines.append(hourlyText)
        lines.append("")
        lines.append("Context switches per hour (avg): \(String(format: "%.2f", switches.reduce(0) { $0 + $1.averageSwitches } / Double(max(switches.count, 1))))")
        if let longest {
            lines.append("Longest focus block: \(format(duration: longest.duration)) in \(longest.category.rawValue) at \(format(date: longest.start))")
        }
        if let mostFragmented {
            lines.append("Most fragmented hour: \(String(format: "%02d", mostFragmented.hour)):00 with \(String(format: "%.2f", mostFragmented.averageSwitches)) switches")
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
}
