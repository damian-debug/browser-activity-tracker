import Testing
import Foundation
@testable import TimeTrackerCore

// Ported from extension/tests/rule-engine.test.ts — the deterministic engine's
// behaviour is the contract, so these assertions are kept as close to the
// originals as the language allows.

@Suite("Rule matchers")
struct RuleMatcherTests {
    @Test("domain_equals matches case-insensitively and ignores www")
    func domainEquals() {
        let r = makeRule(type: .domainEquals, value: "Bubble.io", projectId: "p1")
        #expect(RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [r]).projectId == "p1")

        let other = browserSnapshot(url: "https://github.com/acme/repo")
        #expect(RuleEngine.run(RuleMatchContext(other), rules: [r]).projectId == nil)
    }

    @Test("www. on the rule value is stripped before comparing")
    func domainEqualsStripsWWW() {
        let r = makeRule(type: .domainEquals, value: "www.bubble.io", projectId: "p1")
        #expect(RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [r]).projectId == "p1")
    }

    @Test("url_contains matches substrings and scores as a strong URL rule")
    func urlContains() {
        let r = makeRule(type: .urlContains, value: "bubble.io/page?id=sampleapp", projectId: "p1")
        let result = RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [r])
        #expect(result.projectId == "p1")
        #expect(result.assignmentConfidence == Confidence.urlContains)
    }

    @Test("url_starts_with matches prefixes only")
    func urlStartsWith() {
        let r = makeRule(type: .urlStartsWith, value: "https://bubble.io/page", projectId: "p1")
        #expect(RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [r]).projectId == "p1")

        // The value appearing later in the URL must not match a prefix rule.
        let redirect = browserSnapshot(url: "https://other.com/?next=https://bubble.io/page")
        #expect(RuleEngine.run(RuleMatchContext(redirect), rules: [r]).projectId == nil)
    }

    @Test("path_contains matches against the path only, never the query string")
    func pathContains() {
        let r = makeRule(type: .pathContains, value: "/project/acme", projectId: "p1")

        let inPath = browserSnapshot(url: "https://app.example.com/project/acme/board")
        #expect(RuleEngine.run(RuleMatchContext(inPath), rules: [r]).projectId == "p1")

        let inQuery = browserSnapshot(url: "https://app.example.com/?path=/project/acme")
        #expect(RuleEngine.run(RuleMatchContext(inQuery), rules: [r]).projectId == nil)
    }

    @Test("query_param_equals matches the exact parameter value")
    func queryParamEquals() {
        let r = makeRule(
            type: .queryParamEquals, value: "sampleapp",
            projectId: "p1", queryParamName: "id"
        )
        let result = RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [r])
        #expect(result.projectId == "p1")
        #expect(result.assignmentConfidence == Confidence.queryParam)

        let other = browserSnapshot(url: "https://bubble.io/page?id=other")
        #expect(RuleEngine.run(RuleMatchContext(other), rules: [r]).projectId == nil)
    }

    @Test("title_contains matches case-insensitively")
    func titleContains() {
        let r = makeRule(type: .titleContains, value: "SAMPLEAPP", projectId: "p1")
        #expect(RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [r]).projectId == "p1")
    }

    @Test("regex matches against the URL and tolerates invalid patterns")
    func regexMatching() {
        let good = makeRule(
            type: .regex, value: #"bubble\.io\/page\?id=sampleapp"#, projectId: "p1"
        )
        #expect(RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [good]).projectId == "p1")

        // An invalid user-supplied pattern must never match, and must not throw.
        let invalid = makeRule(type: .regex, value: "([unclosed", projectId: "p2")
        #expect(RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [invalid]).projectId == nil)
    }

    @Test("browser-only matchers fail closed for native app activity")
    func browserMatchersIgnoreNativeActivity() {
        let native = nativeSnapshot(title: "main.swift — acme")
        for type in [ProjectRuleType.domainEquals, .urlContains, .urlStartsWith, .pathContains, .regex] {
            let r = makeRule(type: type, value: "acme", projectId: "p1")
            #expect(
                RuleEngine.run(RuleMatchContext(native), rules: [r]).projectId == nil,
                "\(type.rawValue) should not match activity with no URL"
            )
        }
    }

    @Test("app_bundle_equals matches the frontmost app, case-insensitively")
    func appBundleEquals() {
        let r = makeRule(type: .appBundleEquals, value: "com.microsoft.vscode", projectId: "p1")
        let result = RuleEngine.run(RuleMatchContext(nativeSnapshot()), rules: [r])
        #expect(result.projectId == "p1")
        #expect(result.assignmentConfidence == Confidence.appBundle)

        let other = nativeSnapshot(bundleID: "com.apple.Terminal")
        #expect(RuleEngine.run(RuleMatchContext(other), rules: [r]).projectId == nil)
    }

    @Test("document_path_contains matches a project folder")
    func documentPathContains() {
        let r = makeRule(type: .documentPathContains, value: "/Projects/acme/", projectId: "p1")
        let inProject = nativeSnapshot(documentPath: "/Users/d/Projects/acme/src/main.swift")
        let result = RuleEngine.run(RuleMatchContext(inProject), rules: [r])
        #expect(result.projectId == "p1")
        #expect(result.assignmentConfidence == Confidence.documentPath)

        let elsewhere = nativeSnapshot(documentPath: "/Users/d/Projects/other/main.swift")
        #expect(RuleEngine.run(RuleMatchContext(elsewhere), rules: [r]).projectId == nil)
    }

    @Test("an empty rule value never matches")
    func emptyValueNeverMatches() {
        let r = makeRule(type: .urlContains, value: "", projectId: "p1")
        #expect(RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [r]).projectId == nil)
    }
}

