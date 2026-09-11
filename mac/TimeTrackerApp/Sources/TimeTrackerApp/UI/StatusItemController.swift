import AppKit
import OSLog
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
    private static let log = Logger(subsystem: "studio.goodspeed.timetracker", category: "menubar")
    private var windowed: NSWindow?
    private var hasShownHiddenNotice = false

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

        // macOS hides the icon without telling anyone when the menu bar is
        // full — and a new app's icon is the first to go. Give the menu bar a
        // moment to place it, then look where it actually went; look again
        // whenever the displays change (unplugging an external monitor leaves
        // only the notched one).
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.checkIconVisibility()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
    }

    // ── A hidden icon ────────────────────────────────────────────────────

    private var iconIsHidden: Bool {
        switch MenuBarVisibility.state(of: statusItem) {
        case .offScreen, .behindNotch: return true
        // Unsure is not hidden: never pop a window on a guess.
        case .visible, .unknown: return false
        }
    }

    private func checkIconVisibility() {
        // Logged for support, readable with `log show` or Console.app. Only
        // the icon's position — nothing about what is being tracked.
        let frame = statusItem.button?.window?.frame ?? .zero
        let state = MenuBarVisibility.state(of: statusItem).rawValue
        Self.log.notice("Menu bar icon at x=\(Int(frame.minX), privacy: .public) w=\(Int(frame.width), privacy: .public): \(state, privacy: .public)")
        guard iconIsHidden, !hasShownHiddenNotice else { return }
        hasShownHiddenNotice = true
        showWindowed(iconHidden: true)
    }

    @objc private func screensChanged() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.checkIconVisibility()
        }
    }

    /// The app was opened again — from Spotlight, Launchpad or Applications.
    /// Before this, that did nothing at all, which is exactly what someone
    /// whose icon is hidden would try first.
    func reopen() {
        if iconIsHidden {
            showWindowed(iconHidden: true)
        } else if !popover.isShown {
            showPopover()
        }
    }

    private func showWindowed(iconHidden: Bool) {
        popover.performClose(nil)
        let window = windowed ?? {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.title = "Activity Tracker"
            window.isReleasedWhenClosed = false
            window.center()
            windowed = window
            return window
        }()
        window.contentViewController = NSHostingController(
            rootView: HiddenIconView(
                model: model,
                iconHidden: iconHidden,
                openMenuBarSettings: {
                    // macOS 26 calls this pane Menu Bar; it holds the
                    // "Allow in the Menu Bar" list. Older versions open
                    // Control Centre, where menu bar items were set before.
                    if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                },
                openDashboard: { [weak self] in self?.dashboard.show() }
            )
        )
        Task { await model.refresh() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        Task { await model.refresh() }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        // An accessory app is not activated by a click, so the popover
        // would otherwise open behind whatever is frontmost.
        popover.contentViewController?.view.window?.makeKey()
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
