import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { STORAGE_KEYS, MAX_CREDIT_GAP_SECONDS } from "../src/shared/constants";
import type { Session } from "../src/shared/types";

// ─────────────────────────────────────────────────────────────────────────────
// Mocks
//
// saveSession is the only side-effecting dependency that hits IndexedDB. We
// redirect it to a sink on globalThis so it (a) never touches Dexie and (b)
// SURVIVES vi.resetModules() — which we use to simulate the MV3 service worker
// being terminated and restarted. The chrome.storage mock lives on globalThis
// for the same reason: real extension storage persists across SW death.
// ─────────────────────────────────────────────────────────────────────────────

vi.mock("../src/storage/session-repo", () => ({
  saveSession: async (s: Session) => {
    (globalThis as unknown as { __saved: Session[] }).__saved.push(s);
  },
}));

const ACTIVE_KEY = STORAGE_KEYS.ACTIVE;

interface ChromeStorageMock {
  storage: {
    local: {
      get: (key: string) => Promise<Record<string, unknown>>;
      set: (obj: Record<string, unknown>) => Promise<void>;
      remove: (key: string) => Promise<void>;
    };
  };
  __store: Record<string, unknown>;
}

function installChromeMock(): ChromeStorageMock {
  const store: Record<string, unknown> = {};
  const mock: ChromeStorageMock = {
    storage: {
      local: {
        get: async (key: string) =>
          key in store ? { [key]: structuredClone(store[key]) } : {},
        set: async (obj: Record<string, unknown>) => {
          for (const [k, v] of Object.entries(obj)) store[k] = structuredClone(v);
        },
        remove: async (key: string) => {
          delete store[key];
        },
      },
    },
    __store: store,
  };
  (globalThis as unknown as { chrome: unknown }).chrome = mock;
  return mock;
}

// Fresh module instance = the service worker starting cold. Storage and the
// saved-sessions sink persist across this because they live on globalThis.
async function loadSessionManager() {
  vi.resetModules();
  return import("../src/background/session-manager");
}

// ── Time control ─────────────────────────────────────────────────────────────
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
function persistedActive(mock: ChromeStorageMock) {
  return mock.__store[ACTIVE_KEY] as
    | { session: { accumulatedSeconds: number; segmentStart: number | null; url: string }; pauseReasons: number; lastCheckpoint: number }
    | undefined;
}

let chromeMock: ChromeStorageMock;

beforeEach(() => {
  vi.useFakeTimers();
  setNow(BASE);
  (globalThis as unknown as { __saved: Session[] }).__saved = [];
  chromeMock = installChromeMock();
});

afterEach(() => {
  vi.useRealTimers();
});

const FIGMA_URL = "https://www.figma.com/design/abc123/My-File";
const BUBBLE_URL = "https://bubble.io/page?id=myapp";

describe("active time accrual", () => {
  it("accrues elapsed time within a tracking segment", async () => {
    const sm = await loadSessionManager();
    await sm.startSession(BUBBLE_URL, "Editor");
    advance(60);
    expect(sm.getCurrentDurationSeconds()).toBe(60);
  });

  it("persists the active session to storage on start", async () => {
    const sm = await loadSessionManager();
    await sm.startSession(BUBBLE_URL, "Editor");
    const p = persistedActive(chromeMock);
    expect(p).toBeDefined();
    expect(p!.session.url).toBe(BUBBLE_URL);
    expect(p!.session.accumulatedSeconds).toBe(0);
  });

  it("captures detected entity from the URL (figma)", async () => {
    const sm = await loadSessionManager();
    await sm.startSession(FIGMA_URL, "My File");
    const active = sm.getActiveSession();
    expect(active?.service).toBe("figma");
    expect(active?.detectedEntityId).toBe("abc123");
  });

  it("stores the provided assignment and marks manual sources reviewed", async () => {
    const sm = await loadSessionManager();
    await sm.startSession(BUBBLE_URL, "Editor", {
      projectId: "proj-1",
      projectName: "RoleKick",
      assignmentSource: "manual_popup",
      assignmentConfidence: 100,
      tagIds: ["tag-1"],
      billable: true,
    });
    advance(10);
    await sm.endCurrentSession();

    const s = saved()[0];
    expect(s.projectId).toBe("proj-1");
    expect(s.projectName).toBe("RoleKick");
    expect(s.assignmentSource).toBe("manual_popup");
    expect(s.assignmentConfidence).toBe(100);
    expect(s.tagIds).toEqual(["tag-1"]);
    expect(s.billable).toBe(true);
    expect(s.reviewed).toBe(true);
    expect(s.syncedToSheets).toBe(0);
  });

  it("defaults to unassigned when no assignment is provided", async () => {
    const sm = await loadSessionManager();
    await sm.startSession(BUBBLE_URL, "Editor");
    advance(10);
    await sm.endCurrentSession();

    const s = saved()[0];
    expect(s.projectId).toBeNull();
    expect(s.assignmentSource).toBe("unassigned");
    expect(s.assignmentConfidence).toBe(0);
    expect(s.reviewed).toBe(false);
  });
});

