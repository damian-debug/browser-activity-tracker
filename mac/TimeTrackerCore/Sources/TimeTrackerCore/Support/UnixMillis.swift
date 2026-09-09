import Foundation

// The Chrome extension stored every timestamp as unix milliseconds (a JS
// `number`). We use `Date` throughout the Swift core because its arithmetic is
// far safer, and convert only at the persistence and backup boundaries.
//
// Exactness note: current-era timestamps (~1.7e12 ms) sit well inside Double's
// 15-16 significant digits, so this round-trips losslessly. Do not widen this
// to nanoseconds without revisiting that.
public extension Date {
    init(unixMillis: Int64) {
        self.init(timeIntervalSince1970: Double(unixMillis) / 1000)
    }

    var unixMillis: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
    }
}
