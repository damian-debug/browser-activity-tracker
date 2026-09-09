import Testing
import Foundation
@testable import TimeTrackerCore

// Ported from extension/tests/session-manager.test.ts. The accrual, pause and
// gap rules survive the platform change unchanged; the service-worker-restart
// half of the original suite is gone, because a native process isn't killed
// every 30 seconds.

private let base = Date(unixMillis: 1_700_000_000_000)
private func at(_ seconds: Int) -> Date { base.addingTimeInterval(Double(seconds)) }

@Suite("Active time accrual")
struct AccrualTests {
    @Test("accrues elapsed time within a segment")
    func accrual() {
        let session = ActiveSession(snapshot: browserSnapshot(), now: base)
        #expect(session.duration(at: at(60)) == 60)
    }

    @Test("captures the detected entity from the URL")
    func capturesEntity() {
        let session = ActiveSession(
            snapshot: browserSnapshot(url: "https://www.figma.com/design/abc123/My-File"),
            now: base
        )
        let finished = try! #require(session.finalized(at: at(10)))
        #expect(finished.service == "figma")
        #expect(finished.detectedEntityId == "abc123")
    }

    @Test("stores the assignment and marks manual sources reviewed")
    func manualIsReviewed() {
        let assignment = Assignment(
            projectId: "proj-1", projectName: "Acme Corp",
            assignmentSource: .manualDashboard, assignmentConfidence: 100,
            tagIds: ["tag-1"], billable: true
        )
        let session = ActiveSession(snapshot: browserSnapshot(), assignment: assignment, now: base)
        let finished = try! #require(session.finalized(at: at(10)))

        #expect(finished.projectId == "proj-1")
        #expect(finished.projectName == "Acme Corp")
        #expect(finished.assignmentConfidence == 100)
        #expect(finished.tagIds == ["tag-1"])
        #expect(finished.billable)
        #expect(finished.reviewed)
    }

    @Test("defaults to unassigned and unreviewed")
    func unassignedDefault() {
        let session = ActiveSession(snapshot: browserSnapshot(), now: base)
        let finished = try! #require(session.finalized(at: at(10)))
        #expect(finished.projectId == nil)
        #expect(finished.assignmentSource == .unassigned)
        #expect(finished.assignmentConfidence == 0)
        #expect(!finished.reviewed)
    }

    @Test("an auto-rule assignment is NOT automatically reviewed")
    func autoRuleNeedsReview() {
        let assignment = Assignment(
            projectId: "p1", assignmentSource: .autoRule, assignmentConfidence: 60
        )
        let session = ActiveSession(snapshot: browserSnapshot(), assignment: assignment, now: base)
        let finished = try! #require(session.finalized(at: at(10)))
        #expect(!finished.reviewed)
    }
}

@Suite("Finalizing sessions")
struct FinalizeTests {
    @Test("records the correct duration")
    func duration() {
        let session = ActiveSession(snapshot: browserSnapshot(), now: base)
        let finished = try! #require(session.finalized(at: at(120)))
        #expect(finished.durationSeconds == 120)
        #expect(finished.domain == "bubble.io")
        #expect(finished.startTime == base)
        #expect(finished.endTime == at(120))
    }

    @Test("discards sessions shorter than the minimum")
    func discardsTooShort() {
        let session = ActiveSession(snapshot: browserSnapshot(), now: base)
        #expect(session.finalized(at: at(1)) == nil)
        #expect(session.finalized(at: at(2)) != nil)
    }

    @Test("a native app session carries app identity and no browser fields")
    func nativeSession() {
        let snapshot = nativeSnapshot(title: "main.swift — acme", documentPath: "/Users/d/acme/main.swift")
        let session = ActiveSession(snapshot: snapshot, now: base)
        let finished = try! #require(session.finalized(at: at(30)))

        #expect(finished.appBundleID == "com.microsoft.VSCode")
        #expect(finished.appName == "Code")
        #expect(finished.documentPath == "/Users/d/acme/main.swift")
        #expect(finished.url == nil)
        #expect(finished.domain == nil)
        #expect(finished.title == "main.swift — acme")
    }
}

