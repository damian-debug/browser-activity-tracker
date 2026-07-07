import { db } from "./db";
import type {
  Session,
  DomainSummary,
  EntitySummary,
  ProjectTotal,
  TagTotal,
  DashboardStats,
  Project,
  Tag,
} from "../shared/types";
import { startOfDayMs, endOfDayMs, todayDateString } from "../shared/utils";
import { DEFAULT_REVIEW_CONFIDENCE_THRESHOLD } from "../shared/constants";

export async function saveSession(session: Session): Promise<void> {
  await db.sessions.put(session);
}

// Filters on startTime only: a session spanning midnight is attributed
// entirely to the day it STARTED. Deliberate — totals stay simple and no
// session is double-counted across two days.
export async function getSessionsInRange(fromMs: number, toMs: number): Promise<Session[]> {
  return db.sessions.where("startTime").between(fromMs, toMs, true, true).toArray();
}

export async function updateSession(
  id: string,
  patch: Partial<Omit<Session, "id" | "createdAt">>
): Promise<void> {
  await db.sessions.update(id, {
    ...patch,
    updatedAt: Date.now(),
  });
}

export async function deleteSession(id: string): Promise<void> {
  await db.sessions.delete(id);
}

export async function deleteAllSessions(): Promise<void> {
  await db.sessions.clear();
}

// Replaces one session with its split segments atomically.
export async function replaceSessionWith(originalId: string, segments: Session[]): Promise<void> {
  await db.transaction("rw", db.sessions, async () => {
    await db.sessions.delete(originalId);
    await db.sessions.bulkPut(segments);
  });
}

export function needsReview(s: Session, threshold = DEFAULT_REVIEW_CONFIDENCE_THRESHOLD): boolean {
  if (s.reviewed) return false;
  return s.projectId === null || s.assignmentSource === "unassigned" || s.assignmentConfidence < threshold;
}

export async function getReviewQueue(
  fromMs: number,
  toMs: number,
  threshold = DEFAULT_REVIEW_CONFIDENCE_THRESHOLD
): Promise<Session[]> {
  const sessions = await getSessionsInRange(fromMs, toMs);
  return sessions.filter((s) => needsReview(s, threshold));
}

export async function getDashboardStats(
  fromMs: number,
  toMs: number,
  threshold = DEFAULT_REVIEW_CONFIDENCE_THRESHOLD
): Promise<DashboardStats> {
  const [sessions, projects, tags] = await Promise.all([
    getSessionsInRange(fromMs, toMs),
    db.projects.toArray(),
    db.tags.toArray(),
  ]);

  const projectById = new Map<string, Project>(projects.map((p) => [p.id, p]));
  const tagById = new Map<string, Tag>(tags.map((t) => [t.id, t]));

  let totalActiveSeconds = 0;
  let billableSeconds = 0;
  let unassignedSeconds = 0;
  let needsReviewSeconds = 0;
  let needsReviewCount = 0;

  const domainMap = new Map<string, DomainSummary>();
  const entityMap = new Map<string, EntitySummary>();
  const projectMap = new Map<string, ProjectTotal>();
  const tagMap = new Map<string, TagTotal>();

  for (const s of sessions) {
    totalActiveSeconds += s.durationSeconds;
    if (s.billable) billableSeconds += s.durationSeconds;
    if (s.projectId === null) unassignedSeconds += s.durationSeconds;
    if (needsReview(s, threshold)) {
      needsReviewSeconds += s.durationSeconds;
      needsReviewCount += 1;
    }

    // Domains
    const d = domainMap.get(s.domain);
    if (d) {
      d.totalSeconds += s.durationSeconds;
      d.sessionCount += 1;
    } else {
      domainMap.set(s.domain, {
        domain: s.domain,
        service: s.service,
        totalSeconds: s.durationSeconds,
        sessionCount: 1,
      });
    }

    // Detected entities (Figma files, Bubble apps)
    if (s.detectedEntityId && s.service) {
      const key = `${s.service}::${s.detectedEntityId}`;
      const e = entityMap.get(key);
      if (e) {
        e.totalSeconds += s.durationSeconds;
        e.sessionCount += 1;
        if (s.endTime > e.lastSeen) e.lastSeen = s.endTime;
        if (s.detectedEntityName && !e.detectedEntityName) e.detectedEntityName = s.detectedEntityName;
      } else {
        entityMap.set(key, {
          service: s.service,
          detectedEntityId: s.detectedEntityId,
          detectedEntityName: s.detectedEntityName,
          domain: s.domain,
          totalSeconds: s.durationSeconds,
          sessionCount: 1,
          lastSeen: s.endTime,
        });
      }
    }

    // Project totals ("__unassigned__" bucket for null)
    const pKey = s.projectId ?? "__unassigned__";
    let p = projectMap.get(pKey);
    if (!p) {
      const proj = s.projectId ? projectById.get(s.projectId) : undefined;
      p = {
        projectId: s.projectId,
        projectName: s.projectId ? (proj?.name ?? s.projectName ?? "Unknown project") : "Unassigned",
        clientName: proj?.clientName,
        color: proj?.color,
        totalSeconds: 0,
        billableSeconds: 0,
        nonBillableSeconds: 0,
        sessionCount: 0,
        tagIds: [],
      };
      projectMap.set(pKey, p);
    }
    p.totalSeconds += s.durationSeconds;
    p.sessionCount += 1;
    if (s.billable) p.billableSeconds += s.durationSeconds;
    else p.nonBillableSeconds += s.durationSeconds;
    for (const tagId of s.tagIds) {
      if (!p.tagIds.includes(tagId)) p.tagIds.push(tagId);
    }

    // Tag totals (a session with N tags counts toward each)
    for (const tagId of s.tagIds) {
      let t = tagMap.get(tagId);
      if (!t) {
        const tag = tagById.get(tagId);
        t = {
          tagId,
          tagName: tag?.name ?? "Unknown tag",
          color: tag?.color,
          totalSeconds: 0,
          sessionCount: 0,
        };
        tagMap.set(tagId, t);
      }
      t.totalSeconds += s.durationSeconds;
      t.sessionCount += 1;
    }
  }

  return {
    totalActiveSeconds,
    billableSeconds,
    unassignedSeconds,
    needsReviewSeconds,
    needsReviewCount,
    sessionCount: sessions.length,
    domainCount: domainMap.size,
    domains: [...domainMap.values()].sort((a, b) => b.totalSeconds - a.totalSeconds),
    entities: [...entityMap.values()].sort((a, b) => b.totalSeconds - a.totalSeconds),
    projectTotals: [...projectMap.values()].sort((a, b) => b.totalSeconds - a.totalSeconds),
    tagTotals: [...tagMap.values()].sort((a, b) => b.totalSeconds - a.totalSeconds),
  };
}

export async function getTodayStats(): Promise<DashboardStats> {
  const today = todayDateString();
  return getDashboardStats(startOfDayMs(today), endOfDayMs(today));
}
