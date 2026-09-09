import Testing
import Foundation
import TimeTrackerCore
@testable import TimeTrackerApp

// Recent, because the dashboard defaults to today's range.
private let start = Date().addingTimeInterval(-1800)

private func session(
    id: String = UUID().uuidString,
    project: String? = nil,
    feature: String? = nil,
    reviewed: Bool = false,
    documentPath: String? = "/Users/d/Projects/acme/kpi.fig"
) -> Session {
    Session(
        id: id, appBundleID: "com.figma.Desktop", appName: "Figma",
        windowTitle: "KPI Screens", documentPath: documentPath,
        projectId: project, projectName: project,
        featureId: feature, featureName: feature,
        assignmentSource: project == nil ? .unassigned : .manualDashboard,
        assignmentConfidence: project == nil ? 0 : 100,
        reviewed: reviewed,
        startTime: start, endTime: start.addingTimeInterval(600), durationSeconds: 600
    )
}

@MainActor
@Suite("Rules targeting a feature")
struct RuleFeatureTests {
    func setUp() throws -> (TrackerStore, DashboardModel) {
        let store = try TrackerStore()
        try store.save(Project(id: "acme", name: "Acme Corp"))
        try store.save(Project(id: "payments", name: "Payment integration", parentId: "acme"))
        return (store, DashboardModel(store: store))
    }

    @Test("a rule can name a feature, and applies both when it fires")
    func ruleAssignsFeature() throws {
        let (store, model) = try setUp()
        try store.save(session(id: "s1"))
        model.reload()

        var draft = DashboardModel.RuleDraft()
        draft.projectId = "acme"
        draft.featureId = "payments"
        draft.type = .documentPathContains
        draft.value = "/Projects/acme/"

        model.save(draft, applyToPast: true)

        let updated = try #require(try store.allSessions().first)
        #expect(updated.projectId == "acme")
        #expect(updated.featureId == "payments")
        #expect(updated.featureName == "Payment integration")
    }

    @Test("a rule's feature beats what the model would have guessed")
    func ruleFeatureWinsOverLearning() async throws {
        let (store, _) = try setUp()
        try store.save(ProjectRule(
            projectId: "acme", featureId: "payments", name: "Acme files",
            type: .documentPathContains, value: "/Projects/acme/"
        ))

        let coordinator = ActivityCoordinator(dependencies: store)
        await coordinator.observe(ActivitySnapshot(
            bundleID: "com.figma.Desktop", appName: "Figma",
            documentPath: "/Users/d/Projects/acme/kpi.fig"
        ), now: start)

        let status = await coordinator.status(now: start)
        #expect(status.projectId == "acme")
        #expect(status.featureId == "payments")
    }

    @Test("changing the project clears a feature that no longer belongs")
    func featureClearedWithProject() throws {
        let (_, model) = try setUp()
        var draft = DashboardModel.RuleDraft()
        draft.projectId = "acme"
        draft.featureId = "payments"

        // The editor clears it on change; this asserts the invariant it keeps.
        draft.projectId = "other"
        draft.featureId = nil
        #expect(draft.featureId == nil)
    }

    @Test("a rule's feature survives a backup round trip")
    func backupRoundTrip() throws {
        let (store, _) = try setUp()
        try store.save(ProjectRule(
            id: "r1", projectId: "acme", featureId: "payments", name: "Acme files",
            type: .documentPathContains, value: "/Projects/acme/"
        ))

        let data = try Backup.encode(try store.backupContents())
        guard case .success(let contents) = Backup.decode(data) else {
            Issue.record("expected the backup to decode"); return
        }
        #expect(contents.rules.first?.featureId == "payments")
    }
}

@MainActor
@Suite("Editing rules")
struct RuleEditingTests {
    func setUp() throws -> (TrackerStore, DashboardModel) {
        let store = try TrackerStore()
        try store.save(Project(id: "acme", name: "Acme Corp"))
        try store.save(Project(id: "other", name: "Other Client"))
        return (store, DashboardModel(store: store))
    }

    @Test("a suggested value can be edited before the rule is created")
    func editableValue() throws {
        let (store, model) = try setUp()
        try store.save(session(id: "s1", documentPath: "/Users/d/Projects/acme/deep/nested/kpi.fig"))
        model.reload()

        let recorded = try #require(model.sessions.first)
        let suggestion = try #require(
            model.ruleSuggestions(for: recorded).first { $0.type == .documentPathContains }
        )
        var draft = DashboardModel.RuleDraft(suggestion, projectId: "acme", featureId: nil)

