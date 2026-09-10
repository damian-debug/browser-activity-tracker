import Testing
import Foundation
@testable import TimeTrackerCore

private let base = Date(unixMillis: 1_700_000_000_000)

@Suite("Project and feature hierarchy")
struct HierarchyTests {
    let acme = Project(id: "acme", name: "Acme Corp")
    let payments = Project(id: "payments", name: "Payment integration", parentId: "acme")
    let checkout = Project(id: "checkout", name: "Checkout redesign", parentId: "acme")
    let internalWork = Project(id: "internal", name: "Internal")

    var all: [Project] { [acme, payments, checkout, internalWork] }

    @Test("top-level projects exclude features")
    func topLevel() {
        #expect(Set(all.topLevel.map(\.id)) == ["acme", "internal"])
    }

    @Test("features are found by their parent, in display order")
    func features() {
        #expect(all.features(of: "acme").map(\.id) == ["checkout", "payments"])
        #expect(all.features(of: "internal").isEmpty)
    }

    @Test("a feature knows it is one")
    func isFeature() {
        #expect(payments.isFeature)
        #expect(!acme.isFeature)
    }
}

@Suite("Feature totals")
struct FeatureTotalTests {
    func session(
        project: String?, feature: String? = nil, seconds: Int = 600, billable: Bool = false
    ) -> Session {
        Session(
            appBundleID: "com.figma.Desktop", appName: "Figma",
            projectId: project, projectName: project,
            featureId: feature, featureName: feature,
            billable: billable,
            startTime: base, endTime: base.addingTimeInterval(Double(seconds)),
            durationSeconds: seconds
        )
    }

    let projects = [
        Project(id: "acme", name: "Acme Corp"),
        Project(id: "payments", name: "Payment integration", parentId: "acme"),
        Project(id: "checkout", name: "Checkout redesign", parentId: "acme"),
    ]

    @Test("features roll up inside their project, not alongside it")
    func rollUp() {
        // The project total must stay whole however finely the work is split,
        // or a breakdown would silently change the invoice.
        let stats = StatsBuilder.build(
            sessions: [
                session(project: "acme", feature: "payments", seconds: 600),
                session(project: "acme", feature: "checkout", seconds: 300),
                session(project: "acme", feature: nil, seconds: 100),
            ],
            projects: projects
        )

        let acme = try! #require(stats.projectTotals.first { $0.projectId == "acme" })
        #expect(acme.totalSeconds == 1000, "the project still totals everything")

        #expect(stats.featureTotals.count == 2)
        #expect(stats.featureTotals.reduce(0) { $0 + $1.totalSeconds } == 900,
                "unfeatured time belongs to the project but to no feature")
    }

    @Test("feature totals resolve names and carry their project")
    func names() {
        let stats = StatsBuilder.build(
            sessions: [session(project: "acme", feature: "payments")], projects: projects
        )
        let feature = try! #require(stats.featureTotals.first)
        #expect(feature.featureName == "Payment integration")
        #expect(feature.projectName == "Acme Corp")
    }

    @Test("billable time is tracked per feature as well")
    func billablePerFeature() {
        let stats = StatsBuilder.build(
            sessions: [
                session(project: "acme", feature: "payments", seconds: 600, billable: true),
                session(project: "acme", feature: "payments", seconds: 300, billable: false),
            ],
            projects: projects
        )
        let feature = try! #require(stats.featureTotals.first)
        #expect(feature.totalSeconds == 900)
        #expect(feature.billableSeconds == 600)
    }

    @Test("a deleted feature falls back to the name stored on the session")
    func orphanedFeature() {
        let stats = StatsBuilder.build(
            sessions: [session(project: "acme", feature: "gone")], projects: projects
        )
        #expect(stats.featureTotals.first?.featureName == "gone")
    }

    @Test("no features means no feature breakdown, not an empty row")
    func noFeatures() {
        let stats = StatsBuilder.build(sessions: [session(project: "acme")], projects: projects)
        #expect(stats.featureTotals.isEmpty)
        #expect(stats.projectTotals.count == 1)
    }
}

@Suite("Features survive a backup round trip")
struct FeatureBackupTests {
    @Test("the hierarchy and per-session feature are preserved")
    func roundTrip() throws {
        let contents = Backup.Contents(
            projects: [
                Project(id: "acme", name: "Acme Corp"),
                Project(id: "payments", name: "Payment integration", parentId: "acme"),
            ],
            sessions: [
                Session(
                    id: "s1", appBundleID: "com.microsoft.VSCode", appName: "Code",
                    gitBranch: "feature/payments",
                    projectId: "acme", featureId: "payments", featureName: "Payment integration",
                    startTime: base, endTime: base.addingTimeInterval(600), durationSeconds: 600
                )
            ]
        )

        let data = try Backup.encode(contents)
        guard case .success(let restored) = Backup.decode(data) else {
            Issue.record("expected the backup to decode"); return
        }

        #expect(restored.projects.first { $0.id == "payments" }?.parentId == "acme")
        let session = try #require(restored.sessions.first)
        #expect(session.featureId == "payments")
        #expect(session.featureName == "Payment integration")
        #expect(session.gitBranch == "feature/payments")
    }

    @Test("an older backup with no features still imports")
    func olderBackupsStillWork() {
        // v3 files from the Chrome extension know nothing about features.
        let v3 = #"""
        {"format":"bat-backup","schemaVersion":3,"exportedAt":0,"settings":{},
         "projects":[{"id":"p1","name":"Acme Corp"}],"tags":[],"rules":[],
         "sessions":[{"id":"s1","startTime":1,"endTime":2,"durationSeconds":1}]}
        """#
        guard case .success(let contents) = Backup.decode(v3.data(using: .utf8)!) else {
            Issue.record("expected the older file to import"); return
        }
        #expect(contents.projects.first?.parentId == nil)
        #expect(contents.sessions.first?.featureId == nil)
    }
}

@Suite("Finding a feature by name")
struct FeatureByNameTests {
    let projects = [
        Project(id: "acme", name: "Acme"),
        Project(id: "beta", name: "Beta"),
        Project(id: "pay", name: "Payments", parentId: "acme"),
        Project(id: "beta-pay", name: "Payments", parentId: "beta"),
    ]

    @Test("matches regardless of case and surrounding space")
    func caseAndSpace() {
        #expect(projects.feature(named: "  payMENTS ", in: "acme")?.id == "pay")
    }

    @Test("only within the given project")
    func scopedToProject() {
        #expect(projects.feature(named: "Payments", in: "beta")?.id == "beta-pay")
        #expect(projects.feature(named: "Payments", in: "nope") == nil)
    }

    @Test("a blank name matches nothing")
    func blank() {
        #expect(projects.feature(named: "   ", in: "acme") == nil)
    }

    @Test("a top-level project is never returned as a feature")
    func notTopLevel() {
        #expect(projects.feature(named: "Beta", in: "acme") == nil)
    }
}
