import AppKit
import ApplicationServices

/// Getting a useful identity out of Electron apps.
///
/// Apps like Claude and VS Code report a window title of just the app's own
/// name, which is useless for attribution — every conversation, repository and
/// document looks identical. But they are Chromium underneath, and Chromium
/// exposes a web area with a real URL once asked.
///
/// Two costs are worth stating plainly:
///
///  - Asking (`AXManualAccessibility`) makes Chromium build and maintain its
///    full accessibility tree, which is real work for the target app. So this
///    is opt-in per app rather than done to everything that might be Electron.
///  - That tree contains the app's entire visible text. We read the URL and a
///    title and nothing else. Conversation content is never touched, and the
///    search below is written to make that obvious.
@MainActor
enum WebAppReader {
    /// Apps we know how to read, and only these. Enabling the tree costs the
    /// target app performance, so it is never done speculatively.
    static let supported: Set<String> = [
        "com.anthropic.claudefordesktop",
    ]

    static func isSupported(_ bundleID: String) -> Bool { supported.contains(bundleID) }

    struct WebContent {
        var url: String?
        /// A human-readable name for the thing being worked on — the
        /// conversation, document or repository.
        var title: String?
    }

    private static var enabledApps: Set<pid_t> = []

    static func read(pid: pid_t, bundleID: String) -> WebContent {
        guard isSupported(bundleID) else { return WebContent() }

        let app = AXUIElementCreateApplication(pid)
        if !enabledApps.contains(pid) {
            // Chromium ships a stub tree of empty groups until a client asks
            // for the real one. Without this, these apps look like they expose
            // nothing at all.
            let result = AXUIElementSetAttributeValue(
                app, "AXManualAccessibility" as CFString, kCFBooleanTrue
            )
            // Only remember success. Before Accessibility is granted this call
            // is refused, and marking the app done anyway meant it was never
            // asked again: grant permission while Claude is already open and
            // its conversations stayed untitled until the tracker restarted.
            guard result == .success else { return WebContent() }
            enabledApps.insert(pid)
            // The tree is not built synchronously; this sample will come back
            // empty and the next one, two seconds later, will not.
            return WebContent()
        }

        guard let window = copyElement(app, kAXFocusedWindowAttribute)
            ?? copyElement(app, kAXMainWindowAttribute)
        else { return WebContent() }

        return WebContent(
            url: webAreaURL(in: window),
            title: documentTitle(in: window, bundleID: bundleID)
        )
    }

    /// The address of the innermost web area showing real content.
    ///
    /// Electron apps nest a `file://` shell around the actual page, so the
    /// local one is skipped in favour of whatever it hosts.
    private static func webAreaURL(in window: AXUIElement) -> String? {
        var best: String?
        var budget = 400
        search(window, budget: &budget) { element, role in
            guard role == "AXWebArea",
                  let url = string(element, "AXURL"),
                  url.hasPrefix("http://") || url.hasPrefix("https://")
            else { return false }
            best = url
            return true
        }
        return best
    }

    /// A readable name for the current document or conversation.
    ///
    /// Necessarily app-specific: there is no standard place for this, so each
    /// app gets one narrow rule. When a rule stops matching — and a UI change
    /// will eventually break one — the caller falls back to the URL, which
    /// still distinguishes one thing from another.
    private static func documentTitle(in window: AXUIElement, bundleID: String) -> String? {
        switch bundleID {
        case "com.anthropic.claudefordesktop":
            // The conversation's own rename control is labelled with its title,
            // e.g. "Payments refactor, rename session".
            let suffix = ", rename session"
            var title: String?
            var budget = 400
            search(window, budget: &budget) { element, role in
                guard role == "AXButton",
                      let description = string(element, kAXDescriptionAttribute),
                      description.hasSuffix(suffix)
                else { return false }
                title = String(description.dropLast(suffix.count))
                return true
            }
            return title?.isEmpty == false ? title : nil

        default:
            return nil
        }
    }

    // ── Bounded traversal ────────────────────────────────────────────────

    /// Breadth-first, budgeted, and stops at the first hit.
    ///
    /// Bounded deliberately: these trees contain everything on screen, and an
    /// unbounded walk on every sample would be both slow and far more reading
    /// than this needs to do.
    private static func search(
        _ root: AXUIElement,
        budget: inout Int,
        matches: (AXUIElement, String) -> Bool
    ) {
        var queue = [root]
        while !queue.isEmpty, budget > 0 {
            let element = queue.removeFirst()
            budget -= 1

            let role = string(element, kAXRoleAttribute) ?? ""
            if matches(element, role) { return }

            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                element, kAXChildrenAttribute as CFString, &children
            ) == .success, let list = children as? [AXUIElement] {
                queue.append(contentsOf: list)
            }
        }
    }

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        if CFGetTypeID(value) == CFStringGetTypeID() { return (value as! CFString) as String }
        if CFGetTypeID(value) == CFURLGetTypeID() { return (value as! CFURL as URL).absoluteString }
        return nil
    }
}
