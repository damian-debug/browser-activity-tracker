import type { ProjectRuleType, Session } from "../shared/types";

export interface RuleSuggestion {
  label: string;
  type: ProjectRuleType;
  value: string;
  queryParamName?: string;
}

// Given a session, propose rule templates the user can turn into a ProjectRule
// (spec §23). Ordered most → least specific; the UI offers them as choices.
export function suggestRulesFromSession(session: Session): RuleSuggestion[] {
  const suggestions: RuleSuggestion[] = [];

  // Service-specific entity rules first — these are the highest-value ones.
  if (session.service === "bubble" && session.detectedEntityId) {
    try {
      const u = new URL(session.url);
      if (u.searchParams.get("id") === session.detectedEntityId) {
        suggestions.push({
          label: `Bubble app "${session.detectedEntityId}"`,
          type: "query_param_equals",
          value: session.detectedEntityId,
          queryParamName: "id",
        });
      }
    } catch {
      // fall through to generic suggestions
    }
  }

  if (session.service === "figma" && session.detectedEntityId) {
    try {
      const u = new URL(session.url);
      const m = u.pathname.match(/^\/(file|design|proto|board)\/[^/]+/);
      if (m) {
        suggestions.push({
          label: `Figma file "${session.detectedEntityName ?? session.detectedEntityId}"`,
          type: "url_contains",
          value: `figma.com${m[0]}`,
        });
      }
    } catch {
      // fall through to generic suggestions
    }
  }

  // Generic options.
  suggestions.push({
    label: "Only this exact URL",
    type: "url_starts_with",
    value: session.url,
  });

  try {
    const u = new URL(session.url);
    const firstPathSegment = u.pathname.split("/").filter(Boolean)[0];
    if (firstPathSegment) {
      suggestions.push({
        label: `URL path contains "/${firstPathSegment}"`,
        type: "path_contains",
        value: `/${firstPathSegment}`,
      });
    }
  } catch {
    // skip path suggestion for unparseable URLs
  }

  suggestions.push({
    label: `Everything on ${session.domain}`,
    type: "domain_equals",
    value: session.domain,
  });

  if (session.title) {
    suggestions.push({
      label: `Title contains "${session.title.slice(0, 40)}"`,
      type: "title_contains",
      value: session.title,
    });
  }

  return suggestions;
}
