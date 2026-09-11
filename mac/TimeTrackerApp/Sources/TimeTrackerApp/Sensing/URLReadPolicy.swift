import Foundation

/// Decides when to spend an Apple Event asking a browser for its URL.
///
/// Extracted and made pure because getting this wrong is invisible: too eager
/// and the app fires tens of thousands of synchronous Apple Events a day at the
/// user's browser; too lazy and it misses tab switches and attributes time to
/// the wrong site. Neither failure announces itself, so both get a test.
struct URLReadPolicy {
    /// How many ticks to wait between reads when there are no window titles to
    /// watch (Accessibility not granted), so the fallback stays cheap.
    var blindPollTicks: Int = 3

    /// How often to re-read on a page whose address changes without its title
    /// (a Figma or Framer tab), so moving to another screen is noticed.
    var locationPollTicks: Int = 2

    private var ticksSinceRead = 0

    /// A title can change a moment before the browser reports the new
    /// address, so the read it triggers may return the old one — seen in real
    /// use as a new page's title paired with the previous page's URL. One
    /// more read on the next tick catches it.
    private var confirmNextTick = false

    init(blindPollTicks: Int = 3, locationPollTicks: Int = 2) {
        self.blindPollTicks = blindPollTicks
        self.locationPollTicks = locationPollTicks
    }

    /// - Parameters:
    ///   - haveTitles: whether Accessibility is granted, so title changes can
    ///     be used as a proxy for "the tab changed".
    ///   - appChanged: the frontmost app is different from last sample.
    ///   - titleChanged: the window title is different from last sample.
    ///   - haveCachedURL: whether a previous read is still available to reuse.
    ///   - locationInURL: the current page is one whose address changes
    ///     without its title, so it needs watching on a clock.
    mutating func shouldRead(
        haveTitles: Bool,
        appChanged: Bool,
        titleChanged: Bool,
        haveCachedURL: Bool,
        locationInURL: Bool = false
    ) -> Bool {
        ticksSinceRead += 1
        let read: Bool
        if haveTitles {
            // A title change is a strong signal that the tab moved, and costs
            // nothing to detect — so reads follow real navigation, not a clock.
            read = appChanged || titleChanged || !haveCachedURL || confirmNextTick
                || (locationInURL && ticksSinceRead >= locationPollTicks)
            confirmNextTick = titleChanged
        } else {
            read = appChanged || !haveCachedURL || ticksSinceRead >= blindPollTicks
        }
        if read { ticksSinceRead = 0 }
        return read
    }
}
