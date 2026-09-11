import Testing
import Foundation
@testable import TimeTrackerCore

@Suite("Regex rules cannot stall the tracker")
struct SafeRegexTests {
    @Test("an ordinary pattern still matches")
    func ordinary() {
        #expect(SafeRegex.matches(#"acme\.com/(billing|invoices)"#, in: "https://app.acme.com/billing/42"))
        #expect(!SafeRegex.matches(#"acme\.com/billing"#, in: "https://beta.com/billing"))
    }

    @Test("a catastrophically backtracking pattern gives up quickly instead of hanging")
    func runaway() {
        let evil = "^(a+)+$"
        let input = String(repeating: "a", count: 40) + "!"   // ~2^40 steps unguarded
        let started = Date()
        let matched = SafeRegex.matches(evil, in: input)
        #expect(!matched)
        #expect(Date().timeIntervalSince(started) < 2, "stopped by the time budget")
    }

    @Test("invalid and over-long patterns never match, and say why")
    func unusable() {
        #expect(!SafeRegex.matches("(unclosed", in: "anything"))
        #expect(SafeRegex.problem(with: "(unclosed") != nil)
        let long = String(repeating: "a", count: SafeRegex.maxPatternLength + 1)
        #expect(SafeRegex.problem(with: long) != nil)
        #expect(!SafeRegex.matches(long, in: long))
        #expect(SafeRegex.problem(with: #"^https://acme\.com"#) == nil)
    }

    @Test("a rule through the engine behaves the same")
    func throughEngine() {
        let rule = ProjectRule(projectId: "p", name: "R",
                               conditions: [RuleCondition(type: .regex, value: "^(a+)+$")])
        let context = RuleMatchContext(appBundleID: "x", url: "https://" + String(repeating: "a", count: 40) + "!")
        let started = Date()
        #expect(RuleEngine.run(context, rules: [rule]).projectId == nil)
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test("a backup's unusable regex rule is imported switched off, not dropped")
    func importDisables() {
        let bad = ProjectRule(id: "r1", projectId: "p", name: "Invoices",
                              conditions: [RuleCondition(type: .regex, value: "(unclosed")])
        let fine = ProjectRule(id: "r2", projectId: "p", name: "Billing",
                               conditions: [RuleCondition(type: .regex, value: "billing")])
        let disabled = bad.disablingUnusableRegex()
        #expect(disabled.enabled == false)
        #expect(disabled.name.hasPrefix("Invoices"))
        #expect(disabled.name.contains("switched off"))
        #expect(fine.disablingUnusableRegex() == fine)
        #expect(disabled.disablingUnusableRegex().name == disabled.name, "not labelled twice")
    }
}
