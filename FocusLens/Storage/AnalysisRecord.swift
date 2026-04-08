import Foundation
import GRDB

enum AnalysisType: String, Codable, CaseIterable, Identifiable {
    case dailyRecap = "Daily Recap"
    case productivityAnalysis = "Productivity Analysis"
    case recommendations = "Recommendations"
    case weekInReview = "Week in Review"
    case customPrompt = "Custom Prompt"

    var id: String { rawValue }

    var defaultPrompt: String {
        switch self {
        case .dailyRecap:
            "Summarize what you worked on with concrete references to apps, times, and category shifts."
        case .productivityAnalysis:
            "Analyze your focus patterns, peak hours, distractions, and work rhythms from the data."
        case .recommendations:
            "Generate specific productivity recommendations for you grounded in the data."
        case .weekInReview:
            "Write a weekly review of your wins, major themes, and notable work patterns."
        case .customPrompt:
            ""
        }
    }
}

struct AnalysisRecord: Identifiable, Codable, Hashable {
    var id: Int64?
    var timestamp: Date
    var type: AnalysisType
    var dateRangeStart: Date
    var dateRangeEnd: Date
    var prompt: String
    var response: String

    init(
        id: Int64? = nil,
        timestamp: Date = .now,
        type: AnalysisType,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        prompt: String,
        response: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.type = type
        self.dateRangeStart = dateRangeStart
        self.dateRangeEnd = dateRangeEnd
        self.prompt = prompt
        self.response = response
    }

    init(row: Row) {
        id = row["id"]
        timestamp = Date(timeIntervalSince1970: row["timestamp"] ?? 0)
        type = AnalysisType(rawValue: row["type"] ?? AnalysisType.dailyRecap.rawValue) ?? .dailyRecap
        dateRangeStart = Date(timeIntervalSince1970: row["date_range_start"] ?? 0)
        dateRangeEnd = Date(timeIntervalSince1970: row["date_range_end"] ?? 0)
        prompt = row["prompt"] ?? ""
        response = row["response"] ?? ""
    }
}
