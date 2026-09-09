import AppKit

/// Asks a browser for the address of the page you're looking at.
///
/// Uses Apple Events (AppleScript), which is what every comparable tracker
/// does. Three things are required and all three are easy to get wrong:
///   - `NSAppleEventsUsageDescription` in Info.plist. Without it the send fails
///     with errAEEventNotPermitted (-1743) and **no prompt is ever shown**.
///   - The `com.apple.security.automation.apple-events` entitlement, once the
///     app is signed with the Hardened Runtime.
///   - A separate Automation grant per target browser, prompted on first use.
///
/// Reads are deliberately driven by title changes rather than a timer: each one
/// is a synchronous Apple Event costing tens of milliseconds, so polling would
/// be both wasteful and rude to the browser.
@MainActor
final class BrowserURLReader {
    enum Access: Equatable {
        case unknown
        case granted
        /// The user denied Automation for this browser, or it was never prompted.
        case denied
        /// The browser exposes no usable scripting dictionary (Firefox).
        case unsupported
    }

    /// Browsers that can report their front tab over Apple Events.
    ///
    /// Firefox is absent on purpose: it has never shipped a meaningful
    /// AppleScript dictionary, so it degrades to app-level tracking. Reading its
    /// URL would mean walking the AX tree to an AXWebArea, which is
    /// undocumented and version-fragile — a later experiment, not a default.
    nonisolated private static let scripts: [String: String] = [
        "com.apple.Safari": #"tell application id "com.apple.Safari" to return URL of front document"#,
        "com.google.Chrome": chromiumScript("com.google.Chrome"),
        "com.google.Chrome.canary": chromiumScript("com.google.Chrome.canary"),
        "com.microsoft.edgemac": chromiumScript("com.microsoft.edgemac"),
        "com.brave.Browser": chromiumScript("com.brave.Browser"),
        "com.vivaldi.Vivaldi": chromiumScript("com.vivaldi.Vivaldi"),
        "com.operasoftware.Opera": chromiumScript("com.operasoftware.Opera"),
        "company.thebrowser.Browser": chromiumScript("company.thebrowser.Browser"),
        "company.thebrowser.dia": chromiumScript("company.thebrowser.dia"),
    ]

    nonisolated private static func chromiumScript(_ bundleID: String) -> String {
        // Targeting by bundle id rather than name survives renames and
        // localisation. Plain URL reads need no "Allow JavaScript from Apple
        // Events" — only script injection would.
        #"tell application id "\#(bundleID)" to return URL of active tab of front window"#
    }

    nonisolated static let knownBrowserBundleIDs = Set(scripts.keys).union(["org.mozilla.firefox"])

    nonisolated static func isBrowser(_ bundleID: String) -> Bool {
        knownBrowserBundleIDs.contains(bundleID)
    }

    private var compiled: [String: NSAppleScript] = [:]
    private(set) var access: [String: Access] = [:]

    /// Current URL for a browser, or nil for anything we can't read.
    func url(forBundleID bundleID: String) -> String? {
        guard let source = Self.scripts[bundleID] else {
            if Self.isBrowser(bundleID) { access[bundleID] = .unsupported }
            return nil
        }

        let script: NSAppleScript
        if let cached = compiled[bundleID] {
            script = cached
        } else {
            guard let created = NSAppleScript(source: source) else { return nil }
            compiled[bundleID] = created
            script = created
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)

        if let error {
            let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
            switch code {
            case -1743, -1744:
                // Automation refused. Recording this lets the UI explain the
                // gap instead of silently tracking less than the user expects.
                access[bundleID] = .denied
            default:
                // No window open, browser still launching, transient AppleEvent
                // failure: not a permission problem, so don't record one.
                break
            }
            return nil
        }

        access[bundleID] = .granted
        guard let value = result.stringValue, !value.isEmpty else { return nil }
        // Chromium reports "chrome://newtab/" and friends; treat non-web
        // schemes as no URL so they fall back to app-level tracking.
        guard value.hasPrefix("http://") || value.hasPrefix("https://") else { return nil }
        return value
    }

    /// Whether any known browser has actively refused Automation.
    var hasDeniedBrowser: Bool {
        access.values.contains(.denied)
    }
}
