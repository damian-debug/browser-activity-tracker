import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

// Pin a non-UTC zone (UTC+05:30, no DST) BEFORE using Date: these tests exist
// because date strings were previously derived via toISOString() (UTC) while
// startOfDayMs/endOfDayMs interpret them in local time — shifting "today" by
// the timezone offset around midnight.
process.env.TZ = "Asia/Colombo";

import {
  todayDateString,
  daysAgoDateString,
  dateStringForTimestamp,
  startOfDayMs,
  endOfDayMs,
} from "../src/shared/utils";

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("local date strings (UTC/local mismatch fix)", () => {
  it("uses the LOCAL date shortly after local midnight (UTC still on the previous day)", () => {
    // 2026-01-01 20:00 UTC = 2026-01-02 01:30 in Asia/Colombo
    vi.setSystemTime(new Date("2026-01-01T20:00:00Z"));
    expect(todayDateString()).toBe("2026-01-02");
    expect(dateStringForTimestamp(Date.now())).toBe("2026-01-02");
    expect(daysAgoDateString(0)).toBe("2026-01-02");
    expect(daysAgoDateString(1)).toBe("2026-01-01");
  });

  it("keeps 'now' inside today's [startOfDay, endOfDay] window at any hour", () => {
    // The invariant the dashboard/popup rely on. Check the tricky edges.
    for (const iso of [
      "2026-01-01T18:31:00Z", // 2026-01-02 00:01 local
      "2026-01-02T18:29:00Z", // 2026-01-02 23:59 local
      "2026-01-02T06:30:00Z", // 2026-01-02 12:00 local
    ]) {
      vi.setSystemTime(new Date(iso));
      const today = todayDateString();
      expect(startOfDayMs(today)).toBeLessThanOrEqual(Date.now());
      expect(endOfDayMs(today)).toBeGreaterThanOrEqual(Date.now());
    }
  });

  it("day windows are contiguous: yesterday's end + 1ms = today's start", () => {
    vi.setSystemTime(new Date("2026-01-02T06:30:00Z"));
    expect(endOfDayMs(daysAgoDateString(1)) + 1).toBe(startOfDayMs(todayDateString()));
  });
});
