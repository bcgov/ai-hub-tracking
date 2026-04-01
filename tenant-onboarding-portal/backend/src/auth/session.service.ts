import {
  Inject,
  Injectable,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { createHash, randomBytes } from 'node:crypto';

import { getSettings } from '../config/settings';
import { SessionStoreService } from '../storage/session-store.service';
import type {
  OidcTokenSet,
  PortalLoginState,
  PortalRedirectState,
  PortalSessionRecord,
  PortalUser,
} from '../types';
import { TokenValidatorService } from './token-validator.service';

const SESSION_COOKIE_NAME = 'tenant-portal-session';
const LOGIN_STATE_TTL_SECONDS = 10 * 60;
const REDIRECT_STATE_TTL_SECONDS = 10 * 60;
const MOCK_SESSION_TTL_SECONDS = 8 * 60 * 60;
const SESSION_REFRESH_INTERVAL_MS = 2 * 60 * 1000;
const RETURN_TO_ROUTE_PATTERNS = [
  /^\/$/,
  /^\/tenants$/,
  /^\/tenants\/new$/,
  /^\/tenants\/[A-Za-z0-9._~-]+$/,
  /^\/tenants\/[A-Za-z0-9._~-]+\/edit$/,
  /^\/admin\/dashboard$/,
  /^\/admin\/review\/[A-Za-z0-9._~-]+\/[A-Za-z0-9._~-]+$/,
];

@Injectable()
export class AuthSessionService {
  /**
   * Injects the dependencies required for session lifecycle management.
   *
   * @param sessionStore - Provides persistent read/write access to session data.
   * @param tokenValidator - Validates and decodes bearer tokens for new sessions.
   */
  constructor(
    @Inject(SessionStoreService)
    private readonly sessionStore: SessionStoreService,
    @Inject(TokenValidatorService)
    private readonly tokenValidator: TokenValidatorService,
  ) {}

  /**
   * Returns the currently authenticated user, or `null` if there is no valid session.
   *
   * @param request - The incoming HTTP request.
   * @param response - The outgoing HTTP response, used to refresh or clear the session cookie.
   * @returns The authenticated user, or `null` if unauthenticated.
   */
  async getOptionalUser(request: Request, response: Response): Promise<PortalUser | null> {
    const session = await this.getSession(request, response);
    return session?.user ?? null;
  }

  /**
   * Returns the currently authenticated user, throwing if no valid session exists.
   *
   * @param request - The incoming HTTP request.
   * @param response - The outgoing HTTP response, used to refresh or clear the session cookie.
   * @returns The authenticated user.
   * @throws {UnauthorizedException} If there is no active session.
   */
  async requireUser(request: Request, response: Response): Promise<PortalUser> {
    const user = await this.getOptionalUser(request, response);
    if (!user) {
      throw new UnauthorizedException('Authentication required');
    }

    return user;
  }

  /**
   * Initiates the OIDC login flow, redirecting the user toward the identity provider.
   *
   * In `mock` auth mode, creates a mock session immediately and redirects to `returnTo`.
   * In `oidc` mode, persists a PKCE login-state record and redirects to the IdP authorization
   * endpoint with `state` and `code_challenge` parameters.
   *
   * @param request - The incoming HTTP request.
   * @param response - The outgoing HTTP response used for the redirect.
   * @param returnTo - Optional relative URL to redirect to after a successful login.
   * @throws {ServiceUnavailableException} If the OIDC metadata is missing an authorization endpoint.
   */
  async beginLogin(request: Request, response: Response, returnTo?: string): Promise<void> {
    const normalizedReturnTo = this.normalizeReturnTo(returnTo);
    const settings = getSettings();

    if (settings.authMode === 'mock') {
      await this.createMockSession(response, request);
      await this.redirectToStoredTarget(response, normalizedReturnTo);
      return;
    }

    const config = await this.tokenValidator.publicConfig();
    if (!config.authorizationEndpoint) {
      throw new ServiceUnavailableException('OIDC configuration is incomplete');
    }

    const loginState = this.createLoginState(request, normalizedReturnTo);
    await this.sessionStore.saveLoginState(loginState);

    const loginUrl = new URL(config.authorizationEndpoint);
    loginUrl.searchParams.set('client_id', config.clientId);
    loginUrl.searchParams.set('redirect_uri', loginState.redirectUri);
    loginUrl.searchParams.set('response_type', 'code');
    loginUrl.searchParams.set('response_mode', 'query');
    loginUrl.searchParams.set('scope', config.scope || 'openid email profile');
    loginUrl.searchParams.set('state', loginState.state);
    loginUrl.searchParams.set('code_challenge', this.createCodeChallenge(loginState.codeVerifier));
    loginUrl.searchParams.set('code_challenge_method', 'S256');

    response.redirect(302, loginUrl.toString());
  }

  /**
   * Completes the OIDC authorization-code flow after the identity provider redirects back.
   *
   * Validates the `state` parameter, exchanges the authorization code for tokens, validates
   * the access token, persists the session record, sets the session cookie, and redirects
   * the user to the URL stored in the login state.
   *
   * @param request - The incoming HTTP request containing the OIDC callback parameters.
   * @param response - The outgoing HTTP response used for the redirect.
   * @param payload - Query-string parameters returned by the identity provider.
   * @throws {UnauthorizedException} If the IdP returned an error, required parameters are
   *   missing, or the login state cannot be found.
   */
  async completeLogin(
    request: Request,
    response: Response,
    payload:
      | {
          code?: string;
          state?: string;
          error?: string;
          error_description?: string;
        }
      | undefined,
  ): Promise<void> {
    if (payload?.error) {
      throw new UnauthorizedException(payload.error_description ?? payload.error);
    }

    if (!payload?.code || !payload.state) {
      throw new UnauthorizedException('Missing OIDC callback parameters');
    }

    const loginState = await this.sessionStore.consumeLoginState(payload.state);
    if (!loginState) {
      throw new UnauthorizedException('OIDC login state is missing or expired');
    }

    const tokens = await this.tokenValidator.exchangeAuthorizationCode(
      payload.code,
      loginState.redirectUri,
      loginState.codeVerifier,
    );
    const user = await this.tokenValidator.validateAccessToken(tokens.accessToken);
    const session = this.buildSessionRecord(user, tokens);

    await this.sessionStore.saveSession(session);
    this.setSessionCookie(response, request, session.id, session.expiresAt);
    response.redirect(302, loginState.returnTo);
  }

  /**
   * Completes an internal redirect callback by resolving a stored redirect-state token.
   *
   * This indirection keeps user-supplied `return_to` values out of direct redirect sinks while
   * preserving deep-link behavior for login and logout flows.
   *
   * @param response - The outgoing HTTP response used for the redirect.
   * @param state - The short-lived redirect-state token created earlier in the auth flow.
   */
  async completeRedirect(response: Response, state?: string): Promise<void> {
    if (!state) {
      response.redirect(302, '/');
      return;
    }

    const redirectState = await this.sessionStore.consumeRedirectState(state);
    response.redirect(302, redirectState?.returnTo ?? '/');
  }

  /**
   * Logs the current user out by deleting the server-side session and clearing the session cookie.
   *
   * When OIDC is active and the IdP exposes an end-session endpoint, the user is redirected
   * there so the IdP session is also terminated. Otherwise the user is redirected to `returnTo`.
   *
   * @param request - The incoming HTTP request.
   * @param response - The outgoing HTTP response used for the redirect.
   * @param returnTo - Optional relative URL to redirect to after logout.
   */
  async logout(request: Request, response: Response, returnTo?: string): Promise<void> {
    const normalizedReturnTo = this.normalizeReturnTo(returnTo);
    const sessionId = this.readSessionId(request);
    const session = sessionId ? await this.sessionStore.getSession(sessionId) : null;

    if (sessionId) {
      await this.sessionStore.deleteSession(sessionId);
    }

    this.clearSessionCookie(response, request);

    if (getSettings().authMode !== 'oidc') {
      await this.redirectToStoredTarget(response, normalizedReturnTo);
      return;
    }

    const config = await this.tokenValidator.publicConfig();
    if (!config.endSessionEndpoint) {
      await this.redirectToStoredTarget(response, normalizedReturnTo);
      return;
    }

    const redirectState = await this.createAndStoreRedirectState(normalizedReturnTo);

    const logoutUrl = new URL(config.endSessionEndpoint);
    logoutUrl.searchParams.set('client_id', config.clientId);
    logoutUrl.searchParams.set(
      'post_logout_redirect_uri',
      this.absoluteUrl(request, this.redirectStatePath(redirectState.state)),
    );
    if (session?.idToken) {
      logoutUrl.searchParams.set('id_token_hint', session.idToken);
    }

    response.redirect(302, logoutUrl.toString());
  }

  /**
   * Retrieves the active session for the current request, refreshing tokens if needed.
   *
   * If no session cookie is present and mock-auth is enabled, a mock session is created.
   * If tokens are near expiry, they are refreshed via the IdP refresh-token endpoint and
   * the session record is updated. Returns `null` when the session is missing, invalid,
   * or token refresh fails.
   *
   * @param request - The incoming HTTP request.
   * @param response - The outgoing HTTP response, used to update or clear the session cookie.
   * @returns The active session record, or `null` if unauthenticated.
   */
  private async getSession(
    request: Request,
    response: Response,
  ): Promise<PortalSessionRecord | null> {
    const sessionId = this.readSessionId(request);
    if (!sessionId) {
      if (getSettings().authMode === 'mock') {
        return this.createMockSession(response, request);
      }

      return null;
    }

    const session = await this.sessionStore.getSession(sessionId);
    if (!session) {
      this.clearSessionCookie(response, request);
      if (getSettings().authMode === 'mock') {
        return this.createMockSession(response, request);
      }

      return null;
    }

    if (
      getSettings().authMode === 'oidc' &&
      session.accessToken &&
      session.refreshToken &&
      this.shouldRefreshSession(session)
    ) {
      try {
        const tokens = await this.tokenValidator.refreshTokens(session.refreshToken);
        const user = await this.tokenValidator.validateAccessToken(tokens.accessToken);
        const refreshedSession = this.updateSessionRecord(session, user, tokens);
        await this.sessionStore.saveSession(refreshedSession);
        this.setSessionCookie(response, request, refreshedSession.id, refreshedSession.expiresAt);
        return refreshedSession;
      } catch {
        await this.sessionStore.deleteSession(session.id);
        this.clearSessionCookie(response, request);
        return null;
      }
    }

    return session;
  }

  /**
   * Creates a new PKCE login-state record with a random `state` token and code verifier.
   *
   * @param request - The current request, used to derive the absolute callback URI.
   * @param returnTo - The relative URL to redirect to after a successful login.
   * @returns A new {@link PortalLoginState} ready to be persisted.
   */
  private createLoginState(request: Request, returnTo: string): PortalLoginState {
    const now = new Date();
    const expiresAt = new Date(now.getTime() + LOGIN_STATE_TTL_SECONDS * 1000);
    return {
      state: randomBytes(24).toString('base64url'),
      codeVerifier: randomBytes(48).toString('base64url'),
      redirectUri: this.absoluteUrl(request, '/api/auth/callback'),
      returnTo,
      createdAt: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
    };
  }

  /**
   * Creates a short-lived redirect-state record for a validated internal target path.
   *
   * @param returnTo - The validated internal path to use after the auth flow completes.
   * @returns A new {@link PortalRedirectState} ready to be persisted.
   */
  private createRedirectState(returnTo: string): PortalRedirectState {
    const now = new Date();
    const expiresAt = new Date(now.getTime() + REDIRECT_STATE_TTL_SECONDS * 1000);
    return {
      state: randomBytes(24).toString('base64url'),
      returnTo,
      createdAt: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
    };
  }

  /**
   * Persists a redirect-state record and returns it to the caller.
   *
   * @param returnTo - The validated internal path to use after the redirect callback.
   * @returns The persisted redirect-state record.
   */
  private async createAndStoreRedirectState(returnTo: string): Promise<PortalRedirectState> {
    const redirectState = this.createRedirectState(returnTo);
    await this.sessionStore.saveRedirectState(redirectState);
    return redirectState;
  }

  /**
   * Persists a redirect-state record and redirects the browser to the fixed callback route.
   *
   * @param response - The outgoing HTTP response used for the redirect.
   * @param returnTo - The validated internal path to restore after the callback route resolves.
   */
  private async redirectToStoredTarget(response: Response, returnTo: string): Promise<void> {
    const redirectState = await this.createAndStoreRedirectState(returnTo);
    response.redirect(302, this.redirectStatePath(redirectState.state));
  }

  /**
   * Builds the fixed internal callback path for a redirect-state token.
   *
   * @param state - The server-generated redirect-state token.
   * @returns The callback path that will resolve the stored redirect target.
   */
  private redirectStatePath(state: string): string {
    const params = new URLSearchParams({ state });
    return `/api/auth/redirect?${params.toString()}`;
  }

  /**
   * Creates and persists a mock session using the configured mock-user settings.
   *
   * Used in `mock` auth mode and when no session cookie is present but mock-auth is active.
   * Sets the session cookie on the response before returning.
   *
   * @param response - The outgoing HTTP response, used to set the session cookie.
   * @param request - The incoming HTTP request, used to derive the cookie security flag.
   * @returns The newly created session record.
   */
  private async createMockSession(
    response: Response,
    request: Request,
  ): Promise<PortalSessionRecord> {
    const now = new Date();
    const expiresAt = new Date(now.getTime() + MOCK_SESSION_TTL_SECONDS * 1000);
    const settings = getSettings();
    const session: PortalSessionRecord = {
      id: randomBytes(32).toString('base64url'),
      user: {
        email: settings.mockUser.email,
        name: settings.mockUser.name,
        preferred_username: settings.mockUser.preferred_username,
        roles: settings.mockUser.roles,
      },
      accessToken: settings.mockUser.accessToken,
      refreshToken: '',
      idToken: '',
      tokenType: 'Bearer',
      createdAt: now.toISOString(),
      updatedAt: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
    };

    await this.sessionStore.saveSession(session);
    this.setSessionCookie(response, request, session.id, session.expiresAt);
    return session;
  }

  /**
   * Builds a new session record from a validated user and a fresh OIDC token set.
   *
   * @param user - The authenticated user extracted from the access token.
   * @param tokens - The OIDC token set returned by the token exchange.
   * @returns A fully populated {@link PortalSessionRecord}.
   */
  private buildSessionRecord(user: PortalUser, tokens: OidcTokenSet): PortalSessionRecord {
    const now = new Date();
    const expiresAt = this.sessionExpiry(now, tokens);
    return {
      id: randomBytes(32).toString('base64url'),
      user,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      idToken: tokens.idToken,
      tokenType: tokens.tokenType,
      createdAt: now.toISOString(),
      updatedAt: now.toISOString(),
      expiresAt: expiresAt.toISOString(),
    };
  }

  /**
   * Merges refreshed tokens and updated user claims into an existing session record.
   *
   * @param session - The existing session record to update.
   * @param user - The re-validated user from the refreshed access token.
   * @param tokens - The new OIDC token set from the refresh response.
   * @returns An updated copy of the session record with new tokens and expiry.
   */
  private updateSessionRecord(
    session: PortalSessionRecord,
    user: PortalUser,
    tokens: OidcTokenSet,
  ): PortalSessionRecord {
    const now = new Date();
    return {
      ...session,
      user,
      accessToken: tokens.accessToken,
      refreshToken: tokens.refreshToken,
      idToken: tokens.idToken,
      tokenType: tokens.tokenType,
      updatedAt: now.toISOString(),
      expiresAt: this.sessionExpiry(now, tokens).toISOString(),
    };
  }

  /**
   * Returns `true` if the session's access token is expired or the session has not been
   * refreshed within the {@link SESSION_REFRESH_INTERVAL_MS} window.
   *
   * @param session - The session record to evaluate.
   * @returns `true` if the session should be refreshed before the next request.
   */
  private shouldRefreshSession(session: PortalSessionRecord): boolean {
    if (this.tokenValidator.isAccessTokenExpired(session.accessToken)) {
      return true;
    }

    const lastRefreshAt = Date.parse(session.updatedAt || session.createdAt);
    if (Number.isNaN(lastRefreshAt)) {
      return true;
    }

    return Date.now() - lastRefreshAt >= SESSION_REFRESH_INTERVAL_MS;
  }

  /**
   * Calculates the session expiry date from the longer of the access- or refresh-token lifetimes.
   *
   * @param now - The current timestamp used as the base for expiry calculation.
   * @param tokens - The token set containing `expiresIn` and `refreshExpiresIn` values in seconds.
   * @returns The computed expiry {@link Date}.
   */
  private sessionExpiry(now: Date, tokens: OidcTokenSet): Date {
    const ttlSeconds = Math.max(tokens.refreshExpiresIn, tokens.expiresIn, 60);
    return new Date(now.getTime() + ttlSeconds * 1000);
  }

  /**
   * Computes the PKCE S256 code challenge from the supplied code verifier.
   *
   * @param codeVerifier - The random code-verifier string generated for the login state.
   * @returns The base64url-encoded SHA-256 hash of the code verifier.
   */
  private createCodeChallenge(codeVerifier: string): string {
    return createHash('sha256').update(codeVerifier).digest('base64url');
  }

  /**
   * Reads and decodes the session ID from the session cookie in the request headers.
   *
   * @param request - The incoming HTTP request.
   * @returns The session ID string, or `null` if the cookie is absent.
   */
  private readSessionId(request: Request): string | null {
    const cookieHeader = request.header('cookie');
    if (!cookieHeader) {
      return null;
    }

    for (const entry of cookieHeader.split(';')) {
      const [name, ...rest] = entry.trim().split('=');
      if (name === SESSION_COOKIE_NAME) {
        return decodeURIComponent(rest.join('='));
      }
    }

    return null;
  }

  /**
   * Appends a `Set-Cookie` header to the response to persist the session ID.
   *
   * @param response - The outgoing HTTP response.
   * @param request - The incoming HTTP request, used to determine the `Secure` attribute.
   * @param sessionId - The session ID to store in the cookie value.
   * @param expiresAt - ISO 8601 timestamp used to derive the cookie `Max-Age` and `Expires`.
   */
  private setSessionCookie(
    response: Response,
    request: Request,
    sessionId: string,
    expiresAt: string,
  ): void {
    response.append('Set-Cookie', this.serializeCookie(sessionId, request, expiresAt));
  }

  /**
   * Clears the session cookie by overwriting it with an expired, empty value.
   *
   * @param response - The outgoing HTTP response.
   * @param request - The incoming HTTP request, used to determine the `Secure` attribute.
   */
  private clearSessionCookie(response: Response, request: Request): void {
    response.append('Set-Cookie', this.serializeCookie('', request, new Date(0).toISOString(), 0));
  }

  /**
   * Serializes the session cookie into a `Set-Cookie` header string.
   *
   * The cookie is `HttpOnly`, `SameSite=Lax`, and conditionally `Secure` when the request
   * arrived over HTTPS or via a trusted forwarded-protocol header.
   *
   * @param value - The cookie value (session ID) to URL-encode.
   * @param request - The incoming HTTP request, used to determine the `Secure` attribute.
   * @param expiresAt - ISO 8601 expiry timestamp.
   * @param maxAge - Optional override for `Max-Age`; derived from `expiresAt` if omitted.
   * @returns The fully serialized `Set-Cookie` header value.
   */
  private serializeCookie(
    value: string,
    request: Request,
    expiresAt: string,
    maxAge?: number,
  ): string {
    const expiryTime = Date.parse(expiresAt);
    const resolvedMaxAge = maxAge ?? Math.max(0, Math.floor((expiryTime - Date.now()) / 1000));
    const secure = this.isSecureRequest(request);
    const parts = [
      `${SESSION_COOKIE_NAME}=${encodeURIComponent(value)}`,
      'Path=/',
      'HttpOnly',
      'SameSite=Lax',
      `Max-Age=${resolvedMaxAge}`,
      `Expires=${new Date(expiresAt).toUTCString()}`,
    ];

    if (secure) {
      parts.push('Secure');
    }

    return parts.join('; ');
  }

  /**
   * Returns `true` if the request was received over HTTPS, either directly or via a
   * load-balancer that sets the `X-Forwarded-Proto: https` header.
   *
   * @param request - The incoming HTTP request to inspect.
   * @returns `true` when the connection is considered secure.
   */
  private isSecureRequest(request: Request): boolean {
    const forwardedProto = request.header('x-forwarded-proto');
    return request.protocol === 'https' || forwardedProto?.split(',')[0]?.trim() === 'https';
  }

  /**
   * Normalizes the `returnTo` redirect target to a safe relative path.
   *
   * Any absolute URL, protocol-relative path (`//`), or otherwise untrusted value is
   * replaced with `'/'` to prevent open-redirect vulnerabilities.
   *
   * @param value - The raw `returnTo` value from request parameters.
   * @returns A safe relative URL path, defaulting to `'/'`.
   */
  private normalizeReturnTo(value: string | undefined): string {
    if (!value || !value.startsWith('/') || value.startsWith('//')) {
      return '/';
    }

    try {
      const parsed = new URL(value, 'http://localhost');
      if (parsed.origin !== 'http://localhost') {
        return '/';
      }

      const pathname = this.normalizeReturnPath(parsed.pathname);
      if (!this.isAllowedReturnPath(pathname)) {
        return '/';
      }

      return `${pathname}${parsed.search}${parsed.hash}`;
    } catch {
      return '/';
    }
  }

  /**
   * Normalizes a return-path pathname by trimming trailing slashes from non-root routes.
   *
   * @param pathname - The parsed pathname component of the target URL.
   * @returns The canonical pathname used for route allowlist matching.
   */
  private normalizeReturnPath(pathname: string): string {
    if (pathname === '/') {
      return pathname;
    }

    return pathname.replace(/\/+$/, '');
  }

  /**
   * Returns `true` when the pathname matches one of the known SPA routes.
   *
   * @param pathname - The canonical pathname to validate.
   * @returns `true` when the pathname is safe to use as a post-auth return target.
   */
  private isAllowedReturnPath(pathname: string): boolean {
    return RETURN_TO_ROUTE_PATTERNS.some((pattern) => pattern.test(pathname));
  }

  /**
   * Builds an absolute URL by combining the request origin with the given relative path.
   *
   * @param request - The incoming HTTP request, used to derive the protocol and host.
   * @param path - A relative URL path (e.g. `'/api/auth/callback'`).
   * @returns The fully-qualified absolute URL string.
   */
  private absoluteUrl(request: Request, path: string): string {
    const origin = `${request.protocol}://${request.get('host')}`;
    return new URL(path, origin).toString();
  }
}
