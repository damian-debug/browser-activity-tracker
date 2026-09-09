import Testing
import Foundation
@testable import TimeTrackerCore

private let base = Date(unixMillis: 1_700_000_000_000)

private func session(
    app: String = "com.google.Chrome",
    appName: String = "Google Chrome",
    url: String? = nil,
    domain: String? = nil,
    service: String? = nil,
    entityId: String? = nil,
    entityName: String? = nil,
    documentPath: String? = nil,
    title: String? = "Some window",
    projectId: String? = nil,
    reviewed: Bool = false
) -> Session {
    Session(
        appBundleID: app, appName: appName, windowTitle: title, documentPath: documentPath,
        url: url, domain: domain, title: title ?? "",
        service: service, detectedEntityId: entityId, detectedEntityName: entityName,
        projectId: projectId, reviewed: reviewed,
        startTime: base, endTime: base.addingTimeInterval(600), durationSeconds: 600
    )
}

@Suite("Suggesting a rule from real work")
struct RuleSuggestionTests {
    @Test("the most specific option comes first, the broadest last")
    func orderedBySafety() {
        // Ordering is a safety property: pinning one file cannot swallow
        // unrelated work, whereas claiming a whole app certainly can.
        let suggestions = RuleSuggester.suggestions(for: session(
            url: "https://www.figma.com/design/abc123/KPI-Screens",
            domain: "figma.com", service: "figma",
            entityId: "abc123", entityName: "KPI Screens"
        ))
        #expect(suggestions.first?.type == .urlContains)
        #expect(suggestions.first?.value == "figma.com/design/abc123")
        #expect(suggestions.last?.type == .titleContains)
        #expect(suggestions.contains { $0.type == .appBundleEquals })
    }

    @Test("a Bubble app is offered as its query parameter")
    func bubbleEntity() {
        let suggestions = RuleSuggester.suggestions(for: session(
            url: "https://bubble.io/page?id=sampleapp&tab=Design",
            domain: "bubble.io", service: "bubble", entityId: "sampleapp"
        ))
        let first = try! #require(suggestions.first)
        #expect(first.type == .queryParamEquals)
        #expect(first.value == "sampleapp")
        #expect(first.queryParamName == "id")
    }

    @Test("a document's folder is offered, since that is usually the project")
    func documentFolder() {
        let suggestions = RuleSuggester.suggestions(for: session(
            app: "com.figma.Desktop", appName: "Figma",
            documentPath: "/Users/d/Projects/acme/kpi.fig"
        ))
        let folder = try! #require(suggestions.first { $0.type == .documentPathContains })
        #expect(folder.value == "/Users/d/Projects/acme/")
        #expect(folder.label.contains("acme"))
    }

    @Test("a native app with no document still offers something usable")
    func bareNativeApp() {
        let suggestions = RuleSuggester.suggestions(for: session(
            app: "com.apple.Terminal", appName: "Terminal", title: "zsh"
        ))
        #expect(!suggestions.isEmpty)
        #expect(suggestions.contains { $0.type == .appBundleEquals })
    }

    @Test("each suggestion says what confidence it would carry")
    func suggestionsCarryConfidence() {
        let suggestions = RuleSuggester.suggestions(for: session(
            url: "https://app.example.com/project/acme", domain: "app.example.com"
        ))
        let domainRule = try! #require(suggestions.first { $0.type == .domainEquals })
        #expect(domainRule.confidence == Confidence.domain)
    }

    @Test("a chosen suggestion becomes a working rule")
    func buildsARule() {
        let suggestion = RuleSuggestion(
            label: "Everything on figma.com", type: .domainEquals, value: "figma.com"
        )
        let rule = RuleSuggester.rule(
            from: suggestion, projectId: "p1", projectName: "Acme Corp", now: base
        )
        #expect(rule.projectId == "p1")
        #expect(rule.name.contains("Acme Corp"))
        #expect(rule.enabled)

        // And it actually matches the work it came from.
        let context = RuleMatchContext(
            appBundleID: "com.google.Chrome", url: "https://figma.com/x", domain: "figma.com"
        )
        #expect(RuleEngine.run(context, rules: [rule]).projectId == "p1")
    }
}

