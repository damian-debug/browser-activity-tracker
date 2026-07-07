import "fake-indexeddb/auto";
import { describe, it, expect, beforeEach, vi } from "vitest";
import Dexie from "dexie";

const DB_NAME = "BrowserActivityTracker";

// V1 record shape (projectId/projectName held PARSER output back then).
const V1_SESSIONS = [
  {
    id: "s1",
    url: "https://bubble.io/page?id=meltx",
    domain: "bubble.io",
    title: "meltx | Bubble Editor",
    service: "bubble",
    projectId: "meltx",
    projectName: null,
    startTime: 1_000_000,
    endTime: 1_060_000,
    durationSeconds: 60,
    synced: false,
  },
  {
    id: "s2",
    url: "https://www.figma.com/design/abc123/My-File",
    domain: "figma.com",
    title: "My File – Figma",
    service: "figma",
    projectId: "abc123",
    projectName: "My File",
    startTime: 2_000_000,
    endTime: 2_120_000,
    durationSeconds: 120,
    synced: true,
  },
  {
    id: "s3",
    url: "https://example.com/docs",
    domain: "example.com",
    title: "Docs",
    service: null,
    projectId: null,
    projectName: null,
    startTime: 3_000_000,
    endTime: 3_030_000,
    durationSeconds: 30,
    synced: false,
  },
];

async function createV1Database(): Promise<void> {
  const v1 = new Dexie(DB_NAME);
  v1.version(1).stores({
    sessions: "id, domain, startTime, endTime, projectId, service, synced",
  });
  await v1.open();
  await v1.table("sessions").bulkPut(V1_SESSIONS);
  v1.close();
}

beforeEach(async () => {
  await Dexie.delete(DB_NAME);
  vi.resetModules();
});

describe("V1 → V2 migration", () => {
  it("moves parser output to detectedEntity* and resets attribution", async () => {
    await createV1Database();

    const { db } = await import("../src/storage/db");
    const sessions = await db.sessions.orderBy("startTime").toArray();
    expect(sessions).toHaveLength(3);

    const [bubble, figma, plain] = sessions;

    // Parser output moved
    expect(bubble.detectedEntityId).toBe("meltx");
    expect(bubble.detectedEntityName).toBeNull();
    expect(figma.detectedEntityId).toBe("abc123");
    expect(figma.detectedEntityName).toBe("My File");
    expect(plain.detectedEntityId).toBeNull();

    // Attribution reset to unassigned for all
    for (const s of sessions) {
      expect(s.projectId).toBeNull();
      expect(s.assignmentSource).toBe("unassigned");
      expect(s.assignmentConfidence).toBe(0);
      expect(s.tagIds).toEqual([]);
      expect(s.billable).toBe(false);
      expect(s.reviewed).toBe(false);
      expect("synced" in s).toBe(false);
    }

    // Tracking data untouched
    expect(figma.durationSeconds).toBe(120);
    expect(figma.startTime).toBe(2_000_000);
    db.close();
  });

  it("strips sync bookkeeping fields entirely (v3)", async () => {
    await createV1Database();

    const { db } = await import("../src/storage/db");

    // v1's `synced` was converted to `syncedToSheets` in v2, then dropped in
    // v3 when the Sheets sync was removed. Neither survives.
    const all = await db.sessions.toArray();
    for (const s of all as unknown as Record<string, unknown>[]) {
      expect("synced" in s).toBe(false);
      expect("syncedToSheets" in s).toBe(false);
    }
    db.close();
  });

  it("seedDefaults is idempotent and only fills empty tables", async () => {
    await createV1Database();

    const { db } = await import("../src/storage/db");
    const { seedDefaults } = await import("../src/storage/seed-defaults");

    await seedDefaults();
    const tagCount = await db.tags.count();
    const projectCount = await db.projects.count();
    expect(tagCount).toBe(10);
    expect(projectCount).toBe(1);
    expect((await db.projects.toArray())[0].name).toBe("Internal");

    // Second run must not duplicate
    await seedDefaults();
    expect(await db.tags.count()).toBe(10);
    expect(await db.projects.count()).toBe(1);
    db.close();
  });

  it("fresh install (no V1 data) opens cleanly at v3", async () => {
    const { db } = await import("../src/storage/db");
    await db.open();
    expect(await db.sessions.count()).toBe(0);
    expect(db.verno).toBe(3);
    db.close();
  });
});
