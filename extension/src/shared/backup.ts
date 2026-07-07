import type { AppSettings, Project, ProjectRule, Session, Tag } from "./types";

// ─────────────────────────────────────────────────────────────────────────────
// Backup / restore file format. Pure logic only — no chrome.* or Dexie access —
// so every branch is unit-testable. src/storage/backup-repo.ts does the I/O.
// ─────────────────────────────────────────────────────────────────────────────

export const BACKUP_FORMAT = "bat-backup";
// Matches the Dexie schema version the records were exported from.
export const BACKUP_SCHEMA_VERSION = 3;

export interface BackupFile {
  format: typeof BACKUP_FORMAT;
  schemaVersion: number;
  exportedAt: number;
  settings: AppSettings;
  projects: Project[];
  tags: Tag[];
  rules: ProjectRule[];
  sessions: Session[];
}

export interface BackupData {
  settings: AppSettings;
  projects: Project[];
  tags: Tag[];
  rules: ProjectRule[];
  sessions: Session[];
}

export function buildBackup(data: BackupData, now = Date.now()): BackupFile {
  return {
    format: BACKUP_FORMAT,
    schemaVersion: BACKUP_SCHEMA_VERSION,
    exportedAt: now,
    settings: data.settings,
    projects: data.projects,
    tags: data.tags,
    rules: data.rules,
    sessions: data.sessions,
  };
}

export type ValidationResult =
  | { ok: true; backup: BackupFile }
  | { ok: false; error: string };

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function everyHasStringId(arr: unknown[]): boolean {
  return arr.every((r) => isRecord(r) && typeof r.id === "string" && r.id.length > 0);
}

export function validateBackup(raw: unknown): ValidationResult {
  if (!isRecord(raw)) return { ok: false, error: "Not a backup file (expected a JSON object)." };
  if (raw.format !== BACKUP_FORMAT) {
    return { ok: false, error: "Not an Activity Tracker backup file." };
  }
  if (typeof raw.schemaVersion !== "number" || raw.schemaVersion > BACKUP_SCHEMA_VERSION) {
    return {
      ok: false,
      error: "This backup was created by a newer version of the extension. Update the extension first.",
    };
  }
  for (const key of ["projects", "tags", "rules", "sessions"] as const) {
    const arr = raw[key];
    if (!Array.isArray(arr)) return { ok: false, error: `Backup is missing its "${key}" list.` };
    if (!everyHasStringId(arr)) return { ok: false, error: `Backup contains invalid records in "${key}".` };
  }
  const sessions = raw.sessions as unknown[];
  const sessionsValid = sessions.every(
    (s) =>
      isRecord(s) &&
      typeof s.startTime === "number" &&
      typeof s.endTime === "number" &&
      typeof s.durationSeconds === "number"
  );
  if (!sessionsValid) return { ok: false, error: "Backup contains sessions with missing time fields." };
  if (!isRecord(raw.settings)) return { ok: false, error: "Backup is missing its settings." };
  return { ok: true, backup: raw as unknown as BackupFile };
}

export type ImportMode = "merge" | "replace";

export interface ImportPlan {
  mode: ImportMode;
  projects: Project[];
  tags: Tag[];
  rules: ProjectRule[];
  sessions: Session[];
  // Records not imported because the local copy has a newer updatedAt (merge only)
  skipped: number;
}

interface HasIdAndUpdatedAt {
  id: string;
  updatedAt: number;
}

// Merge semantics: upsert by id; when both sides have a record, the one with
// the newer updatedAt wins. Idempotent, and safe to exchange backups between
// two devices in either order.
function mergeTable<T extends HasIdAndUpdatedAt>(
  incoming: T[],
  existing: T[]
): { put: T[]; skipped: number } {
  const existingById = new Map(existing.map((r) => [r.id, r]));
  const put: T[] = [];
  let skipped = 0;
  for (const record of incoming) {
    const local = existingById.get(record.id);
    if (local && local.updatedAt >= record.updatedAt) {
      skipped += 1;
    } else {
      put.push(record);
    }
  }
  return { put, skipped };
}

export function planImport(
  backup: BackupFile,
  existing: { projects: Project[]; tags: Tag[]; rules: ProjectRule[]; sessions: Session[] },
  mode: ImportMode
): ImportPlan {
  if (mode === "replace") {
    return {
      mode,
      projects: backup.projects,
      tags: backup.tags,
      rules: backup.rules,
      sessions: backup.sessions,
      skipped: 0,
    };
  }

  const projects = mergeTable(backup.projects, existing.projects);
  const tags = mergeTable(backup.tags, existing.tags);
  const rules = mergeTable(backup.rules, existing.rules);
  const sessions = mergeTable(backup.sessions, existing.sessions);

  return {
    mode,
    projects: projects.put,
    tags: tags.put,
    rules: rules.put,
    sessions: sessions.put,
    skipped: projects.skipped + tags.skipped + rules.skipped + sessions.skipped,
  };
}
