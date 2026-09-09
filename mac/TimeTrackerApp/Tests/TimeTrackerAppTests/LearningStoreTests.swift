import Testing
import Foundation
import TimeTrackerCore
@testable import TimeTrackerApp

private let now = Date(timeIntervalSince1970: 1_700_000_000)
private func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

private func observation(
    _ feature: String, _ project: String, weight: Double = 1, at: Date = now
) -> FeatureObservation {
    FeatureObservation(feature: feature, projectId: project, weight: weight, at: at)
}

@Suite("Learning store")
struct LearningStoreTests {
    @Test("observations accumulate into associations")
    func accumulates() throws {
        let store = try TrackerStore()
        try store.recordObservations([
            observation("entity:figma::abc", "acme"),
            observation("host:figma.com", "acme"),
        ])
        try store.recordObservations([observation("entity:figma::abc", "acme")])

        let rows = try store.loadAssociations(forFeatureKeys: ["entity:figma::abc"])
        #expect(rows.count == 1)
        #expect(rows[0].observations == 2)
        #expect(rows[0].mass == 2)
    }

    @Test("the same feature can point at more than one project")
    func multipleProjects() throws {
        let store = try TrackerStore()
        try store.recordObservations([
            observation("app:com.figma.Desktop", "acme"),
            observation("app:com.figma.Desktop", "internal"),
        ])

        let rows = try store.loadAssociations(forFeatureKeys: ["app:com.figma.Desktop"])
        #expect(rows.count == 2)
        #expect(Set(rows.map(\.projectId)) == ["acme", "internal"])
    }

    @Test("lookups only return the features asked for")
    func narrowLookup() throws {
        let store = try TrackerStore()
        try store.recordObservations([
            observation("entity:figma::abc", "acme"),
            observation("entity:figma::zzz", "internal"),
        ])

        let rows = try store.loadAssociations(forFeatureKeys: ["entity:figma::abc"])
        #expect(rows.map(\.feature) == ["entity:figma::abc"])
        #expect(try store.loadAssociations(forFeatureKeys: []).isEmpty)
    }

    @Test("evidence decays with time rather than accumulating forever")
    func decayOnWrite() throws {
        let store = try TrackerStore()
        try store.recordObservations([observation("app:x", "acme", weight: 10, at: daysAgo(21))])

        // Three weeks later, add one more: the old mass should have halved first.
        try store.recordObservations([observation("app:x", "acme", weight: 1, at: now)])

        let rows = try store.loadAssociations(forFeatureKeys: ["app:x"])
        #expect(abs(rows[0].mass - 6) < 0.05)
    }

    @Test("a correction reduces the evidence for the wrong project")
    func corrections() throws {
        let store = try TrackerStore()
        try store.recordObservations([observation("entity:figma::abc", "internal", weight: 3)])
        try store.recordObservations([observation("entity:figma::abc", "internal", weight: -2)])

        let rows = try store.loadAssociations(forFeatureKeys: ["entity:figma::abc"])
        #expect(rows.count == 1)
        #expect(abs(rows[0].mass - 1) < 0.01)
    }

    @Test("evidence corrected away entirely is removed, not left at zero")
    func fullyCorrectedRowsDisappear() throws {
        let store = try TrackerStore()
        try store.recordObservations([observation("entity:figma::abc", "internal", weight: 1)])
        try store.recordObservations([observation("entity:figma::abc", "internal", weight: -5)])

        #expect(try store.loadAssociations(forFeatureKeys: ["entity:figma::abc"]).isEmpty)
    }

    @Test("compaction drops weak stale evidence but keeps strong evidence")
    func compaction() throws {
        let store = try TrackerStore()
        try store.recordObservations([
            observation("app:barely-seen", "acme", weight: 1, at: daysAgo(1)),
            observation("app:well-established", "acme", weight: 20, at: daysAgo(1)),
        ])

        // Five months on: the single sighting is gone, the established one
        // is faint but still real.
        let removed = try store.compactLearning(now: now.addingTimeInterval(150 * 86_400))
        #expect(removed == 1)
        #expect(try store.learningRowCount() == 1)
    }

    @Test("evidence never revisited eventually disappears completely")
    func everythingFadesEventually() throws {
        // Intended: a project you stopped working on a year ago should stop
        // influencing suggestions, however heavily it was used at the time.
        let store = try TrackerStore()
        try store.recordObservations([
            observation("app:last-year", "acme", weight: 50, at: daysAgo(1)),
        ])

        try store.compactLearning(now: now.addingTimeInterval(365 * 86_400))
        #expect(try store.learningRowCount() == 0)
    }

