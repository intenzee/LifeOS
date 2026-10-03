import { defineConfig } from "vitest/config";

// Plain Node: the core (src/app.ts and below) uses only web standards
// (fetch, Request, crypto.subtle). Workers-only bindings live in src/worker.ts.
export default defineConfig({
  test: { include: ["test/**/*.test.ts"], environment: "node" },
});
