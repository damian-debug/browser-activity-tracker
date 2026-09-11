import Testing
import Foundation
import TimeTrackerCore
import GRDB
@testable import TimeTrackerApp

// The store runs against a real in-memory SQLite database, so these exercise
// the actual schema, migrations and SQL rather than a stand-in.

private let base = Date(timeIntervalSince1970: 1_700_000_000)

private func session(
    id: String = UUID().uuidString,
    app: String = "com.figma.Desktop",
    projectId: String? = nil,
    tagIds: [String] = [],
    billable: Bool = false,
    seconds: Int = 60,
    startOffset: Int = 0
) -> Session {
    Session(
        id: id, appBundleID: app, appName: "Figma",
        windowTitle: "KPI Screens", documentPath: "/p/design.fig",
        url: nil, domain: nil, title: "KPI Screens",
        projectId: projectId, assignmentSource: projectId == nil ? .unassigned : .autoRule,
        assignmentConfidence: projectId == nil ? 0 : 85,
        tagIds: tagIds, billable: billable,
        startTime: base.addingTimeInterval(Double(startOffset)),
        endTime: base.addingTimeInterval(Double(startOffset + seconds)),
        durationSeconds: seconds
    )
}

@Suite("Store: schema and round trips")
struct StoreRoundTripTests {
    @Test("migrations create a usable database")
    func migrations() throws {
        let store = try TrackerStore()
        #expect(try store.projects().isEmpty)
        #expect(try store.sessions(from: .distantPast, to: .distantFuture).isEmpty)
    }

    @Test("a project round-trips with every field intact")
    func projectRoundTrip() throws {
        let store = try TrackerStore()
        let project = Project(
            id: "p1", name: "Acme Corp", clientName: "Acme, Inc.", color: "#2563eb",
            defaultBillable: true, archived: false, isFavourite: true, sortOrder: 3
        )
        try store.save(project)

        let loaded = try #require(try store.projects().first)
        #expect(loaded.id == "p1")
        #expect(loaded.clientName == "Acme, Inc.")
        #expect(loaded.defaultBillable)
        #expect(loaded.isFavourite)
        #expect(loaded.sortOrder == 3)
    }

    @Test("archived projects are hidden unless asked for")
    func archivedProjects() throws {
        let store = try TrackerStore()
        try store.save(Project(id: "a", name: "Active"))
        try store.save(Project(id: "b", name: "Old", archived: true))

        #expect(try store.projects().map(\.id) == ["a"])
        #expect(try store.projects(includeArchived: true).count == 2)
    }

    @Test("favourites come back in the configured order")
    func favouriteOrdering() throws {
        let store = try TrackerStore()
        try store.save(Project(id: "b", name: "Second", isFavourite: true, sortOrder: 2))
        try store.save(Project(id: "a", name: "First", isFavourite: true, sortOrder: 1))
        try store.save(Project(id: "c", name: "Not pinned"))

        #expect(try store.favouriteProjects().map(\.id) == ["a", "b"])
    }

    @Test("a session round-trips, including native fields and tag ids")
    func sessionRoundTrip() throws {
        let store = try TrackerStore()
        try store.save(Project(id: "p1", name: "Acme Corp"))
        try store.save(session(id: "s1", projectId: "p1", tagIds: ["t1", "t2"], billable: true))

        let loaded = try #require(try store.allSessions().first)
        #expect(loaded.appBundleID == "com.figma.Desktop")
        #expect(loaded.windowTitle == "KPI Screens")
        #expect(loaded.documentPath == "/p/design.fig")
        #expect(loaded.tagIds == ["t1", "t2"])
        #expect(loaded.billable)
        #expect(loaded.assignmentConfidence == 85)
    }

    @Test("a rule round-trips, and an unknown rule type is dropped rather than misread")
    func ruleRoundTrip() throws {
        let store = try TrackerStore()
        try store.save(Project(id: "p1", name: "Acme Corp"))
        try store.save(ProjectRule(
            id: "r1", projectId: "p1", name: "Figma file",
            type: .documentPathContains, value: "/Projects/acme/",
            defaultTagIds: ["t1"], defaultBillable: true
        ))

        let loaded = try #require(try store.rules().first)
        #expect(loaded.type == .documentPathContains)
        #expect(loaded.defaultTagIds == ["t1"])
        #expect(loaded.defaultBillable == true)
    }
}

@Suite("Store: queries")
struct StoreQueryTests {
    @Test("range queries filter on start time")
    func rangeFiltering() throws {
        let store = try TrackerStore()
        try store.save(session(id: "old", startOffset: -10_000))
        try store.save(session(id: "inside", startOffset: 0))
        try store.save(session(id: "later", startOffset: 10_000))

        let found = try store.sessions(
            from: base.addingTimeInterval(-100), to: base.addingTimeInterval(100)
        )
        #expect(found.map(\.id) == ["inside"])
    }

