import { v4 as uuidv4 } from "uuid";
import type { Session } from "./types";

export interface SplitSegmentSpec {
  // Wall-clock boundary times; segment i runs boundaries[i]..boundaries[i+1]
  projectId: string | null;
  projectName: string | null;
  tagIds: string[];
  billable: boolean;
}

export interface SplitRequest {
  // Interior boundary timestamps (ms), strictly inside (startTime, endTime),
  // strictly ascending. N boundaries produce N+1 segments.
  boundaries: number[];
  segments: SplitSegmentSpec[];
}

export type SplitResult =
  | { ok: true; sessions: Session[] }
  | { ok: false; error: string };

// Pure: splits one session into consecutive segments at the given wall-clock
// boundaries (spec §17). Active seconds are distributed proportionally to each
// segment's share of wall time, with the last segment absorbing rounding
// remainder so the total exactly equals the original duration.
export function splitSession(original: Session, request: SplitRequest): SplitResult {
  const { boundaries, segments } = request;

  if (segments.length < 2) {
    return { ok: false, error: "A split needs at least two segments." };
  }
  if (boundaries.length !== segments.length - 1) {
    return { ok: false, error: "Boundary count must be one less than segment count." };
  }
  for (let i = 0; i < boundaries.length; i++) {
    if (boundaries[i] <= original.startTime || boundaries[i] >= original.endTime) {
      return { ok: false, error: "Split times must be inside the session's start and end." };
    }
    if (i > 0 && boundaries[i] <= boundaries[i - 1]) {
      return { ok: false, error: "Split times must be in ascending order." };
    }
  }

  const edges = [original.startTime, ...boundaries, original.endTime];
  const totalWall = original.endTime - original.startTime;
  const now = Date.now();

  let allocated = 0;
  const sessions: Session[] = segments.map((spec, i) => {
    const segStart = edges[i];
    const segEnd = edges[i + 1];

    let durationSeconds: number;
    if (i === segments.length - 1) {
      // Last segment absorbs rounding so totals are conserved exactly.
      durationSeconds = original.durationSeconds - allocated;
    } else {
      durationSeconds = Math.round((original.durationSeconds * (segEnd - segStart)) / totalWall);
      allocated += durationSeconds;
    }

    return {
      ...original,
      id: uuidv4(),
      projectId: spec.projectId,
      projectName: spec.projectName,
      assignmentSource: "manual_dashboard",
      assignmentConfidence: 100,
      matchedRuleId: undefined,
      tagIds: spec.tagIds,
      billable: spec.billable,
      // Segments the user assigned a project to are reviewed by definition.
      reviewed: spec.projectId !== null,
      startTime: segStart,
      endTime: segEnd,
      durationSeconds,
      syncedToSheets: 0 as const,
      createdAt: now,
      updatedAt: now,
    };
  });

  const total = sessions.reduce((sum, s) => sum + s.durationSeconds, 0);
  if (total !== original.durationSeconds) {
    return { ok: false, error: "Internal error: split durations do not sum to the original." };
  }

  return { ok: true, sessions };
}
