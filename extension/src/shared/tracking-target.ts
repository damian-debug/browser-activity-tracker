import { parseProjectFromUrl } from "../parsers";

export interface TargetLike {
  service: string | null;
  detectedEntityId: string | null;
  url: string;
}

// Decides whether navigating to `url` is the SAME tracking target as the current
// session — i.e. whether to keep accruing or start fresh.
//
// When both the current session and the new URL resolve to a known entity
// (service + detectedEntityId), continuity is decided by entity identity. This
// is the key to "broad spectrum" tracking: clicking around inside one Bubble app
// or one Figma file rewrites the URL constantly, but it's still the same work,
// so it stays one continuous session instead of fragmenting into discarded
// slivers.
//
// If either side has no entity identity, fall back to an exact URL match.
export function isSameTarget(current: TargetLike, url: string): boolean {
  if (current.service && current.detectedEntityId) {
    const parsed = parseProjectFromUrl(url);
    if (parsed) {
      return current.service === parsed.service && current.detectedEntityId === parsed.projectId;
    }
  }
  return current.url === url;
}
