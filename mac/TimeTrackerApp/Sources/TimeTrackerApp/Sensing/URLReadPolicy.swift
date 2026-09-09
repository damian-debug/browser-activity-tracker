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

    private var ticksSinceRead = 0

    init(blindPollTicks: Int = 3) {
        self.blindPollTicks = blindPollTicks
    }

    /// - Parameters:
    ///   - haveTitles: whether Accessibility is granted, so title changes can
    ///     be used as a proxy for "the tab changed".
    ///   - appChanged: the frontmost app is different from last sample.
    ///   - titleChanged: the window title is different from last sample.
    ///   - haveCachedURL: whether a previous read is still available to reuse.
    mutating func shouldRead(
        haveTitles: Bool,
        appChanged: Bool,
        titleChanged: Bool,
        haveCachedURL: Bool
    ) -> Bool {
        let read: Bool
        if haveTitles {
            // A title change is a strong signal that the tab moved, and costs
            // nothing to detect — so reads follow real navigation, not a clock.
            read = appChanged || titleChanged || !haveCachedURL
        } else {
            ticksSinceRead += 1
            read = appChanged || !haveCachedURL || ticksSinceRead >= blindPollTicks
        }
        if read { ticksSinceRead = 0 }
        return read
    }
}
