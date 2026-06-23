/**
 * Slam Stack — Kanidm Identity Provider Tests
 *
 * Validates the Kanidm login page loads and the OAuth2/OIDC discovery
 * endpoint returns a valid configuration.
 */

import { test, expect } from '@playwright/test';

const KANIDM_BASE = process.env.KANIDM_URL || 'http://127.0.0.1:18443';

test.describe('Kanidm Identity Provider', () => {

  test('Kanidm web UI loads', async ({ page }) => {
    // Kanidm uses a self-signed cert in the cluster.
    const response = await page.goto(KANIDM_BASE);

    expect(response?.status()).toBeLessThan(500);
    await expect(page.locator('body')).toBeVisible();
  });

  test('OIDC discovery endpoint returns valid config', async ({ request }) => {
    const response = await request.get(
      `${KANIDM_BASE}/oauth2/openid/slam-stack/.well-known/openid-configuration`
    );

    // The discovery endpoint may return 404 if OAuth2 client isn't configured
    // in this flavor — skip gracefully in that case.
    if (response.status() === 404) {
      test.skip(true, 'OAuth2 client not configured for this flavor');
    }

    expect(response.status()).toBe(200);

    const config = await response.json();
    expect(config.issuer).toBeTruthy();
    expect(config.authorization_endpoint).toBeTruthy();
    expect(config.token_endpoint).toBeTruthy();
    expect(config.jwks_uri).toBeTruthy();
  });
});
