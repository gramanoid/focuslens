import AppKit
import Foundation
import GRDB

struct SessionRecord: Identifiable, Codable, Hashable {
    var id: Int64?
    var timestamp: Date
    var app: String
    var bundleID: String?
    var category: ActivityCategory
    var task: String
    var confidence: Double
    var screenshotPath: String?
    var rawResponse: String?

    init(
        id: Int64? = nil,
        timestamp: Date,
        app: String,
        bundleID: String? = nil,
        category: ActivityCategory,
        task: String,
        confidence: Double,
        screenshotPath: String? = nil,
        rawResponse: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.app = app
        self.bundleID = bundleID
        self.category = category
        self.task = task
        self.confidence = confidence
        self.screenshotPath = screenshotPath
        self.rawResponse = rawResponse
    }

    init(row: Row) {
        id = row["id"]
        let timestampValue: Double = row["timestamp"] ?? 0
        timestamp = Date(timeIntervalSince1970: timestampValue)
        bundleID = row["bundle_id"]
        let storedApp: String = row["app"] ?? "Unknown"
        app = AppIconResolver.displayName(for: bundleID, fallback: storedApp)
        let categoryValue: String = row["category"] ?? ActivityCategory.unknown.rawValue
        category = ActivityCategory(rawValue: categoryValue) ?? .unknown
        task = row["task"] ?? ""
        confidence = row["confidence"] ?? 0
        screenshotPath = row["screenshot_path"]
        rawResponse = row["raw_response"]
    }
}
