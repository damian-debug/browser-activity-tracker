import AppKit
import ApplicationServices

/// Reads the focused window's title and open document via the Accessibility API.
///
/// Why AX and not CGWindowList/ScreenCaptureKit: `kCGWindowName` is silently
/// omitted unless the app holds Screen Recording, and since macOS 15 that
/// permission re-prompts the user **every month, forever** — intolerable for
/// something meant to run all day. Accessibility is a one-time grant and also
/// exposes `kAXDocumentAttribute`, which is what makes "this time was spent on
/// that file" possible at all.
@MainActor
enum AccessibilityReader {
    /// Whether the Accessibility grant is currently held. Never prompts.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Ask for the grant, showing the system prompt.
    ///
    /// The prompt only points the user at System Settings; macOS gives no way
    /// to grant programmatically, and the answer arrives asynchronously via
    /// `isTrusted` flipping — there is no completion callback.
    static func requestAccess() {
        // The literal rather than kAXTrustedCheckOptionPrompt: the SDK
        // exposes that constant as a global var, which Swift 6 rejects as
        // shared mutable state. The underlying string is stable.
        let promptKey = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    }

    static func openSystemSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )!
        NSWorkspace.shared.open(url)
    }

    struct WindowDetails {
        var title: String?
        var documentPath: String?
    }

    /// Focused-window details for a process, or empty details when the grant is
    /// missing, the app exposes nothing, or anything else goes wrong. Total by
    /// design: a failed read must degrade to app-level tracking, never throw.
    static func focusedWindowDetails(pid: pid_t) -> WindowDetails {
        guard isTrusted else { return WindowDetails() }

        let app = AXUIElementCreateApplication(pid)
        guard let window = copyElement(app, kAXFocusedWindowAttribute)
            ?? copyElement(app, kAXMainWindowAttribute)
        else { return WindowDetails() }

        return WindowDetails(
            title: copyString(window, kAXTitleAttribute),
            documentPath: documentPath(of: window)
        )
    }

    /// The open document's path, and only ever a path.
    ///
    /// `kAXDocumentAttribute` is documented as a file URL, but browsers return
    /// the page address instead — Chrome reports `https://…` and
    /// `chrome://newtab/`. Storing those as document paths duplicated the URL
    /// signal and polluted the learned model with nonsense folder features, so
    /// anything that is not a real file path is rejected here.
    private static func documentPath(of window: AXUIElement) -> String? {
        guard let raw = copyString(window, kAXDocumentAttribute), !raw.isEmpty else { return nil }

        let path: String
        if let url = URL(string: raw), url.isFileURL {
            path = url.path
        } else if raw.hasPrefix("/") {
            // Some apps report a bare POSIX path rather than a URL.
            path = raw
        } else {
            return nil
        }
        return markingFolders(path)
    }

    /// A trailing slash on a path that is itself a folder — a terminal's
    /// working directory — so it is not mistaken for a file whose folder is
    /// one level up. Packages (.xcodeproj, .app) are folders on disk but
    /// documents to the person using them, so they stay as they are.
    private static func markingFolders(_ path: String) -> String {
        guard !path.hasSuffix("/") else { return path }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              !NSWorkspace.shared.isFilePackage(atPath: path)
        else { return path }
        return path + "/"
    }

    // ── AX plumbing ──────────────────────────────────────────────────────

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == CFStringGetTypeID() else { return nil }
        let string = value as! CFString as String
        return string.isEmpty ? nil : string
    }
}
