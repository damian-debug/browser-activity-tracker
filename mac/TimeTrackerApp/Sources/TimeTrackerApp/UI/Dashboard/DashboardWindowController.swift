import AppKit
import SwiftUI

/// Owns the dashboard window.
///
/// An accessory app is never activated by a click, so opening a window without
/// activating first leaves it behind whatever the user was doing.
@MainActor
final class DashboardWindowController {
    private var window: NSWindow?
    private let store: TrackerStore

    init(store: TrackerStore) {
        self.store = store
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let model = DashboardModel(store: store)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Activity Tracker"
        window.contentViewController = NSHostingController(rootView: DashboardView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("dashboard")

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
