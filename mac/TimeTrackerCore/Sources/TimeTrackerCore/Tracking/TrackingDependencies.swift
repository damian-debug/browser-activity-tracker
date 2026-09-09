import Foundation

/// Everything the coordinator needs from the outside world. Narrow on purpose:
/// the app target supplies a GRDB-backed implementation, tests supply an
/// in-memory one, and the coordinator itself stays pure enough to reason about.
public protocol TrackingDependencies: Sendable {
    func enabledRules() async -> [ProjectRule]
    func project(_ id: String) async -> Project?
    func currentOverride() async -> ActiveProjectOverride?
    func clearOverride() async
    func persist(_ session: Session) async

    // ── Learning ─────────────────────────────────────────────────────────

    /// Associations for exactly these feature keys. Narrow on purpose: this is
    /// an indexed lookup, not a scan of everything ever learned.
    func associations(forFeatureKeys keys: [String]) async -> [FeatureAssociation]

    /// Top-level projects that still exist and are not archived. Suggesting a
    /// deleted project would be worse than saying nothing.
    func eligibleProjectIds() async -> Set<String>

    /// Features belonging to a project. Suggesting a feature is a second,
    /// narrower pass over the same model, so a confident project and an
    /// unsure feature is a perfectly ordinary outcome.
    func featureIds(ofProject projectId: String) async -> Set<String>

    /// Display name for a project or feature.
    func projectName(_ id: String) async -> String?

    /// The feature you said you were working on, if any.
    ///
    /// Persistent and deliberate — it stays set until changed, and applies only
    /// while its own project is the one being tracked. You know which feature
    /// you are on; the Mac does not.
    func currentFeature() async -> (id: String, projectId: String, name: String)?

    func record(_ observations: [FeatureObservation]) async
}

public extension TrackingDependencies {
    // Defaults so a dependency that does not care about learning — a test
    // double, say — need not implement it.
    func associations(forFeatureKeys keys: [String]) async -> [FeatureAssociation] { [] }
    func eligibleProjectIds() async -> Set<String> { [] }
    func featureIds(ofProject projectId: String) async -> Set<String> { [] }
    func projectName(_ id: String) async -> String? { nil }
    func currentFeature() async -> (id: String, projectId: String, name: String)? { nil }
    func record(_ observations: [FeatureObservation]) async {}
}

/// A snapshot of tracking state for the UI to render.
public struct TrackingStatus: Hashable, Sendable {
    public var isTracking: Bool
    public var isPaused: Bool
    public var pauseReasons: PauseReasons
    public var elapsedSeconds: Int
    public var appName: String?
    public var displayTitle: String?
    public var projectId: String?
    public var projectName: String?
    public var featureId: String?
    public var featureName: String?
    public var assignmentSource: AssignmentSource?
    public var assignmentConfidence: Int?

    public static let idle = TrackingStatus(
        isTracking: false, isPaused: false, pauseReasons: [], elapsedSeconds: 0
    )
}
