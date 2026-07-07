import type { ActiveProjectOverride, ActiveProjectOverrideExpires } from "../shared/types";
import { STORAGE_KEYS } from "../shared/constants";

export function computeExpiresAt(
  expires: ActiveProjectOverrideExpires,
  now = Date.now()
): number | undefined {
  switch (expires) {
    case "manual":
      return undefined;
    case "thirty_minutes":
      return now + 30 * 60 * 1000;
    case "end_of_day": {
      const d = new Date(now);
      d.setHours(23, 59, 59, 999);
      return d.getTime();
    }
  }
}

export async function getOverride(): Promise<ActiveProjectOverride | null> {
  const stored = await chrome.storage.local.get(STORAGE_KEYS.OVERRIDE);
  return (stored[STORAGE_KEYS.OVERRIDE] as ActiveProjectOverride | undefined) ?? null;
}

export async function setOverride(override: ActiveProjectOverride): Promise<void> {
  await chrome.storage.local.set({ [STORAGE_KEYS.OVERRIDE]: override });
}

export async function clearOverride(): Promise<void> {
  await chrome.storage.local.remove(STORAGE_KEYS.OVERRIDE);
}
