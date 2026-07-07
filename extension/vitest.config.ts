import { defineConfig } from "vitest/config";

// Separate from vite.config.ts (which is the extension build config) so the
// React plugin and multi-entry rollup setup don't interfere with the test run.
export default defineConfig({
  test: {
    environment: "node",
    include: ["tests/**/*.test.ts"],
  },
});
