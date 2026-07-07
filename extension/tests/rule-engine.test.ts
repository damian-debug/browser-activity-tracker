import { describe, it, expect } from "vitest";
import { runRuleEngine } from "../src/attribution/rule-engine";
import { assignSession, isOverrideActive } from "../src/attribution/assign-session";
import { computeExpiresAt } from "../src/attribution/override-store";
import { CONFIDENCE } from "../src/attribution/confidence";
import type { ProjectRule, RuleEngineInput, ActiveProjectOverride } from "../src/shared/types";

function rule(partial: Partial<ProjectRule> & Pick<ProjectRule, "type" | "value" | "projectId">): ProjectRule {
  return {
    id: partial.id ?? `rule-${partial.type}-${partial.value}`,
    name: partial.name ?? "test rule",
    queryParamName: partial.queryParamName,
    priority: partial.priority ?? 0,
    enabled: partial.enabled ?? true,
    defaultTagIds: partial.defaultTagIds,
    defaultBillable: partial.defaultBillable,
    createdAt: 0,
    updatedAt: 0,
    ...{ type: partial.type, value: partial.value, projectId: partial.projectId },
  };
}

function input(partial: Partial<RuleEngineInput> = {}): RuleEngineInput {
  return {
    url: "https://bubble.io/page?id=sampleapp&tab=Design",
    domain: "bubble.io",
    title: "sampleapp | Bubble Editor",
    service: "bubble",
    detectedEntityId: "sampleapp",
    detectedEntityName: null,
    ...partial,
  };
}

describe("rule matchers", () => {
  it("domain_equals matches case-insensitively and ignores www", () => {
    const r = rule({ type: "domain_equals", value: "Bubble.io", projectId: "p1" });
    expect(runRuleEngine(input(), [r]).projectId).toBe("p1");
    expect(runRuleEngine(input({ domain: "github.com" }), [r]).projectId).toBeNull();
  });

  it("url_contains matches substrings", () => {
    const r = rule({ type: "url_contains", value: "bubble.io/page?id=sampleapp", projectId: "p1" });
    expect(runRuleEngine(input(), [r]).projectId).toBe("p1");
    expect(runRuleEngine(input(), [r]).assignmentConfidence).toBe(CONFIDENCE.URL_CONTAINS);
  });

  it("url_starts_with matches prefixes only", () => {
    const r = rule({ type: "url_starts_with", value: "https://bubble.io/page", projectId: "p1" });
    expect(runRuleEngine(input(), [r]).projectId).toBe("p1");
    expect(
      runRuleEngine(input({ url: "https://other.com/?next=https://bubble.io/page" }), [r]).projectId
    ).toBeNull();
  });

  it("path_contains matches against the pathname only", () => {
    const r = rule({ type: "path_contains", value: "/project/acme", projectId: "p1" });
    expect(
      runRuleEngine(input({ url: "https://app.example.com/project/acme/board" }), [r]).projectId
    ).toBe("p1");
    // Value in query string must NOT match a path rule
    expect(
      runRuleEngine(input({ url: "https://app.example.com/?path=/project/acme" }), [r]).projectId
    ).toBeNull();
  });

  it("query_param_equals matches the exact parameter value", () => {
    const r = rule({
      type: "query_param_equals",
      value: "sampleapp",
      queryParamName: "id",
      projectId: "p1",
    });
    expect(runRuleEngine(input(), [r]).projectId).toBe("p1");
    expect(runRuleEngine(input({ url: "https://bubble.io/page?id=other" }), [r]).projectId).toBeNull();
    expect(runRuleEngine(input(), [r]).assignmentConfidence).toBe(CONFIDENCE.QUERY_PARAM);
  });

  it("title_contains matches case-insensitively", () => {
    const r = rule({ type: "title_contains", value: "SAMPLEAPP", projectId: "p1" });
    expect(runRuleEngine(input(), [r]).projectId).toBe("p1");
  });

  it("regex matches against the URL and tolerates invalid patterns", () => {
    const good = rule({ type: "regex", value: "bubble\\.io\\/page\\?id=sampleapp", projectId: "p1" });
    expect(runRuleEngine(input(), [good]).projectId).toBe("p1");

    const invalid = rule({ type: "regex", value: "([unclosed", projectId: "p2" });
    expect(runRuleEngine(input(), [invalid]).projectId).toBeNull();
  });
});

