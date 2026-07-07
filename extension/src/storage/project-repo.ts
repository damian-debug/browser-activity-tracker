import { v4 as uuidv4 } from "uuid";
import { db } from "./db";
import type { Project } from "../shared/types";

export async function listProjects(includeArchived = false): Promise<Project[]> {
  const all = await db.projects.orderBy("name").toArray();
  return includeArchived ? all : all.filter((p) => !p.archived);
}

export async function getProject(id: string): Promise<Project | undefined> {
  return db.projects.get(id);
}

export async function createProject(
  data: Pick<Project, "name"> & Partial<Pick<Project, "clientName" | "color" | "defaultBillable">>
): Promise<Project> {
  const now = Date.now();
  const project: Project = {
    id: uuidv4(),
    name: data.name,
    clientName: data.clientName,
    color: data.color,
    defaultBillable: data.defaultBillable ?? false,
    archived: false,
    createdAt: now,
    updatedAt: now,
  };
  await db.projects.put(project);
  return project;
}

export async function updateProject(
  id: string,
  patch: Partial<Omit<Project, "id" | "createdAt">>
): Promise<void> {
  await db.projects.update(id, { ...patch, updatedAt: Date.now() });
}

export async function archiveProject(id: string, archived = true): Promise<void> {
  await db.projects.update(id, { archived, updatedAt: Date.now() });
}
