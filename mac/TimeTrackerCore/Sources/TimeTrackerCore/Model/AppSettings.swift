import Foundation

public struct AppSettings: Hashable, Sendable {
    /// Stop counting after this much inactivity.
    public var idleThresholdSeconds: Int

    /// Sessions assigned below this confidence (or unassigned/unreviewed)
    /// surface in Review Needed.
    public var reviewConfidenceThreshold: Int

    /// Never tracked.
    public var excludedDomains: [String]
    public var excludedAppBundleIDs: [String]

    /// Discard sessions shorter than this — window flickers, app switches
    /// passed through on the way somewhere else.
    public var minimumSessionSeconds: Int

    /// On wake, a gap longer than this is treated as the machine having slept
    /// rather than the user having worked, and is not credited.
    public var maximumCreditedGapSeconds: Int

    public init(
        idleThresholdSeconds: Int = 60,
        reviewConfidenceThreshold: Int = 70,
        excludedDomains: [String] = ["localhost", "127.0.0.1", "0.0.0.0"],
        excludedAppBundleIDs: [String] = [],
        minimumSessionSeconds: Int = 2,
        maximumCreditedGapSeconds: Int = 150
    ) {
        self.idleThresholdSeconds = idleThresholdSeconds
        self.reviewConfidenceThreshold = reviewConfidenceThreshold
        self.excludedDomains = excludedDomains
        self.excludedAppBundleIDs = excludedAppBundleIDs
        self.minimumSessionSeconds = minimumSessionSeconds
        self.maximumCreditedGapSeconds = maximumCreditedGapSeconds
    }

    public static let `default` = AppSettings()

    /// Tags seeded once, on first run only.
    public static let defaultTagNames = [
        "Development", "Design", "QA", "Bug Fix", "Research",
        "Planning", "Admin", "Support", "Content", "Client Work",
    ]

    public func excludes(_ snapshot: ActivitySnapshot) -> Bool {
        if excludedAppBundleIDs.contains(where: {
            $0.caseInsensitiveCompare(snapshot.bundleID) == .orderedSame
        }) { return true }

        if let domain = snapshot.domain {
            let lower = domain.lowercased()
            if excludedDomains.contains(where: {
                let ex = $0.lowercased()
                return lower == ex || lower.hasSuffix("." + ex)
            }) { return true }
        }
        return false
    }
}