@Suite("Applying a new rule to past work")
struct RuleBackfillTests {
    let rule = ProjectRule(
        id: "r1", projectId: "p1", name: "Acme: figma",
        type: .domainEquals, value: "figma.com",
        defaultTagIds: ["t1"], defaultBillable: true
    )

    @Test("matching unassigned sessions are claimed")
    func claimsMatching() {
        let sessions = [
            session(url: "https://figma.com/a", domain: "figma.com"),
            session(url: "https://figma.com/b", domain: "figma.com"),
            session(url: "https://example.com/", domain: "example.com"),
        ]
        let matched = RuleBackfill.sessionsToUpdate(matching: rule, in: sessions)
        #expect(matched.count == 2)
    }

    @Test("work you already decided on is never overwritten")
    func respectsExistingDecisions() {
        // A rule written today must not reach back and relabel a judgement the
        // user already made.
        let sessions = [
            session(url: "https://figma.com/a", domain: "figma.com", projectId: "other"),
            session(url: "https://figma.com/b", domain: "figma.com", reviewed: true),
        ]
        #expect(RuleBackfill.sessionsToUpdate(matching: rule, in: sessions).isEmpty)
    }

    @Test("applying the rule fills in project, tags, billable and marks it settled")
    func applyingTheRule() {
        let target = session(url: "https://figma.com/a", domain: "figma.com")
        let updated = RuleBackfill.applied(rule, to: target, projectName: "Acme Corp", now: base)

        #expect(updated.projectId == "p1")
        #expect(updated.projectName == "Acme Corp")
        #expect(updated.assignmentSource == .autoRule)
        #expect(updated.assignmentConfidence == Confidence.domain)
        #expect(updated.matchedRuleId == "r1")
        #expect(updated.tagIds == ["t1"])
        #expect(updated.billable)
        #expect(updated.reviewed, "writing the rule from this work is itself the review")
    }

    @Test("native sessions are matched on their own signals, not just URLs")
    func nativeBackfill() {
        let documentRule = ProjectRule(
            id: "r2", projectId: "p1", name: "Acme: folder",
            type: .documentPathContains, value: "/Projects/acme/"
        )
        let sessions = [
            session(app: "com.figma.Desktop", documentPath: "/Users/d/Projects/acme/kpi.fig"),
            session(app: "com.figma.Desktop", documentPath: "/Users/d/Projects/other/x.fig"),
        ]
        #expect(RuleBackfill.sessionsToUpdate(matching: documentRule, in: sessions).count == 1)
    }
}

@Suite("Compound rules")
struct CompoundRuleTests {
    func slack(title: String) -> Session {
        Session(
            appBundleID: "com.tinyspeck.slackmacgap", appName: "Slack",
            windowTitle: title, title: title,
            startTime: base, endTime: base.addingTimeInterval(600), durationSeconds: 600
        )
    }

    @Test("every condition must hold for the rule to fire")
    func allConditionsRequired() {
        let rule = ProjectRule(
            projectId: "acme", name: "Acme in Slack",
            conditions: [
                RuleCondition(type: .appBundleEquals, value: "com.tinyspeck.slackmacgap"),
                RuleCondition(type: .titleContains, value: "acme"),
            ]
        )

        let acmeChannel = RuleBackfill.context(for: slack(title: "Slack | #acme-internal"))
        #expect(RuleEngine.run(acmeChannel, rules: [rule]).projectId == "acme")

        // Right app, wrong channel: this is the whole point — Slack alone must
        // not claim every project's conversations.
        let otherChannel = RuleBackfill.context(for: slack(title: "Slack | #general"))
        #expect(RuleEngine.run(otherChannel, rules: [rule]).projectId == nil)

        // Right words, wrong app.
        var elsewhere = RuleBackfill.context(for: slack(title: "acme notes"))
        elsewhere.appBundleID = "com.apple.Notes"
        #expect(RuleEngine.run(elsewhere, rules: [rule]).projectId == nil)
    }

    @Test("combining conditions raises confidence above either alone")
    func confidenceCombines() {
        let appOnly = ProjectRule(
            projectId: "p", name: "app", type: .appBundleEquals, value: "com.tinyspeck.slackmacgap"
        )
        let titleOnly = ProjectRule(
            projectId: "p", name: "title", type: .titleContains, value: "acme"
        )
        let both = ProjectRule(
            projectId: "p", name: "both",
            conditions: appOnly.conditions + titleOnly.conditions
        )

        #expect(both.confidence > appOnly.confidence)
        #expect(both.confidence > titleOnly.confidence)
        // Never as certain as a person saying so.
        #expect(both.confidence < Confidence.manual)
    }

