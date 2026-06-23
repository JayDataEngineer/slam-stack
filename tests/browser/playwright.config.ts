import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright configuration for slam-stack browser tests.
 *
 * These tests run inside Docker (mcr.microsoft.com/playwright) because the
 * host may not support Playwright's native browser dependencies.
 *
 * The BASE_URL and service URLs are injected via environment variables
 * from tests/browser/run-docker.sh, which sets up port-forwards before
 * running the container.
 */
export default defineConfig({
  testDir: './tests',
  fullyParallel: false,        // Sequential — services share port-forwards
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers: 1,                  // Single worker — port-forward limitation
  reporter: [
    ['list'],
    ['html', { open: 'never', outputFolder: 'test-results/html-report' }],
    ['junit', { outputFile: 'test-results/junit.xml' }],
  ],
  timeout: 30_000,
  expect: { timeout: 10_000 },
  use: {
    // Services are reached via host port-forwards on localhost.
    baseURL: process.env.BASE_URL || 'http://127.0.0.1:18080',

    // TLS certs in the cluster are self-signed / internal-CA signed.
    ignoreHTTPSErrors: true,

    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    trace: 'retain-on-failure',

    // Extra HTTP headers for all requests.
    extraHTTPHeaders: {
      'X-Slam-Stack-Test': 'playwright',
    },
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
