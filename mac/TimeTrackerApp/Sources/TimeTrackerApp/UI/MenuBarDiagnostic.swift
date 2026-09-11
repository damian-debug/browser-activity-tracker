import AppKit

/// `--diagnose-menu-bar`: what the menu bar did with our icon, for support.
/// Starts no tracking and touches no data.
@MainActor
enum MenuBarDiagnostic {
    static func run(extraItems: Int, seconds: Int) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        var items: [NSStatusItem] = []
        let ours = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        ours.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Activity Tracker")
        ours.button?.title = " 0:00:00"
        items.append(ours)
        for i in 0..<extraItems {
            let dummy = NSStatusBar.system.statusItem(withLength: 90)
            dummy.button?.title = "test \(i + 1)"
            items.append(dummy)
        }

        for screen in NSScreen.screens {
            let g = MenuBarVisibility.ScreenGeometry(screen)
            print("screen x=\(Int(g.frame.minX))…\(Int(g.frame.maxX))" +
                  (g.notch.map { "  notch x=\(Int($0.lowerBound))…\(Int($0.upperBound))" } ?? "  no notch"))
        }

        // Give the menu bar a moment to lay the items out before judging them.
        RunLoop.main.run(until: Date().addingTimeInterval(TimeInterval(max(1, seconds))))
        for (index, item) in items.enumerated() {
            let frame = item.button?.window?.frame ?? .zero
            let label = index == 0 ? "Activity Tracker icon" : "dummy \(index)"
            print(String(format: "%-22@ x=%7.0f w=%4.0f  isVisible=%@  → %@",
                         label as NSString, frame.minX, frame.width,
                         item.isVisible ? "true" : "false",
                         MenuBarVisibility.state(of: item).rawValue))
        }
        items.forEach { NSStatusBar.system.removeStatusItem($0) }
        exit(0)
    }
}
