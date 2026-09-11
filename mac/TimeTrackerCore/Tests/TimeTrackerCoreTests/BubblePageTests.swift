import Testing
import Foundation
@testable import TimeTrackerCore

// Real editor URL shapes, from recorded sessions.
private let gpPortal = "https://bubble.io/page?id=meltx&tab=Data&name=gp-portal&version=33j34&type=page&type_id=buyerlistentry"
private let setup = "https://bubble.io/page?id=meltx&tab=Design&name=setup&version=33j34"
private let otherApp = "https://bubble.io/page?id=meltx-dev&tab=Data&name=gp-portal"

@Suite("Bubble pages")
struct BubblePageTests {
    func session(_ url: String) -> Session {
        let parsed = ParserRegistry.parse(url)
        return Session(
            appBundleID: "com.google.Chrome", appName: "Google Chrome",
            windowTitle: "meltx | Bubble Editor", url: url, domain: "bubble.io", title: "meltx | Bubble Editor",
            service: parsed?.service, detectedEntityId: parsed?.entityId,
            startTime: Date(), endTime: Date(), durationSeconds: 60
        )
    }

    @Test("the page being edited is the screen within the app")
    func parsesPage() throws {
        let parsed = try #require(ParserRegistry.parse(gpPortal))
        #expect(parsed.entityId == "meltx")
        #expect(parsed.subEntityId == "gp-portal")
    }

    @Test("moving between pages or tabs of one app is still one piece of work")
    func continuity() {
        let a = ActivitySnapshot(bundleID: "com.google.Chrome", appName: "Chrome", windowTitle: "meltx | Bubble Editor", url: gpPortal)
        let b = ActivitySnapshot(bundleID: "com.google.Chrome", appName: "Chrome", windowTitle: "meltx | Bubble Editor", url: setup)
        #expect(a.identity.continues(b.identity))
    }

    @Test("the address is watched, since the title never names the page")
    func watched() {
        #expect(ParserRegistry.locationChangesWithoutTitle(gpPortal))
    }

    @Test("the page is offered first as a rule, pinned exactly to this app")
    func suggestion() throws {
        let first = try #require(RuleSuggester.suggestions(for: session(gpPortal)).first)
        #expect(first.label == "The “gp-portal” page of meltx")
        let rule = ProjectRule(projectId: "meltx", featureId: "gp", name: "GP Portal", conditions: first.conditions)

        #expect(RuleEngine.run(RuleBackfill.context(for: session(gpPortal)), rules: [rule]).featureId == "gp")
        #expect(RuleEngine.run(RuleBackfill.context(for: session(setup)), rules: [rule]).projectId == nil,
                "another page of the same app")
        #expect(RuleEngine.run(RuleBackfill.context(for: session(otherApp)), rules: [rule]).projectId == nil,
                "the same page name in a different app whose id merely contains this one")
    }

    @Test("a finished session teaches its page")
    func learned() {
        let keys = Set(FeatureExtractor.features(for: session(gpPortal)).map(\.key))
        #expect(keys.contains("place:bubble::meltx#gp-portal"))
    }
}

@Suite("Leaving a Bubble page")
struct LeavingPageTests {
    static func page(_ name: String) -> ActivitySnapshot {
        ActivitySnapshot(bundleID: "com.google.Chrome", appName: "Google Chrome",
                         windowTitle: "meltx | Bubble Editor",
                         url: "https://bubble.io/page?id=meltx&tab=Design&name=\(name)")
    }

    func deps() -> FakeDependencies {
        var gp = ProjectRule(id: "gp", projectId: "meltx", featureId: "gp-portal", name: "GP Portal",
                             conditions: [RuleCondition(type: .queryParamEquals, value: "meltx", queryParamName: "id"),
                                          RuleCondition(type: .queryParamEquals, value: "gp-portal", queryParamName: "name")])
        gp.priority = 1
        let app = ProjectRule(id: "app", projectId: "meltx", name: "MeltX",
                              conditions: [RuleCondition(type: .queryParamEquals, value: "meltx", queryParamName: "id")])
        return FakeDependencies(rules: [gp, app], projects: [
            Project(id: "meltx", name: "MeltX"), Project(id: "gp-portal", name: "GP Portal", parentId: "meltx"),
        ])
    }

    @Test("moving from the GP Portal page to another page stops counting GP Portal")
    func leavesFeatureBehind() async {
        let deps = deps()
        let coordinator = ActivityCoordinator(dependencies: deps)
        await coordinator.observe(Self.page("gp-portal"), now: Date(timeIntervalSince1970: 0))
        await coordinator.observe(Self.page("admin"), now: Date(timeIntervalSince1970: 60))
        await coordinator.endSession(at: Date(timeIntervalSince1970: 100))

        let sessions = await deps.persisted
        #expect(sessions.map(\.featureId) == ["gp-portal", nil])
        #expect(sessions.map(\.projectId) == ["meltx", "meltx"])
        #expect(sessions.map(\.durationSeconds) == [60, 40])
    }

    @Test("a feature picked in the popover still spans every page")
    func chosenFeatureSpansPages() async {
        let deps = deps()
        await deps.choose(feature: (id: "gp-portal", projectId: "meltx", name: "GP Portal"))
        let coordinator = ActivityCoordinator(dependencies: deps)
        await coordinator.observe(Self.page("gp-portal"), now: Date(timeIntervalSince1970: 0))
        await coordinator.observe(Self.page("admin"), now: Date(timeIntervalSince1970: 60))
        await coordinator.endSession(at: Date(timeIntervalSince1970: 100))
        #expect(await deps.persisted.map(\.featureId) == ["gp-portal"])
    }

    @Test("pages of an app with no features at all stay one session")
    func noFeaturesNoSplits() async {
        let deps = FakeDependencies(rules: [
            ProjectRule(id: "app", projectId: "meltx", name: "MeltX",
                        conditions: [RuleCondition(type: .queryParamEquals, value: "meltx", queryParamName: "id")]),
        ])
        let coordinator = ActivityCoordinator(dependencies: deps)
        for (i, name) in ["setup", "admin", "gp-portal"].enumerated() {
            await coordinator.observe(Self.page(name), now: Date(timeIntervalSince1970: Double(i * 30)))
        }
        await coordinator.endSession(at: Date(timeIntervalSince1970: 90))
        #expect(await deps.persisted.count == 1)
    }

    @Test("a Framer selection is not a page, so clicking away keeps the feature")
    func framerSelectionIsNotAPage() throws {
        #expect(try #require(ParserRegistry.parse("https://framer.com/projects/A--FC91PjIN9PCSOTMJzDXU?node=X")).subEntityIsPage == false)
        #expect(try #require(ParserRegistry.parse("https://acme.framer.app/pricing")).subEntityIsPage == true)
        #expect(try #require(ParserRegistry.parse("https://bubble.io/page?id=meltx&name=admin")).subEntityIsPage == true)
    }
}
