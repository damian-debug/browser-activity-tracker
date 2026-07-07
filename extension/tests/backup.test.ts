import { describe, it, expect } from "vitest";
import {
  buildBackup,
  validateBackup,
  planImport,
  BACKUP_FORMAT,
  BACKUP_SCHEMA_VERSION,
  type BackupData,
} from "../src/shared/backup";
import { DEFAULT_SETTINGS } from "../src/shared/constants";
import type { Project, ProjectRule, Session, Tag } from "../src/shared/types";

function project(id: string, updatedAt: number, name = `Project ${id}`): Project {
  return { id, name, defaultBillable: false, archived: false, createdAt: 0, updatedAt };
}

function tag(id: string, updatedAt: number): Tag {
  return { id, name: `Tag ${id}`, createdAt: 0, updatedAt };
}

function rule(id: string, updatedAt: number): ProjectRule {
  return {
    id, projectId: "p1", name: `Rule ${id}`, type: "domain_equals", value: "example.com",
    priority: 0, enabled: true, createdAt: 0, updatedAt,
  };
}

function session(id: string, updatedAt: number): Session {
  return {
    id, url: "https://example.com/", domain: "example.com", title: "Example",
    service: null, detectedEntityId: null, detectedEntityName: null,
    projectId: null, projectName: null, assignmentSource: "unassigned",
    assignmentConfidence: 0, tagIds: [], billable: false, reviewed: false,
    startTime: 1000, endTime: 2000, durationSeconds: 1,
    createdAt: 0, updatedAt,
  };
}

function sampleData(): BackupData {
  return {
    settings: DEFAULT_SETTINGS,
    projects: [project("p1", 10)],
    tags: [tag("t1", 10)],
    rules: [rule("r1", 10)],
    sessions: [session("s1", 10)],
  };
}

describe("buildBackup / validateBackup", () => {
  it("round-trips through JSON and validates", () => {
    const backup = buildBackup(sampleData(), 123);
    expect(backup.format).toBe(BACKUP_FORMAT);
    expect(backup.schemaVersion).toBe(BACKUP_SCHEMA_VERSION);
    expect(backup.exportedAt).toBe(123);

    const parsed = JSON.parse(JSON.stringify(backup));
    const result = validateBackup(parsed);
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.backup.sessions).toHaveLength(1);
      expect(result.backup.projects[0].name).toBe("Project p1");
    }
  });

  it("rejects non-objects and foreign files", () => {
    expect(validateBackup(null).ok).toBe(false);
    expect(validateBackup([]).ok).toBe(false);
    expect(validateBackup("{}").ok).toBe(false);
    expect(validateBackup({ format: "something-else" }).ok).toBe(false);
  });

  it("rejects backups from a NEWER schema version", () => {
    const backup = JSON.parse(JSON.stringify(buildBackup(sampleData())));
    backup.schemaVersion = BACKUP_SCHEMA_VERSION + 1;
    const result = validateBackup(backup);
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toMatch(/newer version/);
  });

  it("rejects missing tables, records without ids, and sessions without time fields", () => {
    const base = () => JSON.parse(JSON.stringify(buildBackup(sampleData())));

    const noTags = base();
    delete noTags.tags;
    expect(validateBackup(noTags).ok).toBe(false);

    const badId = base();
    badId.projects[0].id = "";
    expect(validateBackup(badId).ok).toBe(false);

    const badSession = base();
    delete badSession.sessions[0].startTime;
    expect(validateBackup(badSession).ok).toBe(false);

    const noSettings = base();
    delete noSettings.settings;
    expect(validateBackup(noSettings).ok).toBe(false);
  });
});

describe("planImport", () => {
  it("replace mode imports everything verbatim", () => {
    const backup = buildBackup(sampleData());
    const plan = planImport(
      backup,
      { projects: [project("px", 99)], tags: [], rules: [], sessions: [session("sx", 99)] },
      "replace"
    );
    expect(plan.projects.map((p) => p.id)).toEqual(["p1"]);
    expect(plan.sessions.map((s) => s.id)).toEqual(["s1"]);
    expect(plan.skipped).toBe(0);
  });

  it("merge mode adds new records and lets the newer updatedAt win on conflicts", () => {
    const backup = buildBackup({
      settings: DEFAULT_SETTINGS,
      projects: [project("p1", 20, "Incoming newer"), project("p2", 5, "Incoming new")],
      tags: [tag("t1", 5)], // older than local
      rules: [],
      sessions: [session("s1", 20), session("s2", 5)],
    });
    const existing = {
      projects: [project("p1", 10, "Local older")],
      tags: [tag("t1", 10)],
      rules: [rule("r-local", 10)],
      sessions: [session("s1", 30)], // local newer
    };

    const plan = planImport(backup, existing, "merge");

    // p1 incoming is newer → imported; p2 is new → imported
    expect(plan.projects.map((p) => p.id).sort()).toEqual(["p1", "p2"]);
    expect(plan.projects.find((p) => p.id === "p1")!.name).toBe("Incoming newer");
    // t1 local is newer → skipped
    expect(plan.tags).toHaveLength(0);
    // s1 local newer → skipped; s2 new → imported
    expect(plan.sessions.map((s) => s.id)).toEqual(["s2"]);
    // skipped = t1 + s1
    expect(plan.skipped).toBe(2);
  });

  it("merge is idempotent: importing the same backup twice plans no changes", () => {
    const backup = buildBackup(sampleData());
    const afterFirst = {
      projects: backup.projects,
      tags: backup.tags,
      rules: backup.rules,
      sessions: backup.sessions,
    };
    const plan = planImport(backup, afterFirst, "merge");
    expect(plan.projects).toHaveLength(0);
    expect(plan.tags).toHaveLength(0);
    expect(plan.rules).toHaveLength(0);
    expect(plan.sessions).toHaveLength(0);
    expect(plan.skipped).toBe(4);
  });
});
