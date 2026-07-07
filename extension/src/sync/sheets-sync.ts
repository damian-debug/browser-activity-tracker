import { getUnsyncedSessions, markSessionsSynced } from "../storage/session-repo";
import { db } from "../storage/db";
import type { Session } from "../shared/types";

interface SyncRow {
  id: string;
  date: string;
  startTime: string;
  endTime: string;
  durationSeconds: number;
  project: string;
  client: string;
  tags: string;
  billable: boolean;
  reviewed: boolean;
  assignmentSource: string;
  assignmentConfidence: number;
  domain: string;
  service: string;
  detectedEntityId: string;
  detectedEntityName: string;
  title: string;
  url: string;
  notes: string;
}

async function toRows(sessions: Session[]): Promise<SyncRow[]> {
  const [projects, tags] = await Promise.all([db.projects.toArray(), db.tags.toArray()]);
  const projectById = new Map(projects.map((p) => [p.id, p]));
  const tagById = new Map(tags.map((t) => [t.id, t]));

  return sessions.map((s) => {
    const project = s.projectId ? projectById.get(s.projectId) : undefined;
    return {
      id: s.id,
      date: new Date(s.startTime).toISOString(),
      startTime: new Date(s.startTime).toISOString(),
      endTime: new Date(s.endTime).toISOString(),
      durationSeconds: s.durationSeconds,
      project: project?.name ?? s.projectName ?? "Unassigned",
      client: project?.clientName ?? "",
      tags: s.tagIds.map((id) => tagById.get(id)?.name ?? id).join(", "),
      billable: s.billable,
      reviewed: s.reviewed,
      assignmentSource: s.assignmentSource,
      assignmentConfidence: s.assignmentConfidence,
      domain: s.domain,
      service: s.service ?? "",
      detectedEntityId: s.detectedEntityId ?? "",
      detectedEntityName: s.detectedEntityName ?? "",
      title: s.title,
      url: s.url,
      notes: s.notes ?? "",
    };
  });
}

export async function syncToSheets(webhookUrl: string): Promise<boolean> {
  if (!webhookUrl) return false;

  const unsynced = await getUnsyncedSessions();
  if (unsynced.length === 0) return true;

  try {
    const sessions = await toRows(unsynced);
    const response = await fetch(webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ version: 2, sessions }),
    });

    if (!response.ok) return false;

    await markSessionsSynced(unsynced.map((s) => s.id));
    return true;
  } catch {
    return false;
  }
}
