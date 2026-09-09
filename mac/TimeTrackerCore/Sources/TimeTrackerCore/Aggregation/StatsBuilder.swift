import Foundation

public enum StatsBuilder {
    /// Whether a session should surface in Review Needed.
    ///
    /// An explicit human decision (`reviewed`) always wins; otherwise anything
    /// unassigned or below the confidence threshold needs a look.
    public static func needsReview(_ session: Session, threshold: Int) -> Bool {
        if session.reviewed { return false }
        return session.projectId == nil
            || session.assignmentSource == .unassigned
            || session.assignmentConfidence < threshold
    }

    /// Single pass over the sessions, building every breakdown at once.
    /// Pure: hand it rows, get totals. The store decides which rows.
    public static func build(
        sessions: [Session],
        projects: [Project] = [],
        tags: [Tag] = [],
        threshold: Int = AppSettings.default.reviewConfidenceThreshold
    ) -> DashboardStats {
        let projectsById = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let tagsById = Dictionary(tags.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var stats = DashboardStats.empty
        stats.sessionCount = sessions.count

        var apps: [String: AppSummary] = [:]
        var domains: [String: DomainSummary] = [:]
        var entities: [String: EntitySummary] = [:]
        var projectTotals: [String: ProjectTotal] = [:]
        var featureTotals: [String: FeatureTotal] = [:]
        var tagTotals: [String: TagTotal] = [:]

        for session in sessions {
            let seconds = session.durationSeconds
            stats.totalActiveSeconds += seconds
            if session.billable { stats.billableSeconds += seconds }
            if session.projectId == nil { stats.unassignedSeconds += seconds }
            if session.countedWhileAway { stats.awaySeconds += seconds }
            if needsReview(session, threshold: threshold) {
                stats.needsReviewSeconds += seconds
                stats.needsReviewCount += 1
            }

            // Apps
            apps[session.appBundleID, default: AppSummary(
                bundleID: session.appBundleID, appName: session.appName,
                totalSeconds: 0, sessionCount: 0
            )].add(seconds)

            // Domains (browser sessions only)
            if let domain = session.domain, !domain.isEmpty {
                if domains[domain] == nil {
                    domains[domain] = DomainSummary(
                        domain: domain, service: session.service,
                        totalSeconds: 0, sessionCount: 0
                    )
                }
                domains[domain]?.totalSeconds += seconds
                domains[domain]?.sessionCount += 1
            }

            // Detected entities
            if let service = session.service, let entityId = session.detectedEntityId {
                let key = "\(service)::\(entityId)"
                if entities[key] == nil {
                    entities[key] = EntitySummary(
                        service: service, entityId: entityId,
                        entityName: session.detectedEntityName,
                        totalSeconds: 0, sessionCount: 0, lastSeen: session.endTime
                    )
                }
                entities[key]?.totalSeconds += seconds
                entities[key]?.sessionCount += 1
                if session.endTime > (entities[key]?.lastSeen ?? .distantPast) {
                    entities[key]?.lastSeen = session.endTime
                }
                if entities[key]?.entityName == nil {
                    entities[key]?.entityName = session.detectedEntityName
                }
            }

            // Project totals, with a bucket for unassigned time
            let projectKey = session.projectId ?? "__unassigned__"
            if projectTotals[projectKey] == nil {
                let project = session.projectId.flatMap { projectsById[$0] }
                projectTotals[projectKey] = ProjectTotal(
                    projectId: session.projectId,
                    projectName: session.projectId == nil
                        ? "Unassigned"
                        : (project?.name ?? session.projectName ?? "Unknown project"),
                    clientName: project?.clientName,
                    color: project?.color,
                    totalSeconds: 0, billableSeconds: 0, nonBillableSeconds: 0,
                    sessionCount: 0, tagIds: []
                )
            }
            projectTotals[projectKey]?.totalSeconds += seconds
            projectTotals[projectKey]?.sessionCount += 1
            if session.billable {
                projectTotals[projectKey]?.billableSeconds += seconds
            } else {
                projectTotals[projectKey]?.nonBillableSeconds += seconds
            }
            for tagId in session.tagIds where !(projectTotals[projectKey]?.tagIds.contains(tagId) ?? true) {
                projectTotals[projectKey]?.tagIds.append(tagId)
            }

            // Feature totals. These roll up *inside* a project rather than
            // alongside it, so project figures stay whole however the work is
            // broken down.
            if let featureId = session.featureId {
                if featureTotals[featureId] == nil {
                    let feature = projectsById[featureId]
                    featureTotals[featureId] = FeatureTotal(
                        featureId: featureId,
                        featureName: feature?.name ?? session.featureName ?? "Unknown feature",
                        projectId: session.projectId,
                        projectName: session.projectId.flatMap { projectsById[$0]?.name }
                            ?? session.projectName ?? "Unassigned",
                        totalSeconds: 0, billableSeconds: 0, sessionCount: 0
                    )
                }
                featureTotals[featureId]?.totalSeconds += seconds
                featureTotals[featureId]?.sessionCount += 1
                if session.billable { featureTotals[featureId]?.billableSeconds += seconds }
            }

            // Tag totals — a session with N tags counts toward each of them, so
            // these deliberately sum to more than the total.
            for tagId in session.tagIds {
                if tagTotals[tagId] == nil {
                    tagTotals[tagId] = TagTotal(
                        tagId: tagId, tagName: tagsById[tagId]?.name ?? "Unknown tag",
                        color: tagsById[tagId]?.color, totalSeconds: 0, sessionCount: 0
                    )
                }
                tagTotals[tagId]?.totalSeconds += seconds
                tagTotals[tagId]?.sessionCount += 1
            }
        }

        let byTime: (Int, Int) -> Bool = { $0 > $1 }
        stats.apps = apps.values.sorted { byTime($0.totalSeconds, $1.totalSeconds) }
        stats.domains = domains.values.sorted { byTime($0.totalSeconds, $1.totalSeconds) }
        stats.entities = entities.values.sorted { byTime($0.totalSeconds, $1.totalSeconds) }
        stats.projectTotals = projectTotals.values.sorted { byTime($0.totalSeconds, $1.totalSeconds) }
        stats.featureTotals = featureTotals.values.sorted { byTime($0.totalSeconds, $1.totalSeconds) }
        stats.tagTotals = tagTotals.values.sorted { byTime($0.totalSeconds, $1.totalSeconds) }
        return stats
    }
}

private extension AppSummary {
    mutating func add(_ seconds: Int) {
        totalSeconds += seconds
        sessionCount += 1
    }
}
