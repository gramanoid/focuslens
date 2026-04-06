import Foundation
import GRDB

enum DatabaseStorageMode: Equatable {
    case persistent(URL)
    case inMemory
}

final class AppDatabase: @unchecked Sendable {
    let dbQueue: DatabaseQueue
    let storageMode: DatabaseStorageMode
    let startupWarning: String?

    init(storageMode: DatabaseStorageMode, startupWarning: String? = nil) throws {
        self.storageMode = storageMode
        self.startupWarning = startupWarning
        switch storageMode {
        case .persistent(let url):
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            dbQueue = try DatabaseQueue(path: url.path)
        case .inMemory:
            dbQueue = try DatabaseQueue()
        }
        try migrator.migrate(dbQueue)
    }

    static func makeDefault() -> AppDatabase {
        do {
            let appSupportDirectory = try ImageHelpers.applicationSupportDirectory()
            let databaseURL = appSupportDirectory.appendingPathComponent("focuslens.sqlite")
            return try AppDatabase(storageMode: .persistent(databaseURL))
        } catch {
            do {
                return try AppDatabase(
                    storageMode: .inMemory,
                    startupWarning: "FocusLens fell back to in-memory storage: \(error.localizedDescription)"
                )
            } catch {
                preconditionFailure("Unable to initialize any database: \(error.localizedDescription)")
            }
        }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createSessions") { db in
            try db.create(table: "sessions", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("timestamp", .double).notNull()
                table.column("app", .text).notNull()
                table.column("bundle_id", .text)
                table.column("category", .text).notNull()
                table.column("task", .text).notNull()
                table.column("confidence", .double).notNull()
                table.column("screenshot_path", .text)
                table.column("raw_response", .text)
            }
            try db.create(index: "sessions_timestamp_idx", on: "sessions", columns: ["timestamp"], ifNotExists: true)
        }

        migrator.registerMigration("createKeystrokes") { db in
            try db.create(table: "keystrokes", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("session_id", .integer).notNull().references("sessions", onDelete: .cascade)
                table.column("timestamp", .double).notNull()
                table.column("app", .text).notNull()
                table.column("bundle_id", .text)
                table.column("typed_text", .text).notNull()
                table.column("keystroke_count", .integer).notNull()
            }
            try db.create(index: "keystrokes_session_idx", on: "keystrokes", columns: ["session_id"], ifNotExists: true)
        }

        migrator.registerMigration("createAnalyses") { db in
            try db.create(table: "analyses", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("timestamp", .double).notNull()
                table.column("type", .text).notNull()
                table.column("date_range_start", .double).notNull()
                table.column("date_range_end", .double).notNull()
                table.column("prompt", .text).notNull()
                table.column("response", .text).notNull()
            }
            try db.create(index: "analyses_timestamp_idx", on: "analyses", columns: ["timestamp"], ifNotExists: true)
        }

        return migrator
    }

    @discardableResult
    func saveSession(_ session: SessionRecord) throws -> SessionRecord {
        var stored = session
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO sessions (timestamp, app, bundle_id, category, task, confidence, screenshot_path, raw_response)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    stored.timestamp.timeIntervalSince1970,
                    stored.app,
                    stored.bundleID,
                    stored.category.rawValue,
                    stored.task,
                    stored.confidence,
                    stored.screenshotPath,
                    stored.rawResponse
                ]
            )
            stored.id = db.lastInsertedRowID
        }
        return stored
    }

    func fetchRecentSessions(limit: Int = 5) throws -> [SessionRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM sessions ORDER BY timestamp DESC LIMIT ?",
                arguments: [limit]
            ).map(SessionRecord.init(row:))
        }
    }

    func fetchSessions(in interval: DateInterval) throws -> [SessionRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT *
                FROM sessions
                WHERE timestamp >= ? AND timestamp < ?
                ORDER BY timestamp ASC
                """,
                arguments: [interval.start.timeIntervalSince1970, interval.end.timeIntervalSince1970]
            ).map(SessionRecord.init(row:))
        }
    }

    func fetchDistinctApps() throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT DISTINCT app
                FROM sessions
                WHERE app <> ''
                ORDER BY app COLLATE NOCASE ASC
                """
            )
        }
    }

    @discardableResult
    func saveAnalysis(_ analysis: AnalysisRecord) throws -> AnalysisRecord {
        var stored = analysis
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO analyses (timestamp, type, date_range_start, date_range_end, prompt, response)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    stored.timestamp.timeIntervalSince1970,
                    stored.type.rawValue,
                    stored.dateRangeStart.timeIntervalSince1970,
                    stored.dateRangeEnd.timeIntervalSince1970,
                    stored.prompt,
                    stored.response
                ]
            )
            stored.id = db.lastInsertedRowID
        }
        return stored
    }

    func fetchAnalyses(limit: Int = 50) throws -> [AnalysisRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM analyses ORDER BY timestamp DESC LIMIT ?",
                arguments: [limit]
            ).map(AnalysisRecord.init(row:))
        }
    }

    func deleteAnalysis(id: Int64) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM analyses WHERE id = ?", arguments: [id])
        }
    }

    // MARK: - Keystrokes

    func saveKeystrokes(_ records: [KeystrokeRecord]) throws {
        guard !records.isEmpty else { return }
        try dbQueue.write { db in
            for record in records {
                try db.execute(
                    sql: """
                    INSERT INTO keystrokes (session_id, timestamp, app, bundle_id, typed_text, keystroke_count)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        record.sessionID,
                        record.timestamp.timeIntervalSince1970,
                        record.app,
                        record.bundleID,
                        record.typedText,
                        record.keystrokeCount
                    ]
                )
            }
        }
    }

    func fetchKeystrokes(forSession sessionID: Int64) throws -> [KeystrokeRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM keystrokes WHERE session_id = ? ORDER BY timestamp ASC",
                arguments: [sessionID]
            ).map(KeystrokeRecord.init(row:))
        }
    }

    func fetchKeystrokes(in interval: DateInterval) throws -> [KeystrokeRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT *
                FROM keystrokes
                WHERE timestamp >= ? AND timestamp < ?
                ORDER BY timestamp ASC
                """,
                arguments: [interval.start.timeIntervalSince1970, interval.end.timeIntervalSince1970]
            ).map(KeystrokeRecord.init(row:))
        }
    }
}
