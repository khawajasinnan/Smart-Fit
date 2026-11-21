import { defineConfig, devices } from '@playwright/test';

import { admin } from './helpers/env';

/**
 * End-to-end tests of SmartFit (SRDS 4.3.6): the Flutter web build driven through its
 * accessibility tree (built with --dart-define=E2E=true), against the local backend
 * (backend/run_local.bat) and the hosted Supabase, with the two test shoppers made by
 * backend/scripts/e2e_users.py. Files run in order: later ones reuse the woman's
 * session and the outfit she saved.
 */
export default defineConfig({
  globalSetup: './global-setup.ts',
  testDir: './tests',
  testMatch: /.*\.(spec|setup)\.ts/,
  fullyParallel: false,
  workers: 1,
  retries: 0,
  timeout: 240_000, // AI steps (Gemini, GPU try-on, hairstyles) take up to a few minutes
  expect: { timeout: 30_000 },
  reporter: [['list'], ['html', { open: 'never' }], ['json', { outputFile: 'test-results/results.json' }]],
  use: {
    baseURL: 'http://localhost:5055', // not 5000: see serve.mjs
    ...devices['Pixel 7'],
    browserName: 'chromium',
    isMobile: false, // Flutter web reads mouse events most reliably
    hasTouch: false,
    viewport: { width: 412, height: 915 },
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    actionTimeout: 30_000,
  },
  webServer: [
    { command: 'node serve.mjs', url: 'http://localhost:5055', reuseExistingServer: true },
    // the web admin panel, only when tests/10-admin.spec.ts has a login to use
    ...(admin.email && admin.password
      ? [{ command: 'npm run dev', cwd: '../admin-panel', url: 'http://localhost:5173', reuseExistingServer: true }]
      : []),
  ],
});
