import Testing
import Foundation
@testable import TimeTrackerCore

// Prints the confidence the model actually produces for representative
// histories. Not an assertion of exact values — those will be tuned against
// real data — but a guard that the ordering stays sane and a quick way to see
// where the band boundaries fall.
@Suite("Calibration")
struct CalibrationProbe {
    @Test("confidence rises with consistency and evidence, in a sensible order")
    func calibrationTable() {
        let now = Date(unixMillis: 1_700_000_000_000)
        let index = LearnedIndex.default
        let snapshot = ActivitySnapshot(
            bundleID: "com.google.Chrome", appName: "Google Chrome",
            windowTitle: "KPI Screens",
            url: "https://www.figma.com/design/abc123/KPI-Screens"
        )
        let features = FeatureExtractor.features(for: snapshot)

        func confidence(_ associations: [FeatureAssociation]) -> Int {
            index.suggest(
                features: features, associations: associations,
                eligibleProjectIds: ["acme", "internal"], now: now
            )?.confidence ?? 0
        }
        func row(_ feature: String, _ project: String, _ mass: Double, _ n: Int) -> FeatureAssociation {
            FeatureAssociation(
                feature: feature, projectId: project,
                mass: mass, observations: n, lastUpdated: now
            )
        }

        let seenOnce = confidence([row("entity:figma::abc123", "acme", 1, 1)])
        let seenAFew = confidence([row("entity:figma::abc123", "acme", 3, 3)])
        let established = confidence([
            row("entity:figma::abc123", "acme", 20, 20),
            row("host:figma.com", "acme", 20, 20),
        ])
        let overwhelming = confidence([
            row("entity:figma::abc123", "acme", 100, 100),
            row("host:figma.com", "acme", 100, 100),
            row("app:com.google.Chrome", "acme", 100, 100),
        ])
        let contested = confidence([
            row("entity:figma::abc123", "acme", 20, 20),
            row("entity:figma::abc123", "internal", 18, 18),
        ])

        print("""

        ── learned confidence calibration ─────────────────────
          seen once            \(seenOnce)
          seen a few times     \(seenAFew)
          established          \(established)
          overwhelming         \(overwhelming)
          contested 20 v 18    \(contested)
          review threshold     \(AppSettings.default.reviewConfidenceThreshold)
        ───────────────────────────────────────────────────────
        """)

        // Ordering is the real contract; the exact numbers are tunable.
        #expect(seenOnce < seenAFew)
        #expect(seenAFew < established)
        #expect(established <= overwhelming)
        #expect(contested < established, "disagreement must cost confidence")
    }
}
