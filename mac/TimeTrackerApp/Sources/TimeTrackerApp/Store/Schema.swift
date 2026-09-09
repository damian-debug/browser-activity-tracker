import Foundation
import GRDB

/// Database schema and migrations.
///
/// Two lessons carried over from the extension's IndexedDB layer, both of which
/// cost real debugging time there:
///   - Booleans are stored as INTEGER 0|1. SQLite has no boolean type, just as
///     IndexedDB could not index one.
///   - Timestamps are stored as numeric unix seconds so range scans use the
///     index, and any date bucketing is done in LOCAL time at the query site,
///     never UTC.
enum Schema {
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "project") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("clientName", .text)
                t.column("color", .text)
                t.column("defaultBillable", .integer).notNull().defaults(to: 0)
                t.column("archived", .integer).notNull().defaults(to: 0)
                t.column("isFavourite", .integer).notNull().defaults(to: 0)
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
            try db.create(indexOn: "project", columns: ["name"])

            try db.create(table: "tag") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("color", .text)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
            try db.create(indexOn: "tag", columns: ["name"])

            try db.create(table: "projectRule") { t in
                t.primaryKey("id", .text)
                t.column("projectId", .text).notNull()
                    .references("project", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("type", .text).notNull()
                t.column("value", .text).notNull()
                t.column("queryParamName", .text)
                t.column("priority", .integer).notNull().defaults(to: 0)
                t.column("enabled", .integer).notNull().defaults(to: 1)
                t.column("defaultTagIds", .text)
                t.column("defaultBillable", .integer)
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
            try db.create(indexOn: "projectRule", columns: ["projectId"])
            try db.create(indexOn: "projectRule", columns: ["priority"])

            try db.create(table: "session") { t in
                t.primaryKey("id", .text)
                t.column("appBundleID", .text).notNull()
                t.column("appName", .text).notNull()
                t.column("windowTitle", .text)
                t.column("documentPath", .text)
                t.column("url", .text)
                t.column("domain", .text)
                t.column("title", .text).notNull().defaults(to: "")
                t.column("service", .text)
                t.column("detectedEntityId", .text)
                t.column("detectedEntityName", .text)
                // Deliberately NOT a foreign key: deleting a project must not
                // delete the time that was spent on it. projectName is
                // denormalised so history stays readable afterwards.
                t.column("projectId", .text)
                t.column("projectName", .text)
                t.column("assignmentSource", .text).notNull()
                t.column("assignmentConfidence", .integer).notNull().defaults(to: 0)
                t.column("matchedRuleId", .text)
                t.column("tagIds", .text).notNull().defaults(to: "[]")
                t.column("notes", .text)
                t.column("billable", .integer).notNull().defaults(to: 0)
                t.column("reviewed", .integer).notNull().defaults(to: 0)
                t.column("countedWhileAway", .integer).notNull().defaults(to: 0)
                t.column("startTime", .double).notNull()
                t.column("endTime", .double).notNull()
                t.column("durationSeconds", .integer).notNull()
                t.column("createdAt", .double).notNull()
                t.column("updatedAt", .double).notNull()
            }
            try db.create(indexOn: "session", columns: ["startTime"])
            try db.create(indexOn: "session", columns: ["projectId"])
            try db.create(indexOn: "session", columns: ["appBundleID"])
            try db.create(indexOn: "session", columns: ["domain"])

            // Small key/value store for settings and the active override, so
            // the entire app state lives in one file that is trivial to back up.
            try db.create(table: "appState") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
        }

        migrator.registerMigration("v2-learning") { db in
            try db.create(table: "featureAssociation") { t in
                // Composite key: one row per (feature, project) pair. Its
                // index is also the lookup path — suggesting only ever reads
                // the handful of features present in the current activity,
                // never a scan of everything ever learned.
                t.column("feature", .text).notNull()
                t.column("projectId", .text).notNull()
                t.column("mass", .double).notNull()
                t.column("observations", .integer).notNull()
                t.column("lastUpdated", .double).notNull()
                t.primaryKey(["feature", "projectId"])
            }
        }

        migrator.registerMigration("v3-features") { db in
            // A feature is a project with a parent. Nullable, so every existing
            // project is already a valid top-level one.
            try db.alter(table: "project") { t in
                t.add(column: "parentId", .text)
            }
            try db.create(indexOn: "project", columns: ["parentId"])

            try db.alter(table: "session") { t in
                t.add(column: "featureId", .text)
                t.add(column: "featureName", .text)
                t.add(column: "gitBranch", .text)
            }
            try db.create(indexOn: "session", columns: ["featureId"])
        }

        migrator.registerMigration("v4-clean-document-paths") { db in
            // Browsers report kAXDocumentAttribute as the page address rather
            // than a file, so early rows stored "https://..." and "chrome://..."
            // as document paths. That duplicated the URL signal and produced
            // nonsense folder features in the learned model. The reader now
            // rejects them; this clears what was already written, along with any
            // associations derived from them.
            try db.execute(sql: "UPDATE session SET documentPath = NULL WHERE documentPath IS NOT NULL AND documentPath NOT LIKE '/%'")
            try db.execute(sql: "DELETE FROM featureAssociation WHERE feature LIKE 'document:%' AND feature NOT LIKE 'document:/%'")
        }

        return migrator
    }
}
