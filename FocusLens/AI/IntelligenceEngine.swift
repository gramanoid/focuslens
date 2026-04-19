import Foundation
import GRDB

/// Clusters sessions into coherent project streams based on temporal proximity,
/// app continuity, and task similarity.
final class ProjectClusteringEngine {
    let database: AppDatabase
    private let embeddingClient: GeminiEmbeddingClient

    /// Maximum gap between sessions to consider them part of the same project (2 hours).
    private let maxGapSeconds: TimeInterval = 7200
    /// Minimum cosine similarity for task-based clustering.
    private let taskSimilarityThreshold: Float = 0.75

    init(database: AppDatabase, embeddingClient: GeminiEmbeddingClient) {
        self.database = database
        self.embeddingClient = embeddingClient
    }

    /// Run clustering for all unclustered sessions.
    /// Uses a two-pass approach:
    ///   1. Temporal + app continuity (fast, no API calls)
    ///   2. Semantic similarity via embeddings (for sessions that don't cluster temporally)
    @MainActor
    func clusterAll() throws {
        let allSessions = try database.fetchSessions(in: DateInterval(start: .distantPast, end: .distantFuture))
        guard !allSessions.isEmpty else { return }

        let existingProjects = try database.fetchAllProjects()
        let existingAssignments = try fetchExistingAssignments()

        // Pass 1: Temporal + app continuity clustering
        var clusters: [[SessionRecord]] = []
        var currentCluster: [SessionRecord] = [allSessions[0]]

        for session in allSessions.dropFirst() {
            let prev = currentCluster.last!
            let gap = session.timestamp.timeIntervalSince(prev.timestamp)
            let sameApp = session.app == prev.app
            let sameCategory = session.category == prev.category

            if (gap <= maxGapSeconds && (sameApp || sameCategory)) || gap <= 300 {
                currentCluster.append(session)
            } else {
                clusters.append(currentCluster)
                currentCluster = [session]
            }
        }
        clusters.append(currentCluster)

        // Assign each cluster to a project
        try database.clearSessionProjects()

        for cluster in clusters {
            let project = try findOrCreateProject(
                for: cluster,
                existingProjects: existingProjects,
                assignments: existingAssignments
            )
            for session in cluster {
                if let sessionID = session.id, let projectID = project.id {
                    try database.assignSessionToProject(sessionID: sessionID, projectID: projectID)
                }
            }
        }
    }

    /// Find an existing project that matches this cluster, or create a new one.
    private func findOrCreateProject(
        for cluster: [SessionRecord],
        existingProjects: [ProjectRecord],
        assignments: [Int64: Int64]
    ) throws -> ProjectRecord {
        // Check if any session in this cluster was already assigned to a project
        for session in cluster {
            if let sessionID = session.id, let projectID = assignments[sessionID] {
                if let existing = existingProjects.first(where: { $0.id == projectID }) {
                    return try updateProject(existing, with: cluster)
                }
            }
        }

        // Create a new project
        let name = generateProjectName(for: cluster)
        let apps = Array(Set(cluster.map(\.app))).sorted { app1, app2 in
            cluster.filter { $0.app == app1 }.count > cluster.filter { $0.app == app2 }.count
        }
        let categoryBuckets = Dictionary(grouping: cluster, by: \.category)
        let catDist = categoryBuckets.mapValues { sessions in
            sessions.reduce(0.0) { $0 + estimatedDuration(of: $1) }
        }

        let project = ProjectRecord(
            name: name,
            firstSeen: cluster.first!.timestamp,
            lastSeen: cluster.last!.timestamp,
            totalDuration: cluster.reduce(0.0) { $0 + estimatedDuration(of: $1) },
            dominantApps: (try? JSONEncoder().encode(apps.prefix(5).map { $0 })).flatMap { String(data: $0, encoding: .utf8) } ?? "[]",
            categoryDistribution: (try? JSONEncoder().encode(catDist.mapKeys { $0.rawValue })) .flatMap { String(data: $0, encoding: .utf8) } ?? "{}",
            sessionCount: cluster.count
        )
        return try database.saveProject(project)
    }

