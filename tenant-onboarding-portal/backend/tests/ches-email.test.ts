import { afterEach, beforeEach, expect, test, vi } from 'vitest';

import { resetSettingsCache } from '../src/config/settings';
import { ChesEmailService } from '../src/services/ches-email.service';
import type { PortalUser, TenantRecord } from '../src/types';

const CHES_ENV = {
  PORTAL_NOTIFICATION_ADMIN_EMAILS: 'admin.one@gov.bc.ca, Admin.Two@gov.bc.ca',
  PORTAL_CHES_CLIENT_ID: 'ches-client',
  PORTAL_CHES_CLIENT_SECRET: 'ches-secret',
  PORTAL_CHES_FROM_ADDRESS: 'AI Hub <aihub@gov.bc.ca>',
  PORTAL_CHES_TOKEN_URL: 'https://token.example.invalid/token',
  PORTAL_CHES_API_URL: 'https://ches.example.invalid/api/v1',
  PORTAL_PUBLIC_BASE_URL: 'https://portal.example.invalid/',
};

const tenant: TenantRecord = {
  PartitionKey: 'my-tenant',
  RowKey: 'v2',
  DisplayName: '<b>My Tenant</b>',
  Ministry: 'CITZ',
  Status: 'submitted',
  SubmittedBy: 'owner@gov.bc.ca',
  CreatedAt: '2026-09-29T00:00:00.000Z',
  UpdatedAt: '2026-09-29T00:00:00.000Z',
};

const user: PortalUser = {
  email: 'owner@gov.bc.ca',
  name: 'Owner',
  preferred_username: 'owner',
  roles: [],
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

beforeEach(() => {
  for (const [key, value] of Object.entries(CHES_ENV)) {
    process.env[key] = value;
  }
  resetSettingsCache();
});

afterEach(() => {
  for (const key of Object.keys(CHES_ENV)) {
    delete process.env[key];
  }
  resetSettingsCache();
  vi.unstubAllGlobals();
});

test('sends an escaped admin notification through CHES and caches the token', async () => {
  const fetchMock = vi.fn(async (url: string) =>
    url.endsWith('/token')
      ? jsonResponse({ access_token: 'abc', expires_in: 300 })
      : jsonResponse({ txId: 'tx-1', messages: [{ msgId: 'm-1' }] }, 201),
  );
  vi.stubGlobal('fetch', fetchMock);
  const service = new ChesEmailService();

  await service.notifyTenantRequest('updated', tenant, 'v2', user);
  await service.notifyTenantRequest('submitted', tenant, 'v3', user);

  const tokenCalls = fetchMock.mock.calls.filter(([url]) => url.endsWith('/token'));
  expect(tokenCalls).toHaveLength(1);

  const [emailUrl, emailInit] = fetchMock.mock.calls[1] as unknown as [string, RequestInit];
  expect(emailUrl).toBe('https://ches.example.invalid/api/v1/email');
  expect((emailInit.headers as Record<string, string>).Authorization).toBe('Bearer abc');

  const payload = JSON.parse(emailInit.body as string);
  expect(payload.to).toEqual(['admin.one@gov.bc.ca', 'admin.two@gov.bc.ca']);
  expect(payload.from).toBe('AI Hub <aihub@gov.bc.ca>');
  expect(payload.subject).toContain('Tenant request updated');
  expect(payload.body).toContain('&lt;b&gt;My Tenant&lt;/b&gt;');
  expect(payload.body).not.toContain('<b>My Tenant</b>');
  expect(payload.body).toContain('https://portal.example.invalid/admin/review/my-tenant/v2');
});

test('does nothing when no admin recipients are configured', async () => {
  delete process.env.PORTAL_NOTIFICATION_ADMIN_EMAILS;
  resetSettingsCache();
  const fetchMock = vi.fn();
  vi.stubGlobal('fetch', fetchMock);
  const service = new ChesEmailService();

  expect(service.isEnabled()).toBe(false);
  await service.notifyTenantRequest('submitted', tenant, 'v1', user);
  expect(fetchMock).not.toHaveBeenCalled();
});

test('swallows CHES failures so submissions are not affected', async () => {
  vi.stubGlobal(
    'fetch',
    vi.fn(async (url: string) =>
      url.endsWith('/token')
        ? jsonResponse({ access_token: 'abc', expires_in: 300 })
        : jsonResponse({ detail: 'boom' }, 500),
    ),
  );
  const service = new ChesEmailService();

  await expect(
    service.notifyTenantRequest('submitted', tenant, 'v1', user),
  ).resolves.toBeUndefined();
});
