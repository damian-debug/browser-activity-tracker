import Testing
import Foundation
@testable import TimeTrackerCore

private let base = Date(unixMillis: 1_700_000_000_000)

private func session(
    id: String = UUID().uuidString,
    app: String = "com.google.Chrome",
    appName: String = "Google Chrome",
    url: String? = "https://bubble.io/page?id=sampleapp",
    domain: String? = "bubble.io",
    service: String? = nil,
    entityId: String? = nil,
    projectId: String? = nil,
    source: AssignmentSource = .unassigned,
    confidence: Int = 0,
    tagIds: [String] = [],
    billable: Bool = false,
    reviewed: Bool = false,
    away: Bool = false,
    seconds: Int = 60,
    startOffset: Int = 0
) -> Session {
    Session(
        id: id, appBundleID: app, appName: appName,
        url: url, domain: domain,
        service: service, detectedEntityId: entityId,
        projectId: projectId, assignmentSource: source, assignmentConfidence: confidence,
        tagIds: tagIds, billable: billable, reviewed: reviewed, countedWhileAway: away,
        startTime: base.addingTimeInterval(Double(startOffset)),
        endTime: base.addingTimeInterval(Double(startOffset + seconds)),
        durationSeconds: seconds
    )
}

@Suite("Review queue rule")
struct NeedsReviewTests {
    let threshold = 70

    @Test("unassigned time always needs review")
    func unassignedNeedsReview() {
        #expect(StatsBuilder.needsReview(session(), threshold: threshold))
    }

    @Test("a low-confidence auto assignment needs review")
    func lowConfidenceNeedsReview() {
        let s = session(projectId: "p1", source: .autoRule, confidence: Confidence.domain)
        #expect(StatsBuilder.needsReview(s, threshold: threshold))
    }

    @Test("a high-confidence auto assignment does not")
    func highConfidenceSkipsReview() {
        let s = session(projectId: "p1", source: .autoRule, confidence: Confidence.urlContains)
        #expect(!StatsBuilder.needsReview(s, threshold: threshold))
    }

    @Test("confidence exactly at the threshold passes")
    func thresholdIsInclusive() {
        let s = session(projectId: "p1", source: .autoRule, confidence: 70)
        #expect(!StatsBuilder.needsReview(s, threshold: threshold))
    }

    @Test("an explicit review always wins, even when unassigned")
    func reviewedWins() {
        #expect(!StatsBuilder.needsReview(session(reviewed: true), threshold: threshold))
        let lowButReviewed = session(projectId: "p1", source: .autoRule, confidence: 10, reviewed: true)
        #expect(!StatsBuilder.needsReview(lowButReviewed, threshold: threshold))
    }

    @Test("raising the threshold pulls more work into the queue")
    func thresholdIsConfigurable() {
        let s = session(projectId: "p1", source: .autoRule, confidence: 80)
        #expect(!StatsBuilder.needsReview(s, threshold: 70))
        #expect(StatsBuilder.needsReview(s, threshold: 90))
    }
}

@Suite("Dashboard stats")
struct StatsBuilderTests {
    let projects = [
        Project(id: "p1", name: "Acme Corp", clientName: "Acme, Inc.", color: "#f00"),
        Project(id: "p2", name: "Internal"),
    ]
    let tags = [
        Tag(id: "t1", name: "Development"),
        Tag(id: "t2", name: "Design"),
    ]

    @Test("totals add up, and unassigned time is called out")
    func totals() {
        let stats = StatsBuilder.build(
            sessions: [
                session(projectId: "p1", source: .manualDashboard, confidence: 100, billable: true, seconds: 100),
                session(projectId: nil, seconds: 50),
            ],
            projects: projects, tags: tags
        )
        #expect(stats.totalActiveSeconds == 150)
        #expect(stats.billableSeconds == 100)
        #expect(stats.unassignedSeconds == 50)
        #expect(stats.sessionCount == 2)
    }

