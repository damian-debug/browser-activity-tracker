import Foundation

/// How widely a manual project choice applies.
public enum OverrideScope: String, CaseIterable, Hashable, Sendable {
    /// Everything, regardless of app. This is also what a manual timer uses.
    case global
    /// Just the window/document that was focused when the choice was made.
    case currentTarget
    /// Everything in that app (or that domain, when the app is a browser).
    case currentApp
}

public enum OverrideExpiry: String, CaseIterable, Hashable, Sendable {
    case manual
    case thirtyMinutes
    case endOfDay
}

/// A manual "track this as X" instruction that outlives a single session.
public struct ActiveProjectOverride: Hashable, Sendable {
    public var projectId: String
    public var tagIds: [String]
    public var billable: Bool?
    public var scope: OverrideScope
    public var expiry: OverrideExpiry

    /// Set when scope is `.currentTarget`.
    public var target: ActivityIdentity?
    /// Set when scope is `.currentApp`.
    public var bundleID: String?
    /// Set when scope is `.currentApp` and the app is a browser.
    public var domain: String?

    /// True when this override is a manual timer running in
    /// "keep counting while I'm away" mode.
    public var countsWhileAway: Bool

    public var startedAt: Date
    /// Absolute expiry; nil for `.manual`.
    public var expiresAt: Date?

    public init(
        projectId: String,
        tagIds: [String] = [],
        billable: Bool? = nil,
        scope: OverrideScope,
        expiry: OverrideExpiry,
        target: ActivityIdentity? = nil,
        bundleID: String? = nil,
        domain: String? = nil,
        countsWhileAway: Bool = false,
        startedAt: Date = Date(),
        expiresAt: Date? = nil
    ) {
        self.projectId = projectId
        self.tagIds = tagIds
        self.billable = billable
        self.scope = scope
        self.expiry = expiry
        self.target = target
        self.bundleID = bundleID
        self.domain = domain
        self.countsWhileAway = countsWhileAway
        self.startedAt = startedAt
        self.expiresAt = expiresAt
    }
}

public enum OverrideExpiryCalculator {
    /// Absolute expiry instant for an expiry mode. Nil means "until I say so".
    ///
    /// End-of-day is computed in the user's calendar, not UTC — the same
    /// local-vs-UTC trap that produced a real bug in the extension.
    public static func expiresAt(
        _ expiry: OverrideExpiry,
        from now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        switch expiry {
        case .manual:
            return nil
        case .thirtyMinutes:
            return now.addingTimeInterval(30 * 60)
        case .endOfDay:
            return calendar.date(
                bySettingHour: 23, minute: 59, second: 59, of: now
            ).map { $0.addingTimeInterval(0.999) }
        }
    }
}