@Suite("Rule selection")
struct RuleSelectionTests {
    @Test("ignores disabled rules")
    func ignoresDisabled() {
        let r = makeRule(type: .domainEquals, value: "bubble.io", projectId: "p1", enabled: false)
        let result = RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [r])
        #expect(result.projectId == nil)
        #expect(result.assignmentSource == .unassigned)
    }

    @Test("higher priority wins regardless of specificity")
    func priorityBeatsSpecificity() {
        let broad = makeRule(type: .domainEquals, value: "bubble.io", projectId: "broad", priority: 10)
        let narrow = makeRule(
            type: .queryParamEquals, value: "sampleapp",
            projectId: "narrow", queryParamName: "id", priority: 1
        )
        #expect(RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [broad, narrow]).projectId == "broad")
    }

    @Test("equal priority: the more specific rule type wins")
    func specificityBreaksPriorityTies() {
        let broad = makeRule(type: .domainEquals, value: "bubble.io", projectId: "broad")
        let narrow = makeRule(
            type: .queryParamEquals, value: "sampleapp",
            projectId: "narrow", queryParamName: "id"
        )
        let result = RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [broad, narrow])
        #expect(result.projectId == "narrow")
        #expect(result.matchedRuleId == narrow.id)
    }

    @Test("remaining ties break by id, so selection is stable")
    func idBreaksRemainingTies() {
        let a = makeRule(type: .domainEquals, value: "bubble.io", projectId: "a", id: "aaa")
        let b = makeRule(type: .domainEquals, value: "bubble.io", projectId: "b", id: "bbb")
        #expect(RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [b, a]).projectId == "a")
        #expect(RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [a, b]).projectId == "a")
    }

    @Test("returns rule defaults (tags, billable)")
    func returnsRuleDefaults() {
        let r = makeRule(
            type: .domainEquals, value: "bubble.io", projectId: "p1",
            defaultTagIds: ["t1", "t2"], defaultBillable: true
        )
        let result = RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [r])
        #expect(result.defaultTagIds == ["t1", "t2"])
        #expect(result.billable == true)
    }

    @Test("returns unassigned when nothing matches")
    func unassignedFallback() {
        let result = RuleEngine.run(RuleMatchContext(browserSnapshot()), rules: [])
        #expect(result.projectId == nil)
        #expect(result.assignmentSource == .unassigned)
        #expect(result.assignmentConfidence == 0)
    }
}
