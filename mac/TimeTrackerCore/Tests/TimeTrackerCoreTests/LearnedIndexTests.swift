import Testing
import Foundation
@testable import TimeTrackerCore

// The bias here is explicit and non-negotiable: an unfilled gap is a minor
// annoyance, a wrong invoice is not. These tests exist mostly to prove the
// model stays quiet when it should, not that it speaks when it can.

private let now = Date(unixMillis: 1_700_000_000_000)
private func daysAgo(_ n: Double) -> Date { now.addingTimeInterval(-n * 86_400) }

private func association(
    _ feature: String, _ projectId: String,
    mass: Double, observations: Int = 1, at: Date = now
) -> FeatureAssociation {
    FeatureAssociation(
        feature: feature, projectId: projectId,
        mass: mass, observations: observations, lastUpdated: at
    )
}

private func figmaSnapshot() -> ActivitySnapshot {
    ActivitySnapshot(
        bundleID: "com.google.Chrome", appName: "Google Chrome",
        windowTitle: "KPI Screens",
        url: "https://www.figma.com/design/abc123/KPI-Screens"
    )
}

private let index = LearnedIndex.default
private let everyone: Set<String> = ["acme", "internal", "other"]

@Suite("Learned model: decay")
struct LearnedDecayTests {
    @Test("evidence halves over one half-life")
    func halfLife() {
        let old = association("app:x", "acme", mass: 10, at: daysAgo(21))
        #expect(abs(index.decayedMass(old, now: now) - 5) < 0.01)
    }

    @Test("evidence from months ago barely counts")
    func oldEvidenceFades() {
        let ancient = association("app:x", "acme", mass: 10, at: daysAgo(180))
        #expect(index.decayedMass(ancient, now: now) < 0.03)
    }

    @Test("fresh evidence is untouched")
    func freshEvidence() {
        let fresh = association("app:x", "acme", mass: 10, at: now)
        #expect(index.decayedMass(fresh, now: now) == 10)
    }

    @Test("adding an observation ages the old mass first, so it cannot inflate")
    func updateAgesFirst() {
        let old = association("app:x", "acme", mass: 10, observations: 4, at: daysAgo(21))
        let updated = index.updated(old, adding: 1, at: now)
        #expect(abs(updated.mass - 6) < 0.01)   // 10 halved, plus 1
        #expect(updated.observations == 5)
        #expect(updated.lastUpdated == now)
    }

    @Test("a correction can never drive evidence negative")
    func correctionsClampAtZero() {
        let small = association("app:x", "acme", mass: 0.5, observations: 1, at: now)
        let corrected = index.updated(small, adding: -5, at: now)
        #expect(corrected.mass == 0)
        #expect(corrected.observations == 0)
    }
}

@Suite("Learned model: observation weighting")
struct ObservationWeightTests {
    @Test("longer sessions are stronger evidence, but with diminishing returns")
    func weighting() {
        let oneMinute = LearnedIndex.observationWeight(durationSeconds: 60)
        let nineMinutes = LearnedIndex.observationWeight(durationSeconds: 540)
        let fourHours = LearnedIndex.observationWeight(durationSeconds: 14_400)

        #expect(abs(oneMinute - 1) < 0.01)
        #expect(nineMinutes > oneMinute)
        // Four hours is not 240x the evidence of one minute.
        #expect(fourHours <= 3.0)
        #expect(fourHours / oneMinute < 4)
    }

    @Test("a zero-length session is not evidence")
    func zeroLength() {
        #expect(LearnedIndex.observationWeight(durationSeconds: 0) == 0)
    }
}

@Suite("Learned model: the three bands")
struct LearnedBandTests {
    let features = FeatureExtractor.features(for: figmaSnapshot())

    /// Strong, consistent history on a specific entity.
    @Test("a repeated unambiguous pattern is confident enough to assign silently")
    func highConfidence() {
        let associations = [
            association("entity:figma::abc123", "acme", mass: 20, observations: 20),
            association("host:figma.com", "acme", mass: 20, observations: 20),
            association("app:com.google.Chrome", "acme", mass: 20, observations: 20),
        ]
        let suggestion = try! #require(index.suggest(
            features: features, associations: associations,
            eligibleProjectIds: everyone, now: now
        ))
        #expect(suggestion.projectId == "acme")
        // Above the default review threshold, so it does not nag.
        #expect(suggestion.confidence >= AppSettings.default.reviewConfidenceThreshold)
    }

    @Test("a thin pattern is assigned but flagged rather than trusted")
    func mediumConfidence() {
        // Seen a handful of times, consistent, but hardly established.
        let associations = [
            association("entity:figma::abc123", "acme", mass: 2, observations: 2),
        ]
        let suggestion = try! #require(index.suggest(
            features: features, associations: associations,
            eligibleProjectIds: everyone, now: now
        ))
        #expect(suggestion.projectId == "acme")
        #expect(suggestion.confidence < AppSettings.default.reviewConfidenceThreshold,
                "a couple of observations must not buy a silent assignment")
        #expect(suggestion.confidence > 0)
    }

    @Test("genuinely ambiguous history stays quiet rather than guessing")
    func ambiguityIsNotGuessed() {
        // The same Figma file has gone to two projects about equally often.
        // Guessing here would put time on the wrong invoice.
        let associations = [
            association("entity:figma::abc123", "acme", mass: 10, observations: 10),
            association("entity:figma::abc123", "internal", mass: 10, observations: 10),
            association("app:com.google.Chrome", "acme", mass: 10, observations: 10),
            association("app:com.google.Chrome", "internal", mass: 10, observations: 10),
        ]
        let suggestion = index.suggest(
            features: features, associations: associations,
            eligibleProjectIds: everyone, now: now
        )
        let confidence = suggestion?.confidence ?? 0
        #expect(confidence < 60, "a coin flip must not look like knowledge")
    }

    @Test("no history yields no suggestion at all")
    func coldStart() {
        #expect(index.suggest(
            features: features, associations: [],
            eligibleProjectIds: everyone, now: now
        ) == nil)
    }

    @Test("a single weak signal is not enough")
    func singleWeakSignal() {
        // One title word, seen once. That is nothing.
        let associations = [association("title:screens", "acme", mass: 1, observations: 1)]
        let suggestion = index.suggest(
            features: features, associations: associations,
            eligibleProjectIds: everyone, now: now
        )
        #expect((suggestion?.confidence ?? 0) < 30)
    }

    @Test("a learned suggestion never outranks an explicit rule the user wrote")
    func cappedBelowRules() {
        let overwhelming = (0..<5).map { i in
            association("entity:figma::abc123", "acme", mass: 1000, observations: 500 + i)
        }
        let suggestion = try! #require(index.suggest(
            features: features, associations: overwhelming,
            eligibleProjectIds: everyone, now: now
        ))
        #expect(suggestion.confidence <= index.maximumConfidence)
        #expect(suggestion.confidence < Confidence.manual)
    }
}

