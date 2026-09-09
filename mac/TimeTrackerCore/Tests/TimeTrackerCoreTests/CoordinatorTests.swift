import Testing
import Foundation
@testable import TimeTrackerCore

// The coordinator is the native counterpart of the extension's tracker.ts, so
// these cover the same hard-won behaviours: continuity across noisy events,
// pause reasons surviving a session change, wake-gap handling, and timed
// override expiry.

actor FakeDependencies: TrackingDependencies {
    var rules: [ProjectRule] = []
    var projects: [String: Project] = [:]
    var override: ActiveProjectOverride?
    var associations: [FeatureAssociation] = []
    var eligible: Set<String> = ["acme", "internal", "rule-project", "override-project", "p1"]
    private(set) var persisted: [Session] = []
    private(set) var clearOverrideCalls = 0
    private(set) var recorded: [FeatureObservation] = []

    init(rules: [ProjectRule] = [], projects: [Project] = [], override: ActiveProjectOverride? = nil) {
        self.rules = rules
        self.projects = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        self.override = override
    }

    func enabledRules() async -> [ProjectRule] { rules.filter(\.enabled) }
    func project(_ id: String) async -> Project? { projects[id] }
    func currentOverride() async -> ActiveProjectOverride? { override }
    func clearOverride() async {
        override = nil
        clearOverrideCalls += 1
    }
    func persist(_ session: Session) async { persisted.append(session) }

    func associations(forFeatureKeys keys: [String]) async -> [FeatureAssociation] {
        let wanted = Set(keys)
        return associations.filter { wanted.contains($0.feature) }
    }
    func eligibleProjectIds() async -> Set<String> { eligible }
    func record(_ observations: [FeatureObservation]) async { recorded.append(contentsOf: observations) }

    func setOverride(_ value: ActiveProjectOverride?) { override = value }
    func setAssociations(_ value: [FeatureAssociation]) { associations = value }
}

private let base = Date(unixMillis: 1_700_000_000_000)
private func at(_ seconds: Int) -> Date { base.addingTimeInterval(Double(seconds)) }

@Suite("Session lifecycle")
struct CoordinatorLifecycleTests {
    @Test("observing activity starts a session")
    func startsSession() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)

        let status = await coordinator.status(now: at(30))
        #expect(status.isTracking)
        #expect(status.elapsedSeconds == 30)
    }

    @Test("staying on the same target continues one session rather than fragmenting")
    func continuesSameTarget() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(url: "https://bubble.io/page?id=sampleapp&tab=Design"), now: base)
        // Bubble rewrites the URL as you click around; still the same app.
        await coordinator.observe(browserSnapshot(url: "https://bubble.io/page?id=sampleapp&tab=Workflow"), now: at(30))
        await coordinator.observe(browserSnapshot(url: "https://bubble.io/page?id=sampleapp&tab=Settings"), now: at(60))

        #expect(await deps.persisted.isEmpty, "no session should have been closed")
        #expect(await coordinator.status(now: at(90)).elapsedSeconds == 90)
    }

    @Test("switching target closes the old session and opens a new one")
    func switchesTarget() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.observe(nativeSnapshot(title: "main.swift"), now: at(60))

        let persisted = await deps.persisted
        #expect(persisted.count == 1)
        #expect(persisted[0].durationSeconds == 60)
        #expect(persisted[0].domain == "bubble.io")

        let status = await coordinator.status(now: at(60))
        #expect(status.appName == "Code")
    }

    @Test("repeated identical observations do not restart the session")
    func idempotentObservation() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        // macOS fires several events for one user action; all of them arrive here.
        for offset in [0, 0, 1, 1, 2] {
            await coordinator.observe(browserSnapshot(), now: at(offset))
        }
        #expect(await deps.persisted.isEmpty)
    }

    @Test("a session below the minimum is discarded, not saved")
    func discardsFlickers() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.observe(nativeSnapshot(), now: at(1))   // passed through

        #expect(await deps.persisted.isEmpty)
    }

    @Test("excluded activity ends tracking rather than recording it")
    func honoursExclusions() async {
        let settings = AppSettings(excludedAppBundleIDs: ["com.apple.Terminal"])
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps, settings: settings)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.observe(nativeSnapshot(bundleID: "com.apple.Terminal"), now: at(60))

        #expect(await deps.persisted.count == 1)
        #expect(await coordinator.status(now: at(90)).isTracking == false)
    }

    @Test("details arriving late are merged in rather than overwriting with nil")
    func enrichesSnapshot() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        // Permission granted mid-session: first sample has no title, next does.
        let bare = ActivitySnapshot(bundleID: "com.figma.Desktop", appName: "Figma")
        await coordinator.observe(bare, now: base)

        var titled = bare
        titled.windowTitle = "KPI Screens"
        await coordinator.observe(titled, now: at(10))

        // A later sample that lost the title must not erase it.
        await coordinator.observe(bare, now: at(20))
        await coordinator.endSession(at: at(30))

        let saved = try! #require(await deps.persisted.first)
        #expect(saved.windowTitle == "KPI Screens")
        #expect(saved.durationSeconds == 30, "enrichment must not restart the clock")
    }
}

