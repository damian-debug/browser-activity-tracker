import AppKit
import ApplicationServices

/// Dumps what the Accessibility tree actually exposes for the frontmost app.
///
/// Only the tracker holds the Accessibility grant, so this has to live inside
/// it rather than in a script. Off unless a marker file exists, because it
/// walks the tree and that is not free.
///
///     touch ~/Library/Application\ Support/TimeTracker/DEBUG_AX
@MainActor
enum AXInspector {
    static var isEnabled: Bool {
        guard let url = try? markerURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func markerURL() throws -> URL {
        try TrackerStore.defaultDatabaseURL()
            .deletingLastPathComponent()
            .appendingPathComponent("DEBUG_AX")
    }

    private static func outputURL(for bundleID: String) throws -> URL {
        try TrackerStore.defaultDatabaseURL()
            .deletingLastPathComponent()
            .appendingPathComponent("ax-\(bundleID).txt")
    }

    /// Apps already dumped this run. Walking a tree six levels deep is far too
    /// expensive to repeat on every two-second sample, and the shape of an
    /// app's tree does not change often enough to be worth it.
    private static var dumped: Set<String> = []

    static func dumpFrontmostApp() {
        guard isEnabled,
              let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              !dumped.contains(bundleID)
        else { return }
        dumped.insert(bundleID)

        var report = "=== \(app.localizedName ?? bundleID) (\(bundleID)) ===\n"
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // Chromium — and so every Electron app — ships a stub accessibility
        // tree of empty groups until a client asks for the real one by setting
        // this. Without it, Claude and VS Code look like they expose nothing.
        let enabled = AXUIElementSetAttributeValue(
            appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue
        )
        report += "AXManualAccessibility set: \(enabled == .success)\n"
        if enabled == .success {
            // Building the tree is not instantaneous.
            Thread.sleep(forTimeInterval: 1.0)
        }

        report += "\n-- application attributes --\n"
        report += describe(appElement, indent: "  ")

        if let window = copyElement(appElement, kAXFocusedWindowAttribute)
            ?? copyElement(appElement, kAXMainWindowAttribute) {
            report += "\n-- focused window attributes --\n"
            report += describe(window, indent: "  ")

            report += "\n-- window tree (roles, titles, urls) --\n"
            report += tree(window, indent: "  ", depth: 0, maxDepth: 14)

            // Exhaustive hunt for readable text, bounded by node count rather
            // than depth: the question is whether a human-readable label
            // exists anywhere at all, not where it sits.
            report += "\n-- readable text found anywhere (bounded) --\n"
            var budget = 6000
            var found: [String] = []
            collectText(window, budget: &budget, found: &found)
            report += found.prefix(60).joined(separator: "\n")
            report += "\n(nodes visited: \(6000 - budget), texts: \(found.count))\n"
        } else {
            report += "\n(no focused or main window)\n"
        }

        if let url = try? outputURL(for: bundleID) {
            try? report.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // ── Walking ──────────────────────────────────────────────────────────

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func attributeNames(_ element: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyAttributeNames(element, &names) == .success,
              let list = names as? [String] else { return [] }
        return list
    }

    private static func describe(_ element: AXUIElement, indent: String) -> String {
        var out = ""
        for name in attributeNames(element).sorted() {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
                  let value else { continue }

            let typeID = CFGetTypeID(value)
            if typeID == CFStringGetTypeID() {
                let string = value as! CFString as String
                if !string.isEmpty { out += "\(indent)\(name) = \(truncate(string))\n" }
            } else if typeID == CFURLGetTypeID() {
                out += "\(indent)\(name) = \(value as! CFURL)\n"
            } else if typeID == CFArrayGetTypeID() {
                out += "\(indent)\(name) = [\((value as! CFArray as NSArray).count) items]\n"
            } else if typeID == AXUIElementGetTypeID() {
                out += "\(indent)\(name) = <element>\n"
            }
        }
        return out
    }

    /// Roles, titles, values and URLs down the tree — enough to spot where an
    /// app hides the thing a person would call "what I am working on".
    private static func tree(
        _ element: AXUIElement, indent: String, depth: Int, maxDepth: Int
    ) -> String {
        guard depth <= maxDepth else { return "" }

        let role = string(element, kAXRoleAttribute) ?? "?"
        var labels = ""
        for attribute in [kAXTitleAttribute, kAXValueAttribute, kAXDescriptionAttribute, "AXURL"] {
            if let value = string(element, attribute), !value.isEmpty {
                labels += "  \(attribute)=\(truncate(value))"
            }
        }

        // Unlabelled container groups are almost all of an Electron tree and
        // tell us nothing; keep only what carries text or identity.
        var line = ""
        if !labels.isEmpty || !role.hasSuffix("Group") {
            line = "\(indent)\(role)\(labels)\n"
        }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &children
        ) == .success, let list = children as? [AXUIElement] else { return line }

        for child in list.prefix(40) {
            line += tree(child, indent: indent + "  ", depth: depth + 1, maxDepth: maxDepth)
        }
        return line
    }

    /// Walk everything, collecting anything a person could read.
    private static func collectText(
        _ element: AXUIElement, budget: inout Int, found: inout [String]
    ) {
        guard budget > 0 else { return }
        budget -= 1

        let role = string(element, kAXRoleAttribute) ?? ""
        for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            if let value = string(element, attribute),
               value.count > 2, value.count < 200 {
                found.append("\(role).\(attribute): \(truncate(value, limit: 90))")
            }
        }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &children
        ) == .success, let list = children as? [AXUIElement] else { return }
        for child in list {
            collectText(child, budget: &budget, found: &found)
        }
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        if CFGetTypeID(value) == CFStringGetTypeID() { return (value as! CFString) as String }
        if CFGetTypeID(value) == CFURLGetTypeID() { return (value as! CFURL as URL).absoluteString }
        return nil
    }

    private static func truncate(_ text: String, limit: Int = 120) -> String {
        let flattened = text.replacingOccurrences(of: "\n", with: " ")
        return flattened.count > limit ? String(flattened.prefix(limit)) + "…" : flattened
    }
}
