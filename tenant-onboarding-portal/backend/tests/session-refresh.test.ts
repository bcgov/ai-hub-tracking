import { beforeEach, expect, test, vi } from 'vitest';
import type { Request, Response } from 'express';

import { AuthSessionService } from '../src/auth/session.service';
import type { OidcTokenSet, PortalSessionRecord, PortalUser } from '../src/types';

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

function createResponse(setCookieHeaders: string[]): Response {
  return {
    append(name: string, value: string) {
      if (name === 'Set-Cookie') {
        setCookieHeaders.push(value);
      }

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
