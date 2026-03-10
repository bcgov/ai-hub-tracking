import {
  HttpException,
  Injectable,
  InternalServerErrorException,
  ServiceUnavailableException,
  UnauthorizedException,
} from '@nestjs/common';
import jwt, { type JwtPayload } from 'jsonwebtoken';
import jwksClient, { type JwksClient } from 'jwks-rsa';

import { getOidcAudience, getSettings } from '../config/settings';
import type { OidcTokenSet, PortalUser, PublicOidcConfig } from '../types';

@Injectable()
export class TokenValidatorService {
  private metadataPromise: Promise<Record<string, unknown>> | null = null;
  private discoveryUrlCache = '';
  private issuerCache = '';
  private jwksClientCache: JwksClient | null = null;

  /**
   * Validates a Bearer access token. In mock mode the token is compared to the
   * configured mock token. In OIDC mode the token is verified against the JWKS
   * endpoint using the RS256/PS256 family of algorithms.
   *
   * @param token - The raw Bearer token string from the Authorization header.
   * @returns The authenticated user derived from the token claims.
   * @throws UnauthorizedException when the token is absent, expired, or has an invalid signature.
   * @throws ServiceUnavailableException when the OIDC configuration or JWKS endpoint is unreachable.
   */
  async validateAccessToken(token: string): Promise<PortalUser> {
    const settings = getSettings();
    if (settings.authMode === 'mock') {
      if (token !== settings.mockUser.accessToken) {
        throw new UnauthorizedException('Invalid bearer token');
      }

      return {
        email: settings.mockUser.email,
        name: settings.mockUser.name,
        preferred_username: settings.mockUser.preferred_username,
        roles: settings.mockUser.roles,
      };
    }

    const metadata = await this.metadata();
    const jwksUri = typeof metadata.jwks_uri === 'string' ? metadata.jwks_uri : '';
    if (!jwksUri) {
      throw new ServiceUnavailableException('OIDC configuration is incomplete');
    }

    try {
      const decoded = jwt.decode(token, { complete: true });
      const kid =
        typeof decoded === 'object' && decoded?.header && 'kid' in decoded.header
          ? decoded.header.kid
          : undefined;
      if (!kid || typeof kid !== 'string') {
        throw new UnauthorizedException('Invalid bearer token');
      }

      const signingKey = await this.jwksClient(jwksUri).getSigningKey(kid);
      const audience = getOidcAudience();
      const verified = jwt.verify(token, signingKey.getPublicKey(), {
        algorithms: ['RS256', 'RS384', 'RS512', 'PS256', 'PS384', 'PS512'],
        issuer: this.issuerCache,
        audience: audience || undefined,
      }) as JwtPayload;

      return this.buildUser(verified);
    } catch (error) {
      if (error instanceof HttpException) {
        throw error;
      }

      if (
        error instanceof jwt.JsonWebTokenError ||
        error instanceof jwt.NotBeforeError ||
        error instanceof jwt.TokenExpiredError
      ) {
        throw new UnauthorizedException('Invalid bearer token');
      }

      throw new ServiceUnavailableException('Unable to validate bearer token');
    }
  }

  /**
   * Returns true when the given JWT access token's `exp` claim is in the past.
   * Tokens without a valid `exp` claim are considered unexpired.
   *
   * @param token - The raw JWT access token string to inspect.
   * @returns True when the token is expired; false otherwise.
   */
  isAccessTokenExpired(token: string): boolean {
    const decoded = jwt.decode(token);
    if (!decoded || typeof decoded === 'string' || typeof decoded.exp !== 'number') {
      return false;
    }

    return decoded.exp <= Math.floor(Date.now() / 1000);
  }