@Suite("Attribution on session start")
struct CoordinatorAttributionTests {
    @Test("a matching rule assigns the project and its confidence")
    func appliesRules() async {
        let rule = makeRule(type: .domainEquals, value: "bubble.io", projectId: "p1")
        let deps = FakeDependencies(rules: [rule], projects: [Project(id: "p1", name: "Acme Corp")])
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)

        let status = await coordinator.status(now: base)
        #expect(status.projectId == "p1")
        #expect(status.projectName == "Acme Corp")
        #expect(status.assignmentSource == .autoRule)
        #expect(status.assignmentConfidence == Confidence.domain)
    }

    @Test("a disabled rule is ignored")
    func ignoresDisabledRules() async {
        let rule = makeRule(type: .domainEquals, value: "bubble.io", projectId: "p1", enabled: false)
        let deps = FakeDependencies(rules: [rule])
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        #expect(await coordinator.status(now: base).projectId == nil)
    }

    @Test("billable falls back to the project default when the rule says nothing")
    func billableFallsBackToProject() async {
        let rule = makeRule(type: .domainEquals, value: "bubble.io", projectId: "p1")
        let project = Project(id: "p1", name: "Acme Corp", defaultBillable: true)
        let deps = FakeDependencies(rules: [rule], projects: [project])
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.endSession(at: at(30))

        #expect(await deps.persisted.first?.billable == true)
    }

    @Test("an explicit rule value beats the project default")
    func ruleBillableWins() async {
        let rule = makeRule(
            type: .domainEquals, value: "bubble.io", projectId: "p1", defaultBillable: false
        )
        let project = Project(id: "p1", name: "Acme Corp", defaultBillable: true)
        let deps = FakeDependencies(rules: [rule], projects: [project])
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.endSession(at: at(30))

        #expect(await deps.persisted.first?.billable == false)
    }

    @Test("an active override beats the rules")
    func overrideBeatsRules() async {
        let rule = makeRule(type: .domainEquals, value: "bubble.io", projectId: "rule-project")
        let override = ActiveProjectOverride(
            projectId: "override-project", scope: .global, expiry: .manual, startedAt: base
        )
        let deps = FakeDependencies(rules: [rule], override: override)
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)

        let status = await coordinator.status(now: base)
        #expect(status.projectId == "override-project")
        #expect(status.assignmentSource == .activeProjectOverride)
    }
}

@Suite("Pause, resume and reconciliation")
struct CoordinatorPauseTests {
    @Test("idle time is not counted")
    func idleNotCounted() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.pause(.idle, at: at(30))
        await coordinator.resume(.idle, at: at(130))
        await coordinator.endSession(at: at(150))

