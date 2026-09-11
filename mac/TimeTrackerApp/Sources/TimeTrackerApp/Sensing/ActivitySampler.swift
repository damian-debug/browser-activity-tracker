import AppKit
import TimeTrackerCore

/// Produces the stream of `ActivitySnapshot`s the coordinator reasons about,
/// assembling whatever signals the granted permissions allow.
///
/// Degrades in layers, deliberately:
///   - no permissions  → app identity only (still a useful tracker)
///   - + Accessibility → window title and open document
///   - + Automation    → browser tab URL, and with it the Figma/Bubble parsers
@MainActor
final class ActivitySampler {
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private let urlReader = BrowserURLReader()

    /// Cheap AX reads happen every tick; expensive Apple Events do not.
    private let pollInterval: TimeInterval = 2

    private var lastBundleID: String?
    private var lastTitle: String?
    private var cachedURL: String?
    private var urlPolicy = URLReadPolicy()

    /// Branch lookups are a small file read, but they happen on every sample,
    /// so remember the answer per repository directory.
    private var branchCache: [String: String?] = [:]
    private var branchCacheStamp = Date.distantPast

    var onChange: ((ActivitySnapshot) -> Void)?

    var isAccessibilityTrusted: Bool { AccessibilityReader.isTrusted }
    var browserAccess: [String: BrowserURLReader.Access] { urlReader.access }

    func start() {
        stop()
        let center = NSWorkspace.shared.notificationCenter
        // NSWorkspace notifications arrive only on its own centre, never on
        // NotificationCenter.default.
        for name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.emit() }
            }
            observers.append(token)
        }

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.emit() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        emit()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        timer?.invalidate()
        timer = nil
    }

    /// Our own bundle id. Time spent in the tracker's own windows is not work
    /// on a project, and recording it would be self-defeating: opening the
    /// dashboard to review your day would itself create sessions about
    /// reviewing your day, and teach the model about them.
    private let ownBundleID = Bundle.main.bundleIdentifier

    func currentSnapshot() -> ActivitySnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier
        else { return nil }

        guard bundleID != ownBundleID else { return nil }

        let details = AccessibilityReader.focusedWindowDetails(pid: app.processIdentifier)

        // Electron apps report the app's own name as the window title, which
        // makes every conversation and repository look identical. Their web
        // area carries the real identity.
        let web = WebAppReader.read(pid: app.processIdentifier, bundleID: bundleID)
        let title = web.title ?? details.title

        let appChanged = bundleID != lastBundleID
        let titleChanged = title != lastTitle

        var url: String?
        if let webURL = web.url {
            url = webURL
        } else if BrowserURLReader.isBrowser(bundleID) {
            url = browserURL(for: bundleID, appChanged: appChanged, titleChanged: titleChanged)
        } else {
            cachedURL = nil
        }

        lastBundleID = bundleID
        lastTitle = title

        return ActivitySnapshot(
            bundleID: bundleID,
            appName: app.localizedName ?? bundleID,
            windowTitle: title,
            url: url,
            documentPath: details.documentPath,
            gitBranch: details.documentPath.flatMap(branch(forFileAt:)),
            capturedAt: Date()
        )
    }

    /// Checked-out branch for an open document, cached briefly.
    ///
    /// Only available for apps that expose a document path at all, which rules
    /// out Electron editors like VS Code — they report a title but no document.
    private func branch(forFileAt path: String) -> String? {
        let directory = WorkSignals.folder(ofDocument: path)

        // Cheap, but not free, and branches change rarely. Re-check a minute at
        // a time so switching branches is noticed without re-reading constantly.
        if Date().timeIntervalSince(branchCacheStamp) > 60 {
            branchCache.removeAll()
            branchCacheStamp = Date()
        }
        if let cached = branchCache[directory] { return cached }

        let found = WorkSignals.gitBranch(forFileAt: path)
        branchCache[directory] = found
        return found
    }

    /// A title change is an excellent proxy for "the tab changed", so it is what
    /// triggers the expensive read rather than a timer.
    ///
    /// Without Accessibility there are no titles to watch, so fall back to a
    /// slow poll — often enough to be useful, rare enough not to hammer the
    /// browser with tens of thousands of Apple Events a day.
    private func browserURL(for bundleID: String, appChanged: Bool, titleChanged: Bool) -> String? {
        let shouldRead = urlPolicy.shouldRead(
            haveTitles: AccessibilityReader.isTrusted,
            appChanged: appChanged,
            titleChanged: titleChanged,
            haveCachedURL: cachedURL != nil,
            locationInURL: cachedURL.map(ParserRegistry.locationChangesWithoutTitle) ?? false
        )
        guard shouldRead else { return cachedURL }
        cachedURL = urlReader.url(forBundleID: bundleID)
        return cachedURL
    }

    private func emit() {
        AXInspector.dumpFrontmostApp()
        guard let snapshot = currentSnapshot() else { return }
        onChange?(snapshot)
    }
}
