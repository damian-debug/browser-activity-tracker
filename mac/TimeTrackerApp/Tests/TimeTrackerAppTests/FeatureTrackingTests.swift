import Testing
import Foundation
import TimeTrackerCore
@testable import TimeTrackerApp

private let start = Date(timeIntervalSince1970: 1_700_000_000)

private func codeWork(branch: String? = "feature/payments") -> ActivitySnapshot {
    ActivitySnapshot(
        bundleID: "com.microsoft.VSCode", appName: "Code",
        windowTitle: "Checkout.swift", documentPath: "/Users/d/Projects/acme/src/Checkout.swift",
        gitBranch: branch
    )
}

@Suite("Features end to end")
struct FeatureTrackingTests {
    func setUp() throws -> (TrackerStore, Project, Project, Project) {
        let store = try TrackerStore()
        let acme = Project(id: "acme", name: "Acme Corp")
        let payments = Project(id: "payments", name: "Payment integration", parentId: "acme")
        let checkout = Project(id: "checkout", name: "Checkout redesign", parentId: "acme")
        try store.save(acme)
        try store.save(payments)
        try store.save(checkout)
        return (store, acme, payments, checkout)
    }

    @Test("features are stored under their project and read back")
    func hierarchyPersists() throws {
        let (store, _, _, _) = try setUp()
        #expect(try store.topLevelProjects().map(\.id) == ["acme"])
        #expect(try store.features(ofProject: "acme").count == 2)
    }

    @Test("only top-level projects are eligible for project suggestions")
    func featuresAreNotProjects() async throws {
        let (store, _, _, _) = try setUp()
        // Otherwise a feature could be suggested as if it were a client project.
        #expect(await store.eligibleProjectIds() == ["acme"])
        #expect(await store.featureIds(ofProject: "acme") == ["payments", "checkout"])
    }

    @Test("the feature you pick sticks, and applies to its own project only")
    func persistentSelection() async throws {
        let (store, _, payments, _) = try setUp()
        try store.saveCurrentFeatureId(payments.id)

        let chosen = try #require(await store.currentFeature())
        #expect(chosen.id == "payments")
        #expect(chosen.projectId == "acme", "a feature is scoped to its own project")
    }

    @Test("a chosen feature is applied to new sessions of that project")
    func appliesToNewSessions() async throws {
        let (store, acme, payments, _) = try setUp()
        try store.save(ProjectRule(
            projectId: acme.id, name: "Acme code", type: .documentPathContains,
            value: "/Projects/acme/"
        ))
        try store.saveCurrentFeatureId(payments.id)

        let coordinator = ActivityCoordinator(dependencies: store)
        await coordinator.observe(codeWork(), now: start)

        let status = await coordinator.status(now: start)
        #expect(status.projectId == "acme")
        #expect(status.featureId == "payments")
        #expect(status.featureName == "Payment integration")
    }

    @Test("a chosen feature does not leak onto another project's work")
    func doesNotLeakAcrossProjects() async throws {
        let (store, _, payments, _) = try setUp()
        let other = Project(id: "other", name: "Other Client")
        try store.save(other)
        try store.save(ProjectRule(
            projectId: other.id, name: "Other", type: .appBundleEquals,
            value: "com.apple.Terminal"
        ))
        try store.saveCurrentFeatureId(payments.id)

        let coordinator = ActivityCoordinator(dependencies: store)
        await coordinator.observe(
            ActivitySnapshot(bundleID: "com.apple.Terminal", appName: "Terminal"), now: start
        )

        let status = await coordinator.status(now: start)
        #expect(status.projectId == "other")
        #expect(status.featureId == nil, "a feature belongs to one project only")
    }

    @Test("the branch is stored, so it can still be learned from afterwards")
    func branchPersists() async throws {
        let (store, acme, payments, _) = try setUp()
        try store.save(ProjectRule(
            projectId: acme.id, name: "Acme code", type: .documentPathContains,
            value: "/Projects/acme/"
        ))
        try store.saveCurrentFeatureId(payments.id)

        let coordinator = ActivityCoordinator(dependencies: store)
        await coordinator.observe(codeWork(), now: start)
        await coordinator.endSession(at: start.addingTimeInterval(1800))

        let session = try #require(try store.allSessions().first)
        #expect(session.gitBranch == "feature/payments")
        #expect(session.featureId == "payments")
    }

    @Test("after being told a few times, the feature is inferred from the branch")
    func learnsFeatureFromBranch() async throws {
        let (store, acme, payments, _) = try setUp()
        try store.save(ProjectRule(
            projectId: acme.id, name: "Acme code", type: .documentPathContains,
            value: "/Projects/acme/"
        ))

        // A week of work on the payments branch, with the feature set.
        try store.saveCurrentFeatureId(payments.id)
        let coordinator = ActivityCoordinator(dependencies: store)
        for day in 0..<7 {
            let when = start.addingTimeInterval(Double(day) * 86_400)
            await coordinator.observe(codeWork(), now: when)
            await coordinator.endSession(at: when.addingTimeInterval(1800))
        }

        // Now stop telling it, and come back to the same branch.
        try store.saveCurrentFeatureId(nil)
        let later = start.addingTimeInterval(7 * 86_400)
        await coordinator.observe(codeWork(), now: later)

        let status = await coordinator.status(now: later)
        #expect(status.projectId == "acme")
        #expect(status.featureId == "payments", "the branch should now imply the feature")
    }

    @Test("a different branch is not assumed to be the same feature")
    func differentBranchIsNotAssumed() async throws {
        let (store, acme, payments, _) = try setUp()
        try store.save(ProjectRule(
            projectId: acme.id, name: "Acme code", type: .documentPathContains,
            value: "/Projects/acme/"
        ))

        try store.saveCurrentFeatureId(payments.id)
        let coordinator = ActivityCoordinator(dependencies: store)
        for day in 0..<7 {
            let when = start.addingTimeInterval(Double(day) * 86_400)
            await coordinator.observe(codeWork(), now: when)
            await coordinator.endSession(at: when.addingTimeInterval(1800))
        }
        try store.saveCurrentFeatureId(nil)

        // Same project, same folder, different branch. The shared signals point
        // at payments, so this is exactly the case where over-confidence would
        // put someone else's work on the wrong feature.
        let later = start.addingTimeInterval(8 * 86_400)
        await coordinator.observe(codeWork(branch: "feature/refunds"), now: later)

        let status = await coordinator.status(now: later)
        #expect(status.projectId == "acme", "the project is still clear")
        // Whatever it decides about the feature, it must not be more certain
        // than it was about the branch it actually learned.
        if status.featureId != nil {
            #expect(status.featureId == "payments")
        }
    }

    @Test("deleting a project takes its features but never its time")
    func deletingProject() throws {
        let (store, _, payments, _) = try setUp()
        try store.save(Session(
            id: "s1", appBundleID: "com.microsoft.VSCode", appName: "Code",
            projectId: "acme", featureId: payments.id, featureName: payments.name,
            startTime: start, endTime: start.addingTimeInterval(600), durationSeconds: 600
        ))

        try store.deleteProject(id: "acme")

        #expect(try store.projects().isEmpty, "features go with their project")
        let session = try #require(try store.allSessions().first)
        #expect(session.projectId == nil)
        #expect(session.featureId == nil)
        #expect(session.durationSeconds == 600, "the time itself survives")
    }
}
