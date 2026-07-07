import type { AppSettings } from "./types";

export const DEFAULT_IDLE_THRESHOLD_SECONDS = 60;

export const DEFAULT_EXCLUDED_DOMAINS = [
  "localhost",
  "127.0.0.1",
  "0.0.0.0",
  "newtab",
  "extensions",
];

export const EXCLUDED_SCHEMES = ["chrome:", "chrome-extension:", "about:", "edge:", "brave:"];

// Sessions below this confidence (or unassigned/unreviewed) show in Review Needed
export const DEFAULT_REVIEW_CONFIDENCE_THRESHOLD = 70;

export const DEFAULT_SETTINGS: AppSettings = {
  idleThresholdSeconds: DEFAULT_IDLE_THRESHOLD_SECONDS,
  excludedDomains: DEFAULT_EXCLUDED_DOMAINS,
  reviewConfidenceThreshold: DEFAULT_REVIEW_CONFIDENCE_THRESHOLD,
};

export const STORAGE_KEYS = {
  SETTINGS: "bat_settings",
  // In-flight session, persisted so it survives service-worker termination
  ACTIVE: "bat_active",
  // Active project override (manual "track everything to X" state)
  OVERRIDE: "bat_override",
} as const;

export const ALARM_NAMES = {
  HEARTBEAT: "bat_heartbeat",
  // One-shot alarm at a timed override's expiresAt, so the live session stops
  // crediting the override project at the expiry moment.
  OVERRIDE_EXPIRY: "bat_override_expiry",
} as const;

// Heartbeat fires this often: checkpoints the active session to storage AND
// keeps the MV3 service worker alive (each alarm wake resets its idle timer).
// 0.5 min (30s) is the lowest interval Chrome reliably honors.
export const HEARTBEAT_INTERVAL_MINUTES = 0.5;

// On service-worker wake we may find a persisted session whose last checkpoint
// is some seconds old. If the gap is small, the SW was just churning while the
// user kept working, so we credit it. If it exceeds this cap, the machine most
// likely slept or the browser was closed (no alarms/events fire then), so we
// finalize the session at its last checkpoint instead of crediting dead time.
export const MAX_CREDIT_GAP_SECONDS = 150;

// Tags created once on first V2 run (only when the tags table is empty)
export const DEFAULT_TAG_NAMES = [
  "Development",
  "Design",
  "QA",
  "Bug Fix",
  "Research",
  "Planning",
  "Admin",
  "Support",
  "Content",
  "Client Work",
];
