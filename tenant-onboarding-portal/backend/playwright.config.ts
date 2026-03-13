import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  timeout: 60_000,
  expect: {
    timeout: 10_000,
  },
  fullyParallel: false,
  reporter: [['list'], ['html', { open: 'never' }]],
  use: {
    baseURL: 'http://localhost:4300',
    headless: true,
    trace: 'on-first-retry',
  },
  webServer: {
    command: 'npm run e2e:serve',
    url: 'http://localhost:4300/healthz',
    timeout: 120_000,
    reuseExistingServer: false,
  },
});
