import AppKit
import TimeTrackerCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var statusController: StatusItemController?
    private var titleTimer: Timer?

    func applicationWillTerminate(_ notification: Notification) {
        // Bank the session in progress rather than dropping it on quit.
        guard let model else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await model.shutdown()
            semaphore.signal()
        }
        // Termination will not wait for an async task on its own, and losing
        // the last session is worse than a brief pause here.
        _ = semaphore.wait(timeout: .now() + 2)
    }

    /// Opening the app while it is already running. A menu bar app has no
    /// window to bring forward, so this used to do nothing — the one thing
    /// people try when they cannot find the icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        statusController?.reopen()
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app: no Dock icon, no app menu. The menu bar item is the app.
        NSApp.setActivationPolicy(.accessory)

        do {
            let store = try TrackerStore(path: TrackerStore.defaultDatabaseURL().path)
            try store.seedDefaultsIfEmpty()

            let model = AppModel(store: store)
            let statusController = StatusItemController(model: model)
            self.model = model
            self.statusController = statusController

            model.start()

            let timer = Timer(timeInterval: 1, repeats: true) { _ in
                Task { @MainActor in statusController.refreshTitle() }
            }
            RunLoop.main.add(timer, forMode: .common)
            titleTimer = timer
            statusController.refreshTitle()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Activity Tracker could not start"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
        }
    }
}

// Called by scripts/uninstall.sh just before it deletes the app. Handled
// before NSApplication starts, so no menu bar item or tracking ever spins up.
if CommandLine.arguments.contains("--unregister-login-item") {
    exit(LaunchAtLogin.unregisterForUninstall() ? 0 : 1)
}

// Support diagnostic: `TimeTrackerApp --diagnose-menu-bar [extra] [seconds]`
// shows the icon and reports whether macOS really placed it on screen.
// `extra` adds that many dummy icons, to reproduce a full menu bar; `seconds`
// keeps them up that long (default 3).
if let flag = CommandLine.arguments.firstIndex(of: "--diagnose-menu-bar") {
    let rest = CommandLine.arguments.dropFirst(flag + 1).compactMap(Int.init)
    MenuBarDiagnostic.run(extraItems: rest.first ?? 0, seconds: rest.dropFirst().first ?? 3)
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
