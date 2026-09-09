import Testing
import Foundation
@testable import TimeTrackerCore

// End-to-end migration guard.
//
// The fixture here was NOT hand-written: it was emitted by the Chrome
// extension's own `buildBackup()` and committed verbatim. That matters — a
// fixture written from memory only proves the importer matches my recollection
// of the format, whereas this proves it matches the code that actually
// produces the files users will import.

@Suite("Migration from the Chrome extension")
struct MigrationTests {
    func realExportData() throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: "extension-v3-backup", withExtension: "json",
                              subdirectory: "Fixtures"),
            "the committed extension export fixture should be bundled with the tests"
        )
        return try Data(contentsOf: url)
    }

    func imported() throws -> Backup.Contents {
        switch Backup.decode(try realExportData()) {
        case .success(let contents): return contents
        case .failure(let error): throw error
        }
    }

    @Test("a genuine extension export is accepted")
    func acceptsRealExport() throws {
        let contents = try imported()
        #expect(contents.projects.count == 1)
        #expect(contents.tags.count == 1)
        #expect(contents.rules.count == 1)
        #expect(contents.sessions.count == 2)
    }

    @Test("the extension's default settings carry over")
    func settingsCarryOver() throws {
        let contents = try imported()
        #expect(contents.settings.idleThresholdSeconds == 60)
        #expect(contents.settings.reviewConfidenceThreshold == 70)
        #expect(contents.settings.excludedDomains.contains("localhost"))
    }

    @Test("a query-param rule keeps the parameter name it matches on")
    func rulesSurvive() throws {
        let rule = try #require(try imported().rules.first)
        #expect(rule.type == .queryParamEquals)
        #expect(rule.value == "sampleapp")
        #expect(rule.queryParamName == "id")
        #expect(rule.defaultTagIds == ["t1"])
    }

    @Test("imported rules still match the activity they were written for")
    func importedRulesStillWork() throws {
        let contents = try imported()
        let snapshot = browserSnapshot(url: "https://bubble.io/page?id=sampleapp&tab=Design")
        let result = RuleEngine.run(RuleMatchContext(snapshot), rules: contents.rules)

        #expect(result.projectId == "p1", "a rule written in the extension must still fire natively")
        #expect(result.assignmentConfidence == Confidence.queryParam)
    }

    @Test("totals match what the extension's dashboard showed for the same rows")
    func totalsMatch() throws {
        let contents = try imported()
        let stats = StatsBuilder.build(
            sessions: contents.sessions, projects: contents.projects, tags: contents.tags
        )
        #expect(stats.totalActiveSeconds == 90)
        #expect(stats.billableSeconds == 60)
        #expect(stats.unassignedSeconds == 30)
        #expect(stats.sessionCount == 2)
    }

    @Test("re-exporting imported data and importing it again is lossless")
    func reExportIsStable() throws {
        let original = try imported()
        let reEncoded = try Backup.encode(original)

        guard case .success(let round) = Backup.decode(reEncoded) else {
            Issue.record("re-export failed to decode")
            return
        }
        #expect(round.projects == original.projects)
        #expect(round.tags == original.tags)
        #expect(round.rules == original.rules)
        #expect(round.sessions == original.sessions)
    }

    @Test("importing the same export twice is a no-op")
    func reimportIsIdempotent() throws {
        let contents = try imported()
        let plan = Backup.plan(contents, existing: contents, mode: .merge)
        #expect(plan.isEmpty)
    }
}
