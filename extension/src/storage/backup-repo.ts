import { db } from "./db";
import type { AppSettings } from "../shared/types";
import { DEFAULT_SETTINGS, STORAGE_KEYS } from "../shared/constants";
import {
  buildBackup,
  planImport,
  type BackupFile,
  type ImportMode,
} from "../shared/backup";

export async function exportAll(): Promise<BackupFile> {
  const [projects, tags, rules, sessions, stored] = await Promise.all([
    db.projects.toArray(),
    db.tags.toArray(),
    db.projectRules.toArray(),
    db.sessions.toArray(),
    chrome.storage.local.get(STORAGE_KEYS.SETTINGS),
  ]);
  const settings: AppSettings = {
    ...DEFAULT_SETTINGS,
    ...((stored[STORAGE_KEYS.SETTINGS] as Partial<AppSettings> | undefined) ?? {}),
  };
  return buildBackup({ settings, projects, tags, rules, sessions });
}

export interface ImportSummary {
  projects: number;
  tags: number;
  rules: number;
  sessions: number;
  skipped: number;
}

export async function importBackup(backup: BackupFile, mode: ImportMode): Promise<ImportSummary> {
  const existing =
    mode === "merge"
      ? {
          projects: await db.projects.toArray(),
          tags: await db.tags.toArray(),
          rules: await db.projectRules.toArray(),
          sessions: await db.sessions.toArray(),
        }
      : { projects: [], tags: [], rules: [], sessions: [] };

  const plan = planImport(backup, existing, mode);

  await db.transaction("rw", db.projects, db.tags, db.projectRules, db.sessions, async () => {
    if (mode === "replace") {
      await Promise.all([
        db.projects.clear(),
        db.tags.clear(),
        db.projectRules.clear(),
        db.sessions.clear(),
      ]);
    }
    await Promise.all([
      db.projects.bulkPut(plan.projects),
      db.tags.bulkPut(plan.tags),
      db.projectRules.bulkPut(plan.rules),
      db.sessions.bulkPut(plan.sessions),
    ]);
  });

  // Replacing adopts the backup's settings too; merging keeps this device's.
  if (mode === "replace") {
    await chrome.storage.local.set({
      [STORAGE_KEYS.SETTINGS]: { ...DEFAULT_SETTINGS, ...backup.settings },
    });
  }

  return {
    projects: plan.projects.length,
    tags: plan.tags.length,
    rules: plan.rules.length,
    sessions: plan.sessions.length,
    skipped: plan.skipped,
  };
}
