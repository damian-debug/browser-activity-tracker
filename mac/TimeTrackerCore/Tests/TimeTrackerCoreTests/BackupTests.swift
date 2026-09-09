import Testing
import Foundation
@testable import TimeTrackerCore

// Backup compatibility is the migration path off the Chrome extension, so the
// v3 fixture below is written to match the extension's real export byte-shape:
// unix-millisecond timestamps, the top-level key `rules` (not `projectRules`),
// and omitted-rather-than-null optional fields.

private let extensionV3Export = """
{
  "format": "bat-backup",
  "schemaVersion": 3,
  "exportedAt": 1700000000000,
  "settings": {
    "idleThresholdSeconds": 60,
    "excludedDomains": ["localhost", "127.0.0.1"],
    "reviewConfidenceThreshold": 70
  },
  "projects": [
    {
      "id": "p1", "name": "Acme Corp", "clientName": "Acme, Inc.", "color": "#2563eb",
      "defaultBillable": true, "archived": false,
      "createdAt": 1699000000000, "updatedAt": 1699000000000
    },
    {
      "id": "p2", "name": "Internal",
      "defaultBillable": false, "archived": false,
      "createdAt": 1699000000000, "updatedAt": 1699000000000
    }
  ],
  "tags": [
    { "id": "t1", "name": "Development", "createdAt": 1699000000000, "updatedAt": 1699000000000 }
  ],
  "rules": [
    {
      "id": "r1", "projectId": "p1", "name": "Acme Corp: domain",
      "type": "domain_equals", "value": "app.sample-app.com",
      "priority": 0, "enabled": true,
      "createdAt": 1699000000000, "updatedAt": 1699000000000
    },
    {
      "id": "r2", "projectId": "p1", "name": "Acme Corp: bubble app",
      "type": "query_param_equals", "value": "sampleapp", "queryParamName": "id",
      "priority": 0, "enabled": true, "defaultTagIds": ["t1"], "defaultBillable": true,
      "createdAt": 1699000000000, "updatedAt": 1699000000000
    }
  ],
  "sessions": [
    {
      "id": "s1",
      "url": "https://bubble.io/page?id=sampleapp", "domain": "bubble.io",
      "title": "sampleapp | Bubble Editor",
      "service": "bubble", "detectedEntityId": "sampleapp", "detectedEntityName": null,
      "projectId": "p1", "projectName": "Acme Corp",
      "assignmentSource": "auto_rule", "assignmentConfidence": 90,
      "matchedRuleId": "r2",
      "tagIds": ["t1"], "billable": true, "reviewed": false,
      "startTime": 1699900000000, "endTime": 1699900060000, "durationSeconds": 60,
      "createdAt": 1699900060000, "updatedAt": 1699900060000
    },
    {
      "id": "s2",
      "url": "https://example.com/docs", "domain": "example.com", "title": "Docs",
      "service": null, "detectedEntityId": null, "detectedEntityName": null,
      "projectId": null, "projectName": null,
      "assignmentSource": "unassigned", "assignmentConfidence": 0,
      "tagIds": [], "billable": false, "reviewed": false,
      "startTime": 1699901000000, "endTime": 1699901030000, "durationSeconds": 30,
      "createdAt": 1699901030000, "updatedAt": 1699901030000
    }
  ]
}
""".data(using: .utf8)!

@Suite("Reading the extension's backup")
struct BackupV3ImportTests {
    func decoded() throws -> Backup.Contents {
        switch Backup.decode(extensionV3Export) {
        case .success(let contents): return contents
        case .failure(let error): throw error
        }
    }

    @Test("a real v3 export imports cleanly")
    func importsV3() throws {
        let contents = try decoded()
        #expect(contents.projects.count == 2)
        #expect(contents.tags.count == 1)
        #expect(contents.rules.count == 2)
        #expect(contents.sessions.count == 2)
    }

    @Test("project fields survive, including omitted optionals")
    func projectFields() throws {
        let contents = try decoded()
        let acme = try #require(contents.projects.first { $0.id == "p1" })
        #expect(acme.name == "Acme Corp")
        #expect(acme.clientName == "Acme, Inc.")
        #expect(acme.defaultBillable)

        let internalProject = try #require(contents.projects.first { $0.id == "p2" })
        #expect(internalProject.clientName == nil)
        // Fields that didn't exist in v3 take sensible defaults.
        #expect(!internalProject.isFavourite)
    }

