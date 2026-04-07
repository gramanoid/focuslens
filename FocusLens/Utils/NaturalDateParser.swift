import Foundation

/// Extracts date ranges from natural language queries.
/// Returns the cleaned query text and an optional DateInterval.
enum NaturalDateParser {

    static func parse(_ input: String, now: Date = .now, calendar: Calendar = .current) -> (query: String, dateRange: DateInterval?) {
        let lowered = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Check keyword patterns first
        for (pattern, resolver) in keywordPatterns {
            if let range = lowered.range(of: pattern) {
                var cleaned = input
                cleaned.removeSubrange(range)
                cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                let interval = resolver(now, calendar)
                return (cleaned.isEmpty ? input : cleaned, interval)
            }
        }

        // Fall through: no date detected
        return (input, nil)
    }

    // MARK: - Private

    private static let keywordPatterns: [(String, (Date, Calendar) -> DateInterval)] = [
        ("today", { now, cal in
            let start = cal.startOfDay(for: now)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            return DateInterval(start: start, end: end)
        }),
        ("yesterday", { now, cal in
            let todayStart = cal.startOfDay(for: now)
            let start = cal.date(byAdding: .day, value: -1, to: todayStart)!
            return DateInterval(start: start, end: todayStart)
        }),
        ("this week", { now, cal in
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            let start = cal.date(from: comps)!
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: start)!
            return DateInterval(start: start, end: end)
        }),
        ("last week", { now, cal in
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            let thisWeek = cal.date(from: comps)!
            let start = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeek)!
            return DateInterval(start: start, end: thisWeek)
        }),
        ("this month", { now, cal in
            let comps = cal.dateComponents([.year, .month], from: now)
            let start = cal.date(from: comps)!
            let end = cal.date(byAdding: .month, value: 1, to: start)!
            return DateInterval(start: start, end: end)
        }),
        ("last month", { now, cal in
            let comps = cal.dateComponents([.year, .month], from: now)
            let thisMonth = cal.date(from: comps)!
            let start = cal.date(byAdding: .month, value: -1, to: thisMonth)!
            return DateInterval(start: start, end: thisMonth)
        }),
        ("this morning", { now, cal in
            let start = cal.startOfDay(for: now)
            let end = cal.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
            return DateInterval(start: start, end: end)
        }),
        ("this afternoon", { now, cal in
            let start = cal.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
            let end = cal.date(bySettingHour: 17, minute: 0, second: 0, of: now)!
            return DateInterval(start: start, end: end)
        }),
        ("this evening", { now, cal in
            let start = cal.date(bySettingHour: 17, minute: 0, second: 0, of: now)!
            let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
            return DateInterval(start: start, end: end)
        }),
    ]
}
