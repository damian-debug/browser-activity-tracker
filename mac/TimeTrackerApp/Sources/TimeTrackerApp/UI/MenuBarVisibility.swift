import AppKit

/// Whether macOS actually put the menu bar icon somewhere a person can see it.
///
/// There is no API for this: `NSStatusItem.isVisible` reports what the app
/// asked for, and stays true when the system hides the icon. And it does hide
/// it, silently — a full menu bar parks new items off-screen, and on a notched
/// MacBook an item can land behind the camera housing. A menu bar app whose
/// icon never appears looks like an app that never started, while it quietly
/// tracks in the background. So the icon's real position is checked instead.
enum MenuBarVisibility {
    enum State: String {
        case visible
        /// Placed on no screen at all: the menu bar had no room.
        case offScreen
        /// On a notched MacBook, at or left of the camera housing. Menu bar
        /// icons only show to its right: an icon pushed further left sits
        /// behind the notch, then behind the current app's menus.
        case behindNotch
        /// No window yet, or no frame to judge by.
        case unknown
    }

    @MainActor
    static func state(of item: NSStatusItem) -> State {
        guard let window = item.button?.window else { return .unknown }
        return state(ofFrame: window.frame, screens: NSScreen.screens.map(ScreenGeometry.init))
    }

    /// The screen facts needed to judge a frame, separated from NSScreen so the
    /// rule can be tested without a display.
    struct ScreenGeometry {
        var frame: NSRect
        /// Global x range hidden by the notch, if the screen has one.
        var notch: ClosedRange<CGFloat>?

        @MainActor
        init(_ screen: NSScreen) {
            frame = screen.frame
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
               right.minX > left.maxX {
                notch = (screen.frame.minX + left.maxX)...(screen.frame.minX + right.minX)
            }
        }

        init(frame: NSRect, notch: ClosedRange<CGFloat>? = nil) {
            self.frame = frame
            self.notch = notch
        }
    }

    static func state(ofFrame frame: NSRect, screens: [ScreenGeometry]) -> State {
        guard frame.width > 0, frame.height > 0 else { return .unknown }
        // Mostly on a screen, not just touching one.
        guard let screen = screens.first(where: {
            $0.frame.intersection(frame).width >= frame.width / 2
        }) else { return .offScreen }
        if let notch = screen.notch, frame.midX < notch.upperBound {
            return .behindNotch
        }
        return .visible
    }
}
