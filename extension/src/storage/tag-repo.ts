import { v4 as uuidv4 } from "uuid";
import { db } from "./db";
import type { Tag } from "../shared/types";

export async function listTags(): Promise<Tag[]> {
  return db.tags.orderBy("name").toArray();
}

export async function createTag(name: string, color?: string): Promise<Tag> {
  const now = Date.now();
  const tag: Tag = { id: uuidv4(), name, color, createdAt: now, updatedAt: now };
  await db.tags.put(tag);
  return tag;
}

export async function updateTag(
  id: string,
  patch: Partial<Pick<Tag, "name" | "color">>
): Promise<void> {
  await db.tags.update(id, { ...patch, updatedAt: Date.now() });
}

export async function deleteTag(id: string): Promise<void> {
  // Remove the tag and strip it from any sessions/rules that reference it.
  await db.transaction("rw", db.tags, db.sessions, db.projectRules, async () => {
    await db.tags.delete(id);
    await db.sessions
      .toCollection()
      .modify((s) => {
        if (s.tagIds.includes(id)) {
          s.tagIds = s.tagIds.filter((t) => t !== id);
          s.updatedAt = Date.now();
        }
      });
    await db.projectRules
      .toCollection()
      .modify((r) => {
        if (r.defaultTagIds?.includes(id)) {
          r.defaultTagIds = r.defaultTagIds.filter((t) => t !== id);
          r.updatedAt = Date.now();
        }
      });
  });
}