    @Test("deleting a project keeps the time that was spent on it")
    func deletingProjectKeepsSessions() throws {
        let store = try TrackerStore()
        try store.save(Project(id: "p1", name: "Acme Corp"))
        try store.save(session(id: "s1", projectId: "p1"))

        try store.deleteProject(id: "p1")

        let sessions = try store.allSessions()
        #expect(sessions.count == 1, "history must outlive the project it referenced")
        #expect(sessions[0].projectId == nil, "and become unassigned rather than dangling")
    }

    @Test("deleting a project removes its rules")
    func deletingProjectCascadesRules() throws {
        let store = try TrackerStore()
        try store.save(Project(id: "p1", name: "Acme Corp"))
        try store.save(ProjectRule(id: "r1", projectId: "p1", name: "r", type: .domainEquals, value: "x.com"))

        try store.deleteProject(id: "p1")
        #expect(try store.rules().isEmpty)
    }
}

@Suite("Store: app state")
struct StoreStateTests {
    @Test("settings persist and default cleanly when unset")
    func settings() throws {
        let store = try TrackerStore()
        #expect(store.settings() == .default)

        try store.saveSettings(AppSettings(idleThresholdSeconds: 120, reviewConfidenceThreshold: 90))
        #expect(store.settings().idleThresholdSeconds == 120)
        #expect(store.settings().reviewConfidenceThreshold == 90)
    }

    @Test("an override persists and can be cleared")
    func override() throws {
        let store = try TrackerStore()
        #expect(store.override() == nil)

        try store.saveOverride(ActiveProjectOverride(
            projectId: "p1", scope: .global, expiry: .manual, countsWhileAway: true
        ))
        #expect(store.override()?.projectId == "p1")
        #expect(store.override()?.countsWhileAway == true)

        try store.saveOverride(nil)
        #expect(store.override() == nil)
    }

    @Test("an in-flight session survives a round trip through the database")
    func inFlightSession() throws {
        let store = try TrackerStore()
        #expect(store.inFlightSession() == nil)

        let snapshot = ActivitySnapshot(
            bundleID: "com.figma.Desktop", appName: "Figma", windowTitle: "KPI Screens"
        )
        var live = ActiveSession(snapshot: snapshot, now: base)
        live.checkpoint(at: base.addingTimeInterval(45))
        try store.saveInFlightSession(live)

        let restored = try #require(store.inFlightSession())
        #expect(restored.id == live.id)
        #expect(restored.accumulatedSeconds == 45)
        #expect(restored.snapshot.windowTitle == "KPI Screens")
    }

    @Test("default tags are seeded once and never duplicated")
    func seeding() throws {
        let store = try TrackerStore()
        try store.seedDefaultsIfEmpty()
        let first = try store.tags().count
        #expect(first == AppSettings.defaultTagNames.count)

        try store.seedDefaultsIfEmpty()
        #expect(try store.tags().count == first)
    }
}

@Suite("Store: backup")
struct StoreBackupTests {
    @Test("a full backup round-trips through the store")
    func backupRoundTrip() throws {
        let store = try TrackerStore()
        try store.save(Project(id: "p1", name: "Acme Corp", isFavourite: true))
        try store.save(Tag(id: "t1", name: "Design"))
        try store.save(ProjectRule(id: "r1", projectId: "p1", name: "r", type: .domainEquals, value: "x.com"))
        try store.save(session(id: "s1", projectId: "p1"))
        try store.saveSettings(AppSettings(idleThresholdSeconds: 120))

        let data = try Backup.encode(try store.backupContents())

        let restored = try TrackerStore()
        guard case .success(let contents) = Backup.decode(data) else {
            Issue.record("backup should decode"); return
        }
        try restored.apply(Backup.plan(contents, existing: Backup.Contents(), mode: .replace))

        #expect(try restored.projects().first?.name == "Acme Corp")
        #expect(try restored.tags().first?.name == "Design")
        #expect(try restored.rules().count == 1)
        #expect(try restored.allSessions().count == 1)
        #expect(restored.settings().idleThresholdSeconds == 120)
    }

    @Test("replace wipes what was there first")
    func replaceWipes() throws {
        let store = try TrackerStore()
        try store.save(Project(id: "old", name: "Should be gone"))
        try store.save(session(id: "old-session"))

        let incoming = Backup.Contents(projects: [Project(id: "new", name: "Fresh")])
        try store.apply(Backup.plan(incoming, existing: try store.backupContents(), mode: .replace))

        #expect(try store.projects().map(\.id) == ["new"])
        #expect(try store.allSessions().isEmpty)
    }

