import Foundation

// Raw values match the Chrome extension's strings exactly so backup files
// round-trip between the two implementations.
public enum ProjectRuleType: String, CaseIterable, Hashable, Sendable, Codable {
    case domainEquals = "domain_equals"
    case urlContains = "url_contains"
    case urlStartsWith = "url_starts_with"
    case pathContains = "path_contains"
    case queryParamEquals = "query_param_equals"
    case titleContains = "title_contains"
    case regex = "regex"

    // Native additions (no browser equivalent).
    case appBundleEquals = "app_bundle_equals"
    case documentPathContains = "document_path_contains"
}

public struct ProjectRule: Identifiable, Hashable, Sendable {
    public var id: String
    public var projectId: String
    /// Optional feature within that project. Must be a feature *of*
    /// `projectId` — a rule that pointed at another project's feature would
    /// silently file time in two places at once.
    public var featureId: String?
    public var name: String

    /// Every condition must match. An empty list never matches, so a rule can
    /// never accidentally claim everything.
    public var conditions: [RuleCondition]

    public var priority: Int
    public var enabled: Bool
    public var defaultTagIds: [String]?
    public var defaultBillable: Bool?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        projectId: String,
        featureId: String? = nil,
        name: String,
        conditions: [RuleCondition],
        priority: Int = 0,
        enabled: Bool = true,
        defaultTagIds: [String]? = nil,
        defaultBillable: Bool? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.featureId = featureId
        self.name = name
        self.conditions = conditions
        self.priority = priority
        self.enabled = enabled
        self.defaultTagIds = defaultTagIds
        self.defaultBillable = defaultBillable
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Convenience for the common single-condition rule.
    public init(
        id: String = UUID().uuidString,
        projectId: String,
        featureId: String? = nil,
        name: String,
        type: ProjectRuleType,
        value: String,
        queryParamName: String? = nil,
        priority: Int = 0,
        enabled: Bool = true,
        defaultTagIds: [String]? = nil,
        defaultBillable: Bool? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.init(
            id: id, projectId: projectId, featureId: featureId, name: name,
            conditions: [RuleCondition(type: type, value: value, queryParamName: queryParamName)],
            priority: priority, enabled: enabled,
            defaultTagIds: defaultTagIds, defaultBillable: defaultBillable,
            createdAt: createdAt, updatedAt: updatedAt
        )
    }

    /// Confidence this rule assigns when it fires.
    public var confidence: Int { conditions.combinedConfidence }

    // Conveniences for the common single-condition rule. They describe the
    // FIRST condition only, so anything that must account for all of them —
    // matching, confidence, display — uses `conditions` directly.
    public var type: ProjectRuleType { conditions.first?.type ?? .appBundleEquals }
    public var value: String { conditions.first?.value ?? "" }
    public var queryParamName: String? { conditions.first?.queryParamName }
    public var isCompound: Bool { conditions.count > 1 }

    /// How this rule reads in the UI, covering every condition.
    public var summary: String { conditions.summary }
}