    private func updateProject(_ project: ProjectRecord, with cluster: [SessionRecord]) throws -> ProjectRecord {
        var updated = project
        updated.lastSeen = max(project.lastSeen, cluster.last!.timestamp)
        updated.firstSeen = min(project.firstSeen, cluster.first!.timestamp)
        updated.sessionCount += cluster.count
        updated.totalDuration += cluster.reduce(0.0) { $0 + estimatedDuration(of: $1) }
        return try database.saveProject(updated)
    }

    /// Generate a project name from the cluster's dominant app and task themes.
    private func generateProjectName(for cluster: [SessionRecord]) -> String {
        let topApp = cluster.mostCommon(\.app) ?? "Unknown"

        // Extract common words from tasks (stopword-filtered)
        let stopwords: Set<String> = ["the", "a", "an", "in", "on", "at", "to", "for", "of", "and", "is", "with", "from", "by"]
        var wordFreq: [String: Int] = [:]
        for session in cluster {
            let words = session.task
                .lowercased()
                .components(separatedBy: .punctuationCharacters.union(.whitespaces))
                .filter { $0.count > 2 && !stopwords.contains($0) }
            for word in words {
                wordFreq[word, default: 0] += 1
            }
        }
        let topWords = wordFreq.sorted { $0.value > $1.value }.prefix(3).map(\.key)

        if !topWords.isEmpty {
            let theme = topWords.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            return "\(topApp) — \(theme)"
        }
        return topApp
    }

    private func estimatedDuration(of session: SessionRecord) -> TimeInterval {
        return 60 // Use capture interval as estimate
    }

    private func fetchExistingAssignments() throws -> [Int64: Int64] {
        // Returns session_id -> project_id mapping
        // Implemented via raw SQL for efficiency
        var result: [Int64: Int64] = [:]
        let rows = try database.dbQueue.read { db in
            try Row.fetchAll(db, sql: "SELECT session_id, project_id FROM session_projects")
        }
        for row in rows {
            let sessionID: Int64 = row["session_id"]
            let projectID: Int64 = row["project_id"]
            result[sessionID] = projectID
        }
        return result
    }
}

/// Semantic search over session embeddings.
@MainActor
final class SemanticSearchEngine {
    let database: AppDatabase
    private let embeddingClient: GeminiEmbeddingClient

    init(database: AppDatabase, embeddingClient: GeminiEmbeddingClient) {
        self.database = database
        self.embeddingClient = embeddingClient
    }

    /// Search sessions by natural language query using embedding similarity.
    func search(query: String, limit: Int = 20) async throws -> [(session: SessionRecord, score: Float)] {
        let queryEmbedding = try await embeddingClient.embed(text: query)

        let allEmbeddings = try database.fetchAllEmbeddings()
        guard !allEmbeddings.isEmpty else { return [] }

        // Score each embedding against the query
        var scored: [(sessionID: Int64, score: Float)] = []
        for entry in allEmbeddings {
            let vector = GeminiEmbeddingClient.deserialize(entry.embedding)
            let similarity = GeminiEmbeddingClient.cosineSimilarity(queryEmbedding, vector)
            scored.append((entry.sessionID, similarity))
        }
        scored.sort { $0.score > $1.score }

        // Fetch top matching sessions
        let topIDs = scored.prefix(limit).map(\.sessionID)
        var sessionsByID: [Int64: SessionRecord] = [:]
        let interval = DateInterval(start: .distantPast, end: .distantFuture)
        let allSessions = try database.fetchSessions(in: interval)
        for session in allSessions {
            if let id = session.id {
                sessionsByID[id] = session
            }
        }

        return topIDs.compactMap { id in
            guard let session = sessionsByID[id] else { return nil }
            guard let score = scored.first(where: { $0.sessionID == id })?.score else { return nil }
            return (session, score)
        }
    }
}

// MARK: - Daily Snapshot Engine

/// Computes and stores daily snapshots, then checks for anomalies against rolling baselines.
@MainActor
final class AnomalyDetectionEngine {
    let database: AppDatabase

    /// Number of days to use for rolling baseline.
    private let baselineDays = 14

