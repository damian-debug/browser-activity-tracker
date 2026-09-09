import Foundation

/// Suggests a project for an activity, from what has been assigned before.
///
/// Deliberately not machine learning in the heavyweight sense: no model file,
/// no training step, no opaque weights. It is a table of "this feature has
/// pointed at that project, this often, this recently", which can be read,
/// explained and corrected. Everything here is pure — the store owns the rows.
public struct LearnedIndex: Sendable {
    /// How long until a piece of evidence counts for half as much.
    ///
    /// Three weeks: long enough that a project you touch weekly stays learned,
    /// short enough that changing how you work is reflected within days rather
    /// than being outvoted by last quarter.
    public var halfLife: TimeInterval

    /// How much total evidence a single feature needs before its purity is
    /// taken at face value. Stops one lucky observation looking certain.
    public var featureSaturation: Double

    /// How much total score is needed before the *suggestion* is taken at face
    /// value. This is what keeps a brand-new pattern in "assign but ask"
    /// territory rather than assigning silently.
    public var evidenceSaturation: Double

    /// Learned suggestions never outrank an explicit rule the user wrote.
    public var maximumConfidence: Int

    public init(
        halfLife: TimeInterval = 21 * 24 * 60 * 60,
        featureSaturation: Double = 2.0,
        evidenceSaturation: Double = 1.5,
        maximumConfidence: Int = 90
    ) {
        self.halfLife = halfLife
        self.featureSaturation = featureSaturation
        self.evidenceSaturation = evidenceSaturation
        self.maximumConfidence = maximumConfidence
    }

    public static let `default` = LearnedIndex()

    // ── Decay ────────────────────────────────────────────────────────────

    public func decayedMass(_ association: FeatureAssociation, now: Date) -> Double {
        let age = now.timeIntervalSince(association.lastUpdated)
        guard age > 0 else { return association.mass }
        return association.mass * pow(0.5, age / halfLife)
    }

    /// Fold in a new observation, aging both sides to a common reference.
    ///
    /// `observedAt` is when the evidence actually happened, which is not always
    /// now: importing a backup or back-applying a rule to old sessions replays
    /// history, and a year-old session must not count as fresh evidence just
    /// because it was written today.
    ///
    /// Observations can also arrive out of order, so the reference point is the
    /// later of the two and whichever side is older gets decayed to meet it.
    public func updated(
        _ association: FeatureAssociation, adding weight: Double, at observedAt: Date
    ) -> FeatureAssociation {
        let reference = max(association.lastUpdated, observedAt)

        let agedMass = decayedMass(association, now: reference)
        let weightAge = reference.timeIntervalSince(observedAt)
        let agedWeight = weight * pow(0.5, max(0, weightAge) / halfLife)

        var updated = association
        // Never let a correction drive mass negative: the absence of evidence
        // is the floor, not evidence of the opposite.
        updated.mass = max(0, agedMass + agedWeight)
        updated.observations = max(0, association.observations + (weight >= 0 ? 1 : -1))
        updated.lastUpdated = reference
        return updated
    }

    // ── Recording ────────────────────────────────────────────────────────

    /// How much one session is worth as evidence.
    ///
    /// Longer means more deliberate, but only up to a point — four hours on one
    /// thing is not two hundred times the evidence of a one-minute visit, so
    /// this grows with the square root and saturates.
    public static func observationWeight(durationSeconds: Int) -> Double {
        guard durationSeconds > 0 else { return 0 }
        return min(3.0, (Double(durationSeconds) / 60).squareRoot())
    }

    /// Observations to record when a session is attributed to a project.
    public func observations(for session: Session, projectId: String) -> [FeatureObservation] {
        let weight = Self.observationWeight(durationSeconds: session.durationSeconds)
        guard weight > 0 else { return [] }
        return FeatureExtractor.features(for: session).map {
            FeatureObservation(
                feature: $0.key, projectId: projectId,
                weight: weight, at: session.endTime
            )
        }
    }

    /// Observations for an activity still in progress, weighted by how long
    /// it has run so far. Used when the user corrects a live suggestion.
    public func observations(
        features: [ActivityFeature], projectId: String,
        durationSeconds: Int, at: Date
    ) -> [FeatureObservation] {
        let weight = Self.observationWeight(durationSeconds: durationSeconds)
        guard weight > 0 else { return [] }
        return features.map {
            FeatureObservation(feature: $0.key, projectId: projectId, weight: weight, at: at)
        }
    }

    /// Observations to record when the user moves a session off a project.
    /// Recorded as negative evidence so the same mistake decays away.
    public func corrections(for session: Session, wrongProjectId: String) -> [FeatureObservation] {
        observations(for: session, projectId: wrongProjectId).map {
            var correction = $0
            correction.weight = -$0.weight
            return correction
        }
    }

    // ── Suggesting ───────────────────────────────────────────────────────

    /// Best project for these features, or nil when the evidence is too thin.
    ///
    /// - Parameter eligibleProjectIds: projects that still exist and are not
    ///   archived. Suggesting a deleted project would be worse than silence.
    public func suggest(
        features: [ActivityFeature],
        associations: [FeatureAssociation],
        eligibleProjectIds: Set<String>,
        now: Date = Date()
    ) -> LearnedSuggestion? {
        guard !features.isEmpty, !associations.isEmpty else { return nil }

        var byFeature: [String: [FeatureAssociation]] = [:]
        for association in associations where eligibleProjectIds.contains(association.projectId) {
            byFeature[association.feature, default: []].append(association)
        }

        var scores: [String: Double] = [:]
        var evidenceByProject: [String: [SuggestionEvidence]] = [:]

        for feature in features {
            guard let rows = byFeature[feature.key], !rows.isEmpty else { continue }

            let masses = rows.map { (row: $0, mass: decayedMass($0, now: now)) }
            let total = masses.reduce(0) { $0 + $1.mass }
            guard total > 0 else { continue }

            // A feature seen twice should not speak as confidently as one seen
            // fifty times, however pure it looks.
            let attestation = total / (total + featureSaturation)

            for entry in masses where entry.mass > 0 {
                let purity = entry.mass / total
                let contribution = feature.kind.weight * purity * attestation
                scores[entry.row.projectId, default: 0] += contribution
                evidenceByProject[entry.row.projectId, default: []].append(
                    SuggestionEvidence(
                        feature: feature,
                        observations: entry.row.observations,
                        lastSeen: entry.row.lastUpdated,
                        purity: purity,
                        contribution: contribution
                    )
                )
            }
        }

        guard let (bestProject, bestScore) = scores.max(by: { $0.value < $1.value }),
              bestScore > 0
        else { return nil }

        let totalScore = scores.values.reduce(0, +)
        // How dominant the winner is against the alternatives…
        let share = bestScore / totalScore
        // …and how much evidence there is at all. Both must hold.
        let strength = bestScore / (bestScore + evidenceSaturation)

        let confidence = min(maximumConfidence, Int((100 * share * strength).rounded()))
        guard confidence > 0 else { return nil }

        let evidence = (evidenceByProject[bestProject] ?? [])
            .sorted { $0.contribution > $1.contribution }

        return LearnedSuggestion(
            projectId: bestProject, confidence: confidence, evidence: evidence
        )
    }
}
