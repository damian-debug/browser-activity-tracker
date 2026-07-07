import {
  startSession,
  endCurrentSession,
  pauseSession,
  resumeSession,
  heartbeat,
  restoreState,
  getActiveSession,
  getCurrentDurationSeconds,
  isPaused,
} from "./session-manager";
import {
  EXCLUDED_SCHEMES,
  DEFAULT_SETTINGS,
  STORAGE_KEYS,
  ALARM_NAMES,
  HEARTBEAT_INTERVAL_MINUTES,
} from "../shared/constants";
import type {
  ActiveProjectOverride,
  ActiveProjectOverrideExpires,
  ActiveProjectOverrideScope,
  AppSettings,
  Assignment,
} from "../shared/types";
import { extractDomain } from "../shared/utils";
import { isSameTarget } from "../shared/tracking-target";
import { resolveAssignment } from "../attribution/resolve-assignment";
import { setOverride, clearOverride, getOverride, computeExpiresAt } from "../attribution/override-store";
import { parseProjectFromUrl } from "../parsers";
import { seedDefaults } from "../storage/seed-defaults";
import { CONFIDENCE } from "../attribution/confidence";

let settings: AppSettings = DEFAULT_SETTINGS;

// ─────────────────────────────────────────────────────────────────────────────
// Readiness gate. Every event handler awaits ensureReady() before touching
// session state, so the first event after a service-worker wake can't race the
// restore (which would otherwise drop the in-flight session). bootstrap runs
// exactly once per SW lifetime.
// ─────────────────────────────────────────────────────────────────────────────
let readyPromise: Promise<void> | null = null;

function ensureReady(): Promise<void> {
  if (!readyPromise) readyPromise = bootstrap();
  return readyPromise;
}

// ─────────────────────────────────────────────────────────────────────────────
// Serialization queue. Chrome often fires several events for one user action
// (onActivated + onUpdated on a navigation, focus + activation on a window
// switch). Handlers await storage/DB reads, so two in-flight reconciles could
// interleave and each call startSession — fragmenting or double-counting the
// session. Every session-mutating handler runs through this queue so exactly
// one runs at a time, in arrival order.
// ─────────────────────────────────────────────────────────────────────────────
let opQueue: Promise<void> = Promise.resolve();

function enqueue(fn: () => Promise<void>): Promise<void> {
  const run = opQueue.then(fn);
  // Swallow errors on the chain (not on `run`) so one failed op can't wedge
  // every subsequent event handler.
  opQueue = run.catch(() => {});
  return run;
}

async function bootstrap(): Promise<void> {
  await loadSettings();
  chrome.idle.setDetectionInterval(settings.idleThresholdSeconds);
  chrome.alarms.create(ALARM_NAMES.HEARTBEAT, { periodInMinutes: HEARTBEAT_INTERVAL_MINUTES });
  await seedDefaults();
  await restoreState();
  await syncOverrideExpiryAlarm();
  await reconcile();
}

// Timed overrides ("30 minutes" / "end of day") must end the *live* session at
// the expiry moment, not just stop applying to future ones. A one-shot alarm at
// expiresAt handles that; on every bootstrap we re-derive the alarm from the
// stored override (alarms survive SW restarts but not browser restarts) and
// drop an override that expired while the browser was closed.
async function syncOverrideExpiryAlarm(): Promise<void> {
  const override = await getOverride();
  await chrome.alarms.clear(ALARM_NAMES.OVERRIDE_EXPIRY);
  if (!override?.expiresAt) return;
  if (override.expiresAt <= Date.now()) {
    await clearOverride();
  } else {
    chrome.alarms.create(ALARM_NAMES.OVERRIDE_EXPIRY, { when: override.expiresAt });
  }
}

// Fired when a timed override expires: drop it, close the session that was
// accruing under it, and re-attribute the active tab from rules.
async function handleOverrideExpiry(): Promise<void> {
  const override = await getOverride();
  if (!override) return;
  if (override.expiresAt === undefined || override.expiresAt > Date.now()) return;
  await clearOverride();
  await endCurrentSession();
  await reconcile();
}

