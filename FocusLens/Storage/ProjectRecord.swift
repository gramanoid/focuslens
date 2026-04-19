import Foundation
import GRDB

struct ProjectRecord: Identifiable, Codable, Hashable {
    var id: Int64?
    var name: String
    var firstSeen: Date
    var lastSeen: Date
    var totalDuration: TimeInterval
    var dominantApps: String // JSON array of app names
    var categoryDistribution: String // JSON object { category: seconds }
    var sessionCount: Int

    init(
        id: Int64? = nil,
        name: String,
        firstSeen: Date,
        lastSeen: Date,
        totalDuration: TimeInterval = 0,
        dominantApps: String = "[]",
        categoryDistribution: String = "{}",
        sessionCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.totalDuration = totalDuration
        self.dominantApps = dominantApps
        self.categoryDistribution = categoryDistribution
        self.sessionCount = sessionCount
    }

    init(row: Row) {
        id = row["id"]
        name = row["name"] ?? ""
        firstSeen = Date(timeIntervalSince1970: row["first_seen"] ?? 0)
        lastSeen = Date(timeIntervalSince1970: row["last_seen"] ?? 0)
        totalDuration = row["total_duration"] ?? 0
        dominantApps = row["dominant_apps"] ?? "[]"
        categoryDistribution = row["category_distribution"] ?? "{}"
        sessionCount = row["session_count"] ?? 0
    }
}

struct DailySnapshot: Identifiable, Codable, Hashable {
    var id: Int64?
    var date: Date // start of day
    var focusScore: Double
    var deepWorkMinutes: Double
    var reactiveMinutes: Double
    var contextSwitches: Int
    var topApp: String?
    var topCategory: String?
    var sessionCount: Int
    var keystrokeCount: Int

    init(
        id: Int64? = nil,
        date: Date,
        focusScore: Double,
        deepWorkMinutes: Double,
        reactiveMinutes: Double,
        contextSwitches: Int,
        topApp: String? = nil,
        topCategory: String? = nil,
        sessionCount: Int,
        keystrokeCount: Int
    ) {
        self.id = id
        self.date = date
        self.focusScore = focusScore
        self.deepWorkMinutes = deepWorkMinutes
        self.reactiveMinutes = reactiveMinutes
        self.contextSwitches = contextSwitches
        self.topApp = topApp
        self.topCategory = topCategory
        self.sessionCount = sessionCount
        self.keystrokeCount = keystrokeCount
    }

    init(row: Row) {
        id = row["id"]
        date = Date(timeIntervalSince1970: row["date"] ?? 0)
        focusScore = row["focus_score"] ?? 0
        deepWorkMinutes = row["deep_work_minutes"] ?? 0
        reactiveMinutes = row["reactive_minutes"] ?? 0
        contextSwitches = row["context_switches"] ?? 0
        topApp = row["top_app"]
        topCategory = row["top_category"]
        sessionCount = row["session_count"] ?? 0
        keystrokeCount = row["keystroke_count"] ?? 0
    }
}

struct AnomalyEvent: Identifiable, Codable, Hashable {
    var id: Int64?
    var timestamp: Date
    var metric: String
    var value: Double
    var baselineMean: Double
    var baselineStddev: Double
    var severity: String // "low", "medium", "high"
    var message: String

    init(
        id: Int64? = nil,
        timestamp: Date,
        metric: String,
        value: Double,
        baselineMean: Double,
        baselineStddev: Double,
        severity: String,
        message: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.metric = metric
        self.value = value
        self.baselineMean = baselineMean
        self.baselineStddev = baselineStddev
        self.severity = severity
        self.message = message
    }

    init(row: Row) {
        id = row["id"]
        timestamp = Date(timeIntervalSince1970: row["timestamp"] ?? 0)
        metric = row["metric"] ?? ""
        value = row["value"] ?? 0
        baselineMean = row["baseline_mean"] ?? 0
        baselineStddev = row["baseline_stddev"] ?? 0
        severity = row["severity"] ?? "low"
        message = row["message"] ?? ""
    }

    /// Number of standard deviations from the mean.
    var sigma: Double {
        guard baselineStddev > 0 else { return 0 }
        return abs(value - baselineMean) / baselineStddev
    }
}