    @Test("deleting a project forgets what was learned about it")
    func deletingProjectForgets() throws {
        let store = try TrackerStore()
        try store.save(Project(id: "acme", name: "Acme Corp"))
        try store.recordObservations([
            observation("entity:figma::abc", "acme"),
            observation("entity:figma::abc", "internal"),
        ])

        try store.deleteProject(id: "acme")

        let rows = try store.loadAssociations(forFeatureKeys: ["entity:figma::abc"])
        #expect(rows.map(\.projectId) == ["internal"],
                "a deleted project must never be suggested again")
    }

    @Test("only existing projects are eligible for suggestions")
    func eligibility() async throws {
        let store = try TrackerStore()
        try store.save(Project(id: "live", name: "Live"))
        try store.save(Project(id: "archived", name: "Archived", archived: true))

        let eligible = await store.eligibleProjectIds()
        #expect(eligible == ["live"], "archived projects should not be suggested")
    }
}

@Suite("Learning end to end through the store")
struct LearningRoundTripTests {
    @Test("assigning the same work repeatedly makes it recognisable")
    func learnsFromRepetition() throws {
        let store = try TrackerStore()
        try store.save(Project(id: "acme", name: "Acme Corp"))

        let index = LearnedIndex.default
        let snapshot = ActivitySnapshot(
            bundleID: "com.figma.Desktop", appName: "Figma",
            windowTitle: "KPI Screens", documentPath: "/Users/d/Projects/acme/kpi.fig"
        )

        // Ten sessions of real work, each explicitly assigned by hand.
        for day in 0..<10 {
            let start = now.addingTimeInterval(Double(-day) * 86_400)
            let session = Session(
                appBundleID: snapshot.bundleID, appName: snapshot.appName,
                windowTitle: snapshot.windowTitle, documentPath: snapshot.documentPath,
                projectId: "acme", assignmentSource: .manualDashboard, assignmentConfidence: 100,
                startTime: start, endTime: start.addingTimeInterval(1800), durationSeconds: 1800
            )
            try store.recordObservations(index.observations(for: session, projectId: "acme"))
        }

        let features = FeatureExtractor.features(for: snapshot)
        let associations = try store.loadAssociations(forFeatureKeys: features.map(\.key))
        let suggestion = try #require(index.suggest(
            features: features, associations: associations,
            eligibleProjectIds: ["acme"], now: now
        ))

        #expect(suggestion.projectId == "acme")
        #expect(suggestion.confidence >= AppSettings.default.reviewConfidenceThreshold,
                "ten hand-assigned sessions should be enough to stop asking")
    }

    @Test("work split between two projects does not become a confident guess")
    func ambiguousWorkStaysUnsure() throws {
        let store = try TrackerStore()
        let index = LearnedIndex.default
        let snapshot = ActivitySnapshot(
            bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", windowTitle: "Slack"
        )

        // Slack genuinely gets used for both projects, roughly equally.
        for day in 0..<10 {
            let start = now.addingTimeInterval(Double(-day) * 86_400)
            let project = day.isMultiple(of: 2) ? "acme" : "internal"
            let session = Session(
                appBundleID: snapshot.bundleID, appName: snapshot.appName,
                windowTitle: snapshot.windowTitle,
                projectId: project, assignmentSource: .manualDashboard, assignmentConfidence: 100,
                startTime: start, endTime: start.addingTimeInterval(1800), durationSeconds: 1800
            )
            try store.recordObservations(index.observations(for: session, projectId: project))
        }

        let features = FeatureExtractor.features(for: snapshot)
        let associations = try store.loadAssociations(forFeatureKeys: features.map(\.key))
        let suggestion = index.suggest(
            features: features, associations: associations,
            eligibleProjectIds: ["acme", "internal"], now: now
        )

        #expect((suggestion?.confidence ?? 0) < AppSettings.default.learnedMinimumConfidence,
                "genuinely shared tools must stay unassigned rather than guess")
    }
}

@Suite("Replaying history")
struct HistoricalObservationTests {
    @Test("old evidence is recorded as old, not as if it happened today")
    func historyIsNotBackdatedToNow() throws {
        // This matters when replaying history: restoring a backup, or applying
        // a new rule to past sessions. Treating a year-old session as fresh
        // evidence would let stale patterns outvote current ones.
        let store = try TrackerStore()
        try store.recordObservations([
            observation("app:x", "acme", weight: 10, at: daysAgo(180))
        ])

        let row = try #require(try store.loadAssociations(forFeatureKeys: ["app:x"]).first)
        #expect(row.lastUpdated < daysAgo(179), "the timestamp must be the event's, not now")
        #expect(LearnedIndex.default.decayedMass(row, now: now) < 0.1,
                "six-month-old evidence should barely count")
    }

    @Test("observations arriving out of order do not inflate the total")
    func outOfOrderObservations() throws {
        let store = try TrackerStore()
        // Recent first, then an older one replayed afterwards.
        try store.recordObservations([observation("app:x", "acme", weight: 10, at: now)])
        try store.recordObservations([observation("app:x", "acme", weight: 10, at: daysAgo(42))])

        let row = try #require(try store.loadAssociations(forFeatureKeys: ["app:x"]).first)
        // The older observation is aged to the reference point, so it counts
        // for a quarter of its face value rather than a full second helping.
        #expect(row.mass > 10 && row.mass < 13)
    }
}
