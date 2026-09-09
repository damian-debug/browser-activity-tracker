import AppKit
import TimeTrackerCore

/// Reports which app is frontmost, and when that changes.
///
/// Requires no permission whatsoever, works even sandboxed, and is the only
/// signal guaranteed to be available — which is why the app is useful before
/// the user grants anything.
@MainActor
final class FrontmostAppMonitor {
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    /// A slow poll as a backstop. Activation notifications cover app switches,
    /// but this catches anything that changes without one — and later, once
    /// Accessibility is granted, it is where window-title refreshes hang.
    private let pollInterval: TimeInterval = 2

    var onChange: ((ActivitySnapshot) -> Void)?

    func start() {
        stop()
        let center = NSWorkspace.shared.notificationCenter
        // NOTE: NSWorkspace notifications only arrive on its own centre, never
        // NotificationCenter.default.
        for name in [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.emit() }
            }
            observers.append(token)
        }

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.emit() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        emit()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        timer?.invalidate()
        timer = nil
    }

    func currentSnapshot() -> ActivitySnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier
        else { return nil }

        return ActivitySnapshot(
            bundleID: bundleID,
            appName: app.localizedName ?? bundleID,
            capturedAt: Date()
        )
    }

    private func emit() {
        guard let snapshot = currentSnapshot() else { return }
        onChange?(snapshot)
    }
}