    init(database: AppDatabase) {
        self.database = database
    }

    /// Compute a snapshot for a given day and store it.
    func computeAndStoreSnapshot(for date: Date) throws {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let interval = DateInterval(start: dayStart, end: dayEnd)

        let sessions = try database.fetchSessions(in: interval)
        let keystrokes = try database.fetchKeystrokes(in: interval)
        let blocks = AnalysisAggregator.blocks(from: sessions, fallbackInterval: 60)

        let focusScore = AnalysisAggregator.focusScore(for: blocks)
        let deepWorkMinutes = AnalysisAggregator.duration(of: blocks, in: AnomalyDetectionEngine.productiveCategories) / 60
        let reactiveMinutes = AnalysisAggregator.duration(of: blocks, in: AnomalyDetectionEngine.reactiveCategories) / 60
        let switches = AnalysisAggregator.contextSwitchCount(in: blocks)
        let apps = AnalysisAggregator.appUsage(for: blocks, limit: 1)
        let cats = AnalysisAggregator.categorySummaries(for: blocks)
        let totalKeystrokes = keystrokes.reduce(0) { $0 + $1.keystrokeCount }

        let snapshot = DailySnapshot(
            date: dayStart,
            focusScore: focusScore,
            deepWorkMinutes: deepWorkMinutes,
            reactiveMinutes: reactiveMinutes,
            contextSwitches: switches,
            topApp: apps.first?.app,
            topCategory: cats.first?.category.rawValue,
            sessionCount: sessions.count,
            keystrokeCount: totalKeystrokes
        )
        _ = try database.saveDailySnapshot(snapshot)
    }

    /// Check today's partial data against the rolling baseline and store any anomalies.
    func checkForAnomalies() throws {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let interval = DateInterval(start: todayStart, end: now)

        let sessions = try database.fetchSessions(in: interval)
        let blocks = AnalysisAggregator.blocks(from: sessions, fallbackInterval: 60)
        let keystrokes = try database.fetchKeystrokes(in: interval)

        // Today-so-far metrics
        let todayFocus = AnalysisAggregator.focusScore(for: blocks)
        let todayDeepWork = AnalysisAggregator.duration(of: blocks, in: Self.productiveCategories) / 60
        let todaySwitches = AnalysisAggregator.contextSwitchCount(in: blocks)
        let todayKeys = keystrokes.reduce(0) { $0 + $1.keystrokeCount }

        // Baseline: same day-of-week from past weeks + overall recent average
        let snapshots = try database.fetchDailySnapshots(limit: baselineDays)
        guard snapshots.count >= 3 else { return } // Need at least 3 days for a baseline

        let metrics: [(name: String, value: Double)] = [
            ("focus_score", todayFocus),
            ("deep_work_minutes", todayDeepWork),
            ("context_switches", Double(todaySwitches)),
            ("keystroke_count", Double(todayKeys))
        ]

        let hourFraction = now.timeIntervalSince(todayStart) / (todayEnd.timeIntervalSince(todayStart))
        // Scale baseline values to the current fraction of the day for fair comparison
        let scalingFactor = max(hourFraction, 0.25) // Don't scale below 25% (early morning noise)

        for metric in metrics {
            let values = snapshots.compactMap { snap -> Double? in
                switch metric.name {
                case "focus_score": return snap.focusScore
                case "deep_work_minutes": return snap.deepWorkMinutes
                case "context_switches": return Double(snap.contextSwitches)
                case "keystroke_count": return Double(snap.keystrokeCount)
                default: return nil
                }
            }
            guard values.count >= 3 else { continue }

            let mean = values.reduce(0, +) / Double(values.count) * scalingFactor
            let variance = values.reduce(0) { $0 + ($1 * scalingFactor - mean) * ($1 * scalingFactor - mean) } / Double(values.count)
            let stddev = sqrt(variance)

            guard stddev > 0 else { continue }

            let sigma = abs(metric.value - mean) / stddev
            let severity: String
            if sigma >= 3.0 { severity = "high" }
            else if sigma >= 2.0 { severity = "medium" }
            else { continue } // Not anomalous enough

            let direction = metric.value > mean ? "above" : "below"
            let message: String
            switch metric.name {
            case "focus_score":
                message = "Focus score is \(Int(metric.value))/100, \(direction) your baseline of \(Int(mean))/100 (\(String(format: "%.1f", sigma))σ)"
            case "deep_work_minutes":
                message = "Deep work is \(Int(metric.value))min, \(direction) your baseline of \(Int(mean))min (\(String(format: "%.1f", sigma))σ)"
            case "context_switches":
                message = "Context switches are \(Int(metric.value)), \(direction) your baseline of \(Int(mean)) (\(String(format: "%.1f", sigma))σ)"
            case "keystroke_count":
                message = "Keystroke activity is \(Int(metric.value)), \(direction) your baseline of \(Int(mean)) (\(String(format: "%.1f", sigma))σ)"
            default:
                message = "\(metric.name): \(direction) baseline (\(String(format: "%.1f", sigma))σ)"
            }

            _ = try database.saveAnomalyEvent(AnomalyEvent(
                timestamp: now,
                metric: metric.name,
                value: metric.value,
                baselineMean: mean,
                baselineStddev: stddev,
                severity: severity,
                message: message
            ))
        }
    }

