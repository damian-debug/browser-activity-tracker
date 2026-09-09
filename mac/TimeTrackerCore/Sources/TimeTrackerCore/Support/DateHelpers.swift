import Foundation

/// Local-time date bucketing.
///
/// LOAD-BEARING: these must use the user's calendar, never UTC. The extension
/// shipped a real bug where `toISOString()` derived the date in UTC while the
/// day-boundary functions interpreted it locally, so "Today" showed the wrong
/// day for part of every day in any non-UTC timezone. The ported test suite
/// guards this.
public struct DateHelpers: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public static let current = DateHelpers()

    /// Local `YYYY-MM-DD`.
    public func dateString(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public func todayDateString(now: Date = Date()) -> String {
        dateString(for: now)
    }

    public func daysAgoDateString(_ n: Int, now: Date = Date()) -> String {
        let date = calendar.date(byAdding: .day, value: -n, to: now) ?? now
        return dateString(for: date)
    }

    public func date(fromDateString string: String) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        return calendar.date(from: components)
    }

    public func startOfDay(_ dateString: String) -> Date? {
        date(fromDateString: dateString).map { calendar.startOfDay(for: $0) }
    }

    /// Inclusive end of day — the last representable instant before midnight.
    /// Derived from the next day's start so DST transitions stay correct.
    public func endOfDay(_ dateString: String) -> Date? {
        guard let start = startOfDay(dateString),
              let nextDay = calendar.date(byAdding: .day, value: 1, to: start)
        else { return nil }
        return nextDay.addingTimeInterval(-0.001)
    }
}

public enum DurationFormatter {
    /// Compact form for dense UI: `45s`, `12m`, `3m 20s`, `2h 15m`.
    public static func short(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)s" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 && s > 0 { return "\(m)m \(s)s" }
        return "\(m)m"
    }

    /// Rounded form for summaries: `45 sec`, `12m`, `2h 15m`.
    public static func long(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) sec" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0 { return "\(h)h" }
        return "\(m)m"
    }

    /// Zero-padded clock for the menu bar: `0:04:12`.
    public static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