describe("rule selection", () => {
  it("ignores disabled rules", () => {
    const r = rule({ type: "domain_equals", value: "bubble.io", projectId: "p1", enabled: false });
    expect(runRuleEngine(input(), [r]).projectId).toBeNull();
    expect(runRuleEngine(input(), [r]).assignmentSource).toBe("unassigned");
  });

  it("higher priority wins regardless of specificity", () => {
    const broad = rule({ type: "domain_equals", value: "bubble.io", projectId: "broad", priority: 10 });
    const narrow = rule({
      type: "query_param_equals", value: "sampleapp", queryParamName: "id", projectId: "narrow", priority: 1,
    });
    expect(runRuleEngine(input(), [broad, narrow]).projectId).toBe("broad");
  });

  it("equal priority: more specific rule type wins", () => {
    const broad = rule({ type: "domain_equals", value: "bubble.io", projectId: "broad", priority: 0 });
    const narrow = rule({
      type: "query_param_equals", value: "sampleapp", queryParamName: "id", projectId: "narrow", priority: 0,
    });
    const result = runRuleEngine(input(), [broad, narrow]);
    expect(result.projectId).toBe("narrow");
    expect(result.matchedRuleId).toBe(narrow.id);
  });

  it("returns rule defaults (tags, billable)", () => {
    const r = rule({
      type: "domain_equals", value: "bubble.io", projectId: "p1",
      defaultTagIds: ["t1", "t2"], defaultBillable: true,
    });
    const result = runRuleEngine(input(), [r]);
    expect(result.defaultTagIds).toEqual(["t1", "t2"]);
    expect(result.billable).toBe(true);
  });

  it("returns unassigned when nothing matches", () => {
    const result = runRuleEngine(input(), []);
    expect(result.projectId).toBeNull();
    expect(result.assignmentSource).toBe("unassigned");
    expect(result.assignmentConfidence).toBe(0);
  });
});

describe("active project override", () => {
  const NOW = 1_700_000_000_000;

  function override(partial: Partial<ActiveProjectOverride> = {}): ActiveProjectOverride {
    return {
      projectId: "override-project",
      scope: "global",
      expires: "manual",
      startedAt: NOW,
      ...partial,
    };
  }

  it("global override beats any rule", () => {
    const r = rule({ type: "domain_equals", value: "bubble.io", projectId: "rule-project", priority: 99 });
    const result = assignSession(input(), [r], override(), NOW);
    expect(result.projectId).toBe("override-project");
    expect(result.assignmentSource).toBe("active_project_override");
    expect(result.assignmentConfidence).toBe(100);
  });

  it("domain-scoped override only applies on its domain", () => {
    const o = override({ scope: "current_domain", domain: "bubble.io" });
    expect(assignSession(input(), [], o, NOW).projectId).toBe("override-project");
    expect(assignSession(input({ domain: "github.com" }), [], o, NOW).projectId).toBeNull();
  });

  it("tab-scoped override only applies to its tab", () => {
    const o = override({ scope: "current_tab", tabId: 42 });
    expect(assignSession({ ...input(), tabId: 42 }, [], o, NOW).projectId).toBe("override-project");
    expect(assignSession({ ...input(), tabId: 7 }, [], o, NOW).projectId).toBeNull();
  });

  it("expired override is ignored (lazy expiry)", () => {
    const o = override({ expiresAt: NOW - 1 });
    expect(isOverrideActive(o, { domain: "bubble.io" }, NOW)).toBe(false);
    const result = assignSession(input(), [], o, NOW);
    expect(result.assignmentSource).toBe("unassigned");
  });

  it("computeExpiresAt: manual = none, thirty_minutes = +30m, end_of_day = local midnight", () => {
    expect(computeExpiresAt("manual", NOW)).toBeUndefined();
    expect(computeExpiresAt("thirty_minutes", NOW)).toBe(NOW + 30 * 60 * 1000);
    const eod = computeExpiresAt("end_of_day", NOW)!;
    const d = new Date(eod);
    expect(d.getHours()).toBe(23);
    expect(d.getMinutes()).toBe(59);
    expect(eod).toBeGreaterThan(NOW);
  });
});