    @Test("rules keep their type, parameter name and defaults")
    func ruleFields() throws {
        let contents = try decoded()
        let domainRule = try #require(contents.rules.first { $0.id == "r1" })
        #expect(domainRule.type == .domainEquals)
        #expect(domainRule.value == "app.sample-app.com")

        let paramRule = try #require(contents.rules.first { $0.id == "r2" })
        #expect(paramRule.type == .queryParamEquals)
        #expect(paramRule.queryParamName == "id")
        #expect(paramRule.defaultTagIds == ["t1"])
        #expect(paramRule.defaultBillable == true)
    }

    @Test("timestamps convert from unix milliseconds exactly")
    func timestamps() throws {
        let contents = try decoded()
        let session = try #require(contents.sessions.first { $0.id == "s1" })
        #expect(session.startTime == Date(unixMillis: 1_699_900_000_000))
        #expect(session.endTime == Date(unixMillis: 1_699_900_060_000))
        #expect(session.durationSeconds == 60)
    }

    @Test("browser sessions get an honest placeholder app, since v3 never recorded one")
    func importedSessionsGetPlaceholderApp() throws {
        let contents = try decoded()
        let session = try #require(contents.sessions.first)
        #expect(session.appBundleID == Backup.importedBrowserBundleID)
        #expect(session.appName == Backup.importedBrowserAppName)
        #expect(session.url == "https://bubble.io/page?id=sampleapp")
        #expect(session.domain == "bubble.io")
    }

    @Test("attribution and null handling survive the round trip")
    func attribution() throws {
        let contents = try decoded()
        let assigned = try #require(contents.sessions.first { $0.id == "s1" })
        #expect(assigned.projectId == "p1")
        #expect(assigned.assignmentSource == .autoRule)
        #expect(assigned.assignmentConfidence == 90)
        #expect(assigned.matchedRuleId == "r2")
        #expect(assigned.billable)

        let unassigned = try #require(contents.sessions.first { $0.id == "s2" })
        #expect(unassigned.projectId == nil)
        #expect(unassigned.service == nil)
        #expect(unassigned.assignmentSource == .unassigned)
    }

    @Test("imported data is immediately usable by the stats builder")
    func importedDataAggregates() throws {
        let contents = try decoded()
        let stats = StatsBuilder.build(
            sessions: contents.sessions, projects: contents.projects, tags: contents.tags
        )
        #expect(stats.totalActiveSeconds == 90)
        #expect(stats.billableSeconds == 60)
        #expect(stats.unassignedSeconds == 30)
    }
}

@Suite("Backup validation")
struct BackupValidationTests {
    @Test("rejects files that aren't JSON")
    func rejectsNonJSON() {
        let result = Backup.decode("not json at all".data(using: .utf8)!)
        #expect(result == .failure(.notJSON))
    }

