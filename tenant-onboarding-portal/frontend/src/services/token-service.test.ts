import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

function createSessionStorageMock(): Storage {
  const values = new Map<string, string>();

  return {
    get length() {
      return values.size;
    },
    clear() {
      values.clear();
    },
    getItem(key: string) {
      return values.get(key) ?? null;
    },
    key(index: number) {
      return Array.from(values.keys())[index] ?? null;
    },
    removeItem(key: string) {
      values.delete(key);
    },
    setItem(key: string, value: string) {
      values.set(key, value);
    },
  };
}

describe('keycloak service', () => {
  beforeEach(() => {
    vi.stubGlobal('window', {
      location: { href: 'http://localhost:5173/' },
      sessionStorage: createSessionStorageMock(),
    });
  });

  afterEach(() => {
    vi.resetModules();
    vi.restoreAllMocks();
    window.sessionStorage.clear();
  });

  it('caches auth config requests', async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        enabled: false,
        mode: 'mock',
        mockAccessToken: 'dev-token',
      }),
    });

    vi.stubGlobal('fetch', fetchMock);

    const { getAuthConfig } = await import('./token-service');

    const first = await getAuthConfig();
    const second = await getAuthConfig();

    expect(first).toEqual(second);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(fetchMock).toHaveBeenCalledWith('/api/auth/config');
  });

  it('builds a backend login url with a relative return target', async () => {
    const { buildLoginUrl } = await import('./token-service');

    expect(buildLoginUrl('http://localhost:5173/tenants?foo=bar#section')).toBe(
      '/api/auth/login?return_to=%2Ftenants%3Ffoo%3Dbar%23section',
    );
  });

  it('builds a backend logout url with a relative return target', async () => {
    const { buildLogoutUrl } = await import('./token-service');

    expect(buildLogoutUrl('http://localhost:5173/')).toBe('/api/auth/logout?return_to=%2F');
  });
});
