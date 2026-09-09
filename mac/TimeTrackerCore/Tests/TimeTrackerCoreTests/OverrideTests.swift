import Testing
import Foundation
@testable import TimeTrackerCore

// Ported from the "active project override" suite in rule-engine.test.ts,
// with the scopes re-mapped to native concepts.

@Suite("Active project override")
struct OverrideTests {
    func override(
        scope: OverrideScope = .global,
        expiry: OverrideExpiry = .manual,
        target: ActivityIdentity? = nil,
        bundleID: String? = nil,
        domain: String? = nil,
        expiresAt: Date? = nil
    ) -> ActiveProjectOverride {
        ActiveProjectOverride(
            projectId: "override-project",
            scope: scope,
            expiry: expiry,
            target: target,
            bundleID: bundleID,
            domain: domain,
            startedAt: referenceNow,
            expiresAt: expiresAt
        )
    }

    @Test("a global override beats any rule, however high its priority")
    func globalBeatsRules() {
        let r = makeRule(type: .domainEquals, value: "bubble.io", projectId: "rule-project", priority: 99)
        let result = SessionAssigner.assign(
            browserSnapshot(), rules: [r], override: override(), now: referenceNow
        )
        #expect(result.projectId == "override-project")
        #expect(result.assignmentSource == .activeProjectOverride)
        #expect(result.assignmentConfidence == 100)
    }

    @Test("a domain-scoped override applies only on its domain")
    func domainScoped() {
        let o = override(scope: .currentApp, domain: "bubble.io")
        #expect(SessionAssigner.assign(browserSnapshot(), rules: [], override: o, now: referenceNow).projectId == "override-project")

        let elsewhere = browserSnapshot(url: "https://github.com/acme/repo")
        #expect(SessionAssigner.assign(elsewhere, rules: [], override: o, now: referenceNow).projectId == nil)
    }

    @Test("an app-scoped override applies only to its app")
    func appScoped() {
        let o = override(scope: .currentApp, bundleID: "com.microsoft.VSCode")
        #expect(SessionAssigner.assign(nativeSnapshot(), rules: [], override: o, now: referenceNow).projectId == "override-project")

        let otherApp = nativeSnapshot(bundleID: "com.apple.Terminal")
        #expect(SessionAssigner.assign(otherApp, rules: [], override: o, now: referenceNow).projectId == nil)
    }

    @Test("a target-scoped override applies only to that window or document")
    func targetScoped() {
        let editing = nativeSnapshot(documentPath: "/Users/d/acme/main.swift")
        let o = override(scope: .currentTarget, target: editing.identity)

        #expect(SessionAssigner.assign(editing, rules: [], override: o, now: referenceNow).projectId == "override-project")

        let otherDoc = nativeSnapshot(documentPath: "/Users/d/other/main.swift")
        #expect(SessionAssigner.assign(otherDoc, rules: [], override: o, now: referenceNow).projectId == nil)
    }

    @Test("an expired override is ignored, and the rules take over again")
    func lazyExpiry() {
        let o = override(expiresAt: referenceNow.addingTimeInterval(-1))
        #expect(!SessionAssigner.isOverrideActive(o, for: browserSnapshot(), now: referenceNow))

        let result = SessionAssigner.assign(browserSnapshot(), rules: [], override: o, now: referenceNow)
        #expect(result.assignmentSource == .unassigned)
    }

    @Test("an override still inside its window is honoured")
    func notYetExpired() {
        let o = override(expiresAt: referenceNow.addingTimeInterval(60))
        #expect(SessionAssigner.isOverrideActive(o, for: browserSnapshot(), now: referenceNow))
    }

    @Test("expiry: manual never expires, thirty minutes is +30m, end of day is local midnight")
    func expiryCalculation() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Colombo")!

        #expect(OverrideExpiryCalculator.expiresAt(.manual, from: referenceNow, calendar: calendar) == nil)

        let thirty = OverrideExpiryCalculator.expiresAt(.thirtyMinutes, from: referenceNow, calendar: calendar)
        #expect(thirty == referenceNow.addingTimeInterval(30 * 60))

        let eod = try! #require(OverrideExpiryCalculator.expiresAt(.endOfDay, from: referenceNow, calendar: calendar))
        #expect(eod > referenceNow)
        let parts = calendar.dateComponents([.hour, .minute], from: eod)
        #expect(parts.hour == 23)
        #expect(parts.minute == 59)
    }
}