async function loadSettings(): Promise<void> {
  const stored = await chrome.storage.local.get(STORAGE_KEYS.SETTINGS);
  if (stored[STORAGE_KEYS.SETTINGS]) {
    settings = { ...DEFAULT_SETTINGS, ...stored[STORAGE_KEYS.SETTINGS] };
  }
}

function isExcluded(url: string): boolean {
  if (!url) return true;
  if (EXCLUDED_SCHEMES.some((s) => url.startsWith(s))) return true;
  const domain = extractDomain(url);
  if (!domain) return true;
  return settings.excludedDomains.some(
    (ex) => domain === ex || domain.endsWith("." + ex)
  );
}

async function getActiveTabInfo(): Promise<{ url: string; title: string; tabId: number } | null> {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.url || !tab.id) return null;
  return { url: tab.url, title: tab.title ?? "", tabId: tab.id };
}

// Core reconciliation against whatever tab is currently active. Does NOT call
// ensureReady (bootstrap calls this directly — see handleTabChange for the
// event-driven wrapper that does gate on readiness).
async function reconcile(): Promise<void> {
  const info = await getActiveTabInfo();
  if (!info || isExcluded(info.url)) {
    await endCurrentSession();
    return;
  }

  const current = getActiveSession();
  // Same target as the live session: keep accruing. Continuity is by detected
  // entity when one is found (so navigating within a Bubble app / Figma file
  // stays one session), else by exact URL. This is what makes single-tab work
  // accumulate correctly and prevents SPA URL noise from resetting the timer.
  if (current && isSameTarget(current, info.url)) return;

  const domain = extractDomain(info.url);
  if (!domain) return;

  const assignment = await resolveAssignment({
    url: info.url,
    domain,
    title: info.title,
    parsed: parseProjectFromUrl(info.url),
    tabId: info.tabId,
  });

  await startSession(info.url, info.title, assignment);
}

async function handleTabChange(): Promise<void> {
  await ensureReady();
  await enqueue(reconcile);
}

// Registered synchronously at the top level of the SW script (see index.ts) so
// Chrome can wake the worker for these events. Handler bodies may be async.
export function registerListeners(): void {
  // Tab activated (switched to a different tab)
  chrome.tabs.onActivated.addListener(() => handleTabChange());

  // URL changed within a tab. Only react to real URL changes — title-only
  // updates (common on SPAs like Bubble/Figma) must not restart the session.
  chrome.tabs.onUpdated.addListener((_tabId, changeInfo, tab) => {
    if (!tab.active) return;
    if (!changeInfo.url) return;
    return handleTabChange();
  });

  // Window focus changed. tabs.onActivated only fires for tab switches WITHIN
  // a window, so gaining focus must also reconcile — the newly focused window's
  // active tab may be a different page than the session we were tracking.
  chrome.windows.onFocusChanged.addListener(async (windowId) => {
    await ensureReady();
    await enqueue(async () => {
      if (windowId === chrome.windows.WINDOW_ID_NONE) {
        await pauseSession("blur");
      } else {
        await resumeSession("blur");
        await reconcile();
      }
    });
  });

  // Idle state changed
  chrome.idle.onStateChanged.addListener(async (state) => {
    await ensureReady();
    await enqueue(async () => {
      if (state === "active") {
        await resumeSession("idle");
      } else {
        // idle or locked
        await pauseSession("idle");
      }
    });
  });

  // Settings changed from the options page
  chrome.storage.onChanged.addListener((changes) => {
    if (changes[STORAGE_KEYS.SETTINGS]) {
      settings = { ...DEFAULT_SETTINGS, ...changes[STORAGE_KEYS.SETTINGS].newValue };
      chrome.idle.setDetectionInterval(settings.idleThresholdSeconds);
    }
  });

  // Alarms
  chrome.alarms.onAlarm.addListener(async (alarm) => {
    await ensureReady();
    if (alarm.name === ALARM_NAMES.HEARTBEAT) {
      await enqueue(heartbeat);
    }
    if (alarm.name === ALARM_NAMES.OVERRIDE_EXPIRY) {
      await enqueue(handleOverrideExpiry);
    }
  });

  // Messages from popup / dashboard
  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    handleMessage(message, sendResponse);
    return true; // keep the channel open for async responses
  });
}

