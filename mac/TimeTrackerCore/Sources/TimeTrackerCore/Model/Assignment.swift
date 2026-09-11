import Foundation

public enum AssignmentSource: String, CaseIterable, Hashable, Sendable, Codable {
    case autoRule = "auto_rule"
    case manualPopup = "manual_popup"
    case manualDashboard = "manual_dashboard"
    case activeProjectOverride = "active_project_override"
    /// Emitted by the learned-suggestion layer (Phase 3).
    case suggested = "suggested"
    case unassigned = "unassigned"

    /// Sources that represent a deliberate human decision, and are therefore
    /// reviewed by definition.
    public var isManual: Bool {
        self == .manualPopup || self == .manualDashboard
    }
}

/// The project assignment attached to a session, live or stored.
public struct Assignment: Hashable, Sendable, Codable {
    public var projectId: String?
    public var projectName: String?
    public var featureId: String?
    public var featureName: String?
    public var assignmentSource: AssignmentSource
    public var assignmentConfidence: Int
    public var matchedRuleId: String?
    public var tagIds: [String]
    public var billable: Bool

    /// True when the feature is the model's guess rather than something a
    /// person decided (a rule, or the feature picked in the popover). The
    /// model must not learn from its own guesses — now that a learned screen
    /// can also split a session, one that did would lock in its mistakes.
    /// Optional so a session persisted by an older build still restores.
    public var featureWasInferred: Bool?

    public init(
        projectId: String? = nil,
        projectName: String? = nil,
        featureId: String? = nil,
        featureName: String? = nil,
        assignmentSource: AssignmentSource,
        assignmentConfidence: Int,
        matchedRuleId: String? = nil,
        tagIds: [String] = [],
        billable: Bool = false
    ) {
        self.projectId = projectId
        self.projectName = projectName
        self.featureId = featureId
        self.featureName = featureName
        self.assignmentSource = assignmentSource
        self.assignmentConfidence = assignmentConfidence
        self.matchedRuleId = matchedRuleId
        self.tagIds = tagIds
        self.billable = billable
    }

    public static let unassigned = Assignment(
        assignmentSource: .unassigned,
        assignmentConfidence: 0
    )
}