        #expect(await deps.persisted.first?.durationSeconds == 50)
    }

    @Test("a pause survives a session change: switching apps while idle stays paused")
    func pausePersistsAcrossSessions() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.pause(.idle, at: at(10))

        // The frontmost app can still change while the user is away.
        await coordinator.observe(nativeSnapshot(), now: at(20))

        let status = await coordinator.status(now: at(120))
        #expect(status.isPaused, "a new session must inherit the tracker's pause state")
        #expect(status.elapsedSeconds == 0, "no time may accrue while idle")
    }

    @Test("a short gap between heartbeats is credited as work")
    func creditsShortGap() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.heartbeat(now: at(30))
        await coordinator.heartbeat(now: at(60))
        await coordinator.endSession(at: at(60))

        #expect(await deps.persisted.first?.durationSeconds == 60)
    }

    @Test("a long gap is treated as a sleeping machine and closed at the last checkpoint")
    func discardsSleepGap() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.heartbeat(now: at(40))

        // Lid closed; nothing fires for an hour.
        await coordinator.heartbeat(now: at(3640))

        let persisted = await deps.persisted
        #expect(persisted.count == 1)
        #expect(persisted[0].durationSeconds == 40, "dead time must not be billed")
        #expect(await coordinator.status(now: at(3640)).isTracking == false)
    }
}

@Suite("Manual control")
struct CoordinatorManualTests {
    @Test("an expired override is cleared and the activity re-attributed from rules")
    func overrideExpiry() async {
        let rule = makeRule(type: .domainEquals, value: "bubble.io", projectId: "rule-project")
        let override = ActiveProjectOverride(
            projectId: "override-project", scope: .global, expiry: .thirtyMinutes,
            startedAt: base, expiresAt: at(1800)
        )
        let deps = FakeDependencies(rules: [rule], projects: [Project(id: "rule-project", name: "Acme Corp")], override: override)
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        #expect(await coordinator.status(now: base).projectId == "override-project")

        await coordinator.overrideExpired(now: at(1800))

        #expect(await deps.clearOverrideCalls == 1)
        let closed = try! #require(await deps.persisted.first)
        #expect(closed.projectId == "override-project")
        #expect(closed.durationSeconds == 1800, "override time is banked up to the expiry moment")

        // Tracking continues on the same activity, now under the rules.
        let status = await coordinator.status(now: at(1800))
        #expect(status.isTracking)
        #expect(status.projectId == "rule-project")
    }

    @Test("re-assigning the current session does not disturb its clock")
    func reassignKeepsClock() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.reassignCurrentSession(to: Assignment(
            projectId: "p9", projectName: "Chosen",
            assignmentSource: .manualPopup, assignmentConfidence: 100
        ))

        let status = await coordinator.status(now: at(60))
        #expect(status.projectId == "p9")
        #expect(status.elapsedSeconds == 60, "changing the label must not reset the timer")
    }

    @Test("starting a manual timer splits time exactly at the switch moment")
    func manualTimerSplits() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)

        await deps.setOverride(ActiveProjectOverride(
            projectId: "p1", scope: .global, expiry: .manual,
            countsWhileAway: true, startedAt: at(60)
        ))
        await coordinator.restartCurrentSession(ignoringIdle: true, now: at(60))

        let closed = try! #require(await deps.persisted.first)
        #expect(closed.durationSeconds == 60)
        #expect(closed.projectId == nil, "time before the switch keeps its old attribution")

        // The new session runs under the timer and ignores idle.
        await coordinator.pause(.idle, at: at(90))
        let status = await coordinator.status(now: at(120))
        #expect(!status.isPaused)
        #expect(status.projectId == "p1")
    }
}

@Suite("Crash and quit resilience")
struct CoordinatorRestoreTests {
    @Test("a session in progress is saved on a clean quit")
    func shutdownSavesSession() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.shutdown(now: at(300))

