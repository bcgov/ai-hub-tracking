"""FastAPI dependencies for authentication and authorisation.

This module provides reusable ``Depends``-compatible async functions that
enforce authentication and role-based access control on protected routes.

Admin authorisation strategy
-----------------------------
Two complementary checks are applied in order:

1. **Role-based (primary)** — the user's session must contain the configured
   admin role (``PORTAL_OIDC_ADMIN_ROLE``) in the ``roles`` list that was
   populated from the Keycloak access_token during login.  This is the
   authoritative source of truth and works reliably in production.

2. **Email allow-list (secondary / belt-and-suspenders)** — if the role
   check fails *and* ``PORTAL_ADMIN_EMAILS`` is non-empty, the user's email
   is matched against the allow-list.  This provides a fallback for
   environments where Keycloak role mapping has not yet been configured.

In development mode (no OIDC server), the synthetic session created by
:func:`src.auth.oidc.login` already includes the admin role so that
both checks pass without any configuration.
"""

from __future__ import annotations

import logging

from fastapi import HTTPException, Request

from src.config import settings

logger = logging.getLogger(__name__)


async def require_login(request: Request) -> dict:
    """Verify that the request belongs to an authenticated user.

    Reads the ``user`` key from the server-side session.  Returns the user
    dict so that route handlers can access identity information without an
    additional session lookup.

    Parameters
    ----------
    request:
        The incoming HTTP request.  The encrypted session cookie must carry
        a ``user`` payload that was written by :func:`src.auth.oidc.auth_callback`
        (or the dev auto-login route).

    Returns
    -------
    dict
        The session user dict with at minimum ``email``, ``name``,
        ``preferred_username``, and ``roles`` keys.

    Raises
    ------
    HTTPException
        HTTP 401 if no authenticated session exists.
    """
    user = request.session.get("user")
    if not user:
        raise HTTPException(status_code=401, detail="Not authenticated. Please log in via /auth/login")
    return user


async def require_admin(request: Request) -> dict:
    """Verify that the request belongs to an authenticated **admin** user.

    Authentication is checked first via :func:`require_login`.  Admin access
    is then determined by two sequential checks (first match wins):

    1. The user's ``roles`` list (from the Keycloak access_token) contains
       the value of ``settings.oidc_admin_role``.  This is the primary,
       role-based check and is the only one active in a fully-configured
       production deployment.

    2. The user's ``email`` appears in ``settings.admin_email_list``.  This
       allow-list serves as a fallback when Keycloak role mapping has not
       yet been configured.

    Parameters
    ----------
    request:
        The incoming HTTP request.

    Returns
    -------
    dict
        The session user dict (same shape as :func:`require_login`).

    Raises
    ------
    HTTPException
        HTTP 401 if no session exists.
        HTTP 403 if the user is authenticated but lacks admin access.
    """
    user = await require_login(request)

    # Primary: role-based check (populated from Keycloak access_token).
    user_roles: list[str] = user.get("roles", [])
    if settings.oidc_admin_role in user_roles:
        return user

    # Secondary: email allow-list fallback.
    email = user.get("email", "").lower()
    if settings.admin_email_list and email in settings.admin_email_list:
        logger.warning(
            "Admin access granted via email allow-list for %s. "
            "Configure the '%s' Keycloak role for role-based access.",
            email,
            settings.oidc_admin_role,
        )
        return user

    logger.warning("Denied admin access for user=%s roles=%s", email, user_roles)
    raise HTTPException(status_code=403, detail="Admin access required")
