import { describe, it, expect } from "vitest";
import { csvEscape, sessionsToCsv } from "../src/shared/csv";
import type { Project, Session, Tag } from "../src/shared/types";

const project: Project = {
  id: "p1", name: "RoleKick", clientName: "Acme, Inc.", defaultBillable: true,
  archived: false, createdAt: 0, updatedAt: 0,
};

const tags: Tag[] = [
  { id: "t1", name: "Development", createdAt: 0, updatedAt: 0 },
  { id: "t2", name: "QA", createdAt: 0, updatedAt: 0 },
];

function session(overrides: Partial<Session> = {}): Session {
  return {
    id: "s1",
    url: "https://example.com/a?x=1",
    domain: "example.com",
    title: "Plain title",
    service: null, detectedEntityId: null, detectedEntityName: null,
    projectId: "p1", projectName: "RoleKick",
    assignmentSource: "auto_rule", assignmentConfidence: 95,
    tagIds: ["t1", "t2"], billable: true, reviewed: true,
    startTime: Date.UTC(2026, 0, 2, 10, 0, 0),
    endTime: Date.UTC(2026, 0, 2, 11, 0, 0),
    durationSeconds: 3600,
    createdAt: 0, updatedAt: 0,
    ...overrides,
  };
}

describe("csvEscape", () => {
  it("passes plain values through and quotes commas, quotes, and newlines", () => {
    expect(csvEscape("plain")).toBe("plain");
    expect(csvEscape("a,b")).toBe('"a,b"');
    expect(csvEscape('say "hi"')).toBe('"say ""hi"""');
    expect(csvEscape("line1\nline2")).toBe('"line1\nline2"');
  });
});

describe("sessionsToCsv", () => {
  it("emits a header plus one row per session with resolved names", () => {
    const csv = sessionsToCsv([session()], [project], tags);
    const lines = csv.trim().split("\r\n");
    expect(lines).toHaveLength(2);
    expect(lines[0].startsWith("Date,Start,End,Duration (seconds),Project,Client")).toBe(true);
    expect(lines[1]).toContain("RoleKick");
    expect(lines[1]).toContain('"Acme, Inc."');
    expect(lines[1]).toContain("Development, QA");
    expect(lines[1]).toContain("3600");
  });

  it("quotes titles containing commas, quotes, and newlines without breaking rows", () => {
    const tricky = session({ title: 'Board, "Q1" plan\nfinal', tagIds: [] });
    const csv = sessionsToCsv([tricky], [project], tags);
    // The embedded newline is inside quotes — splitting on CRLF must still
    // yield exactly header + 1 logical row terminator.
    expect(csv).toContain('"Board, ""Q1"" plan\nfinal"');
    expect(csv.endsWith("\r\n")).toBe(true);
  });

  it("falls back to Unassigned and denormalized names for unknown projects", () => {
    const orphan = session({ projectId: "gone", projectName: "Old Name", tagIds: ["missing"] });
    const csv = sessionsToCsv([orphan, session({ projectId: null, projectName: null })], [], []);
    const lines = csv.trim().split("\r\n");
    expect(lines[1]).toContain("Old Name");   // falls back to stored name
    expect(lines[1]).toContain("missing");    // unknown tag id kept as-is
    expect(lines[2]).toContain("Unassigned");
  });
});
