import "fake-indexeddb/auto";
import { describe, it, expect, beforeEach, vi } from "vitest";
import Dexie from "dexie";
import type { ProjectRule, Session } from "../src/shared/types";

const DB_NAME = "BrowserActivityTracker";

function session(id: string, overrides: Partial<Session> = {}): Session {
  return {
    id,
    url: "https://app.justvideowalls.com/dashboard",
    domain: "app.justvideowalls.com",
    title: "Just Video Walls",
    service: null, detectedEntityId: null, detectedEntityName: null,
    projectId: null, projectName: null,
    assignmentSource: "unassigned", assignmentConfidence: 0,
    tagIds: [], billable: false, reviewed: false,
    startTime: 1000, endTime: 61000, durationSeconds: 60,
    createdAt: 0, updatedAt: 0,
    ...overrides,
  };
}

function domainRule(overrides: Partial<ProjectRule> = {}): ProjectRule {
  return {
    id: "rule-1", projectId: "p1", name: "JVW: domain",
    type: "domain_equals", value: "app.justvideowalls.com",
    priority: 0, enabled: true, createdAt: 0, updatedAt: 0,
    ...overrides,
  };
}

beforeEach(async () => {
  await Dexie.delete(DB_NAME);
  vi.resetModules();
});

async function setup(sessions: Session[]) {
  const { db } = await import("../src/storage/db");
  await db.projects.put({
    id: "p1", name: "JVW", clientName: "Just Video Walls",
    defaultBillable: true, archived: false, createdAt: 0, updatedAt: 0,
  });
  await db.sessions.bulkPut(sessions);
  const { applyRuleToExistingSessions } = await import(
    "../src/attribution/apply-rule-to-sessions"
  );
  return { db, applyRuleToExistingSessions };
}

describe("applyRuleToExistingSessions", () => {
  it("assigns matching unassigned+unreviewed sessions and marks them reviewed", async () => {
    const { db, applyRuleToExistingSessions } = await setup([
      session("match-1"),
      session("match-2", { url: "https://app.justvideowalls.com/settings" }),
      session("other-domain", { url: "https://example.com/", domain: "example.com" }),
    ]);

    const count = await applyRuleToExistingSessions(domainRule());
    expect(count).toBe(2);

    const updated = await db.sessions.get("match-1");
    expect(updated!.projectId).toBe("p1");
    expect(updated!.projectName).toBe("JVW");
    expect(updated!.assignmentSource).toBe("auto_rule");
    expect(updated!.matchedRuleId).toBe("rule-1");
    expect(updated!.reviewed).toBe(true);
    expect(updated!.billable).toBe(true); // project default (rule has none)

    const untouched = await db.sessions.get("other-domain");
    expect(untouched!.projectId).toBeNull();
    expect(untouched!.reviewed).toBe(false);
    db.close();
  });

  it("never touches manually assigned or already-reviewed sessions", async () => {
    const { db, applyRuleToExistingSessions } = await setup([
      session("manual", {
        projectId: "p-other", projectName: "Other",
        assignmentSource: "manual_dashboard", assignmentConfidence: 100, reviewed: true,
      }),
      session("reviewed-unassigned", { reviewed: true }),
    ]);

    const count = await applyRuleToExistingSessions(domainRule());
    expect(count).toBe(0);

    const manual = await db.sessions.get("manual");
    expect(manual!.projectId).toBe("p-other");
    const reviewed = await db.sessions.get("reviewed-unassigned");
    expect(reviewed!.projectId).toBeNull();
    db.close();
  });

  it("applies rule default tags/billable when present, and skips disabled rules", async () => {
    const { db, applyRuleToExistingSessions } = await setup([session("s1")]);

    expect(await applyRuleToExistingSessions(domainRule({ enabled: false }))).toBe(0);

    const count = await applyRuleToExistingSessions(
      domainRule({ defaultTagIds: ["t-dev"], defaultBillable: false })
    );
    expect(count).toBe(1);
    const s = await db.sessions.get("s1");
    expect(s!.tagIds).toEqual(["t-dev"]);
    expect(s!.billable).toBe(false); // rule's explicit value beats project default
    db.close();
  });
});
