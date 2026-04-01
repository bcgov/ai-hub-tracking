import { beforeEach, expect, test, vi } from 'vitest';
import type { Request, Response } from 'express';

import { AuthSessionService } from '../src/auth/session.service';
import { resetSettingsCache } from '../src/config/settings';
import type { OidcTokenSet, PortalSessionRecord, PortalUser } from '../src/types';

type CapturedRedirect = {
  statusCode: number;
  location: string;
};

function createRequest(cookie: string): Request {
  return {
    protocol: 'https',
    header(name: string) {
      if (name.toLowerCase() === 'cookie') {
        return cookie;
      }

      return undefined;
    },
    get(name: string) {
      if (name.toLowerCase() === 'host') {
        return 'portal.example.test';
      }

      return undefined;
    },
  } as unknown as Request;
}

function createResponse(setCookieHeaders: string[], redirects: CapturedRedirect[] = []): Response {
  return {
    append(name: string, value: string) {
      if (name === 'Set-Cookie') {
        setCookieHeaders.push(value);
      }

      return this;
    },
    redirect(statusCode: number, location: string) {
      redirects.push({ statusCode, location });
      return this;
    },
  } as unknown as Response;
}

function buildSession(overrides: Partial<PortalSessionRecord> = {}): PortalSessionRecord {
  return {
    id: 'session-123',
    user: {
      email: 'dev.user@gov.bc.ca',
      name: 'Dev User',
      preferred_username: 'dev.user',
      roles: ['portal-admin'],
    },
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    idToken: 'id-token',
    tokenType: 'Bearer',
    createdAt: '2026-03-08T10:00:00.000Z',
    updatedAt: '2026-03-08T10:00:00.000Z',
    expiresAt: '2026-03-08T11:00:00.000Z',
    ...overrides,
  };
}

beforeEach(() => {
  process.env.PORTAL_AUTH_MODE = 'oidc';
  process.env.PORTAL_OIDC_DISCOVERY_URL =
    'https://example.invalid/realms/standard/.well-known/openid-configuration';
  process.env.PORTAL_OIDC_CLIENT_ID = 'tenant-onboarding-portal';
  process.env.PORTAL_OIDC_CLIENT_SECRET = 'test-secret';
  resetSettingsCache();
});

test('refreshes active oidc sessions every two minutes and rewrites the cookie', async () => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date('2026-03-08T10:03:00.000Z'));

  const savedSessions: PortalSessionRecord[] = [];
  const setCookieHeaders: string[] = [];
  const currentSession = buildSession({
    updatedAt: '2026-03-08T10:00:00.000Z',
    expiresAt: '2026-03-08T10:30:00.000Z',
  });
  const refreshedTokens: OidcTokenSet = {
    accessToken: 'new-access-token',
    refreshToken: 'new-refresh-token',
    idToken: 'new-id-token',
    tokenType: 'Bearer',
    expiresIn: 300,
    refreshExpiresIn: 1800,
  };
  const refreshedUser: PortalUser = {
    email: 'dev.user@gov.bc.ca',
    name: 'Dev User',
    preferred_username: 'dev.user',
    roles: ['portal-admin'],
  };

  const sessionStore = {
    getSession: vi.fn().mockResolvedValue(currentSession),
    saveSession: vi.fn(async (session: PortalSessionRecord) => {
      savedSessions.push(session);
    }),
    deleteSession: vi.fn(),
  };
  const tokenValidator = {
    isAccessTokenExpired: vi.fn().mockReturnValue(false),
    refreshTokens: vi.fn().mockResolvedValue(refreshedTokens),
    validateAccessToken: vi.fn().mockResolvedValue(refreshedUser),
  };

  const service = new AuthSessionService(sessionStore as any, tokenValidator as any);

  try {
    const user = await service.getOptionalUser(
      createRequest('tenant-portal-session=session-123'),
      createResponse(setCookieHeaders),
    );

    expect(user).toEqual(refreshedUser);
    expect(tokenValidator.refreshTokens).toHaveBeenCalledWith('refresh-token');
    expect(tokenValidator.validateAccessToken).toHaveBeenCalledWith('new-access-token');
    expect(sessionStore.saveSession).toHaveBeenCalledTimes(1);
    expect(savedSessions[0]?.refreshToken).toBe('new-refresh-token');
    expect(savedSessions[0]?.updatedAt).toBe('2026-03-08T10:03:00.000Z');
    expect(setCookieHeaders).toHaveLength(1);
    expect(setCookieHeaders[0]).toContain('tenant-portal-session=session-123');
    expect(setCookieHeaders[0]).toContain('Max-Age=1800');
  } finally {
    vi.useRealTimers();
  }
});

