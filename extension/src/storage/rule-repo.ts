import { v4 as uuidv4 } from "uuid";
import { db } from "./db";
import type { ProjectRule } from "../shared/types";

export async function listRules(projectId?: string): Promise<ProjectRule[]> {
  if (projectId) {
    return db.projectRules.where("projectId").equals(projectId).sortBy("priority");
  }
  return db.projectRules.toArray();
}

// All enabled rules, priority descending — the order the engine consumes.
export async function listEnabledRules(): Promise<ProjectRule[]> {
  const all = await db.projectRules.toArray();
  return all.filter((r) => r.enabled).sort((a, b) => b.priority - a.priority);
}

export async function createRule(
  data: Omit<ProjectRule, "id" | "createdAt" | "updatedAt">
): Promise<ProjectRule> {
  const now = Date.now();
  const rule: ProjectRule = { ...data, id: uuidv4(), createdAt: now, updatedAt: now };
  await db.projectRules.put(rule);
  return rule;
}

export async function updateRule(
  id: string,
  patch: Partial<Omit<ProjectRule, "id" | "createdAt">>
): Promise<void> {
  await db.projectRules.update(id, { ...patch, updatedAt: Date.now() });
}

export async function deleteRule(id: string): Promise<void> {
  await db.projectRules.delete(id);
}
