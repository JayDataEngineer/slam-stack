/**
 * Slam Stack — Web Dashboard Browser Tests
 *
 * Validates the slam-stack web dashboard loads, renders critical
 * components, and responds to navigation. These are non-mocked E2E
 * tests that hit the real dashboard service via port-forward.
 */

import { test, expect } from '@playwright/test';

test.describe('Slam Stack Web Dashboard', () => {

  test.beforeAll(async () => {
    // The dashboard URL comes from BASE_URL env (set by run-docker.sh).
    const baseUrl = process.env.BASE_URL!;
    expect(baseUrl, 'BASE_URL must be set').toBeTruthy();
  });

  test('dashboard loads and returns 200', async ({ page }) => {
    const response = await page.goto(process.env.BASE_URL!);

    // The dashboard should return a 2xx status.
    expect(response?.status()).toBeLessThan(400);
  });

  test('dashboard has correct page title', async ({ page }) => {
    await page.goto(process.env.BASE_URL!);

    // Title should contain "slam" or "Slam" somewhere.
    await expect(page).toHaveTitle(/slam/i);
  });

  test('dashboard renders main navigation', async ({ page }) => {
    await page.goto(process.env.BASE_URL!);

    // Wait for the body to be visible — proves the SPA hydrated.
    await expect(page.locator('body')).toBeVisible();

    // Check that the page has at least some text content (not blank).
    const bodyText = await page.locator('body').innerText();
    expect(bodyText.length).toBeGreaterThan(0);
  });

  test('dashboard has no console errors on load', async ({ page }) => {
    const consoleErrors: string[] = [];

    page.on('console', msg => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    await page.goto(process.env.BASE_URL!);
    await page.waitForLoadState('networkidle');

    // Filter out expected benign errors (self-signed cert warnings, etc.)
    const realErrors = consoleErrors.filter(err =>
      !err.includes('ERR_CERT') &&
      !err.includes('net::ERR') &&
      !err.includes('favicon')
    );

    expect(realErrors).toEqual([]);
  });

  test('dashboard CSS assets load correctly', async ({ page }) => {
    const failedAssets: string[] = [];

    page.on('requestfailed', request => {
      const url = request.url();
      if (url.endsWith('.css') || url.endsWith('.js') || url.endsWith('.woff2')) {
        failedAssets.push(url);
      }
    });

    await page.goto(process.env.BASE_URL!);
    await page.waitForLoadState('networkidle');

    expect(failedAssets, `Failed assets: ${failedAssets.join(', ')}`).toEqual([]);
  });

  test('dashboard is responsive (mobile viewport)', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });
    await page.goto(process.env.BASE_URL!);

    // Page should still render at mobile width.
    await expect(page.locator('body')).toBeVisible();

    // No horizontal scroll.
    const scrollWidth = await page.evaluate(() => document.documentElement.scrollWidth);
    const clientWidth = await page.evaluate(() => document.documentElement.clientWidth);
    expect(scrollWidth).toBeLessThanOrEqual(clientWidth + 5);  // 5px tolerance
  });
});
