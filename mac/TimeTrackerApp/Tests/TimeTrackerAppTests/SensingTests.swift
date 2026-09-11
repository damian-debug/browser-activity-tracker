import Testing
import Foundation
import TimeTrackerCore
@testable import TimeTrackerApp

@Suite("Browser URL read throttling")
struct URLReadPolicyTests {
    @Test("with titles available, reads follow navigation rather than a clock")
    func readsOnTitleChange() {
        var policy = URLReadPolicy()

        // First sample: nothing cached, so read.
        let first = policy.shouldRead(haveTitles: true, appChanged: true, titleChanged: true, haveCachedURL: false)
        #expect(first)

        // The tick after a title change reads once more, in case the address
        // lagged the title (see confirmsAfterTitleChange).
        let confirm = policy.shouldRead(haveTitles: true, appChanged: false, titleChanged: false, haveCachedURL: true)
        #expect(confirm)

        // Nothing changed: reuse the cached URL rather than spending an Apple Event.
        let quiet = policy.shouldRead(haveTitles: true, appChanged: false, titleChanged: false, haveCachedURL: true)
        #expect(!quiet)

        // Title moved: the tab probably did too.
        let afterTitle = policy.shouldRead(haveTitles: true, appChanged: false, titleChanged: true, haveCachedURL: true)
        #expect(afterTitle)

        // Switched browsers.
        let afterApp = policy.shouldRead(haveTitles: true, appChanged: true, titleChanged: false, haveCachedURL: true)
        #expect(afterApp)
    }

    @Test("a quiet browser costs nothing while the user reads one page")
    func idlePageCostsNothing() {
        var policy = URLReadPolicy()
        _ = policy.shouldRead(haveTitles: true, appChanged: true, titleChanged: true, haveCachedURL: false)

        // Thirty minutes on one article at a 2s tick: one read to confirm the
        // address settled after the title arrived, then nothing at all.
        var reads = 0
        for _ in 0..<900 where policy.shouldRead(
            haveTitles: true, appChanged: false, titleChanged: false, haveCachedURL: true
        ) {
            reads += 1
        }
        #expect(reads == 1)
    }

    @Test("without titles, it falls back to a slow poll rather than every tick")
    func blindFallbackIsThrottled() {
        var policy = URLReadPolicy(blindPollTicks: 3)
        // Prime the cache.
        let primed = policy.shouldRead(haveTitles: false, appChanged: true, titleChanged: false, haveCachedURL: false)
        #expect(primed)

        var reads = 0
        for _ in 0..<9 {
            if policy.shouldRead(haveTitles: false, appChanged: false, titleChanged: false, haveCachedURL: true) {
                reads += 1
            }
        }
        // Every third tick, not every tick.
        #expect(reads == 3)
    }

    @Test("an app switch always reads immediately, even in the blind fallback")
    func appSwitchAlwaysReads() {
        var policy = URLReadPolicy(blindPollTicks: 10)
        _ = policy.shouldRead(haveTitles: false, appChanged: true, titleChanged: false, haveCachedURL: false)
        let onSwitch = policy.shouldRead(haveTitles: false, appChanged: true, titleChanged: false, haveCachedURL: true)
        #expect(onSwitch)
    }

    @Test("losing the cached URL forces a re-read")
    func missingCacheForcesRead() {
        var policy = URLReadPolicy()
        let forced = policy.shouldRead(haveTitles: true, appChanged: false, titleChanged: false, haveCachedURL: false)
        #expect(forced)
    }

    @Test("after a title change, the address is read once more to catch a lagging URL")
    func confirmsAfterTitleChange() {
        var policy = URLReadPolicy()
        _ = policy.shouldRead(haveTitles: true, appChanged: true, titleChanged: true, haveCachedURL: false)
        let titled = policy.shouldRead(haveTitles: true, appChanged: false, titleChanged: true, haveCachedURL: true)
        let confirm = policy.shouldRead(haveTitles: true, appChanged: false, titleChanged: false, haveCachedURL: true)
        let settled = policy.shouldRead(haveTitles: true, appChanged: false, titleChanged: false, haveCachedURL: true)
        #expect(titled && confirm)
        #expect(!settled, "one confirmation, not a new habit")
    }

    @Test("a Framer or Figma tab is watched, since its address moves without its title")
    func watchesLocationPages() {
        var policy = URLReadPolicy()
        _ = policy.shouldRead(haveTitles: true, appChanged: true, titleChanged: true, haveCachedURL: false,
                              locationInURL: true)
        var reads = 0
        for _ in 0..<30 where policy.shouldRead(   // one minute at a 2s tick
            haveTitles: true, appChanged: false, titleChanged: false, haveCachedURL: true, locationInURL: true
        ) {
            reads += 1
        }
        // Every 4s: often enough to catch a screen change, far from every tick.
        #expect(reads == 15)
    }

    @Test("which pages count as watched is decided by the parsers")
    func watchedServices() {
        #expect(ParserRegistry.locationChangesWithoutTitle("https://framer.com/projects/Acme--FC91PjIN9PCSOTMJzDXU?node=X"))
        #expect(ParserRegistry.locationChangesWithoutTitle("https://www.figma.com/design/abc123/Acme?node-id=1-2"))
        #expect(!ParserRegistry.locationChangesWithoutTitle("https://github.com/acme/site"))
        #expect(!ParserRegistry.locationChangesWithoutTitle("https://framer.com/projects/folder/recent"))
    }
}

@Suite("Browser support")
struct BrowserSupportTests {
    @Test("the browsers we can read are recognised")
    func recognisesBrowsers() {
        #expect(BrowserURLReader.isBrowser("com.apple.Safari"))
        #expect(BrowserURLReader.isBrowser("com.google.Chrome"))
        #expect(BrowserURLReader.isBrowser("company.thebrowser.Browser"))
        #expect(BrowserURLReader.isBrowser("com.microsoft.edgemac"))
    }

    @Test("Firefox is known as a browser even though its URL cannot be read")
    func firefoxIsKnownButUnreadable() {
        // It matters that we recognise it: the UI can then explain why its time
        // is tracked as one lump, instead of the user assuming a bug.
        #expect(BrowserURLReader.isBrowser("org.mozilla.firefox"))
    }

    @Test("ordinary apps are not treated as browsers")
    func nonBrowsers() {
        #expect(!BrowserURLReader.isBrowser("com.figma.Desktop"))
        #expect(!BrowserURLReader.isBrowser("com.microsoft.VSCode"))
        #expect(!BrowserURLReader.isBrowser(""))
    }
}

@Suite("Accessibility reader")
struct AccessibilityReaderTests {
    @MainActor
    @Test("reading a window without the grant yields nothing rather than failing")
    func degradesWithoutPermission() {
        // Whatever the grant state on this machine, the read must be total:
        // a missing permission has to degrade to app-level tracking, never trap.
        let details = AccessibilityReader.focusedWindowDetails(pid: ProcessInfo.processInfo.processIdentifier)
        if !AccessibilityReader.isTrusted {
            #expect(details.title == nil)
            #expect(details.documentPath == nil)
        }
    }

    @MainActor
    @Test("an invalid pid is handled without trapping")
    func invalidPID() {
        let details = AccessibilityReader.focusedWindowDetails(pid: -1)
        #expect(details.title == nil)
        #expect(details.documentPath == nil)
    }
}
