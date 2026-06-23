/**
 * Slam Stack — Sample Rust App API Tests
 *
 * Browser-level validation of the sample-rust-app REST endpoints.
 * Demonstrates that workloads deployed on the stack are reachable
 * and return correct JSON responses.
 */

import { test, expect } from '@playwright/test';

const API_BASE = process.env.SAMPLE_APP_URL || 'http://127.0.0.1:18081';

test.describe('Sample Rust App API', () => {

  test('GET /healthz returns 200 "ok"', async ({ request }) => {
    const response = await request.get(`${API_BASE}/healthz`);

    expect(response.status()).toBe(200);
    expect(await response.text()).toBe('ok');
  });

  test('GET /api/v1/hello returns greeting JSON', async ({ request }) => {
    const response = await request.get(`${API_BASE}/api/v1/hello?name=Playwright`);

    expect(response.status()).toBe(200);

    const body = await response.json();
    expect(body.message).toBe('Hello, Playwright!');
    expect(body.server).toContain('sample-rust-app');
    expect(body.version).toBeTruthy();
  });

  test('GET /api/v1/hello defaults to "world"', async ({ request }) => {
    const response = await request.get(`${API_BASE}/api/v1/hello`);

    expect(response.status()).toBe(200);

    const body = await response.json();
    expect(body.message).toBe('Hello, world!');
  });

  test('POST /api/v1/echo round-trips JSON', async ({ request }) => {
    const payload = { test: 'browser', nested: { ok: true } };

    const response = await request.post(`${API_BASE}/api/v1/echo`, {
      data: payload,
      headers: { 'Content-Type': 'application/json' },
    });

    expect(response.status()).toBe(200);

    const body = await response.json();
    expect(body.echoed).toEqual(payload);
    expect(body.received_at).toBeTruthy();
    // ISO 8601 timestamp.
    expect(body.received_at).toMatch(/^\d{4}-\d{2}-\d{2}T/);
  });

  test('GET unknown route returns 404', async ({ request }) => {
    const response = await request.get(`${API_BASE}/api/v1/nonexistent`);

    expect(response.status()).toBe(404);
  });
});
