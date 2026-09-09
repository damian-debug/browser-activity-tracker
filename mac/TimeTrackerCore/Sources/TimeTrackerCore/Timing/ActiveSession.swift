import Foundation

/// Why tracking is currently suspended. A bitfield, because reasons overlap:
/// going idle while the screen is also locked must not resume early when only
/// one of them clears.
public struct PauseReasons: OptionSet, Hashable, Sendable, Codable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let idle = PauseReasons(rawValue: 1 << 0)
    public static let screenLocked = PauseReasons(rawValue: 1 << 1)
    public static let displayAsleep = PauseReasons(rawValue: 1 << 2)
}

/// The in-flight session.
///
/// Timing model ported from the extension: `accumulatedSeconds` banks completed
/// segments, `segmentStart` marks the open one (nil while paused). The MV3
/// persistence dance around this is gone — a native process isn't killed every
/// 30 seconds — but the accrual arithmetic is unchanged, because it was correct
/// and well covered.
public struct ActiveSession: Hashable, Sendable, Codable {
    public let id: String
    /// Label for display. Recomputed as richer signals arrive; continuity is
    /// decided by `ActivityIdentity`, never by this.
    public var target: TrackingTarget
    public var snapshot: ActivitySnapshot
    public var assignment: Assignment

    public let startTime: Date
    public private(set) var accumulatedSeconds: Int
    public private(set) var segmentStart: Date?
    public private(set) var pauseReasons: PauseReasons

    /// Last time the elapsed clock was reconciled against the wall clock. Used
    /// on wake to decide whether the gap was work or a sleeping machine.
    public private(set) var lastCheckpoint: Date

    /// Manual timers in "keep counting while I'm away" mode ignore idle, so
    /// meetings and phone calls still accrue. Deliberately opt-in: it breaks
    /// the accuracy-first rule, so sessions recorded this way are marked.
    public var ignoresIdle: Bool

    /// Full-fidelity initialiser, used when restoring a persisted session.
    public init(
        id: String,
        target: TrackingTarget,
        snapshot: ActivitySnapshot,
        assignment: Assignment,
        startTime: Date,
        accumulatedSeconds: Int,
        segmentStart: Date?,
        pauseReasons: PauseReasons,
        lastCheckpoint: Date,
        ignoresIdle: Bool
    ) {
        self.id = id
        self.target = target
        self.snapshot = snapshot
        self.assignment = assignment
        self.startTime = startTime
        self.accumulatedSeconds = accumulatedSeconds
        self.segmentStart = segmentStart
        self.pauseReasons = pauseReasons
        self.lastCheckpoint = lastCheckpoint
        self.ignoresIdle = ignoresIdle
    }

    public init(
        id: String = UUID().uuidString,
        snapshot: ActivitySnapshot,
        assignment: Assignment = .unassigned,
        pauseReasons: PauseReasons = [],
        ignoresIdle: Bool = false,
        now: Date = Date()
    ) {
        self.id = id
        self.target = TrackingTarget.resolve(snapshot)
        self.snapshot = snapshot
        self.assignment = assignment
        self.startTime = now
        self.accumulatedSeconds = 0
        self.pauseReasons = pauseReasons
        self.segmentStart = pauseReasons.isEmpty ? now : nil
        self.lastCheckpoint = now
        self.ignoresIdle = ignoresIdle
    }

    public var isPaused: Bool { !pauseReasons.isEmpty }

    /// Whether `snapshot` is a continuation of this session.
    public func continues(_ snapshot: ActivitySnapshot) -> Bool {
        self.snapshot.identity.continues(snapshot.identity)
    }

    /// Adopt a newer observation of the same work, keeping details it lacks.
    public mutating func absorb(_ snapshot: ActivitySnapshot) {
        self.snapshot = snapshot.enriched(from: self.snapshot)
        self.target = TrackingTarget.resolve(self.snapshot)
    }

