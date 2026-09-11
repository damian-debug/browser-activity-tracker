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
