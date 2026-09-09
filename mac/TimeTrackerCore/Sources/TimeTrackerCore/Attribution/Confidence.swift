import Foundation

/// Confidence scoring. Deterministic and covered by tests; sessions at or above
/// the review threshold (default 70) skip the Review Needed queue.
///
/// The scale is shared with the learned-suggestion layer so both kinds of
/// evidence are directly comparable in the same precedence chain.
public enum Confidence {
    public static let manual = 100
    public static let override = 100
    public static let urlContains = 95          // a strong URL rule
    public static let queryParam = 90
    public static let documentPath = 85         // a project folder is strong evidence
    public static let urlStartsWith = 80
    public static let regex = 80
    public static let pathContains = 75
    public static let titleContains = 70
    public static let appBundle = 65            // coarse: a whole app
    public static let domain = 60               // coarse: a whole site
    public static let unassigned = 0
}

public extension ProjectRuleType {
    var confidence: Int {
        switch self {
        case .urlContains: return Confidence.urlContains
        case .queryParamEquals: return Confidence.queryParam
        case .documentPathContains: return Confidence.documentPath
        case .urlStartsWith: return Confidence.urlStartsWith
        case .regex: return Confidence.regex
        case .pathContains: return Confidence.pathContains
        case .titleContains: return Confidence.titleContains
        case .appBundleEquals: return Confidence.appBundle
        case .domainEquals: return Confidence.domain
        }
    }

    /// Tie-break order when two enabled rules share a priority: the more
    /// specific rule type wins. Lower index = more specific.
    static let specificityOrder: [ProjectRuleType] = [
        .queryParamEquals,
        .documentPathContains,
        .urlStartsWith,
        .urlContains,
        .pathContains,
        .regex,
        .titleContains,
        .appBundleEquals,
        .domainEquals,
    ]

    var specificityIndex: Int {
        Self.specificityOrder.firstIndex(of: self) ?? Self.specificityOrder.count
    }
}
