import Testing
import AppKit
@testable import TimeTrackerApp

// Positions recorded by `--diagnose-menu-bar 12` on a 14" MacBook Pro running
// macOS 26: screen 0…1470, camera housing 646…825, items pushed leftwards.
private let macbook = MenuBarVisibility.ScreenGeometry(
    frame: NSRect(x: 0, y: 0, width: 1470, height: 956), notch: 646...825
)
private func item(_ x: CGFloat, _ width: CGFloat = 106) -> NSRect {
    NSRect(x: x, y: 932, width: width, height: 24)
}
private func state(_ frame: NSRect, _ screens: [MenuBarVisibility.ScreenGeometry] = [macbook]) -> MenuBarVisibility.State {
    MenuBarVisibility.state(ofFrame: frame, screens: screens)
}

@Suite("Is the menu bar icon really visible?")
struct MenuBarVisibilityTests {
    @Test("right of the notch: visible", arguments: [item(942, 90), item(838, 90), item(928)])
    func rightOfNotch(frame: NSRect) { #expect(state(frame) == .visible) }

    @Test("behind the notch, or pushed left of it behind the app's menus: hidden",
          arguments: [item(732), item(626), item(520), item(96), item(-10)])
    func behindNotch(frame: NSRect) { #expect(state(frame) == .behindNotch) }

    @Test("parked off every screen: hidden", arguments: [item(-116), item(-328), item(-4220)])
    func offScreen(frame: NSRect) { #expect(state(frame) == .offScreen) }

    @Test("without a notch, anywhere on the menu bar counts as visible")
    func noNotch() {
        let display = MenuBarVisibility.ScreenGeometry(frame: NSRect(x: 0, y: 0, width: 1920, height: 1080))
        #expect(state(item(500), [display]) == .visible)
    }

    @Test("an icon shown on an external display is visible, notch or not")
    func externalDisplay() {
        let external = MenuBarVisibility.ScreenGeometry(frame: NSRect(x: 1470, y: 0, width: 1920, height: 1080))
        #expect(state(item(3000), [macbook, external]) == .visible)
    }

    @Test("no frame to judge by is unknown — never reported as hidden")
    func unknown() { #expect(state(.zero) == .unknown) }
}
