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

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