        #expect(await deps.persisted.first?.durationSeconds == 300)
    }

    @Test("a session left behind by a crash is picked back up")
    func restoresRecentSession() async {
        let deps = FakeDependencies()
        var orphan = ActiveSession(snapshot: browserSnapshot(), now: base)
        orphan.checkpoint(at: at(120))

        let coordinator = ActivityCoordinator(dependencies: deps)
        // Relaunched a few seconds later.
        await coordinator.restore(orphan, now: at(140))

        #expect(await deps.persisted.isEmpty, "a recent session should resume, not close")
        #expect(await coordinator.status(now: at(140)).elapsedSeconds == 140)
    }

    @Test("a stale session is closed at its last checkpoint, not credited to now")
    func closesStaleSession() async {
        let deps = FakeDependencies()
        var orphan = ActiveSession(snapshot: browserSnapshot(), now: base)
        orphan.checkpoint(at: at(120))

        let coordinator = ActivityCoordinator(dependencies: deps)
        // Relaunched the next morning: the machine was off, not in use.
        await coordinator.restore(orphan, now: at(50_000))

        let saved = try! #require(await deps.persisted.first)
        #expect(saved.durationSeconds == 120, "hours of downtime must not be billed")
        #expect(await coordinator.status(now: at(50_000)).isTracking == false)
    }

    @Test("a restored session keeps its identity, attribution and away mode")
    func restorePreservesState() async {
        let deps = FakeDependencies()
        var orphan = ActiveSession(
            snapshot: browserSnapshot(),
            assignment: Assignment(
                projectId: "p1", projectName: "Acme Corp",
                assignmentSource: .activeProjectOverride, assignmentConfidence: 100
            ),
            ignoresIdle: true,
            now: base
        )
        orphan.checkpoint(at: at(60))

        let coordinator = ActivityCoordinator(dependencies: deps)
        await coordinator.restore(orphan, now: at(80))

        let status = await coordinator.status(now: at(80))
        #expect(status.projectId == "p1")
        #expect(status.projectName == "Acme Corp")

        // Away mode must survive, or a restored meeting timer would stop counting.
        await coordinator.pause(.idle, at: at(90))
        #expect(await coordinator.status(now: at(120)).isPaused == false)
    }

    @Test("a persisted session survives an encode/decode round trip")
    func sessionIsCodable() throws {
        var original = ActiveSession(
            snapshot: nativeSnapshot(title: "main.swift", documentPath: "/p/main.swift"),
            assignment: Assignment(projectId: "p1", assignmentSource: .autoRule, assignmentConfidence: 85),
            ignoresIdle: true,
            now: base
        )
        original.pause(.screenLocked, at: at(30))

        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(ActiveSession.self, from: data)

        #expect(restored.id == original.id)
        #expect(restored.accumulatedSeconds == original.accumulatedSeconds)
        #expect(restored.pauseReasons == original.pauseReasons)
        #expect(restored.ignoresIdle)
        #expect(restored.snapshot.documentPath == "/p/main.swift")
        #expect(restored.duration(at: at(120)) == original.duration(at: at(120)))
    }
}

@Suite("Learned attribution")
struct CoordinatorLearningTests {
    /// Strong, consistent history for the Bubble app in `browserSnapshot()`.
    func establishedHistory(project: String = "acme") -> [FeatureAssociation] {
        [
            FeatureAssociation(feature: "entity:bubble::sampleapp", projectId: project,
                               mass: 25, observations: 25, lastUpdated: base),
            FeatureAssociation(feature: "host:bubble.io", projectId: project,
                               mass: 25, observations: 25, lastUpdated: base),
            FeatureAssociation(feature: "app:\(chromeBundleID)", projectId: project,
                               mass: 25, observations: 25, lastUpdated: base),
        ]
    }

    @Test("with no rule matching, an established pattern is suggested")
    func suggestsFromHistory() async {
        let deps = FakeDependencies(projects: [Project(id: "acme", name: "Acme Corp")])
        await deps.setAssociations(establishedHistory())
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)