    @Test("project totals resolve names and split billable from non-billable")
    func projectTotals() {
        let stats = StatsBuilder.build(
            sessions: [
                session(projectId: "p1", billable: true, seconds: 100),
                session(projectId: "p1", billable: false, seconds: 40),
            ],
            projects: projects, tags: tags
        )
        let acme = try! #require(stats.projectTotals.first { $0.projectId == "p1" })
        #expect(acme.projectName == "Acme Corp")
        #expect(acme.clientName == "Acme, Inc.")
        #expect(acme.totalSeconds == 140)
        #expect(acme.billableSeconds == 100)
        #expect(acme.nonBillableSeconds == 40)
        #expect(acme.sessionCount == 2)
    }

    @Test("unassigned time gets its own bucket")
    func unassignedBucket() {
        let stats = StatsBuilder.build(sessions: [session(seconds: 30)], projects: projects)
        let bucket = try! #require(stats.projectTotals.first)
        #expect(bucket.projectId == nil)
        #expect(bucket.projectName == "Unassigned")
    }

    @Test("a deleted project falls back to the name stored on the session")
    func orphanedProjectName() {
        var s = session(projectId: "gone", seconds: 30)
        s.projectName = "Old Name"
        let stats = StatsBuilder.build(sessions: [s], projects: projects)
        #expect(stats.projectTotals.first?.projectName == "Old Name")
    }

    @Test("apps, domains and entities are each rolled up")
    func breakdowns() {
        let stats = StatsBuilder.build(
            sessions: [
                session(app: "com.google.Chrome", url: "https://www.figma.com/design/abc/F",
                        domain: "figma.com", service: "figma", entityId: "abc", seconds: 100),
                session(app: "com.google.Chrome", url: "https://www.figma.com/design/abc/F",
                        domain: "figma.com", service: "figma", entityId: "abc", seconds: 50),
                session(app: "com.microsoft.VSCode", appName: "Code",
                        url: nil, domain: nil, seconds: 25),
            ],
            projects: projects
        )
        #expect(stats.apps.count == 2)
        #expect(stats.apps.first?.bundleID == "com.google.Chrome")
        #expect(stats.apps.first?.totalSeconds == 150)

        // The native session contributes no domain.
        #expect(stats.domains.count == 1)
        #expect(stats.domains.first?.totalSeconds == 150)

        let entity = try! #require(stats.entities.first)
        #expect(entity.entityId == "abc")
        #expect(entity.totalSeconds == 150)
        #expect(entity.sessionCount == 2)
    }

    @Test("a session with several tags counts toward each of them")
    func tagTotals() {
        let stats = StatsBuilder.build(
            sessions: [session(tagIds: ["t1", "t2"], seconds: 60)],
            projects: projects, tags: tags
        )
        #expect(stats.tagTotals.count == 2)
        #expect(stats.tagTotals.allSatisfy { $0.totalSeconds == 60 })
        #expect(stats.tagTotals.contains { $0.tagName == "Development" })
    }

    @Test("away-time is totalled separately so it never hides in desk-work figures")
    func awayTime() {
        let stats = StatsBuilder.build(
            sessions: [
                session(projectId: "p1", seconds: 100),
                session(projectId: "p1", away: true, seconds: 1800),
            ],
            projects: projects
        )
        #expect(stats.totalActiveSeconds == 1900)
        #expect(stats.awaySeconds == 1800)
    }

    @Test("breakdowns are sorted by time, descending")
    func sorting() {
        let stats = StatsBuilder.build(
            sessions: [
                session(app: "a", seconds: 10),
                session(app: "b", seconds: 100),
                session(app: "c", seconds: 50),
            ]
        )
        #expect(stats.apps.map(\.totalSeconds) == [100, 50, 10])
    }

    @Test("no sessions yields zeroes, not nil")
    func emptyInput() {
        let stats = StatsBuilder.build(sessions: [])
        #expect(stats.totalActiveSeconds == 0)
        #expect(stats.projectTotals.isEmpty)
        #expect(stats.sessionCount == 0)
    }
}