    /// Total active seconds as of `date`, including the open segment.
    public func duration(at date: Date) -> Int {
        guard let segmentStart else { return accumulatedSeconds }
        return accumulatedSeconds + Self.elapsedSeconds(from: segmentStart, to: date)
    }

    static func elapsedSeconds(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start)))
    }

    /// Suspend accrual. Only the first reason banks the open segment; later
    /// reasons just record that they also apply.
    public mutating func pause(_ reason: PauseReasons, at date: Date = Date()) {
        if reason == .idle && ignoresIdle { return }

        let wasPaused = isPaused
        pauseReasons.insert(reason)

        if !wasPaused, let segmentStart {
            accumulatedSeconds += Self.elapsedSeconds(from: segmentStart, to: date)
            self.segmentStart = nil
        }
        lastCheckpoint = date
    }

    /// Clear one reason. The clock only restarts once every reason has cleared.
    public mutating func resume(_ reason: PauseReasons, at date: Date = Date()) {
        pauseReasons.remove(reason)
        if pauseReasons.isEmpty && segmentStart == nil {
            segmentStart = date
        }
        lastCheckpoint = date
    }

    /// Bank elapsed time without interrupting tracking, so a crash or forced
    /// quit loses at most one interval.
    public mutating func checkpoint(at date: Date = Date()) {
        if let segmentStart {
            accumulatedSeconds += Self.elapsedSeconds(from: segmentStart, to: date)
            self.segmentStart = date
        }
        lastCheckpoint = date
    }

    /// Close this session as of `date`.
    ///
    /// Returns nil for sessions below `minimumSessionSeconds` — window flickers
    /// and apps passed through on the way somewhere else are noise, not work.
    public func finalized(
        at date: Date,
        settings: AppSettings = .default,
        now: Date = Date()
    ) -> Session? {
        let seconds = duration(at: date)
        guard seconds >= settings.minimumSessionSeconds else { return nil }

        let parsed = snapshot.parsed
        return Session(
            id: id,
            appBundleID: snapshot.bundleID,
            appName: snapshot.appName,
            windowTitle: snapshot.windowTitle,
            documentPath: snapshot.documentPath,
            gitBranch: snapshot.gitBranch,
            url: snapshot.url,
            domain: snapshot.domain,
            title: snapshot.displayTitle,
            service: parsed?.service,
            detectedEntityId: parsed?.entityId,
            detectedEntityName: parsed?.entityName,
            projectId: assignment.projectId,
            projectName: assignment.projectName,
            featureId: assignment.featureId,
            featureName: assignment.featureName,
            assignmentSource: assignment.assignmentSource,
            assignmentConfidence: assignment.assignmentConfidence,
            matchedRuleId: assignment.matchedRuleId,
            tagIds: assignment.tagIds,
            billable: assignment.billable,
            // A deliberate human choice is reviewed by definition.
            reviewed: assignment.assignmentSource.isManual,
            countedWhileAway: ignoresIdle,
            startTime: startTime,
            endTime: date,
            durationSeconds: seconds,
            createdAt: now,
            updatedAt: now
        )
    }

    /// How to treat time that passed while the app wasn't reconciling — a
    /// sleeping machine, or simply a long stretch between checkpoints.
    public enum GapDecision: Hashable, Sendable {
        /// The user was plausibly working; count it.
        case credit
        /// Too long to be real work; close the session at its last checkpoint.
        case finalizeAtLastCheckpoint(Date)
    }

    /// Wall-clock reconciliation. Timers do not fire while the machine sleeps,
    /// so elapsed time is always recomputed from timestamps rather than assumed.
    public func decideGap(now: Date, settings: AppSettings = .default) -> GapDecision {
        let gap = Self.elapsedSeconds(from: lastCheckpoint, to: now)
        if gap > settings.maximumCreditedGapSeconds {
            return .finalizeAtLastCheckpoint(lastCheckpoint)
        }
        return .credit
    }
}