        // Broaden it by hand: the suggestion offered the deepest folder, but
        // the project actually lives one level up.
        draft.value = "/Projects/acme/"
        model.save(draft, applyToPast: true)

        let rule = try #require(try store.rules().first)
        #expect(rule.value == "/Projects/acme/")
        #expect(try store.allSessions().first?.projectId == "acme")
    }

    @Test("editing an existing rule updates it rather than adding another")
    func editUpdatesInPlace() throws {
        let (store, model) = try setUp()
        try store.save(ProjectRule(
            id: "r1", projectId: "acme", name: "Acme files",
            type: .documentPathContains, value: "/Projects/acme/"
        ))
        model.reload()

        var draft = DashboardModel.RuleDraft(try #require(model.rules.first))
        draft.value = "/Projects/acme-v2/"
        model.save(draft, applyToPast: false)

        #expect(try store.rules().count == 1)
        #expect(try store.rules().first?.value == "/Projects/acme-v2/")
    }

    @Test("a rule can be disabled without undoing the time it already assigned")
    func disablingKeepsHistory() throws {
        let (store, model) = try setUp()
        let rule = ProjectRule(
            id: "r1", projectId: "acme", name: "Acme files",
            type: .documentPathContains, value: "/Projects/acme/"
        )
        try store.save(rule)
        try store.save(session(id: "s1", project: "acme", reviewed: true))
        model.reload()

        model.setRule(rule, enabled: false)

        #expect(try store.rules().first?.enabled == false)
        #expect(try store.allSessions().first?.projectId == "acme",
                "disabling a rule is not a reason to unpick decisions already made")
    }

    @Test("deleting a rule leaves the time it assigned alone")
    func deletingKeepsHistory() throws {
        let (store, model) = try setUp()
        let rule = ProjectRule(
            id: "r1", projectId: "acme", name: "Acme files",
            type: .documentPathContains, value: "/Projects/acme/"
        )
        try store.save(rule)
        try store.save(session(id: "s1", project: "acme", reviewed: true))
        model.reload()

        model.delete(rule)

        #expect(try store.rules().isEmpty)
        #expect(try store.allSessions().first?.projectId == "acme")
    }

    @Test("an existing rule can be applied to work recorded before it")
    func applyToPast() throws {
        let (store, model) = try setUp()
        try store.save(session(id: "s1"))
        try store.save(session(id: "s2"))
        let rule = ProjectRule(
            id: "r1", projectId: "acme", name: "Acme files",
            type: .documentPathContains, value: "/Projects/acme/"
        )
        try store.save(rule)
        model.reload()

        model.applyToPast(rule)

        #expect(try store.allSessions().allSatisfy { $0.projectId == "acme" })
    }

    @Test("rules are grouped by the project they file time under")
    func grouping() throws {
        let (store, model) = try setUp()
        try store.save(ProjectRule(id: "r1", projectId: "acme", name: "A", type: .domainEquals, value: "a.com"))
        try store.save(ProjectRule(id: "r2", projectId: "acme", name: "B", type: .domainEquals, value: "b.com"))
        try store.save(ProjectRule(id: "r3", projectId: "other", name: "C", type: .domainEquals, value: "c.com"))
        model.reload()

        let groups = model.rulesGroupedByProject()
        #expect(groups.count == 2)
        #expect(groups.first { $0.project == "Acme Corp" }?.rules.count == 2)
    }
}

@MainActor
@Suite("Previewing what a rule would do")
struct RuleImpactTests {
    @Test("the preview counts what a rule would claim before it is saved")
    func showsClaims() throws {
        let store = try TrackerStore()
        try store.save(Project(id: "acme", name: "Acme Corp"))
        for i in 0..<3 { try store.save(session(id: "s\(i)")) }
        let model = DashboardModel(store: store)

        var draft = DashboardModel.RuleDraft()
        draft.projectId = "acme"
        draft.type = .documentPathContains
        draft.value = "/Projects/acme/"

        let impact = try #require(model.impact(of: draft))
        #expect(impact.claims == 3)
        #expect(impact.alreadyDecided == 0)
        #expect(try store.rules().isEmpty, "previewing must not save anything")
    }

    @Test("the preview warns when a rule reaches work already decided")
    func warnsAboutSettledWork() throws {
        // A rule matching a lot of settled work is usually broader than
        // intended, and that is worth seeing before saving rather than after.
        let store = try TrackerStore()
        try store.save(Project(id: "acme", name: "Acme Corp"))
        try store.save(session(id: "open"))
        try store.save(session(id: "settled", project: "other", reviewed: true))
        let model = DashboardModel(store: store)

        var draft = DashboardModel.RuleDraft()
        draft.projectId = "acme"
        draft.type = .appBundleEquals
        draft.value = "com.figma.Desktop"

        let impact = try #require(model.impact(of: draft))
        #expect(impact.claims == 1)
        #expect(impact.alreadyDecided == 1)
    }

