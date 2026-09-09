import Testing
import Foundation
@testable import TimeTrackerCore

@Suite("Feature extraction")
struct FeatureExtractionTests {
    func keys(_ features: [ActivityFeature]) -> Set<String> {
        Set(features.map(\.key))
    }

    @Test("a browser page yields app, host, path prefixes and title tokens")
    func browserFeatures() {
        let snapshot = ActivitySnapshot(
            bundleID: "com.google.Chrome", appName: "Google Chrome",
            windowTitle: "Acme dashboard - Google Chrome",
            url: "https://app.example.com/project/acme/board"
        )
        let found = keys(FeatureExtractor.features(for: snapshot))

        #expect(found.contains("app:com.google.Chrome"))
        #expect(found.contains("host:app.example.com"))
        #expect(found.contains("path:app.example.com/project"))
        #expect(found.contains("path:app.example.com/project/acme"))
        #expect(found.contains("title:acme"))
        #expect(found.contains("title:dashboard"))
    }

    @Test("the app's own name is stripped from title tokens, not double-counted")
    func appNameStrippedFromTitle() {
        let tokens = FeatureExtractor.titleTokens(
            "Acme dashboard - Google Chrome", appName: "Google Chrome"
        )
        #expect(tokens.contains("acme"))
        #expect(!tokens.contains("google"))
        #expect(!tokens.contains("chrome"))
    }

    @Test("title noise is dropped: short words, bare numbers, duplicates")
    func titleNoise() {
        let tokens = FeatureExtractor.titleTokens("(3) Acme — acme v2 — a the and", appName: "Slack")
        #expect(tokens.filter { $0 == "acme" }.count == 1, "duplicates collapse")
        #expect(!tokens.contains("3"))
        #expect(!tokens.contains("the"))
        #expect(!tokens.contains("a"))
    }

    @Test("a detected entity becomes its own strong feature")
    func entityFeature() {
        let snapshot = ActivitySnapshot(
            bundleID: "com.google.Chrome", appName: "Google Chrome",
            windowTitle: "KPI Screens",
            url: "https://www.figma.com/design/abc123/KPI-Screens"
        )
        #expect(keys(FeatureExtractor.features(for: snapshot)).contains("entity:figma::abc123"))
    }

    @Test("documents contribute their folders, not the file itself")
    func documentFolders() {
        // Files are rarely reopened; the folder a project lives in is the level
        // that actually generalises.
        let found = keys(FeatureExtractor.documentFeatures("/Users/d/Projects/acme/src/main.swift"))
        #expect(found.contains("document:/Users/d/Projects/acme/src"))
        #expect(found.contains("document:/Users/d/Projects/acme"))
        #expect(!found.contains("document:/Users/d/Projects/acme/src/main.swift"))
    }

    @Test("folder depth is bounded, so /Users never becomes a feature")
    func documentDepthBounded() {
        let found = keys(FeatureExtractor.documentFeatures("/Users/d/a/b/c/d/e/file.txt"))
        #expect(found.count <= 3)
        #expect(!found.contains("document:/Users"))
        #expect(!found.contains("document:/"))
    }

    @Test("an app with no other signal still yields its identity")
    func bareApp() {
        let snapshot = ActivitySnapshot(bundleID: "com.apple.Terminal", appName: "Terminal")
        #expect(keys(FeatureExtractor.features(for: snapshot)) == ["app:com.apple.Terminal"])
    }

    @Test("features round-trip through their storage key")
    func keyRoundTrip() {
        let feature = ActivityFeature(kind: .path, value: "app.example.com/project/acme")
        let parsed = try! #require(ActivityFeature.parse(key: feature.key))
        #expect(parsed == feature)
        #expect(ActivityFeature.parse(key: "nonsense") == nil)
        #expect(ActivityFeature.parse(key: "app:") == nil)
    }

    @Test("specificity ordering matches the hand-written rule table's intuition")
    func weightOrdering() {
        #expect(ActivityFeature.Kind.entity.weight > ActivityFeature.Kind.document.weight)
        #expect(ActivityFeature.Kind.document.weight > ActivityFeature.Kind.path.weight)
        #expect(ActivityFeature.Kind.path.weight > ActivityFeature.Kind.host.weight)
        #expect(ActivityFeature.Kind.host.weight > ActivityFeature.Kind.app.weight)
        #expect(ActivityFeature.Kind.app.weight > ActivityFeature.Kind.title.weight)
    }
}