describe("finalizing sessions", () => {
  it("saves with the correct duration and clears storage", async () => {
    const sm = await loadSessionManager();
    await sm.startSession(BUBBLE_URL, "Editor");
    advance(120);
    await sm.endCurrentSession();

    expect(saved()).toHaveLength(1);
    expect(saved()[0].durationSeconds).toBe(120);
    expect(saved()[0].domain).toBe("bubble.io");
    expect(persistedActive(chromeMock)).toBeUndefined();
    expect(sm.getActiveSession()).toBeNull();
  });

  it("discards sessions shorter than 2 seconds", async () => {
    const sm = await loadSessionManager();
    await sm.startSession(BUBBLE_URL, "Editor");
    advance(1);
    await sm.endCurrentSession();
    expect(saved()).toHaveLength(0);
  });

  it("starting a new session finalizes the previous one", async () => {
    const sm = await loadSessionManager();
    await sm.startSession(BUBBLE_URL, "Editor");
    advance(30);
    await sm.startSession(FIGMA_URL, "My File");
    expect(saved()).toHaveLength(1);
    expect(saved()[0].durationSeconds).toBe(30);
    expect(sm.getActiveSession()?.url).toBe(FIGMA_URL);
  });
});

describe("pause / resume", () => {
  it("does not count time while idle-paused", async () => {
    const sm = await loadSessionManager();
    await sm.startSession(BUBBLE_URL, "Editor");
    advance(30);
    await sm.pauseSession("idle");
    advance(100); // idle — must not count
    await sm.resumeSession("idle");
    advance(20);
    await sm.endCurrentSession();
    expect(saved()[0].durationSeconds).toBe(50); // 30 + 20
  });

  it("stays paused until every pause reason clears (idle + blur)", async () => {
    const sm = await loadSessionManager();
    await sm.startSession(BUBBLE_URL, "Editor");
    advance(10);
    await sm.pauseSession("idle");
    await sm.pauseSession("blur");
    advance(50);
    await sm.resumeSession("blur"); // still idle-paused
    expect(sm.isPaused()).toBe(true);
    advance(50); // still must not count
    await sm.resumeSession("idle"); // now fully active
    expect(sm.isPaused()).toBe(false);
    advance(10);
    await sm.endCurrentSession();
    expect(saved()[0].durationSeconds).toBe(20); // 10 + 10
  });
});

describe("heartbeat", () => {
  it("banks elapsed time and checkpoints to storage", async () => {
    const sm = await loadSessionManager();
    await sm.startSession(BUBBLE_URL, "Editor");
    advance(40);
    await sm.heartbeat();

    const p = persistedActive(chromeMock);
    expect(p!.session.accumulatedSeconds).toBe(40);
    expect(p!.session.segmentStart).toBe(now);
    expect(p!.lastCheckpoint).toBe(now);
  });
});

describe("service-worker restart (the core fix)", () => {
  it("restores an in-flight session and credits a short gap", async () => {
    // SW #1: work 40s, heartbeat checkpoints to storage.
    const sm1 = await loadSessionManager();
    await sm1.startSession(FIGMA_URL, "My File");
    advance(40);
    await sm1.heartbeat();

    // SW killed. Short gap (well under the cap) while the user keeps working.
    const sm2 = await loadSessionManager();
    advance(20);
    await sm2.restoreState();

    expect(sm2.getActiveSession()?.url).toBe(FIGMA_URL);
    // 40 banked + 20 gap credited (the SW was just churning while active).
    expect(sm2.getCurrentDurationSeconds()).toBe(60);

    advance(10);
    await sm2.endCurrentSession();
    expect(saved()[0].durationSeconds).toBe(70);
  });

  it("does NOT credit a long gap (machine slept / browser closed)", async () => {
    const sm1 = await loadSessionManager();
    await sm1.startSession(FIGMA_URL, "My File");
    advance(40);
    await sm1.heartbeat();

    // SW killed, then a gap well beyond the cap (e.g. laptop asleep).
    const sm2 = await loadSessionManager();
    advance(MAX_CREDIT_GAP_SECONDS + 600);
    await sm2.restoreState();

    // Session finalized at the last checkpoint; dead time not counted.
    expect(saved()).toHaveLength(1);
    expect(saved()[0].durationSeconds).toBe(40);
    expect(sm2.getActiveSession()).toBeNull();
    expect(persistedActive(chromeMock)).toBeUndefined();
  });

  it("restores a paused session as paused and credits no gap time", async () => {
    const sm1 = await loadSessionManager();
    await sm1.startSession(BUBBLE_URL, "Editor");
    advance(30);
    await sm1.pauseSession("idle"); // banks 30, clock stopped

    const sm2 = await loadSessionManager();
    advance(60); // short gap, but session was paused
    await sm2.restoreState();

    expect(sm2.isPaused()).toBe(true);
    expect(sm2.getCurrentDurationSeconds()).toBe(30); // no accrual while paused

    await sm2.resumeSession("idle");
    advance(10);
    await sm2.endCurrentSession();
    expect(saved()[0].durationSeconds).toBe(40); // 30 + 10
  });

  it("accumulates correctly across several kill/revive cycles", async () => {
    // Simulates hours on one Bubble tab: SW dies and revives repeatedly,
    // heartbeats checkpoint each interval, time keeps adding up.
    let sm = await loadSessionManager();
    await sm.startSession(BUBBLE_URL, "Editor");

    for (let i = 0; i < 5; i++) {
      advance(30); // a heartbeat interval of active work
      await sm.heartbeat();
      sm = await loadSessionManager(); // SW killed and revived
      advance(15); // short gap before restore
      await sm.restoreState();
    }

    await sm.endCurrentSession();
    // 5 * (30 banked + 15 credited gap) = 225
    expect(saved()[0].durationSeconds).toBe(225);
  });
});