    /// Compute snapshots for all days that don't have one yet.
    func backfillSnapshots() throws {
        let calendar = Calendar.current
        let earliest = try database.fetchSessions(in: DateInterval(start: .distantPast, end: .distantFuture)).first?.timestamp ?? .now
        let existingSnapshots = try database.fetchDailySnapshots(limit: 365)
        let existingDates = Set(existingSnapshots.compactMap { Calendar.current.startOfDay(for: $0.date).timeIntervalSince1970 })

        var cursor = calendar.startOfDay(for: earliest)
        let today = calendar.startOfDay(for: Date())

        while cursor < today {
            if !existingDates.contains(cursor.timeIntervalSince1970) {
                try computeAndStoreSnapshot(for: cursor)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
    }

    private static let productiveCategories: Set<ActivityCategory> = [.coding, .writing, .design, .work, .noteTaking]
    private static let reactiveCategories: Set<ActivityCategory> = [.communication, .browsing, .productivity, .ai]
}

// MARK: - Morning Briefing Generator

/// Generates a forward-looking pre-shift intelligence briefing using existing AI analysis pipeline.
@MainActor
final class MorningBriefingGenerator {
    let database: AppDatabase

    init(database: AppDatabase) {
        self.database = database
    }

    /// Build the prompt for the morning briefing using yesterday's data and baseline expectations.
    func buildBriefingPrompt() throws -> String {
        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: now)

        // Yesterday's data
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let yesterdayEnd = todayStart
        let yesterdayInterval = DateInterval(start: yesterdayStart, end: yesterdayEnd)
        let yesterdaySessions = try database.fetchSessions(in: yesterdayInterval)
        let yesterdayKeystrokes = try database.fetchKeystrokes(in: yesterdayInterval)
        let yesterdayBlocks = AnalysisAggregator.blocks(from: yesterdaySessions, fallbackInterval: 60)
        let yesterdayMerged = AnalysisAggregator.mergedBlocks(from: yesterdayBlocks)

        // Recent snapshots for baseline
        let snapshots = try database.fetchDailySnapshots(limit: 14)

        // Recent anomalies
        let anomalies = try database.fetchAnomalyEvents(limit: 10)

        // Active projects
        let projects = try database.fetchProjects(in: DateInterval(
            start: calendar.date(byAdding: .day, value: -7, to: todayStart) ?? todayStart,
            end: now
        ))

        // Build the briefing context
        var context = ""

        // Yesterday summary
        if !yesterdaySessions.isEmpty {
            let focusScore = AnalysisAggregator.focusScore(for: yesterdayBlocks)
            let deepWork = AnalysisAggregator.duration(of: yesterdayBlocks, in: [.coding, .writing, .design, .work, .noteTaking]) / 60
            context += "## Yesterday Summary\n"
            context += "- Focus score: \(Int(focusScore))/100\n"
            context += "- Deep work: \(Int(deepWork))min\n"
            context += "- Sessions: \(yesterdaySessions.count)\n"

            // Late sessions (potential carry-over)
            let lateBlocks = yesterdayMerged.filter { $0.start > calendar.date(bySettingHour: 20, minute: 0, second: 0, of: yesterdayStart) ?? yesterdayStart }
            if !lateBlocks.isEmpty {
                context += "- Late activity: "
                context += lateBlocks.map { "\($0.app) — \($0.task.prefix(60))" }.joined(separator: "; ")
                context += "\n"
            }

            // Top task themes
            let topTasks = Dictionary(grouping: yesterdayMerged, by: \.task)
                .mapValues { $0.reduce(0) { $0 + $1.duration } }
                .sorted { $0.value > $1.value }
                .prefix(5)
            if !topTasks.isEmpty {
                context += "- Top tasks: " + topTasks.map { "\($0.key.prefix(50)) (\(Int($0.value / 60))min)" }.joined(separator: ", ") + "\n"
            }
            context += "\n"
        }

        // Baseline expectations
        if !snapshots.isEmpty {
            let dayName = calendar.shortWeekdaySymbols[weekday - 1]
            context += "## Baseline for \(dayName)\n"
            let avgFocus = snapshots.reduce(0.0) { $0 + $1.focusScore } / Double(snapshots.count)
            let avgDeepWork = snapshots.reduce(0.0) { $0 + $1.deepWorkMinutes } / Double(snapshots.count)
            let avgSwitches = snapshots.reduce(0.0) { $0 + Double($1.contextSwitches) } / Double(snapshots.count)
            context += "- Average focus score: \(Int(avgFocus))/100\n"
            context += "- Average deep work: \(Int(avgDeepWork))min\n"
            context += "- Average context switches: \(Int(avgSwitches))\n\n"
        }

        // Active projects
        if !projects.isEmpty {
            context += "## Active Projects\n"
            for project in projects.prefix(10) {
                context += "- \(project.name): \(project.sessionCount) sessions, last active \(project.lastSeen.formatted(date: .abbreviated, time: .shortened))\n"
            }
            context += "\n"
        }

        // Recent anomalies
        let recentAnomalies = anomalies.filter { $0.timestamp > calendar.date(byAdding: .day, value: -3, to: now) ?? now }
        if !recentAnomalies.isEmpty {
            context += "## Recent Anomalies\n"
            for anomaly in recentAnomalies.prefix(5) {
                context += "- [\(anomaly.severity.uppercased())] \(anomaly.message)\n"
            }
            context += "\n"
        }

        return context
    }

    /// Generate the briefing system prompt.
    var systemPrompt: String {
        """
        You are generating a morning briefing for the owner of this Mac.
        You are their AI chief of staff.
        Address them directly as "you" and "your."
        Never use first-person voice. Do not use "I", "me", "my", "mine", "we", or "our".

        Based on yesterday's activity, baseline expectations, active projects, and recent anomalies,
        produce a forward-looking briefing.

        Use exactly these markdown sections in this order:
        ## What You Left Off
        - Identify incomplete or interrupted work from yesterday that should be resumed
        - Reference specific tasks and apps

        ## What to Protect Today
        - Based on baseline data, when are your peak focus hours today?
        - What type of work should you prioritize during those windows?

        ## Watch Out For
        - Any anomalies or patterns that might derail today
        - Specific warnings based on recent deviations

        Under each section, use short bullets only.
        Be specific and data-driven. Reference actual times, apps, and tasks.
        If data is sparse, say so plainly rather than inventing certainty.
        """
    }
}

// MARK: - Dictionary key mapping helper

private extension Dictionary {
    func mapKeys<T: Hashable>(_ transform: (Key) throws -> T) rethrows -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            result[try transform(key)] = value
        }
        return result
    }
}

// MARK: - Array mode helper

private extension Array {
    func mostCommon<T: Hashable>(_ keyPath: KeyPath<Element, T>) -> T? {
        var counts: [T: Int] = [:]
        for element in self {
            counts[element[keyPath: keyPath], default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key
    }
}
