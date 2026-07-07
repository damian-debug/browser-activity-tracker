import type {
  ActiveProjectOverride,
  ProjectRule,
  RuleEngineInput,
  RuleEngineResult,
} from "../shared/types";
import { runRuleEngine } from "./rule-engine";
import { CONFIDENCE } from "./confidence";

export function isOverrideActive(
  override: ActiveProjectOverride | null,
  input: { domain: string; tabId?: number },
  now = Date.now()
): boolean {
  if (!override) return false;
  if (override.expiresAt !== undefined && now > override.expiresAt) return false;
  switch (override.scope) {
    case "global":
      return true;
    case "current_domain":
      return override.domain === input.domain;
    case "current_tab":
      return override.tabId !== undefined && override.tabId === input.tabId;
  }
}

// Full attribution order (spec §11): active override → rule engine → unassigned.
// "Parser/entity match" is expressed through rules (e.g. a query-param or
// URL-contains rule pinning a Figma file or Bubble app), so the rule engine
// covers steps 2–9 of the spec order; parsers only supply detectedEntity*.
export function assignSession(
  input: RuleEngineInput & { tabId?: number },
  rules: ProjectRule[],
  override: ActiveProjectOverride | null,
  now = Date.now()
): RuleEngineResult {
  if (override && isOverrideActive(override, input, now)) {
    return {
      projectId: override.projectId,
      assignmentSource: "active_project_override",
      assignmentConfidence: CONFIDENCE.OVERRIDE,
      defaultTagIds: override.tagIds,
      billable: override.billable,
    };
  }

  return runRuleEngine(input, rules);
}