test('does not refresh oidc sessions again before the two minute interval', async () => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date('2026-03-08T10:01:00.000Z'));

  const setCookieHeaders: string[] = [];
  const currentSession = buildSession({
    updatedAt: '2026-03-08T10:00:30.000Z',
  });
  const sessionStore = {
    getSession: vi.fn().mockResolvedValue(currentSession),
    saveSession: vi.fn(),
    deleteSession: vi.fn(),
  };
  const tokenValidator = {
    isAccessTokenExpired: vi.fn().mockReturnValue(false),
    refreshTokens: vi.fn(),
    validateAccessToken: vi.fn(),
  };

  const service = new AuthSessionService(sessionStore as any, tokenValidator as any);

  try {
    const user = await service.getOptionalUser(
      createRequest('tenant-portal-session=session-123'),
      createResponse(setCookieHeaders),
    );

    expect(user).toEqual(currentSession.user);
    expect(tokenValidator.refreshTokens).not.toHaveBeenCalled();
    expect(sessionStore.saveSession).not.toHaveBeenCalled();
    expect(setCookieHeaders).toHaveLength(0);
  } finally {
    vi.useRealTimers();
  }
});

test('mock login stores the return target behind an internal redirect state', async () => {
  process.env.PORTAL_AUTH_MODE = 'mock';
  process.env.PORTAL_OIDC_DISCOVERY_URL = '';
  resetSettingsCache();

  const redirects: CapturedRedirect[] = [];
  const sessionStore = {
    saveSession: vi.fn(),
    saveRedirectState: vi.fn(),
  };
  const tokenValidator = {};
  const service = new AuthSessionService(sessionStore as any, tokenValidator as any);

  await service.beginLogin(
    createRequest(''),
    createResponse([], redirects),
    '/tenants/example-tenant?tab=details#summary',
  );

  expect(sessionStore.saveRedirectState).toHaveBeenCalledWith(
    expect.objectContaining({
      returnTo: '/tenants/example-tenant?tab=details#summary',
    }),
  );
  expect(redirects).toHaveLength(1);
  expect(redirects[0]).toMatchObject({ statusCode: 302 });

  const redirectUrl = new URL(redirects[0].location, 'https://portal.example.test');
  expect(redirectUrl.pathname).toBe('/api/auth/redirect');
  expect(redirectUrl.searchParams.get('state')).toBeTruthy();
});

test('mock login normalizes untrusted return targets to root', async () => {
  process.env.PORTAL_AUTH_MODE = 'mock';
  process.env.PORTAL_OIDC_DISCOVERY_URL = '';
  resetSettingsCache();

  const sessionStore = {
    saveSession: vi.fn(),
    saveRedirectState: vi.fn(),
  };
  const service = new AuthSessionService(sessionStore as any, {} as any);

  await service.beginLogin(createRequest(''), createResponse([]), 'https://evil.example/phish');

  expect(sessionStore.saveRedirectState).toHaveBeenCalledWith(
    expect.objectContaining({ returnTo: '/' }),
  );
});

test('completeRedirect consumes redirect state and restores the stored path', async () => {
  const redirects: CapturedRedirect[] = [];
  const sessionStore = {
    consumeRedirectState: vi.fn().mockResolvedValue({
      state: 'state-123',
      returnTo: '/admin/dashboard',
      createdAt: '2026-03-08T10:00:00.000Z',
      expiresAt: '2026-03-08T10:10:00.000Z',
    }),
  };
  const service = new AuthSessionService(sessionStore as any, {} as any);

  await service.completeRedirect(createResponse([], redirects), 'state-123');

  expect(sessionStore.consumeRedirectState).toHaveBeenCalledWith('state-123');
  expect(redirects).toEqual([{ statusCode: 302, location: '/admin/dashboard' }]);
});

test('oidc logout uses a fixed callback path for post-logout redirection', async () => {
  process.env.PORTAL_AUTH_MODE = 'oidc';
  process.env.PORTAL_OIDC_DISCOVERY_URL =
    'https://example.invalid/realms/standard/.well-known/openid-configuration';
  resetSettingsCache();

  const redirects: CapturedRedirect[] = [];
  const sessionStore = {
    getSession: vi.fn().mockResolvedValue(null),
    deleteSession: vi.fn(),
    saveRedirectState: vi.fn(),
  };
  const tokenValidator = {
    publicConfig: vi.fn().mockResolvedValue({
      endSessionEndpoint: 'https://idp.example.test/logout',
      clientId: 'tenant-onboarding-portal',
    }),
  };
  const service = new AuthSessionService(sessionStore as any, tokenValidator as any);

  await service.logout(
    createRequest(''),
    createResponse([], redirects),
    '/admin/review/example-tenant/v1',
  );

  expect(sessionStore.saveRedirectState).toHaveBeenCalledWith(
    expect.objectContaining({ returnTo: '/admin/review/example-tenant/v1' }),
  );
  expect(redirects).toHaveLength(1);

  const logoutUrl = new URL(redirects[0].location);
  const postLogoutRedirectUri = logoutUrl.searchParams.get('post_logout_redirect_uri');
  expect(logoutUrl.origin).toBe('https://idp.example.test');
  expect(postLogoutRedirectUri).toBeTruthy();

  const callbackUrl = new URL(postLogoutRedirectUri!);
  expect(callbackUrl.origin).toBe('https://portal.example.test');
  expect(callbackUrl.pathname).toBe('/api/auth/redirect');
  expect(callbackUrl.searchParams.get('state')).toBeTruthy();
  expect(postLogoutRedirectUri).not.toContain('/admin/review/example-tenant/v1');
});
