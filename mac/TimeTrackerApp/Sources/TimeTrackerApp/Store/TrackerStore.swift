import Foundation
import GRDB
import TimeTrackerCore

/// The app's persistence layer, and its implementation of the coordinator's
/// dependencies. GRDB's DatabaseQueue is already serialised and Sendable, so
/// this is a thin, safe wrapper rather than another actor.
public final class TrackerStore: Sendable {
    private let dbQueue: DatabaseQueue

    public init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbQueue = try DatabaseQueue(path: path, configuration: config)
        try Schema.migrator().migrate(dbQueue)
    }

    /// In-memory store, for tests.
    public init() throws {
        dbQueue = try DatabaseQueue()
        try Schema.migrator().migrate(dbQueue)
    }

    public static func defaultDatabaseURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("TimeTracker", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("tracker.sqlite")
    }

    // ── Projects ─────────────────────────────────────────────────────────

    public func projects(includeArchived: Bool = false) throws -> [Project] {
        try dbQueue.read { db in
            let records = try ProjectRecord
                .order(Column("name").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db)
            return records.map(\.domain).filter { includeArchived || !$0.archived }
        }
    }

    /// Top-level projects only — the things you bill for.
    public func topLevelProjects() throws -> [Project] {
        try projects().topLevel
    }

    /// Features belonging to a project.
    public func features(ofProject projectId: String) throws -> [Project] {
        try projects().features(of: projectId)
    }

    public func favouriteProjects() throws -> [Project] {
        try projects().filter(\.isFavourite)
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    public func save(_ project: Project) throws {
        try dbQueue.write { try ProjectRecord(project).save($0) }
    }

    public func deleteProject(id: String) throws {
        // Deleting a project takes its features with it, but never the time:
        // sessions survive as unassigned so history stays intact.
        for feature in (try? features(ofProject: id)) ?? [] {
            try deleteProject(id: feature.id)
        }
        _ = try dbQueue.write { db in
            // Sessions deliberately survive: deleting a project must not delete
            // the record of time already spent on it.
            try db.execute(sql: "UPDATE session SET projectId = NULL WHERE projectId = ?", arguments: [id])
            try db.execute(sql: "UPDATE session SET featureId = NULL, featureName = NULL WHERE featureId = ?", arguments: [id])
            // What was learned about it must go, though, or it would keep being
            // suggested from beyond the grave.
            try FeatureAssociationRecord.filter(Column("projectId") == id).deleteAll(db)
            try ProjectRecord.deleteOne(db, key: id)
        }
    }

    // ── Tags ─────────────────────────────────────────────────────────────

    public func tags() throws -> [Tag] {
        try dbQueue.read { db in
            try TagRecord
                .order(Column("name").collating(.localizedCaseInsensitiveCompare))
                .fetchAll(db).map(\.domain)
        }
    }

    public func save(_ tag: Tag) throws {
        try dbQueue.write { try TagRecord(tag).save($0) }
    }

    // ── Rules ────────────────────────────────────────────────────────────

    public func rules(projectId: String? = nil) throws -> [ProjectRule] {
        try dbQueue.read { db in
            var request = RuleRecord.order(Column("priority").desc)
            if let projectId {
                request = request.filter(Column("projectId") == projectId)
            }
            return try request.fetchAll(db).compactMap(\.domain)
        }
    }

    public func save(_ rule: ProjectRule) throws {
        try dbQueue.write { try RuleRecord(rule).save($0) }
    }

    public func deleteRule(id: String) throws {
        _ = try dbQueue.write { try RuleRecord.deleteOne($0, key: id) }
    }

    // ── Sessions ─────────────────────────────────────────────────────────

    public func save(_ session: Session) throws {
        try dbQueue.write { try SessionRecord(session).save($0) }
    }

    /// Sessions that STARTED within the range.
    ///
    /// Filtering on start time only means a session spanning midnight belongs
    /// entirely to the day it began. Deliberate: totals stay simple and no
    /// session is ever counted twice.
    public func sessions(from: Date, to: Date) throws -> [Session] {
        try dbQueue.read { db in
            try SessionRecord
                .filter(Column("startTime") >= from.timeIntervalSince1970)
                .filter(Column("startTime") <= to.timeIntervalSince1970)
                .order(Column("startTime").desc)
                .fetchAll(db)
                .map(\.domainModel)
        }
    }

    public func allSessions() throws -> [Session] {
        try dbQueue.read { db in
            try SessionRecord.order(Column("startTime").desc).fetchAll(db).map(\.domainModel)
        }
    }

    public func updateSession(_ session: Session) throws {
        var updated = session
        updated.updatedAt = Date()
        try dbQueue.write { try SessionRecord(updated).save($0) }
    }

    public func deleteSession(id: String) throws {
        _ = try dbQueue.write { try SessionRecord.deleteOne($0, key: id) }
    }

    public func deleteAllSessions() throws {
        _ = try dbQueue.write { try SessionRecord.deleteAll($0) }
    }

    // ── Key/value state ──────────────────────────────────────────────────

    private static let settingsKey = "settings"
    private static let overrideKey = "override"
    private static let activeSessionKey = "activeSession"
    private static let currentFeatureKey = "currentFeature"
    private static let diagnosticsKey = "diagnostics"

    private func readJSON<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        let raw = try? dbQueue.read { db in
            try AppStateRecord.fetchOne(db, key: key)?.value
        }
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func writeJSON<T: Encodable>(_ key: String, _ value: T?) throws {
        try dbQueue.write { db in
            guard let value else {
                _ = try AppStateRecord.deleteOne(db, key: key)
                return
            }
            let data = try JSONEncoder().encode(value)
            let record = AppStateRecord(key: key, value: String(decoding: data, as: UTF8.self))
            try record.save(db)
        }
    }

    public func settings() -> AppSettings {
        readJSON(Self.settingsKey, as: AppSettings.self) ?? .default
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try writeJSON(Self.settingsKey, settings)
    }

    /// The feature you last said you were working on.
    public func currentFeatureId() -> String? {
        readJSON(Self.currentFeatureKey, as: String.self)
    }

    public func saveCurrentFeatureId(_ id: String?) throws {
        try writeJSON(Self.currentFeatureKey, id)
    }

    public func override() -> ActiveProjectOverride? {
        readJSON(Self.overrideKey, as: ActiveProjectOverride.self)
    }

    public func saveOverride(_ override: ActiveProjectOverride?) throws {
        try writeJSON(Self.overrideKey, override)
    }

    /// The session that was in progress when the app last stopped.
    /// Written on every heartbeat so a crash or force-quit loses at most one
    /// interval rather than the whole stretch of work.
    public func inFlightSession() -> ActiveSession? {
        readJSON(Self.activeSessionKey, as: ActiveSession.self)
    }

    public func saveInFlightSession(_ session: ActiveSession?) throws {
        try writeJSON(Self.activeSessionKey, session)
    }

    /// A record of which signals the app can currently read. Written on each
    /// refresh so permission problems can be diagnosed without attaching a
    /// debugger — which would itself change the frontmost app and the data.
    public struct Diagnostics: Codable, Sendable {
        public var accessibilityTrusted: Bool
        public var browserAccess: [String: String]
        public var updatedAt: Double

        public init(accessibilityTrusted: Bool, browserAccess: [String: String], updatedAt: Double) {
            self.accessibilityTrusted = accessibilityTrusted
            self.browserAccess = browserAccess
            self.updatedAt = updatedAt
        }
    }

    public func saveDiagnostics(_ diagnostics: Diagnostics) throws {
        try writeJSON(Self.diagnosticsKey, diagnostics)
    }

    public func diagnostics() -> Diagnostics? {
        readJSON(Self.diagnosticsKey, as: Diagnostics.self)
    }

    // ── First run ────────────────────────────────────────────────────────

    /// Seeds the default tags once, only when the table is empty.
    public func seedDefaultsIfEmpty() throws {
        try dbQueue.write { db in
            guard try TagRecord.fetchCount(db) == 0 else { return }
            let now = Date()
            for name in AppSettings.defaultTagNames {
                try TagRecord(Tag(name: name, createdAt: now, updatedAt: now)).insert(db)
            }
        }
    }

    // ── Learning ─────────────────────────────────────────────────────────

    private let learned = LearnedIndex.default

    public func loadAssociations(forFeatureKeys keys: [String]) throws -> [FeatureAssociation] {
        guard !keys.isEmpty else { return [] }
        return try dbQueue.read { db in
            try FeatureAssociationRecord
                .filter(keys.contains(Column("feature")))
                .fetchAll(db)
                .map(\.domain)
        }
    }

    /// Fold observations into the model.
    ///
    /// Each observation carries its own timestamp and is aged accordingly, so
    /// replaying history — a restored backup, a rule applied to old sessions —
    /// does not pass year-old evidence off as fresh. Decay needs no background
    /// sweep: it happens wherever a row is touched.
    public func recordObservations(_ observations: [FeatureObservation]) throws {
        guard !observations.isEmpty else { return }
        try dbQueue.write { db in
            for observation in observations {
                let existing = try FeatureAssociationRecord
                    .filter(Column("feature") == observation.feature)
                    .filter(Column("projectId") == observation.projectId)
                    .fetchOne(db)?.domain

                let base = existing ?? FeatureAssociation(
                    feature: observation.feature, projectId: observation.projectId,
                    mass: 0, observations: 0, lastUpdated: observation.at
                )
                let updated = learned.updated(base, adding: observation.weight, at: observation.at)

                // A row that has decayed to nothing is noise; drop it rather
                // than carrying it forever.
                if updated.mass < 0.01 {
                    if existing != nil {
                        try FeatureAssociationRecord
                            .filter(Column("feature") == observation.feature)
                            .filter(Column("projectId") == observation.projectId)
                            .deleteAll(db)
                    }
                } else {
                    try FeatureAssociationRecord(updated).save(db)
                }
            }
        }
    }

    /// Remove associations that have decayed below usefulness.
    ///
    /// Rows are only aged when touched, so a feature never seen again would
    /// otherwise sit at its last value forever. Returns how many were removed.
    @discardableResult
    public func compactLearning(now: Date = Date(), floor: Double = 0.01) throws -> Int {
        try dbQueue.write { db in
            let all = try FeatureAssociationRecord.fetchAll(db)
            var removed = 0
            for record in all where learned.decayedMass(record.domain, now: now) < floor {
                try FeatureAssociationRecord
                    .filter(Column("feature") == record.feature)
                    .filter(Column("projectId") == record.projectId)
                    .deleteAll(db)
                removed += 1
            }
            return removed
        }
    }

    /// Forget everything learned about a project. Used when it is deleted, so
    /// it can never be suggested again.
    public func forgetLearning(projectId: String) throws {
        _ = try dbQueue.write { db in
            try FeatureAssociationRecord.filter(Column("projectId") == projectId).deleteAll(db)
        }
    }

    public func learningRowCount() throws -> Int {
        try dbQueue.read { try FeatureAssociationRecord.fetchCount($0) }
    }

    // ── Backup ───────────────────────────────────────────────────────────

    public func backupContents() throws -> Backup.Contents {
        Backup.Contents(
            settings: settings(),
            projects: try projects(includeArchived: true),
            tags: try tags(),
            rules: try rules(),
            sessions: try allSessions()
        )
    }

    public func apply(_ plan: ImportPlan) throws {
        try dbQueue.write { db in
            if plan.mode == .replace {
                try SessionRecord.deleteAll(db)
                try RuleRecord.deleteAll(db)
                try TagRecord.deleteAll(db)
                try ProjectRecord.deleteAll(db)
            }
            // Projects first: rules reference them.
            for project in plan.projects { try ProjectRecord(project).save(db) }
            for tag in plan.tags { try TagRecord(tag).save(db) }
            for rule in plan.rules { try RuleRecord(rule).save(db) }
            for session in plan.sessions { try SessionRecord(session).save(db) }
        }
        if let settings = plan.settings {
            try saveSettings(settings)
        }
    }
}