interface SwitchProjectPayload {
  projectId: string;
  projectName: string;
  tagIds: string[];
  billable: boolean;
  scope: ActiveProjectOverrideScope;
  expires: ActiveProjectOverrideExpires;
}

// Manual project switch from the popup (spec §§12–13): persist an override for
// future sessions per scope/expiry, then restart the current session under the
// chosen project so time splits exactly at the switch moment.
async function switchProject(payload: SwitchProjectPayload): Promise<void> {
  const info = await getActiveTabInfo();
  const now = Date.now();

  const override: ActiveProjectOverride = {
    projectId: payload.projectId,
    tagIds: payload.tagIds,
    billable: payload.billable,
    scope: payload.scope,
    expires: payload.expires,
    tabId: payload.scope === "current_tab" ? info?.tabId : undefined,
    domain: payload.scope === "current_domain" && info ? extractDomain(info.url) ?? undefined : undefined,
    startedAt: now,
    expiresAt: computeExpiresAt(payload.expires, now),
  };
  await setOverride(override);
  await chrome.alarms.clear(ALARM_NAMES.OVERRIDE_EXPIRY);
  if (override.expiresAt !== undefined) {
    chrome.alarms.create(ALARM_NAMES.OVERRIDE_EXPIRY, { when: override.expiresAt });
  }

  if (!info || isExcluded(info.url)) {
    await endCurrentSession();
    return;
  }

  const assignment: Assignment = {
    projectId: payload.projectId,
    projectName: payload.projectName,
    assignmentSource: "active_project_override",
    assignmentConfidence: CONFIDENCE.OVERRIDE,
    tagIds: payload.tagIds,
    billable: payload.billable,
  };

  // startSession finalizes the previous session first — exactly the required
  // "end current, start new" behavior.
  await startSession(info.url, info.title, assignment);
}

async function handleMessage(
  message: { type: string; payload?: unknown },
  sendResponse: (r: unknown) => void
): Promise<void> {
  await ensureReady();
  switch (message.type) {
    case "GET_ACTIVE": {
      const session = getActiveSession();
      if (!session) {
        sendResponse(null);
      } else {
        sendResponse({
          domain: session.domain,
          title: session.title,
          service: session.service,
          detectedEntityName: session.detectedEntityName,
          projectId: session.assignment.projectId,
          projectName: session.assignment.projectName,
          tagIds: session.assignment.tagIds,
          billable: session.assignment.billable,
          assignmentSource: session.assignment.assignmentSource,
          assignmentConfidence: session.assignment.assignmentConfidence,
          durationSeconds: getCurrentDurationSeconds(),
          paused: isPaused(),
        });
      }
      break;
    }
    case "SWITCH_PROJECT": {
      await enqueue(() => switchProject(message.payload as SwitchProjectPayload));
      sendResponse({ ok: true });
      break;
    }
    case "CLEAR_OVERRIDE": {
      await enqueue(async () => {
        await clearOverride();
        await chrome.alarms.clear(ALARM_NAMES.OVERRIDE_EXPIRY);
        // Re-attribute the active tab from rules now that the override is gone.
        await endCurrentSession();
        await reconcile();
      });
      sendResponse({ ok: true });
      break;
    }
    default:
      sendResponse({ ok: false, error: "Unknown message type" });
  }
}

// Kick off bootstrap proactively (also triggered lazily by the first event).
export function initialize(): void {
  ensureReady();
}