        let status = await coordinator.status(now: base)
        #expect(status.projectId == "acme")
        #expect(status.assignmentSource == .suggested)
        #expect(status.projectName == "Acme Corp")
    }

    @Test("an explicit rule always beats a learned pattern")
    func ruleBeatsLearning() async {
        let rule = makeRule(type: .domainEquals, value: "bubble.io", projectId: "rule-project")
        let deps = FakeDependencies(
            rules: [rule], projects: [Project(id: "rule-project", name: "By Rule")]
        )
        await deps.setAssociations(establishedHistory())
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)

        let status = await coordinator.status(now: base)
        #expect(status.projectId == "rule-project")
        #expect(status.assignmentSource == .autoRule)
    }

    @Test("a manual override beats everything")
    func overrideBeatsLearning() async {
        let deps = FakeDependencies(override: ActiveProjectOverride(
            projectId: "override-project", scope: .global, expiry: .manual, startedAt: base
        ))
        await deps.setAssociations(establishedHistory())
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        #expect(await coordinator.status(now: base).projectId == "override-project")
    }

    @Test("a weak pattern is discarded rather than applied hesitantly")
    func weakPatternLeftUnassigned() async {
        let deps = FakeDependencies()
        // One sighting of one title word: nowhere near enough.
        await deps.setAssociations([
            FeatureAssociation(feature: "title:editor", projectId: "acme",
                               mass: 1, observations: 1, lastUpdated: base)
        ])
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)

        let status = await coordinator.status(now: base)
        #expect(status.projectId == nil, "thin evidence must leave time unassigned")
        #expect(status.assignmentSource == .unassigned)
    }

    @Test("learning can be turned off entirely")
    func learningDisabled() async {
        let deps = FakeDependencies(projects: [Project(id: "acme", name: "Acme Corp")])
        await deps.setAssociations(establishedHistory())
        let coordinator = ActivityCoordinator(
            dependencies: deps, settings: AppSettings(learningEnabled: false)
        )

        await coordinator.observe(browserSnapshot(), now: base)
        #expect(await coordinator.status(now: base).projectId == nil)
    }

    @Test("a suggestion carries the evidence behind it")
    func suggestionIsExplainable() async {
        let deps = FakeDependencies(projects: [Project(id: "acme", name: "Acme Corp")])
        await deps.setAssociations(establishedHistory())
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)

        let suggestion = try! #require(await coordinator.suggestionForCurrentSession())
        #expect(suggestion.projectId == "acme")
        #expect(!suggestion.evidence.isEmpty)
        #expect(suggestion.explanation(projectName: "Acme Corp", now: base).contains("Acme Corp"))
    }
}

@Suite("What the model learns from")
struct CoordinatorLearningFeedbackTests {
    func assignment(_ source: AssignmentSource) -> Assignment {
        Assignment(
            projectId: "acme", projectName: "Acme Corp",
            assignmentSource: source, assignmentConfidence: 100
        )
    }

    @Test("a manual choice is recorded as evidence")
    func learnsFromManual() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.reassignCurrentSession(to: assignment(.manualPopup))
        await coordinator.endSession(at: at(300))

        let recorded = await deps.recorded
        #expect(!recorded.isEmpty)
        #expect(recorded.allSatisfy { $0.projectId == "acme" && $0.weight > 0 })
        #expect(recorded.contains { $0.feature == "entity:bubble::sampleapp" })
    }

    @Test("a rule the user wrote is trustworthy evidence too")
    func learnsFromRules() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.reassignCurrentSession(to: assignment(.autoRule))
        await coordinator.endSession(at: at(300))

        #expect(await !deps.recorded.isEmpty)
    }

    @Test("the model does NOT learn from its own suggestions")
    func doesNotLearnFromItself() async {
        // A model that treats its own output as evidence converges on whatever
        // it guessed first and grows more certain the longer it is wrong.
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.reassignCurrentSession(to: assignment(.suggested))
        await coordinator.endSession(at: at(300))

        #expect(await deps.recorded.isEmpty, "self-reinforcement would make it confidently wrong")
    }

    @Test("unassigned time teaches nothing")
    func unassignedTeachesNothing() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.endSession(at: at(300))

        #expect(await deps.recorded.isEmpty)
    }

    @Test("a discarded flicker is not evidence either")
    func flickersTeachNothing() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.reassignCurrentSession(to: assignment(.manualPopup))
        await coordinator.endSession(at: at(1))   // under the minimum

        #expect(await deps.recorded.isEmpty)
    }
}

