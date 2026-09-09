import Testing
import Foundation
@testable import TimeTrackerCore

// Ported from extension/tests/tracking-target.test.ts, extended to the native
// signals. This is the logic that stops one Figma file fragmenting into dozens
// of discarded slivers as the URL churns.

@Suite("Tracking continuity")
struct TrackingTargetTests {
    let bubbleApp = browserSnapshot(url: "https://bubble.io/page?id=sampleapp&tab=Design")
    let figmaFile = browserSnapshot(url: "https://www.figma.com/design/abc123/My-File")
    let plainPage = browserSnapshot(url: "https://example.com/docs/intro")

    @Test("keeps the session when navigating within the same Bubble app")
    func sameBubbleApp() {
        let target = TrackingTarget.resolve(bubbleApp)
        #expect(target.matches(browserSnapshot(url: "https://bubble.io/page?id=sampleapp&tab=Settings")))
        #expect(target.matches(browserSnapshot(url: "https://bubble.io/page?id=sampleapp&tab=Workflow&x=1")))
    }

    @Test("starts a new session when switching to a different Bubble app")
    func differentBubbleApp() {
        let target = TrackingTarget.resolve(bubbleApp)
        #expect(!target.matches(browserSnapshot(url: "https://bubble.io/page?id=otherapp&tab=Design")))
    }

    @Test("keeps the session across navigation within the same Figma file")
    func sameFigmaFile() {
        let target = TrackingTarget.resolve(figmaFile)
        #expect(target.matches(browserSnapshot(url: "https://www.figma.com/design/abc123/My-File?node-id=12-34")))
    }

    @Test("starts a new session for a different Figma file")
    func differentFigmaFile() {
        let target = TrackingTarget.resolve(figmaFile)
        #expect(!target.matches(browserSnapshot(url: "https://www.figma.com/design/zzz999/Other-File")))
    }

    @Test("falls back to exact URL match when no entity is detected")
    func exactURLFallback() {
        let target = TrackingTarget.resolve(plainPage)
        #expect(target.matches(browserSnapshot(url: "https://example.com/docs/intro")))
        #expect(!target.matches(browserSnapshot(url: "https://example.com/docs/advanced")))
    }

    @Test("starts a new session when leaving a project for a plain page on the same domain")
    func leavingProjectPage() {
        let target = TrackingTarget.resolve(bubbleApp)
        #expect(!target.matches(browserSnapshot(url: "https://bubble.io/home")))
    }

    @Test("starts a new session when the service changes")
    func serviceChange() {
        let target = TrackingTarget.resolve(bubbleApp)
        #expect(!target.matches(browserSnapshot(url: "https://www.figma.com/design/abc123/My-File")))
    }

    // ── Native signals ───────────────────────────────────────────────────

    @Test("a document survives window-title churn (dirty markers, line numbers)")
    func documentBeatsTitle() {
        let editing = nativeSnapshot(title: "main.swift — acme", documentPath: "/Users/d/acme/main.swift")
        let target = TrackingTarget.resolve(editing)
        let dirty = nativeSnapshot(title: "● main.swift — acme", documentPath: "/Users/d/acme/main.swift")
        #expect(target.matches(dirty))
    }

    @Test("switching document within one app starts a new session")
    func differentDocument() {
        let target = TrackingTarget.resolve(
            nativeSnapshot(documentPath: "/Users/d/acme/main.swift")
        )
        #expect(!target.matches(nativeSnapshot(documentPath: "/Users/d/acme/other.swift")))
    }

    @Test("with no document, a native app falls back to window title, then to the app")
    func nativeFallbacks() {
        let titled = nativeSnapshot(title: "Inbox")
        #expect(TrackingTarget.resolve(titled) == .window(bundleID: "com.microsoft.VSCode", title: "Inbox"))

        let bare = nativeSnapshot()
        #expect(TrackingTarget.resolve(bare) == .app(bundleID: "com.microsoft.VSCode"))
    }

    @Test("the same title in two different apps is two different targets")
    func titleIsScopedToApp() {
        let a = nativeSnapshot(bundleID: "com.apple.Notes", title: "Untitled")
        let b = nativeSnapshot(bundleID: "com.apple.TextEdit", title: "Untitled")
        #expect(TrackingTarget.resolve(a) != TrackingTarget.resolve(b))
    }
}
