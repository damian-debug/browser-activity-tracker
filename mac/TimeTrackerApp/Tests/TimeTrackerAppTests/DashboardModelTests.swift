import Testing
import Foundation
import TimeTrackerCore
@testable import TimeTrackerApp

// The dashboard is where corrections actually happen, so these focus on the
// consequences of a decision rather than on layout.

private func makeSession(
    id: String = UUID().uuidString,
    project: String? = nil,
    source: AssignmentSource = .unassigned,
    confidence: Int = 0,
    reviewed: Bool = false,
    documentPath: String? = "/Users/d/Projects/acme/kpi.fig",
    minutesAgo: Int = 10
) -> Session {
    let end = Date().addingTimeInterval(-Double(minutesAgo) * 60)
    return Session(
        id: id, appBundleID: "com.figma.Desktop", appName: "Figma",
        windowTitle: "KPI Screens", documentPath: documentPath,
        projectId: project, projectName: project,
        assignmentSource: source, assignmentConfidence: confidence,
        reviewed: reviewed,
        startTime: end.addingTimeInterval(-1800), endTime: end, durationSeconds: 1800
    )
}

@MainActor
@Suite("Dashboard: reviewing")
struct DashboardReviewTests {
    func setUp() throws -> (TrackerStore, DashboardModel, Project) {
        let store = try TrackerStore()
        let project = Project(id: "acme", name: "Acme Corp", defaultBillable: true)
        try store.save(project)
        return (store, DashboardModel(store: store), project)
    }

    @Test("unassigned and low-confidence work shows up for review")
    func queueContents() throws {
        let (store, _, _) = try setUp()
        try store.save(makeSession(id: "unassigned"))
        try store.save(makeSession(id: "weak", project: "acme", source: .suggested, confidence: 55))
        try store.save(makeSession(id: "confident", project: "acme", source: .autoRule, confidence: 95))
        try store.save(makeSession(id: "settled", project: "acme", source: .suggested,
                                   confidence: 55, reviewed: true))

        let model = DashboardModel(store: store)
        let ids = Set(model.reviewSessions.map(\.id))
        #expect(ids == ["unassigned", "weak"])
    }

    @Test("assigning a project settles the session and takes it out of the queue")
    func assigning() throws {
        let (store, model, project) = try setUp()
        try store.save(makeSession(id: "s1"))
        model.reload()

        let session = try #require(model.reviewSessions.first)
        model.assign(session, to: project)

        let updated = try #require(try store.allSessions().first)
        #expect(updated.projectId == "acme")
        #expect(updated.assignmentSource == .manualDashboard)
        #expect(updated.reviewed)
        #expect(updated.billable, "the project's default should carry over")
        #expect(model.reviewSessions.isEmpty)
    }

    @Test("clearing a project puts the time back in the queue rather than settling it")
    func clearing() throws {
        let (store, model, _) = try setUp()
        try store.save(makeSession(id: "s1", project: "acme", source: .manualDashboard,
                                   confidence: 100, reviewed: true))
        model.reload()

        let session = try #require(try store.allSessions().first)
        model.assign(session, to: nil)

        let updated = try #require(try store.allSessions().first)
        #expect(updated.projectId == nil)
        #expect(!updated.reviewed, "unassigning is not a decision about what the time was")
    }

