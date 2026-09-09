import Foundation

public struct AppSummary: Hashable, Sendable, Identifiable {
    public var bundleID: String
    public var appName: String
    public var totalSeconds: Int
    public var sessionCount: Int
    public var id: String { bundleID }
}

public struct DomainSummary: Hashable, Sendable, Identifiable {
    public var domain: String
    public var service: String?
    public var totalSeconds: Int
    public var sessionCount: Int
    public var id: String { domain }
}

/// A specific Figma file, Bubble app, or other parser-detected thing.
public struct EntitySummary: Hashable, Sendable, Identifiable {
    public var service: String
    public var entityId: String
    public var entityName: String?
    public var totalSeconds: Int
    public var sessionCount: Int
    public var lastSeen: Date
    public var id: String { "\(service)::\(entityId)" }
}

public struct ProjectTotal: Hashable, Sendable, Identifiable {
    /// Nil is the Unassigned bucket.
    public var projectId: String?
    public var projectName: String
    public var clientName: String?
    public var color: String?
    public var totalSeconds: Int
    public var billableSeconds: Int
    public var nonBillableSeconds: Int
    public var sessionCount: Int
    public var tagIds: [String]
    public var id: String { projectId ?? "__unassigned__" }
}

public struct TagTotal: Hashable, Sendable, Identifiable {
    public var tagId: String
    public var tagName: String
    public var color: String?
    public var totalSeconds: Int
    public var sessionCount: Int
    public var id: String { tagId }
}

public struct DashboardStats: Hashable, Sendable {
    public var totalActiveSeconds: Int
    public var billableSeconds: Int
    public var unassignedSeconds: Int
    public var awaySeconds: Int
    public var needsReviewSeconds: Int
    public var needsReviewCount: Int
    public var sessionCount: Int

    public var apps: [AppSummary]
    public var domains: [DomainSummary]
    public var entities: [EntitySummary]
    public var projectTotals: [ProjectTotal]
    public var tagTotals: [TagTotal]

    public static let empty = DashboardStats(
        totalActiveSeconds: 0, billableSeconds: 0, unassignedSeconds: 0, awaySeconds: 0,
        needsReviewSeconds: 0, needsReviewCount: 0, sessionCount: 0,
        apps: [], domains: [], entities: [], projectTotals: [], tagTotals: []
    )
}
