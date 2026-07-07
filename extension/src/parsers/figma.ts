import type { ParsedProject } from "../shared/types";

// Handles:
//   https://www.figma.com/file/{fileId}/{slug}
//   https://www.figma.com/design/{fileId}/{slug}
//   https://www.figma.com/proto/{fileId}/{slug}
//   https://www.figma.com/board/{fileId}/{slug}  (FigJam)
export function parseFigma(url: string): ParsedProject | null {
  try {
    const u = new URL(url);
    if (!u.hostname.includes("figma.com")) return null;

    const match = u.pathname.match(/^\/(file|design|proto|board)\/([^/]+)(?:\/([^/?#]*))?/);
    if (!match) return null;

    const fileId = match[2];
    const rawSlug = match[3] ?? null;
    const projectName = rawSlug ? decodeURIComponent(rawSlug).replace(/-/g, " ").trim() || null : null;

    return {
      service: "figma",
      projectId: fileId,
      projectName,
    };
  } catch {
    return null;
  }
}
