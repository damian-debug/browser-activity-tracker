import type { Assignment, ParsedProject } from "../shared/types";
import { listEnabledRules } from "../storage/rule-repo";
import { getProject } from "../storage/project-repo";
import { assignSession } from "./assign-session";
import { getOverride } from "./override-store";

// Impure glue between the pure attribution logic and the stores. Called by the
// tracker each time a session starts; loads rules + override, runs assignment,
// and denormalizes the project name / billable default.
export async function resolveAssignment(params: {
  url: string;
  domain: string;
  title: string;
  parsed: ParsedProject | null;
  tabId?: number;
}): Promise<Assignment> {
  const [rules, override] = await Promise.all([listEnabledRules(), getOverride()]);

  const result = assignSession(
    {
      url: params.url,
      domain: params.domain,
      title: params.title,
      service: params.parsed?.service ?? null,
      detectedEntityId: params.parsed?.projectId ?? null,
      detectedEntityName: params.parsed?.projectName ?? null,
      tabId: params.tabId,
    },
    rules,
    override
  );

  let projectName: string | null = null;
  let billable = result.billable ?? false;

  if (result.projectId) {
    const project = await getProject(result.projectId);
    projectName = project?.name ?? null;
    // Billable precedence: rule/override explicit value, else project default.
    if (result.billable === undefined) billable = project?.defaultBillable ?? false;
  }

  return {
    projectId: result.projectId,
    projectName,
    assignmentSource: result.assignmentSource,
    assignmentConfidence: result.assignmentConfidence,
    matchedRuleId: result.matchedRuleId,
    tagIds: result.defaultTagIds ?? [],
    billable,
  };
}

export const UNASSIGNED_ASSIGNMENT: Assignment = {
  projectId: null,
  projectName: null,
  assignmentSource: "unassigned",
  assignmentConfidence: 0,
  tagIds: [],
  billable: false,
};