  /**
   * Exchanges an OIDC authorization code for an access token, refresh token,
   * and ID token using the token endpoint from the OIDC discovery document.
   *
   * @param code - The authorization code received in the OIDC redirect callback.
   * @param redirectUri - The redirect URI that was used to obtain the code.
   * @param codeVerifier - The PKCE code verifier; required when PKCE was used during authorization.
   * @returns A token set containing access, refresh, and ID tokens.
   * @throws UnauthorizedException when the code is invalid or already used.
   * @throws ServiceUnavailableException when the token endpoint is unreachable.
   */
  async exchangeAuthorizationCode(
    code: string,
    redirectUri: string,
    codeVerifier?: string,
  ): Promise<OidcTokenSet> {
    const params = new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: redirectUri,
    });

    if (codeVerifier) {
      params.set('code_verifier', codeVerifier);
    }

    return this.exchangeToken(params);
  }

  /**
   * Obtains a new access token and refresh token using a valid refresh token.
   *
   * @param refreshToken - The refresh token from the user's existing session.
   * @returns A new token set with a fresh access token and refresh token.
   * @throws UnauthorizedException when the refresh token is invalid or expired.
   * @throws ServiceUnavailableException when the token endpoint is unreachable.
   */
  async refreshTokens(refreshToken: string): Promise<OidcTokenSet> {
    return this.exchangeToken(
      new URLSearchParams({
        grant_type: 'refresh_token',
        refresh_token: refreshToken,
      }),
    );
  }

  /**
   * Returns the OIDC configuration that the frontend needs to build login and
   * logout URLs without exposing server-side secrets.
   *
   * @returns A `PublicOidcConfig` object with endpoints, client ID, and realm information.
   * @throws InternalServerErrorException when the discovery URL format is not supported.
   * @throws ServiceUnavailableException when the OIDC discovery endpoint is unreachable.
   */
  async publicConfig(): Promise<PublicOidcConfig> {
    const settings = getSettings();
    if (settings.authMode === 'mock') {
      return {
        mode: 'mock',
        enabled: false,
        url: '',
        realm: '',
        clientId: settings.oidcClientId,
        audience: getOidcAudience(),
        adminRole: settings.oidcAdminRole,
        authorizationEndpoint: '',
        endSessionEndpoint: '',
        scope: 'openid email profile',
        mockAccessToken: '',
      };
    }

    const marker = '/realms/';
    if (!settings.oidcDiscoveryUrl.includes(marker)) {
      throw new InternalServerErrorException('OIDC discovery URL has an unsupported format');
    }

    const metadata = await this.metadata();
    const [baseUrl, realmPath] = settings.oidcDiscoveryUrl.split(marker);
    const realm = realmPath.split('/', 1)[0];
    const authorizationEndpoint =
      typeof metadata.authorization_endpoint === 'string' ? metadata.authorization_endpoint : '';
    const endSessionEndpoint =
      typeof metadata.end_session_endpoint === 'string' ? metadata.end_session_endpoint : '';

    return {
      mode: 'oidc',
      enabled: true,
      url: baseUrl,
      realm,
      clientId: settings.oidcClientId,
      audience: getOidcAudience(),
      adminRole: settings.oidcAdminRole,
      authorizationEndpoint,
      endSessionEndpoint,
      scope: 'openid email profile',
      mockAccessToken: '',
    };
  }

  /**
   * Returns true when the user's roles include the admin role name
   * configured in application settings.
   *
   * @param user - The authenticated portal user to check.
   * @returns True when the user has the admin role.
   */
  userHasAdminAccess(user: PortalUser): boolean {
    return user.roles.includes(getSettings().oidcAdminRole);
  }

  /**
   * Fetches and caches the OIDC discovery document from the configured discovery URL.
   * Resets the cache automatically when the discovery URL changes.
   *
   * @returns The parsed discovery document as a plain object.
   * @throws ServiceUnavailableException when the discovery endpoint returns a non-OK response.
   */
  private async metadata(): Promise<Record<string, unknown>> {
    const settings = getSettings();
    if (this.discoveryUrlCache !== settings.oidcDiscoveryUrl) {
      this.discoveryUrlCache = settings.oidcDiscoveryUrl;
      this.metadataPromise = null;
      this.jwksClientCache = null;
      this.issuerCache = '';
    }

    if (!this.metadataPromise) {
      this.metadataPromise = (async () => {
        const response = await fetch(settings.oidcDiscoveryUrl);
        if (!response.ok) {
          throw new ServiceUnavailableException('Unable to validate bearer token');
        }

        const metadata = (await response.json()) as Record<string, unknown>;
        this.issuerCache = typeof metadata.issuer === 'string' ? metadata.issuer : '';
        return metadata;
      })();
    }

    return this.metadataPromise;
  }

  /**
   * Posts token exchange parameters to the OIDC token endpoint using
   * HTTP Basic authentication with the configured client credentials.
   *
   * @param params - URL-encoded form parameters for the token endpoint request.
   * @returns A fully populated `OidcTokenSet`.
   * @throws UnauthorizedException when credentials or grant parameters are rejected.
   * @throws ServiceUnavailableException when the token endpoint is unreachable or returns an incomplete response.
   */
  private async exchangeToken(params: URLSearchParams): Promise<OidcTokenSet> {
    const settings = getSettings();
    if (settings.authMode !== 'oidc') {
      throw new UnauthorizedException('OIDC token exchange is disabled');
    }

    if (!settings.oidcClientId || !settings.oidcClientSecret) {
      throw new ServiceUnavailableException('OIDC client credentials are incomplete');
    }

    const metadata = await this.metadata();
    const tokenEndpoint =
      typeof metadata.token_endpoint === 'string' ? metadata.token_endpoint : '';
    if (!tokenEndpoint) {
      throw new ServiceUnavailableException('OIDC configuration is incomplete');
    }

    const response = await fetch(tokenEndpoint, {
      method: 'POST',
      headers: {
        Authorization: `Basic ${Buffer.from(`${settings.oidcClientId}:${settings.oidcClientSecret}`).toString('base64')}`,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: params,
    });

    if (!response.ok) {
      if (response.status === 400 || response.status === 401) {
        throw new UnauthorizedException('Unable to exchange OIDC tokens');
      }

      throw new ServiceUnavailableException('Unable to exchange OIDC tokens');
    }

    const payload = (await response.json()) as Record<string, unknown>;
    const accessToken = typeof payload.access_token === 'string' ? payload.access_token : '';
    const refreshToken = typeof payload.refresh_token === 'string' ? payload.refresh_token : '';
    const idToken = typeof payload.id_token === 'string' ? payload.id_token : '';
    if (!accessToken || !refreshToken || !idToken) {
      throw new ServiceUnavailableException('OIDC token response is incomplete');
    }

    return {
      accessToken,
      refreshToken,
      idToken,
      tokenType: typeof payload.token_type === 'string' ? payload.token_type : 'Bearer',
      expiresIn: typeof payload.expires_in === 'number' ? payload.expires_in : 0,
      refreshExpiresIn:
        typeof payload.refresh_expires_in === 'number' ? payload.refresh_expires_in : 0,
    };
  }

  /**
   * Returns the singleton `JwksClient` configured for the given JWKS URI,
   * creating it on first call and reusing it on subsequent calls.
   *
   * @param jwksUri - The JWKS endpoint URL from the OIDC discovery document.
   * @returns A configured `JwksClient` instance for key retrieval.
   */
  private jwksClient(jwksUri: string): JwksClient {
    if (!this.jwksClientCache) {
      this.jwksClientCache = jwksClient({ jwksUri });
    }

    return this.jwksClientCache;
  }

  /**
   * Constructs a `PortalUser` from a verified JWT payload by extracting email,
   * display name, preferred username, and roles from realm access, resource
   * access, and custom client role claims.
   *
   * @param claims - The verified JWT payload containing user identity and role claims.
   * @returns A `PortalUser` with deduplicated, sorted roles.
   */
  private buildUser(claims: JwtPayload): PortalUser {
    const settings = getSettings();
    const clientId = settings.oidcClientId || (typeof claims.azp === 'string' ? claims.azp : '');
    const resourceAccess = claims.resource_access as
      | Record<string, { roles?: string[] }>
      | undefined;
    const resourceRoles = resourceAccess?.[clientId]?.roles ?? [];
    const realmAccess = claims.realm_access as { roles?: string[] } | undefined;
    const clientRoles = Array.isArray(claims.client_roles)
      ? claims.client_roles.filter((role): role is string => typeof role === 'string')
      : [];

    return {
      email: typeof claims.email === 'string' ? claims.email.toLowerCase() : '',
      name:
        (typeof claims.name === 'string' && claims.name) ||
        (typeof claims.display_name === 'string' && claims.display_name) ||
        (typeof claims.preferred_username === 'string' ? claims.preferred_username : ''),
      preferred_username:
        typeof claims.preferred_username === 'string' ? claims.preferred_username : '',
      roles: [...new Set([...(realmAccess?.roles ?? []), ...resourceRoles, ...clientRoles])].sort(),
    };
  }
}
