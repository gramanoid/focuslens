import Foundation
import GRDB

struct KeystrokeRecord: Identifiable, Codable, Hashable {
    var id: Int64?
    var sessionID: Int64
    var timestamp: Date
    var app: String
    var bundleID: String?
    var typedText: String
    var keystrokeCount: Int

    init(
        id: Int64? = nil,
        sessionID: Int64,
        timestamp: Date,
        app: String,
        bundleID: String? = nil,
        typedText: String,
        keystrokeCount: Int
    ) {
        self.id = id
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.app = app
        self.bundleID = bundleID
        self.typedText = typedText
        self.keystrokeCount = keystrokeCount
    }

    init(row: Row) {
        id = row["id"]
        sessionID = row["session_id"]
        let timestampValue: Double = row["timestamp"] ?? 0
        timestamp = Date(timeIntervalSince1970: timestampValue)
        app = row["app"] ?? "Unknown"
        bundleID = row["bundle_id"]
        typedText = row["typed_text"] ?? ""
        keystrokeCount = row["keystroke_count"] ?? 0
    }
}
