import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { ALARM_NAMES, STORAGE_KEYS } from "../src/shared/constants";
import type { Session, Assignment } from "../src/shared/types";

// ─────────────────────────────────────────────────────────────────────────────
// Tracker-level tests: real tracker + session-manager modules, mocked chrome
// event surface. Covers the cross-window focus fix, event serialization, and
// timed-override expiry.
// ─────────────────────────────────────────────────────────────────────────────

vi.mock("../src/storage/seed-defaults", () => ({
  seedDefaults: async () => {},
}));

vi.mock("../src/storage/session-repo", () => ({
  saveSession: async (s: Session) => {
    (globalThis as unknown as { __saved: Session[] }).__saved.push(s);
  },
}));

// Rule/project lookups hit Dexie; stub them out and count invocations —
// serialization is observable as "one resolveAssignment per new target".
vi.mock("../src/attribution/resolve-assignment", () => ({
  resolveAssignment: async (params: { url: string }): Promise<Assignment> => {
    const g = globalThis as unknown as { __resolveCalls: string[] };
    g.__resolveCalls.push(params.url);
    return {
      projectId: null,
      projectName: null,
      assignmentSource: "unassigned",
      assignmentConfidence: 0,
      tagIds: [],
      billable: false,
    };
  },
}));

type Listener = (...args: unknown[]) => unknown;

interface ChromeMock {
  chrome: Record<string, unknown>;
  store: Record<string, unknown>;
  alarms: Record<string, { when?: number; periodInMinutes?: number }>;
  setActiveTab: (tab: { url: string; title: string; id: number } | null) => void;
  fire: {
    tabActivated: () => Promise<void>;
    focusChanged: (windowId: number) => Promise<void>;
    alarm: (name: string) => Promise<void>;
    message: (message: { type: string; payload?: unknown }) => Promise<unknown>;
  };
}

function installChromeMock(): ChromeMock {
  const store: Record<string, unknown> = {};
  const alarms: Record<string, { when?: number; periodInMinutes?: number }> = {};
  let activeTab: { url: string; title: string; id: number } | null = null;

  const listeners: Record<string, Listener[]> = {
    tabActivated: [], tabUpdated: [], focusChanged: [], idleChanged: [],
    alarm: [], message: [], storageChanged: [],
  };
  const on = (key: string) => ({ addListener: (f: Listener) => listeners[key].push(f) });

  const chromeMock = {
    storage: {
      local: {
        get: async (key: string) => (key in store ? { [key]: structuredClone(store[key]) } : {}),
        set: async (obj: Record<string, unknown>) => {
          for (const [k, v] of Object.entries(obj)) store[k] = structuredClone(v);
        },
        remove: async (key: string) => {
          delete store[key];
        },
      },
      onChanged: on("storageChanged"),
    },
    tabs: {
      onActivated: on("tabActivated"),
      onUpdated: on("tabUpdated"),
      query: async () =>
        activeTab ? [{ url: activeTab.url, title: activeTab.title, id: activeTab.id, active: true }] : [],
    },
    windows: {
      WINDOW_ID_NONE: -1,
      onFocusChanged: on("focusChanged"),
    },
    idle: {
      setDetectionInterval: () => {},
      onStateChanged: on("idleChanged"),
    },
    alarms: {
      create: (name: string, info: { when?: number; periodInMinutes?: number }) => {
        alarms[name] = info;
      },
      clear: async (name: string) => {
        delete alarms[name];
        return true;
      },
      onAlarm: on("alarm"),
    },
    runtime: { onMessage: on("message") },
  };

  (globalThis as unknown as { chrome: unknown }).chrome = chromeMock;

  const fireAll = async (key: string, ...args: unknown[]) => {
    await Promise.all(listeners[key].map((f) => f(...args)));
  };

  return {
    chrome: chromeMock,
    store,
    alarms,
    setActiveTab: (tab) => {
      activeTab = tab;
    },
    fire: {
      tabActivated: () => fireAll("tabActivated", { tabId: activeTab?.id ?? 0, windowId: 1 }),
      focusChanged: (windowId: number) => fireAll("focusChanged", windowId),
      alarm: (name: string) => fireAll("alarm", { name }),
      // The onMessage listener responds asynchronously via sendResponse; wait for it.
      message: (message) =>
        new Promise((resolve) => {
          for (const f of listeners.message) f(message, {}, resolve);
        }),
    },
  };
}

async function loadTracker() {
  vi.resetModules();
  const tracker = await import("../src/background/tracker");
  const sm = await import("../src/background/session-manager");
  tracker.registerListeners();
  return { tracker, sm };
}

const BASE = 1_700_000_000_000;
let now = BASE;
function setNow(ms: number) {
  now = ms;
  vi.setSystemTime(now);
}
function advance(seconds: number) {
  setNow(now + seconds * 1000);
}

function saved(): Session[] {
  return (globalThis as unknown as { __saved: Session[] }).__saved;
}
function resolveCalls(): string[] {
  return (globalThis as unknown as { __resolveCalls: string[] }).__resolveCalls;
}

const TAB_A = { url: "https://bubble.io/page?id=appa", title: "App A", id: 11 };
const TAB_B = { url: "https://www.figma.com/design/fileb/File-B", title: "File B", id: 22 };

let mock: ChromeMock;