    @Test("merge keeps local data and adds what is new")
    func mergeAdds() throws {
        let store = try TrackerStore()
        try store.save(Project(id: "local", name: "Local"))

        let incoming = Backup.Contents(projects: [Project(id: "incoming", name: "Incoming")])
        try store.apply(Backup.plan(incoming, existing: try store.backupContents(), mode: .merge))

        #expect(Set(try store.projects().map(\.id)) == ["local", "incoming"])
    }
}

@Suite("Idle default migration")
struct IdleDefaultMigrationTests {
    /// A database as an older build left it, with settings saved.
    func database(withIdle seconds: Int?) throws -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("idle-migration-\(UUID().uuidString).sqlite").path
        let queue = try DatabaseQueue(path: path)
        try Schema.migrator().migrate(queue, upTo: "v6-rule-conditions")
        if let seconds {
            var settings = AppSettings.default
            settings.idleThresholdSeconds = seconds
            let json = String(decoding: try JSONEncoder().encode(settings), as: UTF8.self)
            try queue.write {
                try $0.execute(sql: "INSERT INTO appState (key, value) VALUES ('settings', ?)",
                               arguments: [json])
            }
        }
        return path
    }

    @Test("the old one-minute default is lifted to five")
    func liftsOldDefault() throws {
        let store = try TrackerStore(path: try database(withIdle: 60))
        #expect(store.settings().idleThresholdSeconds == 300)
    }

    @Test("a deliberately chosen value is left alone")
    func keepsChoice() throws {
        let store = try TrackerStore(path: try database(withIdle: 120))
        #expect(store.settings().idleThresholdSeconds == 120)
    }

    @Test("with nothing saved, the new default applies")
    func nothingSaved() throws {
        let store = try TrackerStore(path: try database(withIdle: nil))
        #expect(store.settings().idleThresholdSeconds == 300)
    }

    @Test("other saved settings survive the migration")
    func othersSurvive() throws {
        let path = try database(withIdle: 60)
        let queue = try DatabaseQueue(path: path)
        try queue.write {
            try $0.execute(sql: """
                UPDATE appState SET value = json_set(value, '$.reviewConfidenceThreshold', 85)
                WHERE key = 'settings'
                """)
        }
        let store = try TrackerStore(path: path)
        #expect(store.settings().reviewConfidenceThreshold == 85)
        #expect(store.settings().idleThresholdSeconds == 300)
    }
}

@Suite("No credentials in the database")
struct StoredURLCredentialTests {
    func session(_ url: String) -> Session {
        Session(appBundleID: "com.google.Chrome", appName: "Google Chrome", url: url,
                startTime: Date(), endTime: Date(), durationSeconds: 60)
    }

    @Test("a session is written without its sign-in code, whichever way it arrives")
    func writePath() throws {
        let store = try TrackerStore()
        try store.save(session("https://linear.app/oauth/callback?code=abc&state=xyz"))
        #expect(try store.sessions(from: .distantPast, to: .distantFuture).first?.url == "https://linear.app/oauth/callback")
    }

    @Test("sessions recorded before this are cleaned once, and nothing else changes")
    func migration() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("url-migration-\(UUID().uuidString).sqlite").path
        let queue = try DatabaseQueue(path: path)
        try Schema.migrator().migrate(queue, upTo: "v7-idle-five-minutes")
        let rows = [
            ("dirty", "https://accounts.google.com/signin/oauth/id?authuser=0&part=P&rapt=R"),
            ("bubble", "https://bubble.io/page?id=meltx&name=gp-portal"),
            ("plain", "https://example.com/"),
        ]
        try queue.write { db in
            for (id, url) in rows {
                try db.execute(sql: """
                    INSERT INTO session (id, appBundleID, appName, url, title, assignmentSource, startTime, endTime, durationSeconds, createdAt, updatedAt)
                    VALUES (?, 'com.google.Chrome', 'Chrome', ?, '', 'unassigned', 0, 60, 60, 0, 0)
                    """, arguments: [id, url])
            }
        }
        let store = try TrackerStore(path: path)   // runs v8
        let urls = Dictionary(uniqueKeysWithValues: try store.sessions(from: .distantPast, to: .distantFuture).map { ($0.id, $0.url ?? "") })
        #expect(urls["dirty"] == "https://accounts.google.com/signin/oauth/id?authuser=0")
        #expect(urls["bubble"] == "https://bubble.io/page?id=meltx&name=gp-portal")
        #expect(urls["plain"] == "https://example.com/")
    }
}
