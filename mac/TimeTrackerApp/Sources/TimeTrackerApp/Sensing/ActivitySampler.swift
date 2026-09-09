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

    func currentSnapshot() -> ActivitySnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier
        else { return nil }

        let details = AccessibilityReader.focusedWindowDetails(pid: app.processIdentifier)
        let appChanged = bundleID != lastBundleID
        let titleChanged = details.title != lastTitle

        var url: String?
        if BrowserURLReader.isBrowser(bundleID) {
            url = browserURL(for: bundleID, appChanged: appChanged, titleChanged: titleChanged)
        } else {
            cachedURL = nil
        }

        lastBundleID = bundleID
        lastTitle = details.title

        return ActivitySnapshot(
            bundleID: bundleID,
            appName: app.localizedName ?? bundleID,
            windowTitle: details.title,
            url: url,
            documentPath: details.documentPath,
            capturedAt: Date()
        )
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
            haveCachedURL: cachedURL != nil
        )
        guard shouldRead else { return cachedURL }
        cachedURL = urlReader.url(forBundleID: bundleID)
        return cachedURL
    }

    private func emit() {
        guard let snapshot = currentSnapshot() else { return }
        onChange?(snapshot)
    }
}