beforeEach(() => {
  vi.useFakeTimers();
  setNow(BASE);
  (globalThis as unknown as { __saved: Session[] }).__saved = [];
  (globalThis as unknown as { __resolveCalls: string[] }).__resolveCalls = [];
  mock = installChromeMock();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("cross-window focus switch (B1)", () => {
  it("re-reconciles on window focus gain so time follows the focused window's tab", async () => {
    const { sm } = await loadTracker();

    mock.setActiveTab(TAB_A);
    await mock.fire.tabActivated();
    expect(sm.getActiveSession()?.url).toBe(TAB_A.url);

    advance(60);

    // User focuses a different Chrome window whose active tab is TAB_B.
    // No tabs.onActivated fires for this — only windows.onFocusChanged.
    mock.setActiveTab(TAB_B);
    await mock.fire.focusChanged(2);

    expect(saved()).toHaveLength(1);
    expect(saved()[0].url).toBe(TAB_A.url);
    expect(saved()[0].durationSeconds).toBe(60);
    expect(sm.getActiveSession()?.url).toBe(TAB_B.url);
  });

  it("losing focus pauses; regaining focus on the same tab resumes without restarting", async () => {
    const { sm } = await loadTracker();
    mock.setActiveTab(TAB_A);
    await mock.fire.tabActivated();
    const sessionId = sm.getActiveSession()?.id;

    advance(30);
    await mock.fire.focusChanged(-1); // WINDOW_ID_NONE → blur pause
    expect(sm.isPaused()).toBe(true);

    advance(100); // unfocused — must not count
    await mock.fire.focusChanged(1); // back to the same window/tab
    expect(sm.isPaused()).toBe(false);
    expect(sm.getActiveSession()?.id).toBe(sessionId); // same session continues

    advance(20);
    expect(sm.getCurrentDurationSeconds()).toBe(50); // 30 + 20
  });
});

describe("event serialization (S2)", () => {
  it("overlapping tab events produce exactly one session start per target", async () => {
    const { sm } = await loadTracker();
    mock.setActiveTab(TAB_A);

    // onActivated and onUpdated typically both fire for one navigation.
    // Fire them without awaiting in between so they overlap.
    const p1 = mock.fire.tabActivated();
    const p2 = mock.fire.tabActivated();
    await Promise.all([p1, p2]);

    expect(sm.getActiveSession()?.url).toBe(TAB_A.url);
    // Second reconcile must see the first one's session and early-return.
    expect(resolveCalls()).toEqual([TAB_A.url]);
    expect(saved()).toHaveLength(0); // no phantom finalized fragments
  });
});

describe("timed override expiry (S1)", () => {
  const SWITCH_PAYLOAD = {
    projectId: "p1",
    projectName: "Acme Corp",
    tagIds: [],
    billable: true,
    scope: "global",
    expires: "thirty_minutes",
  };

  it("schedules a one-shot alarm at expiresAt and ends the override session when it fires", async () => {
    const { sm } = await loadTracker();
    mock.setActiveTab(TAB_A);
    await mock.fire.tabActivated();

    await mock.fire.message({ type: "SWITCH_PROJECT", payload: SWITCH_PAYLOAD });
    expect(sm.getActiveSession()?.assignment.projectId).toBe("p1");
    expect(mock.alarms[ALARM_NAMES.OVERRIDE_EXPIRY]?.when).toBe(now + 30 * 60 * 1000);

    // Stay on the same page past expiry; the alarm fires.
    advance(31 * 60);
    await mock.fire.alarm(ALARM_NAMES.OVERRIDE_EXPIRY);

    // Override gone from storage; the override session was closed at expiry
    // handling time; a fresh session for the same tab is re-attributed (rules
    // mock says unassigned).
    expect(mock.store[STORAGE_KEYS.OVERRIDE]).toBeUndefined();
    const overrideSession = saved().find((s) => s.projectId === "p1");
    expect(overrideSession).toBeDefined();
    expect(overrideSession!.durationSeconds).toBe(31 * 60);
    expect(sm.getActiveSession()?.url).toBe(TAB_A.url);
    expect(sm.getActiveSession()?.assignment.projectId).toBeNull();
  });

  it("CLEAR_OVERRIDE clears the expiry alarm too", async () => {
    await loadTracker();
    mock.setActiveTab(TAB_A);
    await mock.fire.tabActivated();
    await mock.fire.message({ type: "SWITCH_PROJECT", payload: SWITCH_PAYLOAD });
    expect(mock.alarms[ALARM_NAMES.OVERRIDE_EXPIRY]).toBeDefined();

    await mock.fire.message({ type: "CLEAR_OVERRIDE" });
    expect(mock.alarms[ALARM_NAMES.OVERRIDE_EXPIRY]).toBeUndefined();
    expect(mock.store[STORAGE_KEYS.OVERRIDE]).toBeUndefined();
  });

  it("bootstrap drops an override that expired while the browser was closed", async () => {
    mock.store[STORAGE_KEYS.OVERRIDE] = {
      projectId: "p1",
      scope: "global",
      expires: "thirty_minutes",
      startedAt: BASE - 60 * 60 * 1000,
      expiresAt: BASE - 30 * 60 * 1000, // already past
    };

    await loadTracker();
    mock.setActiveTab(TAB_A);
    await mock.fire.tabActivated(); // triggers bootstrap

    expect(mock.store[STORAGE_KEYS.OVERRIDE]).toBeUndefined();
    expect(mock.alarms[ALARM_NAMES.OVERRIDE_EXPIRY]).toBeUndefined();
  });

  it("bootstrap re-creates the expiry alarm for a still-active override", async () => {
    const expiresAt = BASE + 10 * 60 * 1000;
    mock.store[STORAGE_KEYS.OVERRIDE] = {
      projectId: "p1",
      scope: "global",
      expires: "thirty_minutes",
      startedAt: BASE - 60 * 1000,
      expiresAt,
    };

    await loadTracker();
    mock.setActiveTab(TAB_A);
    await mock.fire.tabActivated();

    expect(mock.alarms[ALARM_NAMES.OVERRIDE_EXPIRY]?.when).toBe(expiresAt);
  });
});
