import type { ParsedProject } from "../shared/types";

// Handles:
//   https://{appName}.bubbleapps.io/...          (published app)
//   https://{appName}.bubbleapps.io/version-test/... (test version)
//   https://bubble.io/page?name=...&id={appId}  (editor)
export function parseBubble(url: string): ParsedProject | null {
  try {
    const u = new URL(url);

    // Editor: bubble.io/page
    if (u.hostname === "bubble.io" && u.pathname.startsWith("/page")) {
      const appId = u.searchParams.get("id");
      if (!appId) return null;
      return {
        service: "bubble",
        projectId: appId,
        projectName: null,
      };
    }

    // Published/test app: {appName}.bubbleapps.io
    const subdomain = u.hostname.match(/^(.+)\.bubbleapps\.io$/)?.[1];
    if (subdomain) {
      return {
        service: "bubble",
        projectId: subdomain,
        projectName: subdomain,
      };
    }

    return null;
  } catch {
    return null;
  }
}
