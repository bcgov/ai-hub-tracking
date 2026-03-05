"""OIDC authentication with BCGov Keycloak.

This module configures OAuth2/OIDC login, validates the returned tokens, and
stores a lightweight user principal in the encrypted server-side session.

Security design
---------------
Audience validation
    The ``aud`` claim in the id_token is checked against
    ``PORTAL_OIDC_CLIENT_AUDIENCE`` (falling back to ``PORTAL_OIDC_CLIENT_ID``)
    via authlib's ``claims_options``.  This prevents token-confusion attacks
    where an attacker presents a valid token issued for a *different* client.

Role extraction
    Keycloak encodes group/role membership in the **access_token** JWT, not the
    id_token or the userinfo endpoint.  After exchanging the auth code, this
    module decodes the access_token payload (without re-verifying the signature —
    authlib already verified it) to extract:

    * ``realm_access.roles``          — realm-wide roles
    * ``resource_access.<client>.roles`` — client-specific roles

    Both lists are merged and stored in the session as ``roles``.

Development mode
    When ``PORTAL_OIDC_DISCOVERY_URL`` is empty, a synthetic session is
    created with a ``dev@gov.bc.ca`` principal and the configured admin role so
    that every portal feature is accessible locally without a Keycloak server.
"""

from __future__ import annotations

import base64
import json
import logging

from authlib.integrations.starlette_client import OAuth
from fastapi import APIRouter, Request
from fastapi.responses import RedirectResponse

from src.config import settings

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/auth", tags=["auth"])

oauth = OAuth()

if settings.oidc_discovery_url:
    oauth.register(
        name="keycloak",
        client_id=settings.oidc_client_id,
        client_secret=settings.oidc_client_secret,
        server_metadata_url=settings.oidc_discovery_url,
        client_kwargs={
            "scope": settings.oidc_scope,
            # Validate the id_token `aud` claim so that tokens issued for
            # other clients in the same Keycloak realm are rejected.
            "claims_options": {
                "aud": {"essential": True, "values": [settings.oidc_audience]},
            },
        },
    )


def _decode_jwt_payload(token: str) -> dict:
    """Decode the payload section of a JWT without verifying the signature.

    The signature has already been verified by authlib during the token
    exchange.  This function is only used to read non-sensitive claims
    (roles) from the access_token after its authenticity is confirmed.

    Parameters
    ----------
    token:
        A Base64url-encoded JWT string (header.payload.signature).

    Returns
    -------
    dict
        The decoded JSON payload, or an empty dict if decoding fails.
    """
    try:
        parts = token.split(".")
        if len(parts) != 3:
            return {}
        # Base64url decode with padding
        payload_b64 = parts[1] + "=" * (-len(parts[1]) % 4)
        return json.loads(base64.urlsafe_b64decode(payload_b64))
    except Exception:
        logger.debug("Failed to decode JWT payload", exc_info=True)
        return {}


def _extract_roles(access_token: str, client_id: str) -> list[str]:
    """Extract Keycloak role claims from a decoded access_token payload.

    Keycloak populates two role locations in the access_token:

    * ``realm_access.roles``  — roles granted at the realm level.
    * ``resource_access.<client_id>.roles`` — roles scoped to a specific
      client (application).  This is the preferred location for
      application-specific roles like ``portal-admin``.

    Parameters
    ----------
    access_token:
        The raw access_token JWT string returned by the token endpoint.
    client_id:
        The OIDC client ID used to look up ``resource_access`` roles.

    Returns
    -------
    list[str]
        Deduplicated list of role strings.  Empty list on any error.
    """
    claims = _decode_jwt_payload(access_token)
    roles: list[str] = []
    roles.extend(claims.get("realm_access", {}).get("roles", []))
    roles.extend(claims.get("resource_access", {}).get(client_id, {}).get("roles", []))
    return list(set(roles))


@router.get("/login", summary="Initiate OIDC login flow")
async def login(request: Request) -> RedirectResponse:
    """Redirect the user to the Keycloak authorisation endpoint.

    In development mode (``PORTAL_OIDC_DISCOVERY_URL`` is empty) a synthetic
    session is created immediately and the user is redirected to the tenant
    dashboard without contacting Keycloak.  The synthetic session includes
    the configured admin role so that admin features are accessible locally.

    Parameters
    ----------
    request:
        The incoming HTTP request (used to build the redirect URI and to
        write the development session).

    Returns
    -------
    RedirectResponse
        Redirect to Keycloak (production) or directly to ``/tenants/`` (dev).
    """
    if not settings.oidc_discovery_url:
        # Dev mode: create a synthetic admin session so all features work
        # locally without a Keycloak server.
        request.session["user"] = {
            "email": "dev.user@gov.bc.ca",
            "name": "Dev User",
            "preferred_username": "dev.user",
            "roles": [settings.oidc_admin_role],
        }
        logger.warning("OIDC discovery URL not configured — using dev auto-login (never use in production)")
        return RedirectResponse(url="/tenants/")

    redirect_uri = request.url_for("auth_callback")
    return await oauth.keycloak.authorize_redirect(request, redirect_uri)


@router.get("/callback", name="auth_callback", summary="Handle OIDC authorisation callback")
async def auth_callback(request: Request) -> RedirectResponse:
    """Exchange the authorisation code for tokens and populate the session.

    Authlib validates the id_token signature, expiry, issuer, and ``aud``
    claim (configured via ``claims_options`` at registration time).  This
    handler additionally extracts Keycloak role claims from the access_token
    so that role-based authorisation decisions can be made without contacting
    the userinfo endpoint on every request.

    Parameters
    ----------
    request:
        The incoming callback request containing the ``code`` and ``state``
        query parameters set by Keycloak.

    Returns
    -------
    RedirectResponse
        Redirect to ``/tenants/`` on success.  Authlib raises an
        ``OAuthError`` (HTTP 400) on token validation failure.

    Raises
    ------
    authlib.integrations.base_client.errors.OAuthError
        If the token exchange fails or the id_token claims are invalid
        (wrong audience, expired, bad signature, etc.).
    """
    token = await oauth.keycloak.authorize_access_token(request)
    userinfo = token.get("userinfo") or {}

    # Extract roles from the access_token JWT (Keycloak puts them there, not
    # in the id_token or the userinfo endpoint by default).
    roles = _extract_roles(token.get("access_token", ""), settings.oidc_client_id)

    request.session["user"] = {
        "email": userinfo.get("email", "").lower(),
        "name": userinfo.get("name", ""),
        "preferred_username": userinfo.get("preferred_username", ""),
        "roles": roles,
    }
    logger.info("User authenticated: %s, roles: %s", userinfo.get("preferred_username"), roles)
    return RedirectResponse(url="/tenants/")


@router.get("/logout", summary="Clear session and redirect to home")
async def logout(request: Request) -> RedirectResponse:
    """Terminate the user's session.

    Clears the server-side session cookie.  Does **not** initiate a Keycloak
    backchannel logout — the user's Keycloak SSO session remains active and
    they can re-authenticate without re-entering credentials.

    Parameters
    ----------
    request:
        The incoming HTTP request whose session will be cleared.

    Returns
    -------
    RedirectResponse
        Redirect to the portal landing page.
    """
    request.session.clear()
    return RedirectResponse(url="/")
