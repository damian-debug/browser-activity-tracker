import type { ProjectRuleType } from "../shared/types";

// Confidence scoring (spec §10). Deterministic and covered by tests; sessions
// at or above the review threshold (default 70) skip the Review Needed queue.
export const CONFIDENCE = {
  MANUAL: 100,
  OVERRIDE: 100,
  URL_CONTAINS: 95,      // "strong URL rule"
  QUERY_PARAM: 90,
  URL_STARTS_WITH: 80,
  REGEX: 80,
  PATH_CONTAINS: 75,
  TITLE_CONTAINS: 70,
  DOMAIN: 60,
  UNASSIGNED: 0,
} as const;

export const RULE_TYPE_CONFIDENCE: Record<ProjectRuleType, number> = {
  url_contains: CONFIDENCE.URL_CONTAINS,
  query_param_equals: CONFIDENCE.QUERY_PARAM,
  url_starts_with: CONFIDENCE.URL_STARTS_WITH,
  regex: CONFIDENCE.REGEX,
  path_contains: CONFIDENCE.PATH_CONTAINS,
  title_contains: CONFIDENCE.TITLE_CONTAINS,
  domain_equals: CONFIDENCE.DOMAIN,
};

// Tie-break order when two enabled rules share the same priority: the more
// specific rule type wins (spec §21).
export const RULE_TYPE_SPECIFICITY: ProjectRuleType[] = [
  "query_param_equals",
  "url_starts_with",
  "url_contains",
  "path_contains",
  "regex",
  "title_contains",
  "domain_equals",
];
