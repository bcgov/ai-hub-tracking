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
  },
  webServer: [
    {
      command: "node scripts/start-e2e-dev-server.cjs",
      url: "http://127.0.0.1:4173",
      timeout: 120_000,
      reuseExistingServer,
    },
  ],
});
