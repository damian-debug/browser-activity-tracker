import { describe, it, expect } from "vitest";
import { isSameTarget } from "../src/shared/tracking-target";

const bubbleSampleApp = {
  service: "bubble",
  detectedEntityId: "sampleapp",
  url: "https://bubble.io/page?id=sampleapp&tab=Design",
};

const figmaFile = {
  service: "figma",
  detectedEntityId: "abc123",
  url: "https://www.figma.com/design/abc123/My-File",
};

const plainPage = {
  service: null,
  detectedEntityId: null,
  url: "https://example.com/docs/intro",
};

describe("isSameTarget", () => {
  it("keeps the session when navigating within the same Bubble app", () => {
    // Bubble rewrites the URL as you click around the editor — same app, so
    // continuity must hold.
    expect(isSameTarget(bubbleSampleApp, "https://bubble.io/page?id=sampleapp&tab=Settings")).toBe(true);
    expect(isSameTarget(bubbleSampleApp, "https://bubble.io/page?id=sampleapp&tab=Workflow&x=1")).toBe(true);
  });

  it("starts a new session when switching to a different Bubble app", () => {
    expect(isSameTarget(bubbleSampleApp, "https://bubble.io/page?id=otherapp&tab=Design")).toBe(false);
  });

  it("keeps the session across navigation within the same Figma file", () => {
    expect(
      isSameTarget(figmaFile, "https://www.figma.com/design/abc123/My-File?node-id=12-34")
    ).toBe(true);
  });

  it("starts a new session for a different Figma file", () => {
    expect(
      isSameTarget(figmaFile, "https://www.figma.com/design/zzz999/Other-File")
    ).toBe(false);
  });

  it("falls back to exact URL match when no project is detected", () => {
    expect(isSameTarget(plainPage, "https://example.com/docs/intro")).toBe(true);
    expect(isSameTarget(plainPage, "https://example.com/docs/advanced")).toBe(false);
  });

  it("starts a new session when leaving a project for a plain page on the same domain", () => {
    // From the Bubble app editor to the Bubble marketing/settings site root.
    expect(isSameTarget(bubbleSampleApp, "https://bubble.io/home")).toBe(false);
  });

  it("starts a new session when a project page changes to a different service", () => {
    expect(isSameTarget(bubbleSampleApp, "https://www.figma.com/design/abc123/My-File")).toBe(false);
  });
});