@Suite("Correcting a suggestion")
struct CoordinatorCorrectionTests {
    func history(project: String) -> [FeatureAssociation] {
        [
            FeatureAssociation(feature: "entity:bubble::sampleapp", projectId: project,
                               mass: 25, observations: 25, lastUpdated: base),
            FeatureAssociation(feature: "host:bubble.io", projectId: project,
                               mass: 25, observations: 25, lastUpdated: base),
        ]
    }

    @Test("overruling a suggestion records both the mistake and the right answer")
    func correctionRecordsBothSides() async {
        let deps = FakeDependencies(projects: [
            Project(id: "acme", name: "Acme Corp"),
            Project(id: "internal", name: "Internal"),
        ])
        await deps.setAssociations(history(project: "acme"))
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        #expect(await coordinator.status(now: base).assignmentSource == .suggested)

        // The user says: no, this is Internal.
        await coordinator.reassignCurrentSession(
            to: Assignment(
                projectId: "internal", projectName: "Internal",
                assignmentSource: .manualPopup, assignmentConfidence: 100
            ),
            now: at(300)
        )

        let recorded = await deps.recorded
        let negatives = recorded.filter { $0.weight < 0 }
        let positives = recorded.filter { $0.weight > 0 }

        #expect(negatives.allSatisfy { $0.projectId == "acme" }, "the wrong guess is penalised")
        #expect(positives.allSatisfy { $0.projectId == "internal" }, "the correction is learned")
        #expect(!negatives.isEmpty && !positives.isEmpty)
    }

    @Test("agreeing with a suggestion is not treated as a correction")
    func agreeingIsNotACorrection() async {
        let deps = FakeDependencies(projects: [Project(id: "acme", name: "Acme Corp")])
        await deps.setAssociations(history(project: "acme"))
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.reassignCurrentSession(
            to: Assignment(
                projectId: "acme", projectName: "Acme Corp",
                assignmentSource: .manualPopup, assignmentConfidence: 100
            ),
            now: at(300)
        )

        #expect(await deps.recorded.filter { $0.weight < 0 }.isEmpty)
    }

    @Test("changing a project that was never a suggestion records no penalty")
    func manualChangeIsNotACorrection() async {
        let deps = FakeDependencies()
        let coordinator = ActivityCoordinator(dependencies: deps)

        // No history, so the session starts unassigned rather than suggested.
        await coordinator.observe(browserSnapshot(), now: base)
        await coordinator.reassignCurrentSession(
            to: Assignment(
                projectId: "acme", assignmentSource: .manualPopup, assignmentConfidence: 100
            ),
            now: at(300)
        )

        #expect(await deps.recorded.isEmpty, "there was no wrong guess to penalise")
    }

    @Test("a correction clears the stale explanation")
    func correctionClearsExplanation() async {
        let deps = FakeDependencies(projects: [Project(id: "acme", name: "Acme Corp")])
        await deps.setAssociations(history(project: "acme"))
        let coordinator = ActivityCoordinator(dependencies: deps)

        await coordinator.observe(browserSnapshot(), now: base)
        #expect(await coordinator.suggestionForCurrentSession() != nil)

        await coordinator.reassignCurrentSession(
            to: Assignment(projectId: "internal", assignmentSource: .manualPopup,
                           assignmentConfidence: 100),
            now: at(300)
        )
        #expect(await coordinator.suggestionForCurrentSession() == nil)
    }
}
