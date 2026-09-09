import AppKit
import SwiftUI

/// The menu bar item and its popover.
///
/// Deliberately NSStatusItem rather than SwiftUI's MenuBarExtra: MenuBarExtra
/// still has no open/close event (so the panel cannot refresh just-in-time),
/// its `.menu` style blocks the run loop, and it exposes no handle for
/// right-click. NSStatusItem is what shipping menu bar apps use, and hosting
/// SwiftUI inside the popover costs nothing.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let dashboard: DashboardWindowController

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.dashboard = DashboardWindowController(store: model.store)
        super.init()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 420)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(model: model, openDashboard: { [weak self] in
                self?.popover.performClose(nil)
                self?.dashboard.show()
            })
        )
        popover.delegate = self

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "timer", accessibilityDescription: "Activity Tracker"
            )
            // A template image adapts itself to light and dark menu bars.
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// Called on the app's tick so the menu bar clock stays live.
    func refreshTitle() {
        guard let button = statusItem.button else { return }
        let title = model.statusItemTitle
        button.title = title.isEmpty ? "" : " \(title)"
    }

    @objc private func togglePopover() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
            return
        }

        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            Task { await model.refresh() }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // An accessory app is not activated by a click, so the popover
            // would otherwise open behind whatever is frontmost.
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: model.isManuallyPaused ? "Resume Tracking" : "Pause Tracking",
                     action: #selector(togglePause), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Open Dashboard…",
                     action: #selector(openDashboard), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Activity Tracker",
                     action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Detach again so the next left-click opens the popover, not the menu.
        statusItem.menu = nil
    }

    @objc private func togglePause() {
        Task { await model.togglePause() }
    }

    @objc private func openDashboard() {
        dashboard.show()
    }
}