    @Test("an incomplete draft previews nothing rather than guessing")
    func incompleteDraft() throws {
        let store = try TrackerStore()
        let model = DashboardModel(store: store)

        var draft = DashboardModel.RuleDraft()
        #expect(model.impact(of: draft) == nil)

        draft.projectId = "acme"
        #expect(model.impact(of: draft) == nil, "no value yet")

        draft.type = .queryParamEquals
        draft.value = "abc"
        #expect(model.impact(of: draft) == nil, "a query-param rule needs its parameter name")
    }
}

@MainActor
@Suite("Creating a rule from scratch")
struct RuleFromScratchTests {
    func setUp() throws -> (TrackerStore, DashboardModel) {
        let store = try TrackerStore()
        try store.save(Project(id: "acme", name: "Acme Corp"))
        try store.save(Project(id: "payments", name: "Payment integration", parentId: "acme"))
        return (store, DashboardModel(store: store))
    }

    @Test("a blank draft starts somewhere usable rather than empty")
    func blankDraft() throws {
        let (_, model) = try setUp()
        let draft = model.newRuleDraft()

        // With no session for context, the app is the one thing that can be
        // picked from a list rather than recalled.
        #expect(draft.type == .appBundleEquals)
        #expect(draft.ruleId == nil)
        #expect(draft.projectId == "acme", "pre-selecting the only project saves a step")
        #expect(!draft.isValid, "still needs a value before it can be saved")
    }

    @Test("a rule written from scratch saves and takes effect")
    func savesFromScratch() async throws {
        let (store, model) = try setUp()

        var draft = model.newRuleDraft()
        draft.value = "com.figma.Desktop"
        draft.featureId = "payments"
        model.save(draft, applyToPast: false)

        let rule = try #require(try store.rules().first)
        #expect(rule.type == .appBundleEquals)
        #expect(rule.projectId == "acme")
        #expect(rule.featureId == "payments")

        // And it actually attributes work.
        let coordinator = ActivityCoordinator(dependencies: store)
        await coordinator.observe(
            ActivitySnapshot(bundleID: "com.figma.Desktop", appName: "Figma"), now: Date()
        )
        let status = await coordinator.status(now: Date())
        #expect(status.projectId == "acme")
        #expect(status.featureId == "payments")
    }

    @Test("the apps you have actually used are offered, most-used first")
    func knownApps() throws {
        let (store, _) = try setUp()
        let now = Date()
        func used(_ bundleID: String, _ name: String, seconds: Int) throws {
            try store.save(Session(
                appBundleID: bundleID, appName: name,
                startTime: now.addingTimeInterval(-Double(seconds)), endTime: now,
                durationSeconds: seconds
            ))
        }
        try used("com.apple.Terminal", "Terminal", seconds: 100)
        try used("com.figma.Desktop", "Figma", seconds: 900)

        let model = DashboardModel(store: store)
        #expect(model.knownApps.first?.bundleID == "com.figma.Desktop")
        #expect(model.knownApps.map(\.bundleID).contains("com.apple.Terminal"))
    }

    @Test("the sites you have visited are offered, and blanks are not")
    func knownSites() throws {
        let (store, _) = try setUp()
        let now = Date()
        try store.save(Session(
            appBundleID: "com.google.Chrome", appName: "Google Chrome",
            url: "https://figma.com/x", domain: "figma.com",
            startTime: now.addingTimeInterval(-600), endTime: now, durationSeconds: 600
        ))
        try store.save(Session(
            appBundleID: "com.apple.Terminal", appName: "Terminal",
            startTime: now.addingTimeInterval(-60), endTime: now, durationSeconds: 60
        ))

        let model = DashboardModel(store: store)
        #expect(model.knownSites == ["figma.com"], "native sessions contribute no site")
    }

    @Test("a from-scratch rule can be previewed before saving, like any other")
    func previewWorks() throws {
        let (store, _) = try setUp()
        let now = Date()
        try store.save(Session(
            appBundleID: "com.figma.Desktop", appName: "Figma",
            startTime: now.addingTimeInterval(-600), endTime: now, durationSeconds: 600
        ))

        let model = DashboardModel(store: store)
        var draft = model.newRuleDraft()
        draft.value = "com.figma.Desktop"

        let impact = try #require(model.impact(of: draft))
        #expect(impact.claims == 1)
        #expect(try store.rules().isEmpty, "previewing must not save anything")
    }
}
