import { describe, it, expect } from "vitest";
import { splitSession, type SplitRequest } from "../src/shared/split-session";
import type { Session } from "../src/shared/types";

const HOUR = 3600_000;

const original: Session = {
  id: "orig",
  url: "https://bubble.io/page?id=sampleapp",
  domain: "bubble.io",
  title: "sampleapp | Bubble Editor",
  service: "bubble",
  detectedEntityId: "sampleapp",
  detectedEntityName: null,
  projectId: null,
  projectName: null,
  assignmentSource: "unassigned",
  assignmentConfidence: 0,
  tagIds: [],
  billable: false,
  reviewed: false,
  startTime: 9 * HOUR,        // 09:00
  endTime: 17 * HOUR,         // 17:00 (8h wall)
  durationSeconds: 6 * 3600,  // 6h active
  createdAt: 0,
  updatedAt: 0,
};

function segment(projectId: string | null, billable = false) {
  return { projectId, projectName: projectId ? `Project ${projectId}` : null, tagIds: [], billable };
}

describe("splitSession", () => {
  it("splits the spec's 8h example into 3h + 5h wall segments with proportional active time", () => {
    const result = splitSession(original, {
      boundaries: [12 * HOUR], // split at 12:00
      segments: [segment("A"), segment("B")],
    });

    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const [a, b] = result.sessions;

    expect(a.startTime).toBe(9 * HOUR);
    expect(a.endTime).toBe(12 * HOUR);
    expect(b.startTime).toBe(12 * HOUR);
    expect(b.endTime).toBe(17 * HOUR);

    // 3/8 and 5/8 of the 6h active time
    expect(a.durationSeconds).toBe(8100);   // 2h15m
    expect(b.durationSeconds).toBe(13500);  // 3h45m
    expect(a.durationSeconds + b.durationSeconds).toBe(original.durationSeconds);
  });

  it("conserves total active seconds exactly even with rounding", () => {
    const result = splitSession(
      { ...original, durationSeconds: 6001 },
      {
        boundaries: [10 * HOUR + 1234, 13 * HOUR + 5678],
        segments: [segment("A"), segment("B"), segment("C")],
      }
    );
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const total = result.sessions.reduce((sum, s) => sum + s.durationSeconds, 0);
    expect(total).toBe(6001);
  });

  it("assigns new ids and marks segments manual/reviewed", () => {
    const result = splitSession(original, {
      boundaries: [12 * HOUR],
      segments: [segment("A", true), segment(null)],
    });
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    const [a, b] = result.sessions;

    expect(a.id).not.toBe("orig");
    expect(b.id).not.toBe("orig");
    expect(a.id).not.toBe(b.id);

    expect(a.assignmentSource).toBe("manual_dashboard");
    expect(a.assignmentConfidence).toBe(100);
    expect(a.reviewed).toBe(true);     // got a project
    expect(a.billable).toBe(true);
    expect(b.reviewed).toBe(false);    // left unassigned

    // URL/domain/title preserved
    expect(a.url).toBe(original.url);
    expect(a.domain).toBe(original.domain);
    expect(a.title).toBe(original.title);
  });

  it("rejects boundaries outside the session window", () => {
    expect(
      splitSession(original, { boundaries: [8 * HOUR], segments: [segment("A"), segment("B")] }).ok
    ).toBe(false);
    expect(
      splitSession(original, { boundaries: [17 * HOUR], segments: [segment("A"), segment("B")] }).ok
    ).toBe(false);
  });

  it("rejects non-ascending boundaries", () => {
    const req: SplitRequest = {
      boundaries: [13 * HOUR, 11 * HOUR],
      segments: [segment("A"), segment("B"), segment("C")],
    };
    expect(splitSession(original, req).ok).toBe(false);
  });

  it("rejects fewer than two segments", () => {
    expect(splitSession(original, { boundaries: [], segments: [segment("A")] }).ok).toBe(false);
  });
});
