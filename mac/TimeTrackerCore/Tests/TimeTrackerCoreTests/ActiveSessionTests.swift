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

@Suite("Pausing from the last input")
struct BackdatedPauseTests {
    // The idle threshold only fires once it has elapsed, so the pause arrives
    // dated in the past: "they left at their last keystroke". These pin down
    // that the wait itself is never credited as work.

    @Test("a break credits nothing past the last input, even across checkpoints")
    func refundsBankedTime() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        // Working for 10 minutes, then gone. Heartbeats keep banking every 30s
        // for the 5 minutes it takes the idle threshold to notice.
        for t in stride(from: 30, through: 900, by: 30) { session.checkpoint(at: at(t)) }
        session.pause(.idle, at: at(600))

        #expect(session.duration(at: at(900)) == 600)
        #expect(session.duration(at: at(5000)) == 600, "and nothing accrues while away")
    }

    @Test("without checkpoints in between, it is the same answer")
    func noCheckpoints() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        session.pause(.idle, at: at(600))
        #expect(session.duration(at: at(900)) == 600)
    }

    @Test("returning resumes from the moment you are back")
    func resume() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        session.checkpoint(at: at(800))
        session.pause(.idle, at: at(600))
        session.resume(.idle, at: at(2000))
        session.checkpoint(at: at(2100))

        #expect(session.duration(at: at(2400)) == 600 + 400)
    }

    @Test("a session that began after you left credits nothing")
    func startedWhileAway() {
        // e.g. a window changed under you while you were away.
        var session = ActiveSession(snapshot: browserSnapshot(), now: at(700))
        session.checkpoint(at: at(800))
        session.pause(.idle, at: at(600))
        #expect(session.duration(at: at(900)) == 0)
    }

    @Test("never takes back time from before an earlier pause")
    func boundedByCurrentRun() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        session.pause(.screenLocked, at: at(300))       // 300s banked
        session.resume(.screenLocked, at: at(400))
        session.checkpoint(at: at(500))                 // +100
        // A pause dated before the lock even happened must not reach back
        // into the first run: only the current run can be refunded.
        session.pause(.idle, at: at(100))
        #expect(session.duration(at: at(600)) == 300)
    }

    @Test("a second reason does not refund again")
    func secondReason() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        session.checkpoint(at: at(900))
        session.pause(.screenLocked, at: at(600))
        session.pause(.idle, at: at(300))
        #expect(session.duration(at: at(1000)) == 600)
    }

    @Test("the last-checkpoint clock is never wound backwards")
    func checkpointNotRewound() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        session.checkpoint(at: at(900))
        session.pause(.idle, at: at(600))
        #expect(session.lastCheckpoint == at(900))
        // So the wake-gap rule does not mistake a backdated pause for sleep.
        #expect(session.decideGap(now: at(920)) == .credit)
    }

    @Test("a session saved by an older build, without activeSince, still restores")
    func restoresOldCheckpoint() throws {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        session.checkpoint(at: at(60))
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as! [String: Any]
        json.removeValue(forKey: "activeSince")
        let data = try JSONSerialization.data(withJSONObject: json)

        var restored = try JSONDecoder().decode(ActiveSession.self, from: data)
        #expect(restored.activeSince == nil)
        // Falls back to the open segment: it can under-refund, never over-refund.
        restored.checkpoint(at: at(120))
        restored.pause(.idle, at: at(90))
        #expect(restored.duration(at: at(200)) == 120)
    }

    @Test("the idle threshold defaults to five minutes")
    func fiveMinuteDefault() {
        #expect(AppSettings.default.idleThresholdSeconds == 300)
    }
}

@Suite("Checkpoints keep every part-second")
struct CheckpointPrecisionTests {
    @Test("frequent checkpoints at uneven intervals credit the full wall time")
    func unevenSampling() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        // Samples every 2–2.9s, as the real sampler delivers them once
        // Accessibility and browser reads are included.
        var t = 0.0
        let steps = [2.3, 2.7, 2.05, 2.9, 2.45, 2.6, 2.15, 2.85, 2.5, 2.2]
        for i in 0..<48 {
            t += steps[i % steps.count]
            session.checkpoint(at: base.addingTimeInterval(t))
        }
        #expect(session.duration(at: base.addingTimeInterval(t)) == Int(t),
                "at most the final part-second is ever missing")
    }

    @Test("a checkpoint every 1.9s for an hour loses nothing")
    func worstCase() {
        // The old behaviour banked 1s for each of these — half the hour gone.
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        var t = 0.0
        while t + 1.9 <= 3600 {
            t += 1.9
            session.checkpoint(at: base.addingTimeInterval(t))
        }
        #expect(session.duration(at: at(3600)) == 3600)
    }

    @Test("pausing after many checkpoints is still exact")
    func pauseAfterCheckpoints() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        for i in 1...100 { session.checkpoint(at: base.addingTimeInterval(Double(i) * 2.5)) }
        session.pause(.screenLocked, at: base.addingTimeInterval(251))
        #expect(session.duration(at: at(400)) == 251)
    }

    @Test("a backdated idle pause after many checkpoints refunds exactly")
    func backdatedAfterCheckpoints() {
        var session = ActiveSession(snapshot: browserSnapshot(), now: base)
        for i in 1...360 { session.checkpoint(at: base.addingTimeInterval(Double(i) * 2.5)) }
        // Last input at 600s; idle noticed at 900s.
        session.pause(.idle, at: at(600))
        #expect(session.duration(at: at(1000)) == 600)
    }
}
