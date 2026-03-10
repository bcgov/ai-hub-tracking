import type { AuthConfigResponse } from '../types';

let authConfigPromise: Promise<AuthConfigResponse> | null = null;

/**
 * Fetches and caches the portal authentication configuration from the backend.
 * Subsequent calls return the same in-flight promise; the cache is cleared on failure.
 * @returns Promise resolving to the `AuthConfigResponse` from the server.
 */
export function getAuthConfig(): Promise<AuthConfigResponse> {
  if (!authConfigPromise) {
    authConfigPromise = fetch('/api/auth/config')
      .then(async (response) => {
        if (!response.ok) {
          throw new Error('Unable to load portal authentication configuration.');
        }
        return (await response.json()) as AuthConfigResponse;
      })
      .catch((error) => {
        authConfigPromise = null;
        throw error;
      });
  }

  return authConfigPromise;
}

/**
 * Extracts the path, search, and hash components from a URL for use as a safe return-to target.
 * Resolves relative URLs against the current `window.location.origin`.
 * @param url - Absolute or relative URL to convert.
 * @returns Path-relative URL string (pathname + search + hash).
 */
function toReturnTo(url: string): string {
  const currentUrl = new URL(
    url,
    typeof window === 'undefined' ? 'http://localhost' : window.location.origin,
  );
  return `${currentUrl.pathname}${currentUrl.search}${currentUrl.hash}`;
}

/**
 * Builds the backend login URL with the current page encoded as the post-login return target.
 * @param currentUrl - URL to redirect back to after login. Defaults to `window.location.href`.
 * @returns Login URL string with `return_to` query parameter.
 */
export function buildLoginUrl(currentUrl = window.location.href): string {
  return `/api/auth/login?return_to=${encodeURIComponent(toReturnTo(currentUrl))}`;
}

/**
 * Builds the backend logout URL with the given URL encoded as the post-logout return target.
 * @param currentUrl - URL to redirect back to after logout. Defaults to `window.location.href`.
 * @returns Logout URL string with `return_to` query parameter.
 */
export function buildLogoutUrl(currentUrl = window.location.href): string {
  return `/api/auth/logout?return_to=${encodeURIComponent(toReturnTo(currentUrl))}`;
}
