import { v4 as uuidv4 } from "uuid";
import { db } from "./db";
import { DEFAULT_TAG_NAMES } from "../shared/constants";

// Idempotent: seeds the default tags and the "Internal" project only when the
// respective tables are empty. Called from background bootstrap so it covers
// both fresh installs and V1→V2 upgrades (Dexie's populate hook only fires for
// brand-new databases).
export async function seedDefaults(): Promise<void> {
  const now = Date.now();

  const tagCount = await db.tags.count();
  if (tagCount === 0) {
    await db.tags.bulkPut(
      DEFAULT_TAG_NAMES.map((name) => ({
        id: uuidv4(),
        name,
        createdAt: now,
        updatedAt: now,
      }))
    );
  }

  const projectCount = await db.projects.count();
  if (projectCount === 0) {
    await db.projects.put({
      id: uuidv4(),
      name: "Internal",
      defaultBillable: false,
      archived: false,
      createdAt: now,
      updatedAt: now,
    });
  }
}