    @Test("rejects JSON that isn't one of our backups")
    func rejectsForeignJSON() {
        let result = Backup.decode(#"{"format":"something-else"}"#.data(using: .utf8)!)
        #expect(result == .failure(.notABackupFile))
    }

    @Test("refuses a backup from a newer version rather than mangling it")
    func refusesNewerSchema() {
        let future = #"{"format":"bat-backup","schemaVersion":99,"exportedAt":0,"settings":{},"projects":[],"tags":[],"rules":[],"sessions":[]}"#
        #expect(Backup.decode(future.data(using: .utf8)!) == .failure(.tooNew(99)))
    }

    @Test("reports damaged files rather than importing partial data")
    func reportsMalformed() {
        let broken = #"{"format":"bat-backup","schemaVersion":3,"exportedAt":0,"settings":{},"projects":[{"name":"no id"}],"tags":[],"rules":[],"sessions":[]}"#
        let result = Backup.decode(broken.data(using: .utf8)!)
        guard case .failure(.malformed) = result else {
            Issue.record("expected a malformed-file error, got \(result)")
            return
        }
    }

    @Test("a rule of an unrecognised type is dropped, never guessed at")
    func dropsUnknownRuleTypes() throws {
        let json = #"""
        {"format":"bat-backup","schemaVersion":3,"exportedAt":0,"settings":{},
         "projects":[],"tags":[],
         "rules":[{"id":"r1","projectId":"p1","name":"future","type":"telepathy_equals","value":"x"}],
         "sessions":[]}
        """#
        guard case .success(let contents) = Backup.decode(json.data(using: .utf8)!) else {
            Issue.record("expected the file to import")
            return
        }
        #expect(contents.rules.isEmpty, "an unknown rule type must not silently become a different rule")
    }
}

@Suite("Backup round trip")
struct BackupRoundTripTests {
    func sampleContents() -> Backup.Contents {
        Backup.Contents(
            settings: AppSettings(idleThresholdSeconds: 90, reviewConfidenceThreshold: 60),
            projects: [Project(id: "p1", name: "Acme Corp", isFavourite: true, sortOrder: 2)],
            tags: [Tag(id: "t1", name: "Design")],
            rules: [makeRule(type: .documentPathContains, value: "/Projects/acme/", projectId: "p1")],
            sessions: [
                Session(
                    id: "s1", appBundleID: "com.figma.Desktop", appName: "Figma",
                    windowTitle: "KPI Screens", documentPath: nil,
                    projectId: "p1", assignmentSource: .autoRule, assignmentConfidence: 85,
                    countedWhileAway: true,
                    startTime: Date(unixMillis: 1_700_000_000_000),
                    endTime: Date(unixMillis: 1_700_000_060_000),
                    durationSeconds: 60
                )
            ]
        )
    }

    @Test("everything survives an export and re-import, including native fields")
    func roundTrip() throws {
        let original = sampleContents()
        let data = try Backup.encode(original)

        guard case .success(let restored) = Backup.decode(data) else {
            Issue.record("round trip failed to decode")
            return
        }

        #expect(restored.projects.first?.isFavourite == true)
        #expect(restored.projects.first?.sortOrder == 2)
        #expect(restored.rules.first?.type == .documentPathContains)
        #expect(restored.settings.idleThresholdSeconds == 90)
        #expect(restored.settings.reviewConfidenceThreshold == 60)

        let session = try #require(restored.sessions.first)
        #expect(session.appBundleID == "com.figma.Desktop")
        #expect(session.windowTitle == "KPI Screens")
        #expect(session.countedWhileAway)
        #expect(session.startTime == original.sessions[0].startTime)
    }

    @Test("exports declare the current format and version")
    func exportEnvelope() throws {
        let data = try Backup.encode(sampleContents())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["format"] as? String == "bat-backup")
        #expect(object["schemaVersion"] as? Int == Backup.schemaVersion)
    }
}

@Suite("Import planning")
struct ImportPlanTests {
    func project(_ id: String, _ name: String, updated: Int64) -> Project {
        Project(id: id, name: name, updatedAt: Date(unixMillis: updated))
    }

    @Test("replace takes the backup wholesale, including its settings")
    func replaceMode() {
        let incoming = Backup.Contents(
            settings: AppSettings(idleThresholdSeconds: 120),
            projects: [project("p1", "Incoming", updated: 100)]
        )
        let existing = Backup.Contents(projects: [project("px", "Local", updated: 999)])

        let plan = Backup.plan(incoming, existing: existing, mode: .replace)
        #expect(plan.projects.map(\.id) == ["p1"])
        #expect(plan.settings?.idleThresholdSeconds == 120)
        #expect(plan.skipped == 0)
    }

    @Test("merge adds new records and lets the newer copy win")
    func mergeMode() {
        let incoming = Backup.Contents(projects: [
            project("p1", "Incoming newer", updated: 200),
            project("p2", "Brand new", updated: 50),
        ])
        let existing = Backup.Contents(projects: [
            project("p1", "Local older", updated: 100),
            project("p3", "Local only", updated: 100),
        ])

        let plan = Backup.plan(incoming, existing: existing, mode: .merge)
        #expect(Set(plan.projects.map(\.id)) == ["p1", "p2"])
        #expect(plan.projects.first { $0.id == "p1" }?.name == "Incoming newer")
        #expect(plan.skipped == 0)
    }

    @Test("merge keeps a newer local record and counts it as skipped")
    func mergeKeepsNewerLocal() {
        let incoming = Backup.Contents(projects: [project("p1", "Incoming older", updated: 100)])
        let existing = Backup.Contents(projects: [project("p1", "Local newer", updated: 200)])

        let plan = Backup.plan(incoming, existing: existing, mode: .merge)
        #expect(plan.projects.isEmpty)
        #expect(plan.skipped == 1)
    }

    @Test("merge never overwrites local settings")
    func mergeLeavesSettingsAlone() {
        let incoming = Backup.Contents(settings: AppSettings(idleThresholdSeconds: 999))
        let plan = Backup.plan(incoming, existing: Backup.Contents(), mode: .merge)
        #expect(plan.settings == nil)
    }

    @Test("merge is idempotent: importing the same file twice changes nothing")
    func mergeIsIdempotent() {
        let contents = Backup.Contents(projects: [
            project("p1", "Acme Corp", updated: 100),
            project("p2", "Internal", updated: 100),
        ])
        let plan = Backup.plan(contents, existing: contents, mode: .merge)
        #expect(plan.isEmpty)
        #expect(plan.skipped == 2)
    }
}
