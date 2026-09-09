import Foundation

/// Decides whether two observations are "the same work", which is what governs
/// whether a session continues or a new one begins.
///
/// The rule: **compare the strongest signal that BOTH sides actually have.**
/// A session may only end on positive evidence that the activity changed, never
/// on the mere absence of a signal.
///
/// That distinction is load-bearing. Signal availability fluctuates constantly:
/// Accessibility gets granted mid-session, an AX query times out, a browser
/// URL read fails once. Treating "I can't see the title right now" the same as
/// "the title changed" would fragment one hour of work into a hundred slivers,
/// which is the exact failure this type exists to prevent.
public struct ActivityIdentity: Hashable, Sendable, Codable {
    public let bundleID: String
    public let entityKey: String?
    public let documentPath: String?
    public let url: String?
    public let windowTitle: String?

    public init(
        bundleID: String,
        entityKey: String? = nil,
        documentPath: String? = nil,
        url: String? = nil,
        windowTitle: String? = nil
    ) {
        self.bundleID = bundleID
        self.entityKey = entityKey
        self.documentPath = documentPath
        self.url = url
        self.windowTitle = windowTitle
    }

    public init(_ snapshot: ActivitySnapshot) {
        self.bundleID = snapshot.bundleID
        self.entityKey = snapshot.parsed.map { "\($0.service)::\($0.entityId)" }
        self.documentPath = snapshot.documentPath?.isEmpty == false ? snapshot.documentPath : nil
        self.url = snapshot.url?.isEmpty == false ? snapshot.url : nil
        self.windowTitle = snapshot.windowTitle?.isEmpty == false ? snapshot.windowTitle : nil
    }

    /// Whether `other` is a continuation of this activity.
    public func continues(_ other: ActivityIdentity) -> Bool {
        // A different app is always different work.
        guard bundleID == other.bundleID else { return false }

        // Strongest → weakest. The first signal present on both sides decides,
        // so a stable document keeps the session alive through title churn, and
        // a changed entity ends it even when the title happens to match.
        if let a = entityKey, let b = other.entityKey { return a == b }
        if let a = documentPath, let b = other.documentPath { return a == b }
        if let a = url, let b = other.url { return a == b }
        if let a = windowTitle, let b = other.windowTitle { return a == b }

        // Nothing comparable beyond the app itself: same app, same session.
        return true
    }
}

public extension ActivitySnapshot {
    var identity: ActivityIdentity { ActivityIdentity(self) }

    /// Fill in details this snapshot is missing from one we already had.
    /// A signal we cannot currently read must never erase what we already know.
    func enriched(from previous: ActivitySnapshot) -> ActivitySnapshot {
        var merged = self
        merged.windowTitle = windowTitle ?? previous.windowTitle
        merged.url = url ?? previous.url
        merged.documentPath = documentPath ?? previous.documentPath
        merged.gitBranch = gitBranch ?? previous.gitBranch
        return merged
    }
}
