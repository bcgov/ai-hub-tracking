import type { MockPortalUser, PortalAuthMode, PortalSettings } from '../types';

/**
 * Parses an environment variable string as a boolean.
 * Recognises `'1'`, `'true'`, `'yes'`, and `'on'` as truthy values.
 *
 * @param value - The raw environment variable value, or undefined when the variable is not set.
 * @param fallback - The default boolean to return when the variable is absent or empty.
 * @returns The parsed boolean value.
 */
function getBoolean(value: string | undefined, fallback: boolean): boolean {
  if (value === undefined || value === '') {
    return fallback;
  }

  return ['1', 'true', 'yes', 'on'].includes(value.toLowerCase());
}

/**
 * Determines the portal authentication mode from environment variables.
 * Returns `'oidc'` or `'mock'` based on `PORTAL_AUTH_MODE`; when that variable
 * is absent, infers OIDC mode from the presence of `PORTAL_OIDC_DISCOVERY_URL`,
 * otherwise falls back to `'mock'`.
 *
 * @returns The resolved portal authentication mode.
 */
function getAuthMode(): PortalAuthMode {
  const configured = process.env.PORTAL_AUTH_MODE?.trim().toLowerCase();
  if (configured === 'oidc' || configured === 'mock') {
    return configured;
  }

  return process.env.PORTAL_OIDC_DISCOVERY_URL ? 'oidc' : 'mock';
}

/**
 * Reads the configured mock user roles from environment variables.
 * Prefers `PORTAL_MOCK_USER_ROLES`, then falls back to `PORTAL_OIDC_ADMIN_ROLE`,
 * and finally defaults to `'portal-admin'`.
 *
 * @returns An array of role name strings for the mock user.
 */
function getMockRoles(): string[] {
  return (
    process.env.PORTAL_MOCK_USER_ROLES ??
    process.env.PORTAL_OIDC_ADMIN_ROLE ??
    'portal-admin'
  )
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
}

/**
 * Constructs the mock portal user used in local development from environment
 * variables, falling back to safe development defaults when variables are absent.
 *
 * @param adminRole - The admin role name used as the default role when no mock roles are configured.
 * @returns A `MockPortalUser` object with email, name, username, roles, and access token.
 */
function getMockUser(adminRole: string): MockPortalUser {
  const roles = getMockRoles();
  return {
    email: (process.env.PORTAL_MOCK_USER_EMAIL ?? 'dev.user@gov.bc.ca').trim().toLowerCase(),
    name: (process.env.PORTAL_MOCK_USER_NAME ?? 'Dev User').trim(),
    preferred_username: (process.env.PORTAL_MOCK_USER_USERNAME ?? 'dev.user').trim(),
    roles: roles.length > 0 ? roles : [adminRole],
    accessToken: (process.env.PORTAL_MOCK_ACCESS_TOKEN ?? 'dev-token').trim() || 'dev-token',
  };
}

/**
 * Reads the `PORTAL_CORS_ALLOWED_ORIGINS` environment variable and returns a
 * list of allowed HTTP origins for CORS validation.
 *
 * @returns An array of allowed origin strings, or an empty array when the variable is not set.
 */
function getCorsAllowedOrigins(): string[] {
  return (process.env.PORTAL_CORS_ALLOWED_ORIGINS ?? '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);
}

let cachedSettings: PortalSettings | null = null;

/**
 * Returns the cached application settings, building them from environment
 * variables on the first call. Subsequent calls return the cached instance.
 *
 * @returns The fully populated `PortalSettings` object.
 */
export function getSettings(): PortalSettings {
  if (cachedSettings) return cachedSettings;
  const oidcAdminRole = process.env.PORTAL_OIDC_ADMIN_ROLE ?? 'portal-admin';
  cachedSettings = {
    appName: process.env.PORTAL_APP_NAME ?? 'AI Services Hub - Tenant Onboarding Portal',
    debug: getBoolean(process.env.PORTAL_DEBUG, false),
    authMode: getAuthMode(),
    corsAllowedOrigins: getCorsAllowedOrigins(),
    oidcDiscoveryUrl: process.env.PORTAL_OIDC_DISCOVERY_URL ?? '',
    oidcClientId: process.env.PORTAL_OIDC_CLIENT_ID ?? '',
    oidcClientSecret: process.env.PORTAL_OIDC_CLIENT_SECRET ?? '',
    oidcClientAudience: process.env.PORTAL_OIDC_CLIENT_AUDIENCE ?? '',
    oidcAdminRole,
    mockUser: getMockUser(oidcAdminRole),
    tableStorageConnectionString: process.env.PORTAL_TABLE_STORAGE_CONNECTION_STRING ?? '',
    tableStorageAccountUrl: process.env.PORTAL_TABLE_STORAGE_ACCOUNT_URL ?? '',
  };
  return cachedSettings;
}

/**
 * Clears the cached settings so the next call to `getSettings()` re-reads all
 * environment variables. Intended for use in unit tests only.
 */
export function resetSettingsCache(): void {
  cachedSettings = null;
}

/**
 * Returns the OIDC audience value to use when validating access tokens.
 * Prefers `PORTAL_OIDC_CLIENT_AUDIENCE` and falls back to the OIDC client ID.
 *
 * @returns The audience string for JWT validation.
 */
export function getOidcAudience(): string {
  const settings = getSettings();
  return settings.oidcClientAudience || settings.oidcClientId;
}