@Suite("Pause and resume")
struct PauseResumeTests {
    @Test("does not count time while idle")
    func idleNotCounted() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        session.pause(.idle, at: at(30))
        session.resume(.idle, at: at(130))   // 100s idle
        #expect(session.duration(at: at(150)) == 50)   // 30 + 20
    }

    @Test("stays paused until every reason clears")
    func multipleReasons() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        session.pause(.idle, at: at(10))
        session.pause(.screenLocked, at: at(10))

        session.resume(.screenLocked, at: at(60))
        #expect(session.isPaused, "still idle-paused")
        #expect(session.duration(at: at(60)) == 10)

        session.resume(.idle, at: at(110))
        #expect(!session.isPaused)
        #expect(session.duration(at: at(120)) == 20)   // 10 + 10
    }

    @Test("pausing twice for the same reason does not double-bank")
    func idempotentPause() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        session.pause(.idle, at: at(30))
        session.pause(.idle, at: at(60))
        #expect(session.duration(at: at(90)) == 30)
    }

    @Test("a manual timer in away mode keeps counting through idle")
    func awayModeIgnoresIdle() {
        var session = ActiveSession(snapshot: browserSnapshot(), ignoresIdle: true, now: base)
        session.pause(.idle, at: at(30))
        #expect(!session.isPaused)
        #expect(session.duration(at: at(120)) == 120)

        let finished = try! #require(session.finalized(at: at(120)))
        #expect(finished.countedWhileAway, "away-time must stay distinguishable in reports")
    }

    @Test("away mode still pauses for a locked screen")
    func awayModeStillLocks() {
        var session = ActiveSession(snapshot: browserSnapshot(), ignoresIdle: true, now: base)
        session.pause(.screenLocked, at: at(30))
        #expect(session.isPaused)
        #expect(session.duration(at: at(120)) == 30)
    }
}

@Suite("Checkpointing and wake gaps")
struct CheckpointTests {
    @Test("checkpoint banks elapsed time without interrupting tracking")
    func checkpointBanks() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        session.checkpoint(at: at(40))
        #expect(session.accumulatedSeconds == 40)
        #expect(session.segmentStart == at(40))
        #expect(session.duration(at: at(70)) == 70)
    }

    @Test("a short gap is credited: the user was working, we simply weren't looking")
    func shortGapCredited() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        session.checkpoint(at: at(40))

        let decision = session.decideGap(now: at(60))
        #expect(decision == .credit)
        #expect(session.duration(at: at(60)) == 60)
    }

    @Test("a long gap is not credited: the machine was asleep, not in use")
    func longGapDiscarded() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        session.checkpoint(at: at(40))

        let settings = AppSettings.default
        let wake = at(40 + settings.maximumCreditedGapSeconds + 600)
        #expect(session.decideGap(now: wake, settings: settings) == .finalizeAtLastCheckpoint(at(40)))

        // Closing at the checkpoint credits the work done before sleeping, and
        // none of the dead time.
        let finished = try! #require(session.finalized(at: at(40)))
        #expect(finished.durationSeconds == 40)
    }

    @Test("the gap boundary is inclusive of the cap")
    func gapBoundary() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        session.checkpoint(at: at(0))
        let cap = AppSettings.default.maximumCreditedGapSeconds
        #expect(session.decideGap(now: at(cap)) == .credit)
        #expect(session.decideGap(now: at(cap + 1)) == .finalizeAtLastCheckpoint(base))
    }

    @Test("accumulates correctly across many checkpoint cycles")
    func repeatedCheckpoints() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        for i in 1...5 {
            session.checkpoint(at: at(i * 30))
        }
        #expect(session.duration(at: at(150)) == 150)
    }
}