// ── Coordinator dependencies ─────────────────────────────────────────────

extension TrackerStore: TrackingDependencies {
    public func enabledRules() async -> [ProjectRule] {
        (try? rules())?.filter(\.enabled) ?? []
    }

    public func project(_ id: String) async -> Project? {
        try? await dbQueue.read { db in try ProjectRecord.fetchOne(db, key: id)?.domain }
    }

    public func currentOverride() async -> ActiveProjectOverride? {
        self.override()
    }

    public func clearOverride() async {
        try? saveOverride(nil)
    }


    public func persist(_ session: Session) async {
        try? save(session)
    }

    public func associations(forFeatureKeys keys: [String]) async -> [FeatureAssociation] {
        (try? loadAssociations(forFeatureKeys: keys)) ?? []
    }

    public func eligibleProjectIds() async -> Set<String> {
        // Top-level only: which feature it is gets decided by a separate,
        // narrower pass once the project is known.
        Set(((try? topLevelProjects()) ?? []).map(\.id))
    }

    public func featureIds(ofProject projectId: String) async -> Set<String> {
        Set(((try? features(ofProject: projectId)) ?? []).map(\.id))
    }

    public func projectName(_ id: String) async -> String? {
        try? await dbQueue.read { db in try ProjectRecord.fetchOne(db, key: id)?.name }
    }

    public func currentFeature() async -> (id: String, projectId: String, name: String)? {
        guard let id = currentFeatureId(),
              let record = try? await dbQueue.read({ db in try ProjectRecord.fetchOne(db, key: id) }),
              let parentId = record.parentId
        else { return nil }
        return (id: record.id, projectId: parentId, name: record.name)
    }

    public func record(_ observations: [FeatureObservation]) async {
        try? recordObservations(observations)
    }
}
