import type { ProjectRule, Session } from "../shared/types";
import { runRuleEngine } from "./rule-engine";
import { db } from "../storage/db";
import { getProject } from "../storage/project-repo";

// Retroactively apply a newly created rule to existing sessions, so creating a
// rule from the Review queue resolves the sessions it was created from (and
// their siblings) instead of leaving them sitting there.
//
// Only sessions that are still UNASSIGNED and UNREVIEWED are touched — a
// manual assignment or an explicit "mark reviewed" always wins over a new
// rule. Matched sessions are marked reviewed: the user created this rule
// deliberately, so even a low-confidence rule type (e.g. domain) shouldn't
// bounce them straight back into the queue.
//
// Returns the number of sessions updated.
export async function applyRuleToExistingSessions(rule: ProjectRule): Promise<number> {
  if (!rule.enabled) return 0;

  const [project, sessions] = await Promise.all([
    getProject(rule.projectId),
    db.sessions.toArray(),
  ]);

  const now = Date.now();
  const updates: Session[] = [];

  for (const s of sessions) {
    if (s.projectId !== null || s.reviewed) continue;

    const result = runRuleEngine(
      {
        url: s.url,
        domain: s.domain,
        title: s.title,
        service: s.service,
        detectedEntityId: s.detectedEntityId,
        detectedEntityName: s.detectedEntityName,
      },
      [rule]
    );
    if (!result.projectId) continue;

    updates.push({
      ...s,
      projectId: result.projectId,
      projectName: project?.name ?? null,
      assignmentSource: "auto_rule",
      assignmentConfidence: result.assignmentConfidence,
      matchedRuleId: rule.id,
      tagIds: result.defaultTagIds ?? s.tagIds,
      billable: result.billable ?? project?.defaultBillable ?? false,
      reviewed: true,
      updatedAt: now,
    });
  }

  if (updates.length > 0) await db.sessions.bulkPut(updates);
  return updates.length;
}
