import Testing
import Foundation
@testable import TimeTrackerCore

// Ported from extension/tests/utils.test.ts.
//
// These exist because the extension shipped a real bug: date strings were
// derived in UTC via toISOString() while the day-boundary functions parsed them
// as local time, so "Today" showed the wrong day between local midnight and the
// UTC offset. Asia/Colombo (UTC+5:30, no DST) is pinned deliberately — a
// half-hour offset catches a whole class of mistakes a whole-hour zone hides.

private func colomboHelpers() -> DateHelpers {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Colombo")!
    return DateHelpers(calendar: calendar)
}

private func instant(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: iso)!
}

@Suite("Local date handling")
struct DateHelpersTests {
    let helpers = colomboHelpers()

    @Test("uses the LOCAL date shortly after local midnight, while UTC is still on the previous day")
    func localDateAfterMidnight() {
        // 2026-01-01 20:00 UTC is 2026-01-02 01:30 in Colombo.
        let now = instant("2026-01-01T20:00:00Z")
        #expect(helpers.todayDateString(now: now) == "2026-01-02")
        #expect(helpers.dateString(for: now) == "2026-01-02")
        #expect(helpers.daysAgoDateString(0, now: now) == "2026-01-02")
        #expect(helpers.daysAgoDateString(1, now: now) == "2026-01-01")
    }

    @Test("'now' always falls inside today's window, at any hour of the day")
    func nowIsAlwaysInsideToday() {
        let moments = [
            "2026-01-01T18:31:00Z",  // 00:01 local
            "2026-01-02T18:29:00Z",  // 23:59 local
            "2026-01-02T06:30:00Z",  // 12:00 local
        ]
        for iso in moments {
            let now = instant(iso)
            let today = helpers.todayDateString(now: now)
            let start = try! #require(helpers.startOfDay(today))
            let end = try! #require(helpers.endOfDay(today))
            #expect(start <= now, "start of \(today) should not be after \(iso)")
            #expect(end >= now, "end of \(today) should not be before \(iso)")
        }
    }

    @Test("day windows are contiguous: yesterday ends immediately before today starts")
    func contiguousDayWindows() {
        let now = instant("2026-01-02T06:30:00Z")
        let yesterdayEnd = try! #require(helpers.endOfDay(helpers.daysAgoDateString(1, now: now)))
        let todayStart = try! #require(helpers.startOfDay(helpers.todayDateString(now: now)))

        #expect(yesterdayEnd < todayStart)
        // Exactly one millisecond of separation, and no overlap.
        #expect(todayStart.timeIntervalSince(yesterdayEnd) < 0.002)
    }

    @Test("a day is 24 hours long in a zone without DST")
    func dayLength() {
        let start = try! #require(helpers.startOfDay("2026-01-02"))
        let end = try! #require(helpers.endOfDay("2026-01-02"))
        #expect(abs(end.timeIntervalSince(start) - (86_400 - 0.001)) < 0.002)
    }

    @Test("malformed date strings yield nil rather than a wrong date")
    func malformedInput() {
        #expect(helpers.startOfDay("not-a-date") == nil)
        #expect(helpers.startOfDay("2026-01") == nil)
        #expect(helpers.date(fromDateString: "") == nil)
    }
}

@Suite("Duration formatting")
struct DurationFormatterTests {
    @Test("short form matches the extension's compact display")
    func shortForm() {
        #expect(DurationFormatter.short(45) == "45s")
        #expect(DurationFormatter.short(60) == "1m")
        #expect(DurationFormatter.short(200) == "3m 20s")
        #expect(DurationFormatter.short(8100) == "2h 15m")
    }

    @Test("long form rounds to whole minutes")
    func longForm() {
        #expect(DurationFormatter.long(45) == "45 sec")
        #expect(DurationFormatter.long(200) == "3m")
        #expect(DurationFormatter.long(8100) == "2h 15m")
        #expect(DurationFormatter.long(7200) == "2h")
    }

    @Test("clock form is zero-padded for the menu bar")
    func clockForm() {
        #expect(DurationFormatter.clock(65) == "1:05")
        #expect(DurationFormatter.clock(3725) == "1:02:05")
    }
}
