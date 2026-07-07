import { v4 as uuidv4 } from "uuid";
import type { ActiveSession, Assignment, Session } from "../shared/types";
import { saveSession } from "../storage/session-repo";
import { parseProjectFromUrl } from "../parsers";
import { extractDomain } from "../shared/utils";
import { STORAGE_KEYS, MAX_CREDIT_GAP_SECONDS } from "../shared/constants";

// ─────────────────────────────────────────────────────────────────────────────
// In-memory state. In Manifest V3 the service worker is terminated after ~30s
// of inactivity, which wipes these. To survive that, every mutation is mirrored
// to chrome.storage.local (see persist) and restored on the next SW wake (see
// restoreState). Storage is the source of truth across restarts; memory is just
// a fast working copy within a single SW lifetime.
// ─────────────────────────────────────────────────────────────────────────────

let activeSession: ActiveSession | null = null;

// Bitfield: 0b01 = idle paused, 0b10 = blur paused
let pauseReasons = 0;
const PAUSE_IDLE = 0b01;
const PAUSE_BLUR = 0b10;

// Timestamp of the last checkpoint (start / heartbeat / pause / resume). Used by
// restoreState to measure how long the SW was gone and decide whether to credit
// that gap as active time.
let lastCheckpoint = Date.now();

const UNASSIGNED: Assignment = {
  projectId: null,
  projectName: null,
  assignmentSource: "unassigned",
  assignmentConfidence: 0,
  tagIds: [],
  billable: false,
};

interface PersistedState {
  session: ActiveSession;
  pauseReasons: number;
  lastCheckpoint: number;
}

async function persist(): Promise<void> {
  if (activeSession) {
    const state: PersistedState = { session: activeSession, pauseReasons, lastCheckpoint };
    await chrome.storage.local.set({ [STORAGE_KEYS.ACTIVE]: state });
  } else {
    await chrome.storage.local.remove(STORAGE_KEYS.ACTIVE);
  }
}

function computeDuration(session: ActiveSession, endTime: number): number {
  const segmentSeconds =
    session.segmentStart !== null
      ? Math.max(0, Math.floor((endTime - session.segmentStart) / 1000))
      : 0;
  return session.accumulatedSeconds + segmentSeconds;
}

// Finalize the current session as of `endTime`, save it, and clear state.
async function finalizeAt(endTime: number): Promise<void> {
  if (!activeSession) return;

  const duration = computeDuration(activeSession, endTime);
  const finished = activeSession;

  activeSession = null;
  pauseReasons = 0;
  await persist();

  // Discard sessions under 2 seconds — tab flickers, redirects.
  if (duration < 2) return;

  const a = finished.assignment;
  const now = Date.now();
  const session: Session = {
    id: finished.id,
    url: finished.url,
    domain: finished.domain,
    title: finished.title,
    service: finished.service,
    detectedEntityId: finished.detectedEntityId,
    detectedEntityName: finished.detectedEntityName,
    projectId: a.projectId,
    projectName: a.projectName,
    assignmentSource: a.assignmentSource,
    assignmentConfidence: a.assignmentConfidence,
    matchedRuleId: a.matchedRuleId,
    tagIds: a.tagIds,
    billable: a.billable,
    // Manual choices are by definition reviewed (spec §10).
    reviewed: a.assignmentSource === "manual_popup" || a.assignmentSource === "manual_dashboard",
    startTime: finished.startTime,
    endTime,
    durationSeconds: duration,
    createdAt: now,
    updatedAt: now,
  };

  await saveSession(session);
}

export async function startSession(
  url: string,
  title: string,
  assignment: Assignment = UNASSIGNED
): Promise<void> {
  await finalizeAt(Date.now());

  const domain = extractDomain(url);
  if (!domain) return;

  const parsed = parseProjectFromUrl(url);
  const now = Date.now();

  activeSession = {
    id: uuidv4(),
    url,
    domain,
    title,
    service: parsed?.service ?? null,
    detectedEntityId: parsed?.projectId ?? null,
    detectedEntityName: parsed?.projectName ?? null,
    assignment,
    startTime: now,
    accumulatedSeconds: 0,
    segmentStart: pauseReasons === 0 ? now : null,
  };
  lastCheckpoint = now;
  await persist();
}