@Suite("Learned model: safety")
struct LearnedSafetyTests {
    let features = FeatureExtractor.features(for: figmaSnapshot())

    @Test("a deleted or archived project is never suggested")
    func ineligibleProjectsExcluded() {
        let associations = [
            association("entity:figma::abc123", "deleted-project", mass: 50, observations: 50),
        ]
        #expect(index.suggest(
            features: features, associations: associations,
            eligibleProjectIds: ["acme"], now: now
        ) == nil)
    }

    @Test("stale evidence loses to recent evidence, so changing how you work is reflected")
    func recencyWins() {
        let associations = [
            // Heavy but months old.
            association("entity:figma::abc123", "internal", mass: 40, observations: 40, at: daysAgo(120)),
            // Lighter but current.
            association("entity:figma::abc123", "acme", mass: 8, observations: 8, at: daysAgo(1)),
        ]
        let suggestion = try! #require(index.suggest(
            features: features, associations: associations,
            eligibleProjectIds: everyone, now: now
        ))
        #expect(suggestion.projectId == "acme")
    }

    @Test("corrections are recorded as negative evidence against the wrong project")
    func corrections() {
        let session = Session(
            appBundleID: "com.google.Chrome", appName: "Google Chrome",
            windowTitle: "KPI Screens",
            url: "https://www.figma.com/design/abc123/KPI-Screens",
            domain: "figma.com", service: "figma", detectedEntityId: "abc123",
            startTime: now, endTime: now.addingTimeInterval(600), durationSeconds: 600
        )
        let corrections = index.corrections(for: session, wrongProjectId: "internal")
        #expect(!corrections.isEmpty)
        #expect(corrections.allSatisfy { $0.weight < 0 })
        #expect(corrections.allSatisfy { $0.projectId == "internal" })
        #expect(corrections.contains { $0.feature == "entity:figma::abc123" })
    }

    @Test("recording a session produces one observation per feature")
    func recording() {
        let session = Session(
            appBundleID: "com.figma.Desktop", appName: "Figma",
            windowTitle: "KPI Screens", documentPath: "/Users/d/Projects/acme/design.fig",
            startTime: now, endTime: now.addingTimeInterval(300), durationSeconds: 300
        )
        let observations = index.observations(for: session, projectId: "acme")
        #expect(observations.allSatisfy { $0.weight > 0 })
        #expect(observations.contains { $0.feature == "app:com.figma.Desktop" })
        #expect(observations.contains { $0.feature.hasPrefix("document:") })
    }
}

@Suite("Learned model: explanation")
struct LearnedExplanationTests {
    @Test("a suggestion names the evidence it actually used")
    func explanationNamesEvidence() {
        let associations = [
            association("entity:figma::abc123", "acme", mass: 20, observations: 14, at: daysAgo(1)),
            association("app:com.google.Chrome", "acme", mass: 20, observations: 40),
        ]
        let suggestion = try! #require(index.suggest(
            features: FeatureExtractor.features(for: figmaSnapshot()),
            associations: associations, eligibleProjectIds: everyone, now: now
        ))

        // The strongest evidence must lead, not merely the most frequent: the
        // specific Figma file is what matters, not "you use Chrome a lot".
        let top = try! #require(suggestion.evidence.first)
        #expect(top.feature.kind == .entity)
        #expect(top.observations == 14)

        let text = suggestion.explanation(projectName: "Acme Corp", now: now)
        #expect(text.contains("Acme Corp"))
        #expect(text.contains("14 times"))
    }

    @Test("evidence is ordered by contribution, strongest first")
    func evidenceOrdering() {
        let associations = [
            association("entity:figma::abc123", "acme", mass: 20, observations: 20),
            association("host:figma.com", "acme", mass: 20, observations: 20),
            association("app:com.google.Chrome", "acme", mass: 20, observations: 20),
        ]
        let suggestion = try! #require(index.suggest(
            features: FeatureExtractor.features(for: figmaSnapshot()),
            associations: associations, eligibleProjectIds: everyone, now: now
        ))
        let contributions = suggestion.evidence.map(\.contribution)
        #expect(contributions == contributions.sorted(by: >))
    }
}
