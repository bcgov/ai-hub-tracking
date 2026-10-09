import { defineConfig } from "@playwright/test";

const reuseExistingServer = !process.env.CI;

export default defineConfig({
  testDir: "./tests/e2e",
  timeout: 60_000,
  expect: {
    timeout: 10_000,
  },
  fullyParallel: false,
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    baseURL: "http://127.0.0.1:4173",
    headless: true,
    trace: "on-first-retry",
    // CI runs inside the Playwright container as root; Chromium refuses to start as
    // root without --no-sandbox. Scoped to CI so local runs keep the sandbox.
    launchOptions: {
      args: process.env.CI ? ["--no-sandbox"] : [],
    },
  },
  webServer: [
    {
      command: "node scripts/start-e2e-dev-server.cjs",
      // /healthz goes through the Vite proxy to the backend, so this waits for both
      // servers; waiting on the Vite root alone races the slower backend start.
      url: "http://127.0.0.1:4173/healthz",
      timeout: 120_000,
      reuseExistingServer,
    },
  ],
});
