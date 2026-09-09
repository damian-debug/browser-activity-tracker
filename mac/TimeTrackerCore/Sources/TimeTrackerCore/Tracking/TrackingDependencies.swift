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
    public var assignmentSource: AssignmentSource?
    public var assignmentConfidence: Int?

    public static let idle = TrackingStatus(
        isTracking: false, isPaused: false, pauseReasons: [], elapsedSeconds: 0
    )
}
