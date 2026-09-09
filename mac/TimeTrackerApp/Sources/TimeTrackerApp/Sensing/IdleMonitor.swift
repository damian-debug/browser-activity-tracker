import Foundation
import CoreGraphics

/// Watches for the user going idle and coming back.
///
/// `CGEventSource.secondsSinceLastEventType` needs no permission at all — no
/// TCC prompt, no entitlement. That matters: the alternatives (a global event
/// monitor, or a CGEventTap) would require Input Monitoring or Accessibility
/// just to answer "is anyone there?".
@MainActor
final class IdleMonitor {
    /// How often to check. Cheap enough that a short interval costs nothing,
    /// and it bounds how much idle time can be miscredited as active.
    private let pollInterval: TimeInterval = 5

    private var timer: Timer?
    private var isIdle = false

    var thresholdSeconds: TimeInterval
    var onChange: ((Bool) -> Void)?

    init(thresholdSeconds: TimeInterval) {
        self.thresholdSeconds = thresholdSeconds
    }

    static var secondsSinceLastInput: TimeInterval {
        // kCGAnyInputEventType has no Swift enum case; it is the all-ones value
        // and covers keyboard, mouse and tablet input.
        let anyInput = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        // .common so polling continues while a menu or popover is tracking.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func check() {
        let idleNow = Self.secondsSinceLastInput >= thresholdSeconds
        guard idleNow != isIdle else { return }
        isIdle = idleNow
        onChange?(idleNow)
    }

    /// When returning from idle, the time already spent away — used to offer
    /// "you were away 34 minutes, what was that?" rather than silently dropping it.
    var currentIdleSeconds: TimeInterval { Self.secondsSinceLastInput }
}
