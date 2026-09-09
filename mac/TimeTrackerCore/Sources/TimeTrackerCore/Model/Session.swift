import Foundation

/// A completed, stored unit of tracked time.
///
/// Modelling note carried over from the extension's V2 migration, and still the
/// most important distinction in the schema:
///   - `service` / `detectedEntity*` = what the thing IS (parser output)
///   - `projectId` / `projectName`   = what the time BELONGS to (user attribution)
/// V1 conflated these and it caused real pain. Keep them apart.
public struct Session: Identifiable, Hashable, Sendable {
    public var id: String

    // ── What was being used ──────────────────────────────────────────────
    // Native app fields. `appBundleID` is the only signal always available
    // (no permission required), so it is non-optional; everything else
    // depends on granted permissions and degrades to nil.
    public var appBundleID: String
    public var appName: String
    public var windowTitle: String?
    public var documentPath: String?
    /// Branch checked out in the document's repository at the time.
    /// Stored because, unlike a ticket key, it cannot be recovered from the
    /// URL or title afterwards — and it is the strongest signal there is for
    /// which piece of code work this was.
    public var gitBranch: String?

    // Browser fields. Nil for native-app sessions.
    public var url: String?
    public var domain: String?
    public var title: String

    // ── What the page/document IS (parser output) ────────────────────────
    public var service: String?
    public var detectedEntityId: String?
    public var detectedEntityName: String?

    // ── What the time BELONGS to (attribution) ───────────────────────────
    public var projectId: String?
    public var projectName: String?

    /// The feature within that project, when known.
    ///
    /// Additive on purpose: `projectId` still holds the top-level project, so
    /// existing totals, rules and exports are unaffected and a feature is
    /// always a refinement rather than a replacement.
    public var featureId: String?
    public var featureName: String?

    public var assignmentSource: AssignmentSource
    public var assignmentConfidence: Int
    public var matchedRuleId: String?

    public var tagIds: [String]
    public var notes: String?
    public var billable: Bool
    public var reviewed: Bool

    /// True when this time came from a manual timer running in
    /// "keep going while I'm away" mode, so away-time never silently inflates
    /// desk-work totals in reports.
    public var countedWhileAway: Bool

    public var startTime: Date
    public var endTime: Date
    public var durationSeconds: Int

    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        appBundleID: String,
        appName: String,
        windowTitle: String? = nil,
        documentPath: String? = nil,
        gitBranch: String? = nil,
        url: String? = nil,
        domain: String? = nil,
        title: String = "",
        service: String? = nil,
        detectedEntityId: String? = nil,
        detectedEntityName: String? = nil,
        projectId: String? = nil,
        projectName: String? = nil,
        featureId: String? = nil,
        featureName: String? = nil,
        assignmentSource: AssignmentSource = .unassigned,
        assignmentConfidence: Int = 0,
        matchedRuleId: String? = nil,
        tagIds: [String] = [],
        notes: String? = nil,
        billable: Bool = false,
        reviewed: Bool = false,
        countedWhileAway: Bool = false,
        startTime: Date,
        endTime: Date,
        durationSeconds: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.appBundleID = appBundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.documentPath = documentPath
        self.gitBranch = gitBranch
        self.url = url
        self.domain = domain
        self.title = title
        self.service = service
        self.detectedEntityId = detectedEntityId
        self.detectedEntityName = detectedEntityName
        self.projectId = projectId
        self.projectName = projectName
        self.featureId = featureId
        self.featureName = featureName
        self.assignmentSource = assignmentSource
        self.assignmentConfidence = assignmentConfidence
        self.matchedRuleId = matchedRuleId
        self.tagIds = tagIds
        self.notes = notes
        self.billable = billable
        self.reviewed = reviewed
        self.countedWhileAway = countedWhileAway
        self.startTime = startTime
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
