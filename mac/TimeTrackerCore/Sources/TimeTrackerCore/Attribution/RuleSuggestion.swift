import Foundation

/// Turning "this is Acme" into "everything like this is Acme".
///
/// The bridge from a learned pattern or a one-off correction to an explicit,
/// auditable rule the user controls. A rule is better than a learned
/// association wherever the user is sure: it is visible, editable, and never
/// drifts.
public struct RuleSuggestion: Hashable, Sendable, Identifiable {
    public var label: String
    public var type: ProjectRuleType
    public var value: String
    public var queryParamName: String?

    public var id: String { "\(type.rawValue):\(value):\(queryParamName ?? "")" }

    public init(
        label: String, type: ProjectRuleType, value: String, queryParamName: String? = nil
    ) {
        self.label = label
        self.type = type
        self.value = value
        self.queryParamName = queryParamName
    }

    /// Confidence this rule would assign, so the UI can show what it buys.
    public var confidence: Int { type.confidence }
}

public enum RuleSuggester {
    /// Rules that would have caught this session, most specific first.
    ///
    /// Ordered so the safest choice is the default: pinning one Figma file is
    /// far less likely to swallow unrelated work than claiming a whole domain.
    public static func suggestions(for session: Session) -> [RuleSuggestion] {
        var suggestions: [RuleSuggestion] = []

        // A parser-detected entity is the most precise thing available.
        if let service = session.service, let entityId = session.detectedEntityId {
            switch service {
            case "bubble":
                if let url = session.url, URLish.queryValue(url, name: "id") == entityId {
                    suggestions.append(RuleSuggestion(
                        label: "The Bubble app “\(session.detectedEntityName ?? entityId)”",
                        type: .queryParamEquals, value: entityId, queryParamName: "id"
                    ))
                }
            case "figma":
                if let url = session.url, let path = URLish.path(url) {
                    let segments = path.split(separator: "/", omittingEmptySubsequences: false)
                    if segments.count >= 3 {
                        suggestions.append(RuleSuggestion(
                            label: "The Figma file “\(session.detectedEntityName ?? entityId)”",
                            type: .urlContains,
                            value: "figma.com/\(segments[1])/\(segments[2])"
                        ))
                    }
                }
            default:
                break
            }
        }

        // The folder a document lives in is usually exactly the project.
        if let documentPath = session.documentPath {
            let folder = URL(fileURLWithPath: documentPath).deletingLastPathComponent().path
            if folder.count > 1 {
                suggestions.append(RuleSuggestion(
                    label: "Anything in \(URL(fileURLWithPath: folder).lastPathComponent)",
                    type: .documentPathContains, value: folder + "/"
                ))
            }
        }

        if let url = session.url {
            suggestions.append(RuleSuggestion(
                label: "Only this exact page", type: .urlStartsWith, value: url
            ))

            if let path = URLish.path(url) {
                let firstSegment = path.split(separator: "/").first
                if let firstSegment, !firstSegment.isEmpty {
                    suggestions.append(RuleSuggestion(
                        label: "Any page under /\(firstSegment)",
                        type: .pathContains, value: "/\(firstSegment)"
                    ))
                }
            }
        }

        if let domain = session.domain, !domain.isEmpty {
            suggestions.append(RuleSuggestion(
                label: "Everything on \(domain)", type: .domainEquals, value: domain
            ))
        }

        // Broadest, and last: claiming a whole app will catch unrelated work.
        suggestions.append(RuleSuggestion(
            label: "Everything in \(session.appName)",
            type: .appBundleEquals, value: session.appBundleID
        ))

        if let title = session.windowTitle, !title.isEmpty {
            suggestions.append(RuleSuggestion(
                label: "Windows titled “\(title.prefix(40))”",
                type: .titleContains, value: title
            ))
        }

        return suggestions
    }

    /// Build a rule from a chosen suggestion.
    public static func rule(
        from suggestion: RuleSuggestion,
        projectId: String,
        projectName: String,
        featureId: String? = nil,
        featureName: String? = nil,
        now: Date = Date()
    ) -> ProjectRule {
        let target = featureName.map { "\(projectName) › \($0)" } ?? projectName
        return ProjectRule(
            projectId: projectId,
            featureId: featureId,
            name: "\(target): \(suggestion.label)",
            type: suggestion.type,
            value: suggestion.value,
            queryParamName: suggestion.queryParamName,
            createdAt: now,
            updatedAt: now
        )
    }
}

public enum RuleBackfill {
    /// Sessions a newly created rule should claim retroactively.
    ///
    /// Only unassigned, unreviewed sessions are eligible: a manual decision or
    /// an explicit review always outranks a rule written afterwards.
    public static func sessionsToUpdate(
        matching rule: ProjectRule, in sessions: [Session]
    ) -> [Session] {
        sessions.filter { session in
            guard session.projectId == nil, !session.reviewed else { return false }
            return RuleEngine.run(context(for: session), rules: [rule]).projectId != nil
        }
    }

    /// Apply the rule to a session, as the tracker would have at the time.
    public static func applied(
        _ rule: ProjectRule, to session: Session,
        projectName: String?, featureName: String? = nil, now: Date = Date()
    ) -> Session {
        var updated = session
        updated.projectId = rule.projectId
        updated.projectName = projectName
        updated.featureId = rule.featureId
        updated.featureName = featureName
        updated.assignmentSource = .autoRule
        updated.assignmentConfidence = rule.type.confidence
        updated.matchedRuleId = rule.id
        if let tagIds = rule.defaultTagIds { updated.tagIds = tagIds }
        if let billable = rule.defaultBillable { updated.billable = billable }
        // Creating the rule from this work is itself the review.
        updated.reviewed = true
        updated.updatedAt = now
        return updated
    }

    /// The matcher's view of a stored session, so a candidate rule can be
    /// tested against history before it is saved.
    public static func context(for session: Session) -> RuleMatchContext {
        RuleMatchContext(
            appBundleID: session.appBundleID,
            appName: session.appName,
            title: session.windowTitle ?? session.title,
            url: session.url,
            domain: session.domain,
            documentPath: session.documentPath,
            service: session.service,
            detectedEntityId: session.detectedEntityId,
            detectedEntityName: session.detectedEntityName
        )
    }
}
