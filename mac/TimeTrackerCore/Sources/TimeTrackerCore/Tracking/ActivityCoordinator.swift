import Foundation

/// Owns the in-flight session and decides when time starts, continues and ends.
///
/// An `actor` for a specific reason: macOS fires overlapping events for a single
/// user action (an app activation plus a focused-window change plus a title
/// change), and the extension had to hand-roll a promise queue to stop two
/// interleaved reconciles double-starting a session. Actor isolation gives that
/// serialisation for free.
///
/// Time is always passed in rather than read from the clock, so every rule here
/// is deterministic under test.
public actor ActivityCoordinator {
    private let dependencies: any TrackingDependencies
    private var settings: AppSettings
    private var current: ActiveSession?

    /// Reasons that apply to the *tracker*, not to one session, so they survive
    /// a session change (going idle then switching apps should stay paused).
    private var globalPauseReasons: PauseReasons = []

    public init(dependencies: any TrackingDependencies, settings: AppSettings = .default) {
        self.dependencies = dependencies
        self.settings = settings
    }

    public func updateSettings(_ settings: AppSettings) {
        self.settings = settings
    }

    public var activeSession: ActiveSession? { current }

    public func status(now: Date) -> TrackingStatus {
        guard let current else { return .idle }
        return TrackingStatus(
            isTracking: true,
            isPaused: current.isPaused,
            pauseReasons: current.pauseReasons,
            elapsedSeconds: current.duration(at: now),
            appName: current.snapshot.appName,
            displayTitle: current.snapshot.displayTitle,
            projectId: current.assignment.projectId,
            projectName: current.assignment.projectName,
            assignmentSource: current.assignment.assignmentSource,
            assignmentConfidence: current.assignment.assignmentConfidence
        )
    }

    // ── Activity ─────────────────────────────────────────────────────────

    /// The user is now doing `snapshot`. Continues the current session when it
    /// is the same target, otherwise closes it and opens a new one.
    public func observe(_ snapshot: ActivitySnapshot, now: Date = Date()) async {
        guard !settings.excludes(snapshot) else {
            await endSession(at: now)
            return
        }

        if let current, current.continues(snapshot) {
            // Same work: keep accruing, and absorb any detail this observation
            // adds (a title that arrived once Accessibility was granted, a URL
            // that failed to read a moment ago).
            self.current?.absorb(snapshot)
            self.current?.checkpoint(at: now)
            return
        }

        await endSession(at: now)
        await startSession(snapshot, now: now)
    }

    private func startSession(_ snapshot: ActivitySnapshot, now: Date) async {
        let override = await dependencies.currentOverride()
        let rules = await dependencies.enabledRules()
        let result = SessionAssigner.assign(snapshot, rules: rules, override: override, now: now)

        var projectName: String?
        var billable = result.billable ?? false
        if let projectId = result.projectId {
            let project = await dependencies.project(projectId)
            projectName = project?.name
            // Billable precedence: an explicit rule/override value, else the
            // project's own default.
            if result.billable == nil { billable = project?.defaultBillable ?? false }
        }

        let assignment = Assignment(
            projectId: result.projectId,
            projectName: projectName,
            assignmentSource: result.assignmentSource,
            assignmentConfidence: result.assignmentConfidence,
            matchedRuleId: result.matchedRuleId,
            tagIds: result.defaultTagIds ?? [],
            billable: billable
        )

        current = ActiveSession(
            snapshot: snapshot,
            assignment: assignment,
            pauseReasons: globalPauseReasons,
            ignoresIdle: override?.countsWhileAway ?? false,
            now: now
        )
    }

    /// Close the current session, persisting it if it is long enough to matter.
    public func endSession(at date: Date = Date()) async {
        guard let session = current else { return }
        current = nil
        if let finished = session.finalized(at: date, settings: settings, now: date) {
            await dependencies.persist(finished)
        }
    }

    // ── Pause / resume ───────────────────────────────────────────────────

    public func pause(_ reason: PauseReasons, at date: Date = Date()) {
        globalPauseReasons.insert(reason)
        current?.pause(reason, at: date)
    }

    public func resume(_ reason: PauseReasons, at date: Date = Date()) {
        globalPauseReasons.remove(reason)
        current?.resume(reason, at: date)
    }

    // ── Reconciliation ───────────────────────────────────────────────────

    /// Periodic checkpoint. Also the safety net for a machine that slept
    /// without us being told: timers don't fire while asleep, so elapsed time
    /// is always recomputed from wall-clock timestamps.
    public func heartbeat(now: Date = Date()) async {
        guard let session = current else { return }

        switch session.decideGap(now: now, settings: settings) {
        case .credit:
            current?.checkpoint(at: now)
        case .finalizeAtLastCheckpoint(let checkpoint):
            // The gap was too long to be real work. Bank what was verified
            // before it and drop the dead time entirely.
            current = nil
            if let finished = session.finalized(at: checkpoint, settings: settings, now: now) {
                await dependencies.persist(finished)
            }
        }
    }

    /// A timed override has lapsed: drop it, close the time it was claiming,
    /// and let the rules take over again for the same activity.
    public func overrideExpired(now: Date = Date()) async {
        let snapshot = current?.snapshot
        await dependencies.clearOverride()
        await endSession(at: now)
        if let snapshot {
            await startSession(snapshot, now: now)
        }
    }

    /// Re-attribute the in-flight session without disturbing its clock. Used
    /// when the user picks a project for the thing they're already doing.
    public func reassignCurrentSession(to assignment: Assignment) {
        current?.assignment = assignment
    }

    /// Restart tracking under a new assignment, splitting time exactly at this
    /// moment. This is what starting a manual timer does.
    public func restartCurrentSession(
        ignoringIdle: Bool = false,
        now: Date = Date()
    ) async {
        guard let snapshot = current?.snapshot else { return }
        await endSession(at: now)
        await startSession(snapshot, now: now)
        current?.ignoresIdle = ignoringIdle
    }
}
