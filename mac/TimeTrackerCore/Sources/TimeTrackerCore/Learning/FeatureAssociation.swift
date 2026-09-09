import Foundation

/// How strongly one feature has pointed at one project, so far.
///
/// `mass` is decayed lazily: it is only correct as of `lastUpdated`, and every
/// reader ages it forward. That avoids any background sweep — the model has no
/// moving parts beyond the rows themselves.
public struct FeatureAssociation: Hashable, Sendable, Codable {
    public var feature: String
    public var projectId: String
    public var mass: Double
    public var observations: Int
    public var lastUpdated: Date

    public init(
        feature: String,
        projectId: String,
        mass: Double,
        observations: Int,
        lastUpdated: Date
    ) {
        self.feature = feature
        self.projectId = projectId
        self.mass = mass
        self.observations = observations
        self.lastUpdated = lastUpdated
    }
}

/// One thing to record about an activity that has been attributed.
public struct FeatureObservation: Hashable, Sendable {
    public var feature: String
    public var projectId: String
    /// Negative for a correction — the user moved this time somewhere else.
    public var weight: Double
    public var at: Date

    public init(feature: String, projectId: String, weight: Double, at: Date) {
        self.feature = feature
        self.projectId = projectId
        self.weight = weight
        self.at = at
    }
}

/// Why a suggestion was made, in terms a person can check.
public struct SuggestionEvidence: Hashable, Sendable {
    public var feature: ActivityFeature
    public var observations: Int
    public var lastSeen: Date
    /// How exclusively this feature has pointed at the suggested project, 0–1.
    public var purity: Double
    /// This feature's share of the final score.
    public var contribution: Double

    public init(
        feature: ActivityFeature, observations: Int, lastSeen: Date,
        purity: Double, contribution: Double
    ) {
        self.feature = feature
        self.observations = observations
        self.lastSeen = lastSeen
        self.purity = purity
        self.contribution = contribution
    }
}

public struct LearnedSuggestion: Hashable, Sendable {
    public var projectId: String
    /// 0–100, on the same scale as the hand-written rule confidences.
    public var confidence: Int
    public var evidence: [SuggestionEvidence]

    public init(projectId: String, confidence: Int, evidence: [SuggestionEvidence]) {
        self.projectId = projectId
        self.confidence = confidence
        self.evidence = evidence
    }

    /// One sentence explaining the suggestion, for the UI.
    ///
    /// A model that cannot justify itself has no business assigning billable
    /// time, so this is part of the result rather than an afterthought.
    public func explanation(projectName: String, now: Date = Date()) -> String {
        guard let top = evidence.first else {
            return "Suggested \(projectName)."
        }
        let times = top.observations == 1 ? "once" : "\(top.observations) times"
        return "\(projectName), because \(top.feature.describedSubject) has gone to "
            + "\(projectName) \(times) (last \(Self.relative(top.lastSeen, now: now)))."
    }

    static func relative(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
