import Foundation

/// Everything a rule can be matched against, assembled from one activity
/// snapshot. Browser fields are nil for native-app activity, and every matcher
/// that needs them fails closed rather than throwing.
public struct RuleMatchContext: Hashable, Sendable {
    public var appBundleID: String
    public var appName: String
    public var title: String
    public var url: String?
    public var domain: String?
    public var documentPath: String?
    public var service: String?
    public var detectedEntityId: String?
    public var detectedEntityName: String?

    public init(
        appBundleID: String,
        appName: String = "",
        title: String = "",
        url: String? = nil,
        domain: String? = nil,
        documentPath: String? = nil,
        service: String? = nil,
        detectedEntityId: String? = nil,
        detectedEntityName: String? = nil
    ) {
        self.appBundleID = appBundleID
        self.appName = appName
        self.title = title
        self.url = url
        self.domain = domain
        self.documentPath = documentPath
        self.service = service
        self.detectedEntityId = detectedEntityId
        self.detectedEntityName = detectedEntityName
    }

    public init(_ snapshot: ActivitySnapshot) {
        let parsed = snapshot.parsed
        self.init(
            appBundleID: snapshot.bundleID,
            appName: snapshot.appName,
            title: snapshot.windowTitle ?? "",
            url: snapshot.url,
            domain: snapshot.domain,
            documentPath: snapshot.documentPath,
            service: parsed?.service,
            detectedEntityId: parsed?.entityId,
            detectedEntityName: parsed?.entityName
        )
    }
}

public struct RuleEngineResult: Hashable, Sendable {
    public var projectId: String?
    public var matchedRuleId: String?
    public var assignmentSource: AssignmentSource
    public var assignmentConfidence: Int
    public var defaultTagIds: [String]?
    public var billable: Bool?

    public init(
        projectId: String? = nil,
        matchedRuleId: String? = nil,
        assignmentSource: AssignmentSource,
        assignmentConfidence: Int,
        defaultTagIds: [String]? = nil,
        billable: Bool? = nil
    ) {
        self.projectId = projectId
        self.matchedRuleId = matchedRuleId
        self.assignmentSource = assignmentSource
        self.assignmentConfidence = assignmentConfidence
        self.defaultTagIds = defaultTagIds
        self.billable = billable
    }

    public static let unassigned = RuleEngineResult(
        assignmentSource: .unassigned,
        assignmentConfidence: Confidence.unassigned
    )
}

public enum RuleEngine {
    /// Pure and deterministic: highest priority wins; ties break by rule-type
    /// specificity; remaining ties break by id so the outcome is stable.
    public static func run(_ context: RuleMatchContext, rules: [ProjectRule]) -> RuleEngineResult {
        let candidates = rules
            .filter(\.enabled)
            .sorted { a, b in
                if a.priority != b.priority { return a.priority > b.priority }
                if a.type.specificityIndex != b.type.specificityIndex {
                    return a.type.specificityIndex < b.type.specificityIndex
                }
                return a.id < b.id
            }

        for rule in candidates where matches(rule, context) {
            return RuleEngineResult(
                projectId: rule.projectId,
                matchedRuleId: rule.id,
                assignmentSource: .autoRule,
                assignmentConfidence: rule.type.confidence,
                defaultTagIds: rule.defaultTagIds,
                billable: rule.defaultBillable
            )
        }

        return .unassigned
    }

    static func matches(_ rule: ProjectRule, _ context: RuleMatchContext) -> Bool {
        let value = rule.value
        guard !value.isEmpty else { return false }

        switch rule.type {
        case .domainEquals:
            guard let domain = context.domain else { return false }
            var expected = value.lowercased()
            if expected.hasPrefix("www.") { expected = String(expected.dropFirst(4)) }
            return domain.lowercased() == expected

        case .urlContains:
            guard let url = context.url else { return false }
            return url.range(of: value, options: .caseInsensitive) != nil

        case .urlStartsWith:
            guard let url = context.url else { return false }
            return url.lowercased().hasPrefix(value.lowercased())

        case .pathContains:
            guard let url = context.url, let path = URLish.path(url) else { return false }
            return path.range(of: value, options: .caseInsensitive) != nil

        case .queryParamEquals:
            guard let url = context.url,
                  let name = rule.queryParamName, !name.isEmpty,
                  let actual = URLish.queryValue(url, name: name)
            else { return false }
            return actual == value

        case .titleContains:
            return context.title.range(of: value, options: .caseInsensitive) != nil

        case .regex:
            guard let url = context.url else { return false }
            // An invalid user-supplied pattern must never match, and must never
            // throw inside the tracker.
            guard let regex = try? NSRegularExpression(pattern: value) else { return false }
            let range = NSRange(url.startIndex..., in: url)
            return regex.firstMatch(in: url, range: range) != nil

        case .appBundleEquals:
            return context.appBundleID.caseInsensitiveCompare(value) == .orderedSame

        case .documentPathContains:
            guard let path = context.documentPath else { return false }
            return path.range(of: value, options: .caseInsensitive) != nil
        }
    }
}
