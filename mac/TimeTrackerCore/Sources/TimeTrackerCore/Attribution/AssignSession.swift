import Foundation

/// Full attribution order:
///   active override → rule engine → (learned suggestion, Phase 3) → unassigned
///
/// Parser/entity matches are expressed *through* rules (e.g. a query-param rule
/// pinning a Bubble app), so the rule engine covers them; parsers only supply
/// the detected-entity metadata.
public enum SessionAssigner {
    public static func isOverrideActive(
        _ override: ActiveProjectOverride?,
        for snapshot: ActivitySnapshot,
        now: Date = Date()
    ) -> Bool {
        guard let override else { return false }
        if let expiresAt = override.expiresAt, now > expiresAt { return false }

        switch override.scope {
        case .global:
            return true

        case .currentApp:
            // For a browser we scope by site, so switching tabs within the same
            // site keeps the override but navigating elsewhere drops it.
            if let overrideDomain = override.domain {
                return overrideDomain == snapshot.domain
            }
            return override.bundleID == snapshot.bundleID

        case .currentTarget:
            guard let target = override.target else { return false }
            return target.matches(snapshot)
        }
    }

    public static func assign(
        _ snapshot: ActivitySnapshot,
        rules: [ProjectRule],
        override: ActiveProjectOverride?,
        now: Date = Date()
    ) -> RuleEngineResult {
        if let override, isOverrideActive(override, for: snapshot, now: now) {
            return RuleEngineResult(
                projectId: override.projectId,
                assignmentSource: .activeProjectOverride,
                assignmentConfidence: Confidence.override,
                defaultTagIds: override.tagIds.isEmpty ? nil : override.tagIds,
                billable: override.billable
            )
        }

        return RuleEngine.run(RuleMatchContext(snapshot), rules: rules)
    }
}