    @Test("a single-condition rule scores exactly as it always did")
    func singleConditionUnchanged() {
        for type in ProjectRuleType.allCases {
            let rule = ProjectRule(projectId: "p", name: "r", type: type, value: "x")
            #expect(rule.confidence == type.confidence)
        }
    }

    @Test("a rule with no conditions matches nothing")
    func emptyRuleMatchesNothing() {
        // Otherwise stripping a rule's conditions would silently make it claim
        // every activity there is.
        let rule = ProjectRule(projectId: "p", name: "empty", conditions: [])
        #expect(RuleEngine.run(RuleBackfill.context(for: slack(title: "anything")), rules: [rule]).projectId == nil)
    }

    @Test("the more demanding rule wins an otherwise even tie")
    func compoundBeatsSimpleOnTies() {
        let broad = ProjectRule(
            id: "a", projectId: "broad", name: "Slack",
            type: .appBundleEquals, value: "com.tinyspeck.slackmacgap"
        )
        let precise = ProjectRule(
            id: "b", projectId: "precise", name: "Slack + acme",
            conditions: [
                RuleCondition(type: .appBundleEquals, value: "com.tinyspeck.slackmacgap"),
                RuleCondition(type: .titleContains, value: "acme"),
            ]
        )
        let context = RuleBackfill.context(for: slack(title: "Slack | #acme-internal"))
        #expect(RuleEngine.run(context, rules: [broad, precise]).projectId == "precise")
    }

    @Test("a shared app is offered as app-plus-title before whole-app")
    func suggestsCompoundForSharedApps() {
        let suggestions = RuleSuggester.suggestions(for: slack(title: "Slack | #acme-internal | Acme Corp"))

        let compound = try! #require(suggestions.first { $0.isCompound })
        #expect(compound.conditions.contains { $0.type == .appBundleEquals })
        #expect(compound.conditions.contains { $0.type == .titleContains })

        // And it comes before claiming the whole app, which would swallow every
        // other project's conversations.
        let compoundIndex = try! #require(suggestions.firstIndex { $0.isCompound })
        let wholeApp = try! #require(
            suggestions.firstIndex { !$0.isCompound && $0.type == .appBundleEquals }
        )
        #expect(compoundIndex < wholeApp)
    }

    @Test("the distinctive word skips the app's own name and generic chrome")
    func picksDistinctiveWord() {
        #expect(RuleSuggester.distinctiveTitleWord("Slack | #acme-internal", appName: "Slack") == "acme-internal")
        #expect(RuleSuggester.distinctiveTitleWord("Slack", appName: "Slack") == nil)
        #expect(RuleSuggester.distinctiveTitleWord("New Tab", appName: "Safari") == nil)
    }

    @Test("compound rules survive a backup round trip")
    func backupRoundTrip() throws {
        let rule = ProjectRule(
            id: "r1", projectId: "acme", name: "Acme in Slack",
            conditions: [
                RuleCondition(type: .appBundleEquals, value: "com.tinyspeck.slackmacgap"),
                RuleCondition(type: .titleContains, value: "acme"),
            ]
        )
        let data = try Backup.encode(Backup.Contents(rules: [rule]))
        guard case .success(let restored) = Backup.decode(data) else {
            Issue.record("expected the backup to decode"); return
        }
        #expect(restored.rules.first?.conditions.count == 2)
        #expect(restored.rules.first?.confidence == rule.confidence)
    }

    @Test("an older backup's flat rule still imports as one condition")
    func olderBackupsStillImport() {
        let older = #"""
        {"format":"bat-backup","schemaVersion":3,"exportedAt":0,"settings":{},
         "projects":[],"tags":[],
         "rules":[{"id":"r1","projectId":"p1","name":"old","type":"domain_equals","value":"figma.com"}],
         "sessions":[]}
        """#
        guard case .success(let contents) = Backup.decode(older.data(using: .utf8)!) else {
            Issue.record("expected the older file to import"); return
        }
        let rule = try! #require(contents.rules.first)
        #expect(rule.conditions.count == 1)
        #expect(rule.type == .domainEquals)
        #expect(rule.value == "figma.com")
    }
}