// Re-attribute the in-flight session without restarting its clock. Used when
// the user applies a project/tags/billable from the popup.
export async function updateActiveAssignment(assignment: Assignment): Promise<void> {
  if (!activeSession) return;
  activeSession.assignment = assignment;
  await persist();
}

export async function endCurrentSession(): Promise<void> {
  await finalizeAt(Date.now());
}

export async function pauseSession(reason: "idle" | "blur"): Promise<void> {
  if (!activeSession) return;

  const bit = reason === "idle" ? PAUSE_IDLE : PAUSE_BLUR;
  const wasPaused = pauseReasons !== 0;
  pauseReasons |= bit;

  // Only bank the elapsed segment on the first pause reason.
  if (!wasPaused && activeSession.segmentStart !== null) {
    activeSession.accumulatedSeconds += Math.max(
      0,
      Math.floor((Date.now() - activeSession.segmentStart) / 1000)
    );
    activeSession.segmentStart = null;
  }
  lastCheckpoint = Date.now();
  await persist();
}

export async function resumeSession(reason: "idle" | "blur"): Promise<void> {
  if (!activeSession) return;

  const bit = reason === "idle" ? PAUSE_IDLE : PAUSE_BLUR;
  pauseReasons &= ~bit;

  // Only restart the segment timer once every pause reason is cleared.
  if (pauseReasons === 0 && activeSession.segmentStart === null) {
    activeSession.segmentStart = Date.now();
  }
  lastCheckpoint = Date.now();
  await persist();
}

// Fired by the heartbeat alarm. Banks elapsed time and checkpoints to storage so
// a hard crash or browser close loses at most one heartbeat interval.
export async function heartbeat(): Promise<void> {
  if (!activeSession) return;

  const now = Date.now();
  if (activeSession.segmentStart !== null) {
    activeSession.accumulatedSeconds += Math.max(
      0,
      Math.floor((now - activeSession.segmentStart) / 1000)
    );
    activeSession.segmentStart = now;
  }
  lastCheckpoint = now;
  await persist();
}

// Called once when the service worker wakes. Restores the persisted session and
// decides what to do with the time that passed while the SW was gone.
export async function restoreState(): Promise<void> {
  const stored = await chrome.storage.local.get(STORAGE_KEYS.ACTIVE);
  const data = stored[STORAGE_KEYS.ACTIVE] as PersistedState | undefined;
  if (!data?.session) return;

  activeSession = data.session;
  pauseReasons = data.pauseReasons ?? 0;
  lastCheckpoint = data.lastCheckpoint ?? Date.now();

  const gapSeconds = Math.floor((Date.now() - lastCheckpoint) / 1000);

  if (gapSeconds > MAX_CREDIT_GAP_SECONDS) {
    // The machine likely slept or the browser was closed during the gap (no
    // alarms/events fire then). Don't count dead time: finalize the session as
    // of its last checkpoint. computeDuration counts segmentStart..lastCheckpoint
    // which is ~0 because heartbeat resets segmentStart to its own time.
    await finalizeAt(lastCheckpoint);
    return;
  }

  // Small gap: the SW was just churning while the user kept working (any idle or
  // focus change would have woken it). Leave segmentStart as-is so the gap is
  // credited as active time, and re-persist the now-in-memory state.
  await persist();
}

export function getActiveSession(): ActiveSession | null {
  return activeSession;
}

export function getCurrentDurationSeconds(): number {
  if (!activeSession) return 0;
  return computeDuration(activeSession, Date.now());
}

export function isPaused(): boolean {
  return pauseReasons !== 0;
}

export function getPauseReasons(): { idle: boolean; blur: boolean } {
  return {
    idle: (pauseReasons & PAUSE_IDLE) !== 0,
    blur: (pauseReasons & PAUSE_BLUR) !== 0,
  };
}
