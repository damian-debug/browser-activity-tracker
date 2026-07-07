import type { ProjectRule, RuleEngineInput, RuleEngineResult } from "../shared/types";
import { RULE_TYPE_CONFIDENCE, RULE_TYPE_SPECIFICITY, CONFIDENCE } from "./confidence";

function ruleMatches(rule: ProjectRule, input: RuleEngineInput): boolean {
  const value = rule.value;
  switch (rule.type) {
    case "domain_equals":
      return input.domain.toLowerCase() === value.toLowerCase().replace(/^www\./, "");
    case "url_contains":
      return input.url.toLowerCase().includes(value.toLowerCase());
    case "url_starts_with":
      return input.url.toLowerCase().startsWith(value.toLowerCase());
    case "path_contains": {
      try {
        return new URL(input.url).pathname.toLowerCase().includes(value.toLowerCase());
      } catch {
        return false;
      }
    }
    case "query_param_equals": {
      if (!rule.queryParamName) return false;
      try {
        return new URL(input.url).searchParams.get(rule.queryParamName) === value;
      } catch {
        return false;
      }
    }
    case "title_contains":
      return input.title.toLowerCase().includes(value.toLowerCase());
    case "regex": {
      try {
        return new RegExp(value).test(input.url);
      } catch {
        // Invalid user regex: never match rather than throwing in the tracker.
        return false;
      }
    }
  }
}

function specificityIndex(rule: ProjectRule): number {
  const i = RULE_TYPE_SPECIFICITY.indexOf(rule.type);
  return i === -1 ? RULE_TYPE_SPECIFICITY.length : i;
}

// Pure and deterministic: highest priority wins; on ties the more specific rule
// type wins; remaining ties resolve by rule id for stability.
export function runRuleEngine(input: RuleEngineInput, rules: ProjectRule[]): RuleEngineResult {
  const candidates = rules
    .filter((r) => r.enabled)
    .sort((a, b) => {
      if (b.priority !== a.priority) return b.priority - a.priority;
      const spec = specificityIndex(a) - specificityIndex(b);
      if (spec !== 0) return spec;
      return a.id.localeCompare(b.id);
    });

  for (const rule of candidates) {
    if (ruleMatches(rule, input)) {
      return {
        projectId: rule.projectId,
        matchedRuleId: rule.id,
        assignmentSource: "auto_rule",
        assignmentConfidence: RULE_TYPE_CONFIDENCE[rule.type],
        defaultTagIds: rule.defaultTagIds,
        billable: rule.defaultBillable,
      };
    }
  }

  return {
    projectId: null,
    assignmentSource: "unassigned",
    assignmentConfidence: CONFIDENCE.UNASSIGNED,
  };
}
