import Foundation

/// One test a rule makes against an activity.
///
/// Rules hold a list of these and require all of them, because the single most
/// common case a one-condition rule cannot express is the useful one: Slack is
/// not a project, but Slack *and* a channel name is.
public struct RuleCondition: Hashable, Sendable, Codable {
    public var type: ProjectRuleType
    public var value: String
    /// Only for `.queryParamEquals`: the parameter name to look at.
    public var queryParamName: String?

    public init(type: ProjectRuleType, value: String, queryParamName: String? = nil) {
        self.type = type
        self.value = value
        self.queryParamName = queryParamName
    }
}

public extension Array where Element == RuleCondition {
    /// Confidence for a set of conditions that must all hold.
    ///
    /// Each condition independently narrows what can match, so their chances of
    /// being wrong multiply rather than add: "Slack" alone is a coarse guess at
    /// 65, but "Slack and a title containing acme" is a much safer one. Capped
    /// below a manual assignment, which is the only thing that should ever read
    /// as certain.
    var combinedConfidence: Int {
        guard !isEmpty else { return Confidence.unassigned }
        let residual = reduce(1.0) { $0 * (1 - Double($1.type.confidence) / 100) }
        return Swift.min(98, Int(((1 - residual) * 100).rounded()))
    }

    /// Specificity of the narrowest condition, for tie-breaking between rules
    /// of equal priority.
    var bestSpecificityIndex: Int {
        map(\.type.specificityIndex).min() ?? ProjectRuleType.specificityOrder.count
    }

    /// Human phrasing, e.g. "App is Slack and title contains acme".
    var summary: String {
        map(\.summary).joined(separator: " and ")
    }
}

public extension RuleCondition {
    var summary: String {
        switch type {
        case .appBundleEquals: return "app is \(value)"
        case .domainEquals: return "site is \(value)"
        case .urlContains: return "URL contains \(value)"
        case .urlStartsWith: return "URL starts with \(value)"
        case .pathContains: return "path contains \(value)"
        case .queryParamEquals: return "\(queryParamName ?? "parameter") is \(value)"
        case .titleContains: return "title contains \(value)"
        case .regex: return "URL matches \(value)"
        case .documentPathContains: return "file path contains \(value)"
        }
    }
}
