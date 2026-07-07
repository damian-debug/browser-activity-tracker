// ─── Projects, Tags, Rules (V2 attribution layer) ───────────────────────────

export interface Project {
  id: string;
  name: string;
  clientName?: string;
  color?: string;
  defaultBillable: boolean;
  archived: boolean;
  createdAt: number;
  updatedAt: number;
}

export interface Tag {
  id: string;
  name: string;
  color?: string;
  createdAt: number;
  updatedAt: number;
}

export type ProjectRuleType =
  | "domain_equals"
  | "url_contains"
  | "url_starts_with"
  | "path_contains"
  | "query_param_equals"
  | "title_contains"
  | "regex";

export interface ProjectRule {
  id: string;
  projectId: string;
  name: string;
  type: ProjectRuleType;
  value: string;
  // Only for query_param_equals: the parameter name to match; `value` above
  // holds the expected parameter value.
  queryParamName?: string;
  priority: number;
  enabled: boolean;
  defaultTagIds?: string[];
  defaultBillable?: boolean;
  createdAt: number;
  updatedAt: number;
}

export type AssignmentSource =
  | "auto_rule"
  | "manual_popup"
  | "manual_dashboard"
  | "active_project_override"
  | "suggested"
  | "unassigned";

export type ActiveProjectOverrideScope = "global" | "current_tab" | "current_domain";
export type ActiveProjectOverrideExpires = "manual" | "thirty_minutes" | "end_of_day";

export interface ActiveProjectOverride {
  projectId: string;
  tagIds?: string[];
  billable?: boolean;
  scope: ActiveProjectOverrideScope;
  expires: ActiveProjectOverrideExpires;
  tabId?: number;
  domain?: string;
  startedAt: number;
  // Absolute expiry timestamp; undefined for "manual"
  expiresAt?: number;
}

// The project assignment attached to a session (live or stored).
export interface Assignment {
  projectId: string | null;
  projectName: string | null;
  assignmentSource: AssignmentSource;
  assignmentConfidence: number;
  matchedRuleId?: string;
  tagIds: string[];
  billable: boolean;
}

// ─── Sessions ────────────────────────────────────────────────────────────────

export interface Session {
  id: string;
  url: string;
  domain: string;
  title: string;

  // What the page IS, detected by parsers (Figma file, Bubble app, …)
  service: string | null;
  detectedEntityId: string | null;
  detectedEntityName: string | null;

  // Which user Project the time BELONGS to (null = Unassigned)
  projectId: string | null;
  projectName: string | null;
  assignmentSource: AssignmentSource;
  assignmentConfidence: number;
  matchedRuleId?: string;

  tagIds: string[];
  notes?: string;
  billable: boolean;
  reviewed: boolean;

  startTime: number;  // unix ms
  endTime: number;    // unix ms
  durationSeconds: number;

  createdAt: number;
  updatedAt: number;
}

export interface ActiveSession {
  id: string;
  url: string;
  domain: string;
  title: string;
  service: string | null;
  detectedEntityId: string | null;
  detectedEntityName: string | null;

  // Attribution decided at session start; persisted with the in-flight session
  // so it survives service-worker restarts.
  assignment: Assignment;

  startTime: number;
  // Accumulated seconds from previous tracking segments (handles pause/resume)
  accumulatedSeconds: number;
  // When the current tracking segment started (null if paused)
  segmentStart: number | null;
}

export type TrackingState = "TRACKING" | "PAUSED_IDLE" | "PAUSED_BLUR" | "STOPPED";

export interface ParsedProject {
  service: string;
  projectId: string;     // parser-detected entity id (kept name for parser API stability)
  projectName: string | null;
}

// ─── Attribution engine I/O ──────────────────────────────────────────────────

export interface RuleEngineInput {
  url: string;
  domain: string;
  title: string;
  service: string | null;
  detectedEntityId: string | null;
  detectedEntityName: string | null;
}

export interface RuleEngineResult {
  projectId: string | null;
  matchedRuleId?: string;
  assignmentSource: AssignmentSource;
  assignmentConfidence: number;
  defaultTagIds?: string[];
  billable?: boolean;
}

// ─── Aggregates ──────────────────────────────────────────────────────────────

export interface DomainSummary {
  domain: string;
  service: string | null;
  totalSeconds: number;
  sessionCount: number;
}

export interface EntitySummary {
  service: string;
  detectedEntityId: string;
  detectedEntityName: string | null;
  domain: string;
  totalSeconds: number;
  sessionCount: number;
  lastSeen: number;
}

export interface ProjectTotal {
  projectId: string | null;   // null = Unassigned bucket
  projectName: string;
  clientName?: string;
  color?: string;
  totalSeconds: number;
  billableSeconds: number;
  nonBillableSeconds: number;
  sessionCount: number;
  tagIds: string[];
}

export interface TagTotal {
  tagId: string;
  tagName: string;
  color?: string;
  totalSeconds: number;
  sessionCount: number;
}

export interface DashboardStats {
  totalActiveSeconds: number;
  billableSeconds: number;
  unassignedSeconds: number;
  needsReviewSeconds: number;
  needsReviewCount: number;
  sessionCount: number;
  domainCount: number;
  domains: DomainSummary[];
  entities: EntitySummary[];
  projectTotals: ProjectTotal[];
  tagTotals: TagTotal[];
}

// ─── Settings ────────────────────────────────────────────────────────────────

export interface AppSettings {
  idleThresholdSeconds: number;
  excludedDomains: string[];
  // Sessions below this confidence (or unassigned/unreviewed) appear in Review Needed
  reviewConfidenceThreshold: number;
}
