import Dexie, { type Table } from "dexie";
import type { Session, Project, ProjectRule, Tag } from "../shared/types";

// V1 session shape, needed by the v2 upgrade transform.
interface SessionV1 {
  id: string;
  url: string;
  domain: string;
  title: string;
  service: string | null;
  projectId: string | null;   // held the DETECTED entity id (figma file, bubble app)
  projectName: string | null;
  startTime: number;
  endTime: number;
  durationSeconds: number;
  synced: boolean;
}

export class ActivityTrackerDB extends Dexie {
  sessions!: Table<Session, string>;
  projects!: Table<Project, string>;
  projectRules!: Table<ProjectRule, string>;
  tags!: Table<Tag, string>;

  constructor() {
    super("BrowserActivityTracker");

    this.version(1).stores({
      sessions: "id, domain, startTime, endTime, projectId, service, synced",
    });

    // V2: attribution layer. Note: boolean fields (reviewed, billable, enabled,
    // archived) are intentionally NOT indexed — IndexedDB cannot index booleans.
    // syncedToSheets is stored as 0|1 so the sync query can use its index.
    this.version(2)
      .stores({
        sessions:
          "id, domain, startTime, endTime, projectId, service, detectedEntityId, syncedToSheets",
        projects: "id, name, createdAt",
        projectRules: "id, projectId, priority",
        tags: "id, name",
      })
      .upgrade(async (tx) => {
        await tx
          .table("sessions")
          .toCollection()
          .modify((raw: Record<string, unknown>) => {
            const old = raw as unknown as SessionV1;
            // Old projectId/projectName were parser output → move to detectedEntity*.
            raw.detectedEntityId = old.projectId ?? null;
            raw.detectedEntityName = old.projectName ?? null;
            raw.projectId = null;
            raw.projectName = null;
            raw.assignmentSource = "unassigned";
            raw.assignmentConfidence = 0;
            raw.tagIds = [];
            raw.billable = false;
            raw.reviewed = false;
            raw.syncedToSheets = old.synced ? 1 : 0;
            raw.createdAt = old.endTime;
            raw.updatedAt = old.endTime;
            delete raw.synced;
          });
      });

    // V3: Google Sheets sync removed — drop the syncedToSheets index and strip
    // the field from stored records. Local backup/restore replaced sync.
    this.version(3)
      .stores({
        sessions: "id, domain, startTime, endTime, projectId, service, detectedEntityId",
        projects: "id, name, createdAt",
        projectRules: "id, projectId, priority",
        tags: "id, name",
      })
      .upgrade(async (tx) => {
        await tx
          .table("sessions")
          .toCollection()
          .modify((raw: Record<string, unknown>) => {
            delete raw.syncedToSheets;
          });
      });
  }
}

export const db = new ActivityTrackerDB();
