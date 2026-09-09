import AppKit

/// Screen lock, display sleep and system sleep — all reasons to stop counting.
///
/// None of these need permission. Note that the screen-lock notification names
/// are undocumented: they have worked for a decade and are used everywhere, but
/// they are not an API contract, so nothing here should be load-bearing on its
/// own. The wall-clock gap reconciliation in the coordinator is the real safety
/// net for a machine that slept.
@MainActor
final class PowerMonitor {
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []

    var onScreenLocked: ((Bool) -> Void)?
    var onDisplayAsleep: ((Bool) -> Void)?
    /// Fired on wake so the coordinator can reconcile against the wall clock.
    var onWake: (() -> Void)?

    func start() {
        stop()
        let workspace = NSWorkspace.shared.notificationCenter

        func observe(_ name: Notification.Name, _ handler: @escaping @MainActor () -> Void) {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler() }
            }
            workspaceObservers.append(token)
        }

        observe(NSWorkspace.screensDidSleepNotification) { [weak self] in self?.onDisplayAsleep?(true) }
        observe(NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.onDisplayAsleep?(false)
            self?.onWake?()
        }
        observe(NSWorkspace.willSleepNotification) { [weak self] in self?.onDisplayAsleep?(true) }
        observe(NSWorkspace.didWakeNotification) { [weak self] in
            self?.onDisplayAsleep?(false)
            self?.onWake?()
        }
        // Fast user switching: someone else is using the machine now.
        observe(NSWorkspace.sessionDidResignActiveNotification) { [weak self] in self?.onScreenLocked?(true) }
        observe(NSWorkspace.sessionDidBecomeActiveNotification) { [weak self] in
            self?.onScreenLocked?(false)
            self?.onWake?()
        }

        let distributed = DistributedNotificationCenter.default()
        func observeDistributed(_ name: String, _ handler: @escaping @MainActor () -> Void) {
            let token = distributed.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { _ in
                MainActor.assumeIsolated { handler() }
            }
            distributedObservers.append(token)
        }

        observeDistributed("com.apple.screenIsLocked") { [weak self] in self?.onScreenLocked?(true) }
        observeDistributed("com.apple.screenIsUnlocked") { [weak self] in
            self?.onScreenLocked?(false)
            self?.onWake?()
        }
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspace.removeObserver)
        workspaceObservers.removeAll()

        let distributed = DistributedNotificationCenter.default()
        distributedObservers.forEach(distributed.removeObserver)
        distributedObservers.removeAll()
    }
}
