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
    private let learned: LearnedIndex

    /// Explanation for the current session's learned suggestion, if that is
    /// where its project came from. Shown in the UI so an automatic assignment
    /// can always be questioned.
    private(set) var currentSuggestion: LearnedSuggestion?

    /// Reasons that apply to the *tracker*, not to one session, so they survive
    /// a session change (going idle then switching apps should stay paused).
    private var globalPauseReasons: PauseReasons = []

    public init(
        dependencies: any TrackingDependencies,
        settings: AppSettings = .default,
        learned: LearnedIndex = .default
    ) {
        self.dependencies = dependencies
        self.settings = settings
        self.learned = learned
    }

    public func suggestionForCurrentSession() -> LearnedSuggestion? { currentSuggestion }

    public func updateSettings(_ settings: AppSettings) {
        self.settings = settings
    }

    public var activeSession: ActiveSession? { current }

    /// Restore an in-flight session left behind by a previous run.
    ///
    /// A native process isn't killed every 30 seconds the way an MV3 service
    /// worker is, but it does still crash, get force-quit, and go down with a
    /// restart. Losing the last stretch of work to any of those is exactly the
    /// failure a time tracker cannot have, so the same wall-clock reasoning the
    /// extension used on wake applies here on launch.
    public func restore(_ session: ActiveSession, now: Date = Date()) async {
        switch session.decideGap(now: now, settings: settings) {
        case .credit:
            // The app was only briefly gone; carry on where we left off.
            current = session
        case .finalizeAtLastCheckpoint(let checkpoint):
            // Too long to be plausible work. Bank what was verified and stop.
            current = nil
            if let finished = session.finalized(at: checkpoint, settings: settings, now: now) {
                await dependencies.persist(finished)
            }
        }
    }

    /// Close out cleanly on quit, so the session in progress is saved rather
    /// than discarded.
    public func shutdown(now: Date = Date()) async {
        await endSession(at: now)
    }

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
            featureId: current.assignment.featureId,
            featureName: current.assignment.featureName,
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
            if await screenChangeMovesWork(current, to: snapshot, now: now) {
                await endSession(at: now)
                await startSession(snapshot, now: now)
                return
            }
            // Same work: keep accruing, and absorb any detail this observation
            // adds (a title that arrived once Accessibility was granted, a URL
            // that failed to read a moment ago).
            self.current?.absorb(snapshot)
            self.current?.checkpoint(at: now)
            return
        }

        // Only the query or fragment changed. Usually noise, but some sites
        // keep their identity there, so this continues only when the session
        // is already attributed and the new address lands in exactly the same
        // place. Unassigned pages stay apart: merged, one later decision would
        // assign both of them.
        if let current, current.snapshot.identity.differsOnlyInQuery(snapshot.identity),
           await attributesTheSame(current, snapshot, now: now) {
            self.current?.absorb(snapshot)
            self.current?.checkpoint(at: now)
            return
        }

        await endSession(at: now)
        await startSession(snapshot, now: now)
    }

    private func attributesTheSame(
        _ current: ActiveSession, _ snapshot: ActivitySnapshot, now: Date
    ) async -> Bool {
        guard let project = current.assignment.projectId else { return false }
        let override = await dependencies.currentOverride()
        let (next, _) = await attribute(snapshot, override: override, now: now)
        return next.projectId == project && next.featureId == current.assignment.featureId
    }

    private func startSession(_ snapshot: ActivitySnapshot, now: Date) async {
        let override = await dependencies.currentOverride()
        let (assignment, suggestion) = await attribute(snapshot, override: override, now: now)
        currentSuggestion = suggestion
        current = ActiveSession(
            snapshot: snapshot,
            assignment: assignment,
            pauseReasons: globalPauseReasons,
            ignoresIdle: override?.countsWhileAway ?? false,
            now: now
        )
    }

    /// Moving between screens of one project normally stays one session: the
    /// project is the work, and clicking around inside it is not new work.
    /// But when the new screen is attributed somewhere else — a rule or the
    /// model puts it on a different feature — the time from here on belongs
    /// there. Only a screen that resolves to something different splits; one
    /// nothing is known about stays with the session it is part of.
    private func screenChangeMovesWork(
        _ current: ActiveSession, to snapshot: ActivitySnapshot, now: Date
    ) async -> Bool {
        guard let screen = snapshot.parsed?.subEntityId,
              screen != current.snapshot.parsed?.subEntityId
        else { return false }

        let override = await dependencies.currentOverride()
        let (next, _) = await attribute(snapshot, override: override, now: now)
        if let project = next.projectId, project != current.assignment.projectId { return true }
        if let feature = next.featureId, feature != current.assignment.featureId { return true }

        // Moving to a page with no feature of its own. A real page's feature
        // does not follow you onto the next page — without this, time on every
        // other page of a Bubble app counted towards the last feature visited.
        // A selection is different: clicking an element nothing is known about
        // is still the work in progress. (A feature picked in the popover never
        // gets here: it applies to every page, so `next` carries it too.)
        if next.featureId == nil, current.assignment.featureId != nil,
           snapshot.parsed?.subEntityIsPage == true {
            return true
        }
        return false
    }

    /// Who this activity's time belongs to: project, then feature. The single
    /// source of truth for attribution, so starting a session and deciding
    /// whether a new screen is different work can never disagree.
    private func attribute(
        _ snapshot: ActivitySnapshot, override: ActiveProjectOverride?, now: Date
    ) async -> (Assignment, LearnedSuggestion?) {
        let rules = await dependencies.enabledRules()
        var result = SessionAssigner.assign(snapshot, rules: rules, override: override, now: now)

        // Only fall back to what has been learned when nothing explicit
        // matched. A rule the user wrote always wins over a pattern inferred
        // from their history.
        var learnedProject: LearnedSuggestion?
        if result.projectId == nil, settings.learningEnabled {
            if let suggestion = await suggest(for: snapshot, now: now) {
                learnedProject = suggestion
                result = RuleEngineResult(
                    projectId: suggestion.projectId,
                    assignmentSource: .suggested,
                    assignmentConfidence: suggestion.confidence
                )
            }
        }

        var projectName: String?
        var billable = result.billable ?? false
        if let projectId = result.projectId {
            let project = await dependencies.project(projectId)
            projectName = project?.name
            // Billable precedence: an explicit rule/override value, else the
            // project's own default.
            if result.billable == nil { billable = project?.defaultBillable ?? false }
        }

        // A second, narrower pass: which feature of that project is this?
        // Kept separate so being sure of the project and unsure of the feature
        // is an ordinary, expressible outcome rather than an all-or-nothing bet.
        var featureId: String?
        var featureName: String?
        var featureWasInferred = false

        // A rule that names a feature has said so explicitly; nothing should
        // second-guess it.
        if let ruleFeature = result.featureId {
            featureId = ruleFeature
            featureName = await dependencies.projectName(ruleFeature)
        } else if let projectId = result.projectId {
            // What you said beats what the model inferred, exactly as an
            // override beats a rule one level up.
            if let chosen = await dependencies.currentFeature(), chosen.projectId == projectId {
                featureId = chosen.id
                featureName = chosen.name
            } else if settings.learningEnabled,
                      let feature = await suggestFeature(for: snapshot, ofProject: projectId, now: now) {
                featureId = feature.projectId
                featureName = await dependencies.projectName(feature.projectId)
                featureWasInferred = true
            }
        }

        let assignment = Assignment(
            projectId: result.projectId,
            projectName: projectName,
            featureId: featureId,
            featureName: featureName,
            assignmentSource: result.assignmentSource,
            assignmentConfidence: result.assignmentConfidence,
            matchedRuleId: result.matchedRuleId,
            tagIds: result.defaultTagIds ?? [],
            billable: billable
        )
        var attributed = assignment
        attributed.featureWasInferred = featureWasInferred ? true : nil
        return (attributed, learnedProject)
    }

    /// Ask the model what this activity probably is.
    ///
    /// A suggestion below the floor is discarded outright rather than applied
    /// weakly: leaving time unassigned costs a moment of the user's attention,
    /// while a confidently wrong assignment quietly corrupts an invoice.
    private func suggest(for snapshot: ActivitySnapshot, now: Date) async -> LearnedSuggestion? {
        let features = FeatureExtractor.features(for: snapshot)
        guard !features.isEmpty else { return nil }

        let associations = await dependencies.associations(forFeatureKeys: features.map(\.key))
        guard !associations.isEmpty else { return nil }

        let eligible = await dependencies.eligibleProjectIds()
        guard !eligible.isEmpty else { return nil }

        guard let suggestion = learned.suggest(
            features: features, associations: associations,
            eligibleProjectIds: eligible, now: now
        ) else { return nil }

        return suggestion.confidence >= settings.learnedMinimumConfidence ? suggestion : nil
    }

    /// Which feature of `projectId` this activity most likely belongs to.
    private func suggestFeature(
        for snapshot: ActivitySnapshot, ofProject projectId: String, now: Date
    ) async -> LearnedSuggestion? {
        let candidates = await dependencies.featureIds(ofProject: projectId)
        guard !candidates.isEmpty else { return nil }

        let features = FeatureExtractor.features(for: snapshot)
        guard !features.isEmpty else { return nil }

        let associations = await dependencies.associations(forFeatureKeys: features.map(\.key))
        guard let suggestion = learned.suggest(
            features: features, associations: associations,
            eligibleProjectIds: candidates, now: now
        ) else { return nil }

        return suggestion.confidence >= settings.learnedMinimumConfidence ? suggestion : nil
    }

    /// Close the current session, persisting it if it is long enough to matter.
    public func endSession(at date: Date = Date()) async {
        guard let session = current else { return }
        current = nil
        currentSuggestion = nil
        if let finished = session.finalized(at: date, settings: settings, now: date) {
            await dependencies.persist(finished)
            await learn(from: finished, featureWasInferred: session.assignment.featureWasInferred == true)
        }
    }

    /// Feed a finished session back into the model.
    ///
    /// Deliberately does NOT learn from its own suggestions: a model that
    /// treats its own output as evidence converges on whatever it guessed
    /// first, and grows more certain the longer it is wrong. Only decisions
    /// carrying real human intent are recorded — a manual choice, a timer the
    /// user started, or a rule they wrote.
    private func learn(from session: Session, featureWasInferred: Bool = false) async {
        guard settings.learningEnabled,
              let projectId = session.projectId,
              Self.isTrustworthyEvidence(session.assignmentSource)
        else { return }

        var observations = learned.observations(for: session, projectId: projectId)
        // Record against the feature too, so the narrower pass has something to
        // learn from. Features share the project id namespace, so this needs no
        // separate model.
        // Only a feature a person decided; never the model's own guess.
        if let featureId = session.featureId, !featureWasInferred {
            observations += learned.observations(for: session, projectId: featureId)
        }
        await dependencies.record(observations)
    }

    static func isTrustworthyEvidence(_ source: AssignmentSource) -> Bool {
        switch source {
        case .manualPopup, .manualDashboard, .activeProjectOverride, .autoRule:
            return true
        case .suggested, .unassigned:
            return false
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
    ///
    /// If this overrules a suggestion, that is the most valuable signal the
    /// model ever gets: it is told both that it was wrong and what the right
    /// answer was, for exactly this activity.
    public func reassignCurrentSession(to assignment: Assignment, now: Date = Date()) async {
        guard let session = current else { return }
        let previous = session.assignment
        current?.assignment = assignment

        guard settings.learningEnabled else { return }

        let corrected = previous.assignmentSource == .suggested
            && previous.projectId != nil
            && previous.projectId != assignment.projectId

        guard corrected, let wrongProjectId = previous.projectId else { return }

        currentSuggestion = nil
        let features = FeatureExtractor.features(for: session.snapshot)
        let elapsed = session.duration(at: now)

        var observations = learned.observations(
            features: features, projectId: wrongProjectId,
            durationSeconds: elapsed, at: now
        ).map { observation -> FeatureObservation in
            var correction = observation
            correction.weight = -observation.weight
            return correction
        }

        // The replacement is recorded straight away rather than waiting for the
        // session to end, so the very next activity already benefits.
        if let rightProjectId = assignment.projectId, assignment.assignmentSource.isManual {
            observations += learned.observations(
                features: features, projectId: rightProjectId,
                durationSeconds: elapsed, at: now
            )
        }

        await dependencies.record(observations)
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
