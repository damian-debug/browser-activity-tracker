import Testing
import Foundation
@testable import TimeTrackerCore

// Continuity must survive fluctuating signal availability. These cases caught a
// real bug: because a target was resolved from whichever signals happened to be
// present, granting Accessibility mid-session changed the resolved target and
// split one session in two. The rule is now "end a session only on positive
// evidence of change, never on absence of evidence".

@Suite("Continuity under changing signal availability")
struct ActivityIdentityTests {
    let figma = ActivitySnapshot(bundleID: "com.figma.Desktop", appName: "Figma")

    @Test("gaining a window title mid-session does not split the session")
    func gainingTitleKeepsSession() {
        var titled = figma
        titled.windowTitle = "KPI Screens"
        #expect(figma.identity.continues(titled.identity))
        #expect(titled.identity.continues(figma.identity))
    }

    @Test("losing a title we previously had does not split the session")
    func losingTitleKeepsSession() {
        var titled = figma
        titled.windowTitle = "KPI Screens"
        // A single failed AX read must not look like a change of activity.
        #expect(titled.identity.continues(figma.identity))
    }

    @Test("a genuinely different title does split the session")
    func differentTitleSplits() {
        var a = figma; a.windowTitle = "KPI Screens"
        var b = figma; b.windowTitle = "Onboarding Flow"
        #expect(!a.identity.continues(b.identity))
    }

    @Test("the strongest shared signal decides: a stable document outranks a churning title")
    func documentOutranksTitle() {
        var a = nativeSnapshot(title: "main.swift", documentPath: "/p/main.swift")
        a.windowTitle = "main.swift — line 1"
        var b = nativeSnapshot(title: "main.swift", documentPath: "/p/main.swift")
        b.windowTitle = "main.swift — line 402"
        #expect(a.identity.continues(b.identity))
    }

    @Test("a changed document splits even when the title happens to match")
    func documentChangeSplits() {
        let a = nativeSnapshot(title: "Untitled", documentPath: "/p/a.swift")
        let b = nativeSnapshot(title: "Untitled", documentPath: "/p/b.swift")
        #expect(!a.identity.continues(b.identity))
    }

    @Test("a detected entity outranks the raw URL, so tab churn inside one file is one session")
    func entityOutranksURL() {
        let a = browserSnapshot(url: "https://www.figma.com/design/abc/F?node-id=1-2")
        let b = browserSnapshot(url: "https://www.figma.com/design/abc/F?node-id=99-100")
        #expect(a.identity.continues(b.identity))
    }

    @Test("gaining a browser URL mid-session does not split the session")
    func gainingURLKeepsSession() {
        // Automation permission granted part-way through browsing.
        let blind = ActivitySnapshot(bundleID: chromeBundleID, appName: "Google Chrome", windowTitle: "Figma")
        var seeing = blind
        seeing.url = "https://www.figma.com/design/abc/F"
        #expect(blind.identity.continues(seeing.identity))
    }

    @Test("a different app is always different work")
    func differentAppSplits() {
        let a = nativeSnapshot(bundleID: "com.apple.Notes", title: "Untitled")
        let b = nativeSnapshot(bundleID: "com.apple.TextEdit", title: "Untitled")
        #expect(!a.identity.continues(b.identity))
    }

    @Test("with nothing comparable beyond the app, it is the same session")
    func bareAppIsOneSession() {
        #expect(figma.identity.continues(figma.identity))
    }

    @Test("empty strings count as absent, not as a value to compare")
    func emptyStringsAreAbsent() {
        var blank = figma
        blank.windowTitle = ""
        var titled = figma
        titled.windowTitle = "KPI Screens"
        #expect(blank.identity.continues(titled.identity))
    }

    @Test("enrichment fills gaps without overwriting what is already known")
    func enrichment() {
        var known = figma
        known.windowTitle = "KPI Screens"
        known.documentPath = "/p/design.fig"

        var partial = figma
        partial.windowTitle = "KPI Screens v2"

        let merged = partial.enriched(from: known)
        #expect(merged.windowTitle == "KPI Screens v2", "newer values win")
        #expect(merged.documentPath == "/p/design.fig", "missing values are inherited")
    }
}
