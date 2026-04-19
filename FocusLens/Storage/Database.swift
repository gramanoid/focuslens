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

        migrator.registerMigration("createSessionsFTS") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS sessions_fts USING fts5(
                    task, app, content='sessions', content_rowid='id'
                )
            """)
            try db.execute(sql: """
                INSERT INTO sessions_fts(rowid, task, app)
                SELECT id, task, app FROM sessions
            """)
            // Auto-sync triggers
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS sessions_fts_ai AFTER INSERT ON sessions BEGIN
                    INSERT INTO sessions_fts(rowid, task, app) VALUES (new.id, new.task, new.app);
                END
            """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS sessions_fts_ad AFTER DELETE ON sessions BEGIN
                    INSERT INTO sessions_fts(sessions_fts, rowid, task, app) VALUES('delete', old.id, old.task, old.app);
                END
            """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS sessions_fts_au AFTER UPDATE ON sessions BEGIN
                    INSERT INTO sessions_fts(sessions_fts, rowid, task, app) VALUES('delete', old.id, old.task, old.app);
                    INSERT INTO sessions_fts(rowid, task, app) VALUES (new.id, new.task, new.app);
                END
            """)
        }

        migrator.registerMigration("createKeystrokesFTS") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS keystrokes_fts USING fts5(
                    typed_text, app, content='keystrokes', content_rowid='id'
                )
            """)
            try db.execute(sql: """
                INSERT INTO keystrokes_fts(rowid, typed_text, app)
                SELECT id, typed_text, app FROM keystrokes
            """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS keystrokes_fts_ai AFTER INSERT ON keystrokes BEGIN
                    INSERT INTO keystrokes_fts(rowid, typed_text, app) VALUES (new.id, new.typed_text, new.app);
                END
            """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS keystrokes_fts_ad AFTER DELETE ON keystrokes BEGIN
                    INSERT INTO keystrokes_fts(keystrokes_fts, rowid, typed_text, app) VALUES('delete', old.id, old.typed_text, old.app);
                END
            """)
            try db.execute(sql: """
                CREATE TRIGGER IF NOT EXISTS keystrokes_fts_au AFTER UPDATE ON keystrokes BEGIN
                    INSERT INTO keystrokes_fts(keystrokes_fts, rowid, typed_text, app) VALUES('delete', old.id, old.typed_text, old.app);
                    INSERT INTO keystrokes_fts(rowid, typed_text, app) VALUES (new.id, new.typed_text, new.app);
                END
            """)
        }

        migrator.registerMigration("createProjects") { db in
            try db.create(table: "projects", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull()
                table.column("first_seen", .double).notNull()
                table.column("last_seen", .double).notNull()
                table.column("total_duration", .double).notNull().defaults(to: 0)
                table.column("dominant_apps", .text).notNull().defaults(to: "[]")
                table.column("category_distribution", .text).notNull().defaults(to: "{}")
                table.column("session_count", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("createSessionProjects") { db in
            try db.create(table: "session_projects", ifNotExists: true) { table in
                table.column("session_id", .integer).notNull().references("sessions", onDelete: .cascade)
                table.column("project_id", .integer).notNull().references("projects", onDelete: .cascade)
                table.primaryKey(["session_id", "project_id"])
            }
            try db.create(index: "session_projects_session_idx", on: "session_projects", columns: ["session_id"], ifNotExists: true)
            try db.create(index: "session_projects_project_idx", on: "session_projects", columns: ["project_id"], ifNotExists: true)
        }

        migrator.registerMigration("createSessionEmbeddings") { db in
            try db.create(table: "session_embeddings", ifNotExists: true) { table in
                table.column("session_id", .integer).notNull().references("sessions", onDelete: .cascade).unique()
                table.column("embedding", .blob).notNull()
                table.column("dimensions", .integer).notNull()
            }
            try db.create(index: "session_embeddings_session_idx", on: "session_embeddings", columns: ["session_id"], ifNotExists: true)
        }

        migrator.registerMigration("createDailySnapshots") { db in
            try db.create(table: "daily_snapshots", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("date", .double).notNull().unique()
                table.column("focus_score", .double).notNull().defaults(to: 0)
                table.column("deep_work_minutes", .double).notNull().defaults(to: 0)
                table.column("reactive_minutes", .double).notNull().defaults(to: 0)
                table.column("context_switches", .integer).notNull().defaults(to: 0)
                table.column("top_app", .text)
                table.column("top_category", .text)
                table.column("session_count", .integer).notNull().defaults(to: 0)
                table.column("keystroke_count", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("createAnomalyEvents") { db in
            try db.create(table: "anomaly_events", ifNotExists: true) { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("timestamp", .double).notNull()
                table.column("metric", .text).notNull()
                table.column("value", .double).notNull()
                table.column("baseline_mean", .double).notNull()
                table.column("baseline_stddev", .double).notNull()
                table.column("severity", .text).notNull()
                table.column("message", .text).notNull()
            }
            try db.create(index: "anomaly_events_timestamp_idx", on: "anomaly_events", columns: ["timestamp"], ifNotExists: true)
        }

        return migrator
    }

    // MARK: - Search

    func searchSessions(query: String, in interval: DateInterval? = nil, limit: Int = 50) throws -> [SessionRecord] {
        try dbQueue.read { db in
            let ftsQuery = query.split(separator: " ").map { "\($0)*" }.joined(separator: " ")
            if let interval {
                return try Row.fetchAll(
                    db,
                    sql: """
                        SELECT s.*
                        FROM sessions s
                        JOIN sessions_fts ON sessions_fts.rowid = s.id
                        WHERE sessions_fts MATCH ?
                          AND s.timestamp >= ? AND s.timestamp < ?
                        ORDER BY rank LIMIT ?
                    """,
                    arguments: [ftsQuery, interval.start.timeIntervalSince1970, interval.end.timeIntervalSince1970, limit]
                ).map(SessionRecord.init(row:))
            } else {
                return try Row.fetchAll(
                    db,
                    sql: """
                        SELECT s.*
                        FROM sessions s
                        JOIN sessions_fts ON sessions_fts.rowid = s.id
                        WHERE sessions_fts MATCH ?
                        ORDER BY rank LIMIT ?
                    """,
                    arguments: [ftsQuery, limit]
                ).map(SessionRecord.init(row:))
            }
        }
    }

    func searchKeystrokes(query: String, in interval: DateInterval? = nil, limit: Int = 50) throws -> [KeystrokeRecord] {
        try dbQueue.read { db in
            let ftsQuery = query.split(separator: " ").map { "\($0)*" }.joined(separator: " ")
            if let interval {
                return try Row.fetchAll(
                    db,
                    sql: """
                        SELECT k.*
                        FROM keystrokes k
                        JOIN keystrokes_fts ON keystrokes_fts.rowid = k.id
                        WHERE keystrokes_fts MATCH ?
                          AND k.timestamp >= ? AND k.timestamp < ?
                        ORDER BY rank LIMIT ?
                    """,
                    arguments: [ftsQuery, interval.start.timeIntervalSince1970, interval.end.timeIntervalSince1970, limit]
                ).map(KeystrokeRecord.init(row:))
            } else {
                return try Row.fetchAll(
                    db,
                    sql: """
                        SELECT k.*
                        FROM keystrokes k
                        JOIN keystrokes_fts ON keystrokes_fts.rowid = k.id
                        WHERE keystrokes_fts MATCH ?
                        ORDER BY rank LIMIT ?
                    """,
                    arguments: [ftsQuery, limit]
                ).map(KeystrokeRecord.init(row:))
            }
        }
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

    func fetchLowQualitySessions(limit: Int = 20) throws -> [SessionRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM sessions
                WHERE (category = 'other' OR category = 'unknown' OR confidence < 0.5)
                AND screenshot_path IS NOT NULL
                AND category != 'sleeping'
                ORDER BY timestamp DESC
                LIMIT ?
                """,
                arguments: [limit]
            ).map(SessionRecord.init(row:))
        }
    }

    func updateSession(id: Int64, category: String, task: String, confidence: Double, rawResponse: String?) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE sessions SET category = ?, task = ?, confidence = ?, raw_response = ?
                WHERE id = ?
                """,
                arguments: [category, task, confidence, rawResponse, id]
            )
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

    // MARK: - Projects

    func saveProject(_ project: ProjectRecord) throws -> ProjectRecord {
        var stored = project
        try dbQueue.write { db in
            if let id = stored.id {
                try db.execute(
                    sql: """
                    UPDATE projects SET name = ?, first_seen = ?, last_seen = ?, total_duration = ?,
                        dominant_apps = ?, category_distribution = ?, session_count = ?
                    WHERE id = ?
                    """,
                    arguments: [
                        stored.name,
                        stored.firstSeen.timeIntervalSince1970,
                        stored.lastSeen.timeIntervalSince1970,
                        stored.totalDuration,
                        stored.dominantApps,
                        stored.categoryDistribution,
                        stored.sessionCount,
                        id
                    ]
                )
            } else {
                try db.execute(
                    sql: """
                    INSERT INTO projects (name, first_seen, last_seen, total_duration, dominant_apps, category_distribution, session_count)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        stored.name,
                        stored.firstSeen.timeIntervalSince1970,
                        stored.lastSeen.timeIntervalSince1970,
                        stored.totalDuration,
                        stored.dominantApps,
                        stored.categoryDistribution,
                        stored.sessionCount
                    ]
                )
                stored.id = db.lastInsertedRowID
            }
        }
        return stored
    }

    func fetchAllProjects() throws -> [ProjectRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM projects ORDER BY last_seen DESC"
            ).map(ProjectRecord.init(row:))
        }
    }

    func fetchProjects(in interval: DateInterval) throws -> [ProjectRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT * FROM projects
                WHERE last_seen >= ? AND first_seen < ?
                ORDER BY last_seen DESC
                """,
                arguments: [interval.start.timeIntervalSince1970, interval.end.timeIntervalSince1970]
            ).map(ProjectRecord.init(row:))
        }
    }

    func assignSessionToProject(sessionID: Int64, projectID: Int64) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO session_projects (session_id, project_id) VALUES (?, ?)",
                arguments: [sessionID, projectID]
            )
        }
    }

    func fetchProjectIDsForSession(sessionID: Int64) throws -> [Int64] {
        try dbQueue.read { db in
            try Int64.fetchAll(
                db,
                sql: "SELECT project_id FROM session_projects WHERE session_id = ?",
                arguments: [sessionID]
            )
        }
    }

    func fetchSessionsForProject(projectID: Int64) throws -> [SessionRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT s.* FROM sessions s
                JOIN session_projects sp ON sp.session_id = s.id
                WHERE sp.project_id = ?
                ORDER BY s.timestamp ASC
                """,
                arguments: [projectID]
            ).map(SessionRecord.init(row:))
        }
    }

    func clearSessionProjects() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM session_projects")
        }
    }

    // MARK: - Embeddings

    func saveEmbedding(sessionID: Int64, embedding: Data, dimensions: Int) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO session_embeddings (session_id, embedding, dimensions) VALUES (?, ?, ?)",
                arguments: [sessionID, embedding, dimensions]
            )
        }
    }

    func fetchEmbedding(sessionID: Int64) throws -> (embedding: Data, dimensions: Int)? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT embedding, dimensions FROM session_embeddings WHERE session_id = ?",
                arguments: [sessionID]
            ) else { return nil }
            let data: Data = row["embedding"]
            let dims: Int = row["dimensions"]
            return (data, dims)
        }
    }

    func fetchSessionsWithoutEmbeddings(limit: Int = 100) throws -> [SessionRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT s.* FROM sessions s
                LEFT JOIN session_embeddings se ON se.session_id = s.id
                WHERE se.session_id IS NULL
                ORDER BY s.timestamp DESC
                LIMIT ?
                """,
                arguments: [limit]
            ).map(SessionRecord.init(row:))
        }
    }

    func fetchAllEmbeddings() throws -> [(sessionID: Int64, embedding: Data, dimensions: Int)] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT session_id, embedding, dimensions FROM session_embeddings"
            ).map { row in
                (sessionID: row["session_id"], embedding: row["embedding"], dimensions: row["dimensions"])
            }
        }
    }

    // MARK: - Daily Snapshots

    func saveDailySnapshot(_ snapshot: DailySnapshot) throws -> DailySnapshot {
        var stored = snapshot
        try dbQueue.write { db in
            let dateStart = Calendar.current.startOfDay(for: stored.date).timeIntervalSince1970
            // Upsert: update if snapshot for this date already exists
            let existing = try Row.fetchOne(
                db,
                sql: "SELECT id FROM daily_snapshots WHERE date = ?",
                arguments: [dateStart]
            )
            if let existingRow = existing {
                let existingID: Int64 = existingRow["id"]
                try db.execute(
                    sql: """
                    UPDATE daily_snapshots SET focus_score = ?, deep_work_minutes = ?, reactive_minutes = ?,
                        context_switches = ?, top_app = ?, top_category = ?, session_count = ?, keystroke_count = ?
                    WHERE id = ?
                    """,
                    arguments: [
                        stored.focusScore, stored.deepWorkMinutes, stored.reactiveMinutes,
                        stored.contextSwitches, stored.topApp, stored.topCategory,
                        stored.sessionCount, stored.keystrokeCount, existingID
                    ]
                )
                stored.id = existingID
            } else {
                try db.execute(
                    sql: """
                    INSERT INTO daily_snapshots (date, focus_score, deep_work_minutes, reactive_minutes,
                        context_switches, top_app, top_category, session_count, keystroke_count)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        dateStart,
                        stored.focusScore, stored.deepWorkMinutes, stored.reactiveMinutes,
                        stored.contextSwitches, stored.topApp, stored.topCategory,
                        stored.sessionCount, stored.keystrokeCount
                    ]
                )
                stored.id = db.lastInsertedRowID
            }
        }
        return stored
    }

    func fetchDailySnapshots(limit: Int = 90) throws -> [DailySnapshot] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM daily_snapshots ORDER BY date DESC LIMIT ?",
                arguments: [limit]
            ).map(DailySnapshot.init(row:))
        }
    }

    // MARK: - Anomaly Events

    func saveAnomalyEvent(_ event: AnomalyEvent) throws -> AnomalyEvent {
        var stored = event
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO anomaly_events (timestamp, metric, value, baseline_mean, baseline_stddev, severity, message)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    stored.timestamp.timeIntervalSince1970,
                    stored.metric, stored.value,
                    stored.baselineMean, stored.baselineStddev,
                    stored.severity, stored.message
                ]
            )
            stored.id = db.lastInsertedRowID
        }
        return stored
    }

    func fetchAnomalyEvents(limit: Int = 50) throws -> [AnomalyEvent] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM anomaly_events ORDER BY timestamp DESC LIMIT ?",
                arguments: [limit]
            ).map(AnomalyEvent.init(row:))
        }
    }

    func fetchAnomalyEvents(since: Date) throws -> [AnomalyEvent] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM anomaly_events WHERE timestamp >= ? ORDER BY timestamp DESC",
                arguments: [since.timeIntervalSince1970]
            ).map(AnomalyEvent.init(row:))
        }
    }
}
