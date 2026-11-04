import path from "node:path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./vitest.setup.ts"],
    css: false,
    exclude: ["e2e/**", "node_modules/**", ".next/**", "dist/**"],
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "src"),
      // ADR-530: the website's fonts load through Next's compiler only.
      "next/font/google": path.resolve(__dirname, "src/lib/testing/next-font-google.ts"),
    },
  },
});