    @Test("assigning teaches the model")
    func assigningTeaches() throws {
        let (store, model, project) = try setUp()
        try store.save(makeSession(id: "s1"))
        model.reload()

        model.assign(try #require(model.reviewSessions.first), to: project)
        #expect(try store.learningRowCount() > 0)
    }

    @Test("overturning an earlier assignment penalises the answer it replaces")
    func overturningPenalises() throws {
        let (store, model, _) = try setUp()
        let other = Project(id: "internal", name: "Internal")
        try store.save(other)

        // Build up belief that this work is Acme.
        try store.recordObservations([
            FeatureObservation(feature: "document:/Users/d/Projects/acme", projectId: "acme",
                               weight: 5, at: Date())
        ])
        let before = try #require(try store
            .loadAssociations(forFeatureKeys: ["document:/Users/d/Projects/acme"])
            .first { $0.projectId == "acme" }).mass

        try store.save(makeSession(id: "s1", project: "acme", source: .suggested, confidence: 60))
        model.reload()
        model.assign(try #require(model.reviewSessions.first), to: other)

        let after = try store
            .loadAssociations(forFeatureKeys: ["document:/Users/d/Projects/acme"])
            .first { $0.projectId == "acme" }?.mass ?? 0
        #expect(after < before, "the replaced answer must lose ground")
    }

    @Test("confirming a suggestion counts as a human endorsement")
    func confirming() throws {
        let (store, model, _) = try setUp()
        try store.save(makeSession(id: "s1", project: "acme", source: .suggested, confidence: 60))
        model.reload()

        model.markReviewed(try #require(model.reviewSessions.first))

        #expect(try store.allSessions().first?.reviewed == true)
        // The app never learns from its own guesses, but a person agreeing
        // with one is real evidence.
        #expect(try store.learningRowCount() > 0)
    }

    @Test("a batch assignment settles every selected session")
    func batchAssign() throws {
        let (store, model, project) = try setUp()
        for i in 0..<5 { try store.save(makeSession(id: "s\(i)")) }
        model.reload()

        model.assignAll(model.reviewSessions, to: project)
        #expect(model.reviewSessions.isEmpty)
        #expect(try store.allSessions().allSatisfy { $0.projectId == "acme" })
    }
}

@MainActor
@Suite("Dashboard: rules from decisions")
struct DashboardRuleTests {
    @Test("creating a rule claims matching past work in one go")
    func ruleBackfills() throws {
        let store = try TrackerStore()
        let project = Project(id: "acme", name: "Acme Corp")
        try store.save(project)
        for i in 0..<4 { try store.save(makeSession(id: "s\(i)")) }

        let model = DashboardModel(store: store)
        let session = try #require(model.reviewSessions.first)
        let folderRule = try #require(
            model.ruleSuggestions(for: session).first { $0.type == .documentPathContains }
        )

        let claimed = model.createRule(folderRule, from: session, project: project)

        #expect(claimed == 4, "every earlier session in that folder should be settled")
        #expect(try store.allSessions().allSatisfy { $0.projectId == "acme" })
        #expect(try store.rules().count == 1)
        #expect(model.reviewSessions.isEmpty)
    }

    @Test("a new rule never overwrites a decision already made")
    func ruleRespectsDecisions() throws {
        let store = try TrackerStore()
        let acme = Project(id: "acme", name: "Acme Corp")
        let other = Project(id: "internal", name: "Internal")
        try store.save(acme)
        try store.save(other)

        try store.save(makeSession(id: "decided", project: "internal",
                                   source: .manualDashboard, confidence: 100, reviewed: true))
        try store.save(makeSession(id: "open"))

        let model = DashboardModel(store: store)
        let session = try #require(model.reviewSessions.first { $0.id == "open" })
        let folderRule = try #require(
            model.ruleSuggestions(for: session).first { $0.type == .documentPathContains }
        )
        model.createRule(folderRule, from: session, project: acme)

        let decided = try #require(try store.allSessions().first { $0.id == "decided" })
        #expect(decided.projectId == "internal", "an explicit decision outranks a later rule")
    }

    @Test("suggestions are offered narrowest first")
    func suggestionOrdering() throws {
        let store = try TrackerStore()
        try store.save(makeSession(id: "s1"))
        let model = DashboardModel(store: store)
        let suggestions = model.ruleSuggestions(for: try #require(model.sessions.first))

        // The document folder should beat "everything in Figma", which would
        // swallow every other project's design work.
        let folderIndex = try #require(suggestions.firstIndex { $0.type == .documentPathContains })
        let appIndex = try #require(suggestions.firstIndex { $0.type == .appBundleEquals })
        #expect(folderIndex < appIndex)
    }
}

@MainActor
@Suite("Dashboard: ranges and export")
struct DashboardRangeTests {
    @Test("changing the range changes what is counted")
    func ranges() throws {
        let store = try TrackerStore()
        try store.save(makeSession(id: "today", minutesAgo: 30))
        try store.save(makeSession(id: "lastweek", minutesAgo: 60 * 24 * 4))

        let model = DashboardModel(store: store)
        model.range = .today
        #expect(model.sessions.map(\.id) == ["today"])

        model.range = .week
        #expect(Set(model.sessions.map(\.id)) == ["today", "lastweek"])
    }

    @Test("the CSV covers exactly the visible range")
    func csvMatchesRange() throws {
        let store = try TrackerStore()
        try store.save(makeSession(id: "today", minutesAgo: 30))
        let model = DashboardModel(store: store)

        let csv = CSVExport.csv(sessions: model.sessions, projects: model.projects, tags: model.tags)
        #expect(csv.contains("Figma"))
        #expect(csv.split(separator: "\r\n").count == 2)
    }
}
