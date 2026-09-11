import Foundation

/// Turning "this is Acme" into "everything like this is Acme".
///
/// The bridge from a learned pattern or a one-off correction to an explicit,
/// auditable rule the user controls. A rule is better than a learned
/// association wherever the user is sure: it is visible, editable, and never
/// drifts.
public struct RuleSuggestion: Hashable, Sendable, Identifiable {
    public var label: String
    public var conditions: [RuleCondition]

    public var id: String {
        conditions.map { "\($0.type.rawValue):\($0.value):\($0.queryParamName ?? "")" }
            .joined(separator: "&")
    }

    public init(label: String, conditions: [RuleCondition]) {
        self.label = label
        self.conditions = conditions
    }

    public init(
        label: String, type: ProjectRuleType, value: String, queryParamName: String? = nil
    ) {
        self.init(
            label: label,
            conditions: [RuleCondition(type: type, value: value, queryParamName: queryParamName)]
        )
    }

    /// Confidence this rule would assign, so the UI can show what it buys.
    public var confidence: Int { conditions.combinedConfidence }

    // Conveniences for the single-condition case; see ProjectRule.
    public var type: ProjectRuleType { conditions.first?.type ?? .appBundleEquals }
    public var value: String { conditions.first?.value ?? "" }
    public var queryParamName: String? { conditions.first?.queryParamName }
    public var isCompound: Bool { conditions.count > 1 }
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
            // Narrower still: one screen or frame within it. The only way to
            // give a screen its own feature, since titles never name it.
            if let screen = screenCondition(for: session, service: service) {
                let label = service == "bubble"
                    ? "The “\(ParserRegistry.parse(session.url ?? "")?.subEntityId ?? "")” page of \(entityId)"
                    : "This screen of “\(session.detectedEntityName ?? entityId)”"
                suggestions.append(RuleSuggestion(
                    label: label,
                    conditions: [entityCondition(service: service, entityId: entityId), screen]
                ))
            }

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
            case "framer":
                // The id alone: the name before it changes when the project
                // is renamed, and a suffix after it comes and goes.
                if let url = session.url, URLish.extractDomain(url)?.hasSuffix("framer.com") == true {
                    suggestions.append(RuleSuggestion(
                        label: "The Framer project “\(session.detectedEntityName ?? entityId)”",
                        type: .urlContains, value: entityId
                    ))
                }
            default:
                break
            }
        }

        // The folder a document lives in is usually exactly the project.
        if let documentPath = session.documentPath {
            let folder = WorkSignals.folder(ofDocument: documentPath)
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

        // An app plus something from its window is the combination that makes
        // shared tools workable: Slack is not a project, but Slack and a
        // channel name is. Offered above the whole-app option, which would
        // swallow every other project's conversations.
        if let title = session.windowTitle,
           let distinctive = distinctiveTitleWord(title, appName: session.appName) {
            suggestions.append(RuleSuggestion(
                label: "\(session.appName), when the title mentions “\(distinctive)”",
                conditions: [
                    RuleCondition(type: .appBundleEquals, value: session.appBundleID),
                    RuleCondition(type: .titleContains, value: distinctive),
                ]
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

    /// The most project-like word in a window title.
    ///
    /// Picks the longest word that is not the app's own name and not generic
    /// chrome, on the grounds that a channel or client name is usually the
    /// longest distinctive thing in "Slack | #acme-internal | Acme Corp".
    /// The condition that pins a session to one screen within its entity, if
    /// its URL carries one: a Figma frame, a Framer node, a page of a Framer
    /// site. A site's home page is not offered — it would match every page.
    static func screenCondition(for session: Session, service: String) -> RuleCondition? {
        guard let url = session.url,
              let screen = ParserRegistry.parse(url)?.subEntityId
        else { return nil }
        switch service {
        case "bubble":
            return RuleCondition(type: .queryParamEquals, value: screen, queryParamName: "name")
        case "figma":
            return RuleCondition(type: .queryParamEquals, value: screen, queryParamName: "node-id")
        case "framer" where URLish.queryValue(url, name: "node") == screen:
            return RuleCondition(type: .queryParamEquals, value: screen, queryParamName: "node")
        case "framer" where screen != "/":
            return RuleCondition(type: .pathContains, value: screen)
        default:
            return nil
        }
    }

    /// Pins the entity itself. Bubble's app id is a query parameter and short
    /// enough to appear inside another app's id ("meltx" in "meltx-dev"), so
    /// it is matched exactly; elsewhere the id is long and random enough that
    /// appearing in the URL is proof.
    static func entityCondition(service: String, entityId: String) -> RuleCondition {
        service == "bubble"
            ? RuleCondition(type: .queryParamEquals, value: entityId, queryParamName: "id")
            : RuleCondition(type: .urlContains, value: entityId)
    }

    static func distinctiveTitleWord(_ title: String, appName: String) -> String? {
        let appWords = Set(
            appName.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        )
        let noise: Set<String> = ["the", "and", "for", "new", "tab", "untitled", "home", "inbox"]

        let candidates = title
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "-_")) }
            .filter { word in
                let lower = word.lowercased()
                return word.count >= 4
                    && !appWords.contains(lower)
                    && !noise.contains(lower)
                    && !word.allSatisfy(\.isNumber)
            }

        return candidates.max { $0.count < $1.count }
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
            conditions: suggestion.conditions,
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
        updated.assignmentConfidence = rule.confidence
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
