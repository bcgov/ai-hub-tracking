"""Application configuration loaded from environment variables.

All settings are prefixed with ``PORTAL_`` and can be overridden via a
``.env`` file (local development) or Azure App Service application settings
(deployed environments).

Security-relevant settings
---------------------------
``secret_key``
    Used by Starlette's ``SessionMiddleware`` to sign and encrypt the server-
    side session cookie.  Must be at least 32 random bytes in production.

``oidc_client_audience``
    The expected ``aud`` claim in the Keycloak id_token.  Validated during
    the OIDC callback to prevent token-confusion attacks.  Defaults to
    ``oidc_client_id`` when left blank.

``oidc_admin_role``
    Keycloak role (from ``realm_access.roles`` or
    ``resource_access.<client_id>.roles``) that grants portal admin access.
    Role-based checks take precedence over the ``admin_emails`` allow-list.
"""

from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Pydantic settings model for the Tenant Onboarding Portal.

    All fields are read from environment variables with the ``PORTAL_``
    prefix.  Pydantic coerces types automatically (e.g. ``"true"`` → ``True``
    for booleans).
    """

    model_config = SettingsConfigDict(env_prefix="PORTAL_", env_file=".env", extra="ignore")

    # --- App ---
    app_name: str = "AI Services Hub – Tenant Onboarding Portal"
    debug: bool = False
    secret_key: str = "change-me-in-production"
    allowed_hosts: str = "*"

    # --- Keycloak OIDC ---
    oidc_discovery_url: str = ""
    """OIDC discovery URL (.well-known/openid-configuration).  Empty string
    enables dev auto-login mode (no authentication)."""

    oidc_client_id: str = ""
    oidc_client_secret: str = ""
    oidc_redirect_uri: str = "/auth/callback"
    oidc_scope: str = "openid email profile"

    oidc_client_audience: str = ""
    """Expected ``aud`` claim in the id_token.  Falls back to ``oidc_client_id``
    when blank — see :attr:`oidc_audience`."""

    oidc_admin_role: str = "portal-admin"
    """Keycloak role that grants admin access to the portal.  Checked against
    both ``realm_access.roles`` and ``resource_access.<client_id>.roles``."""

    # --- Azure Table Storage ---
    table_storage_connection_string: str = ""
    table_storage_account_url: str = ""

    # --- Admin allow-list ---
    admin_emails: str = ""
    """Comma-separated @gov.bc.ca email addresses for the secondary admin
    allow-list.  Used as a fallback when the user's token has no admin role."""

    @property
    def admin_email_list(self) -> list[str]:
        """Return the admin allow-list as a normalised list of lowercase emails.

        Returns
        -------
        list[str]
            Lowercased, stripped email addresses.  Empty strings are excluded.
        """
        return [e.strip().lower() for e in self.admin_emails.split(",") if e.strip()]

    @property
    def oidc_audience(self) -> str:
        """Return the expected OIDC token audience.

        Returns
        -------
        str
            ``oidc_client_audience`` when set, otherwise ``oidc_client_id``.
            Keycloak id_tokens include the client_id as their ``aud`` claim by
            default, so this fallback is safe for standard Keycloak setups.
        """
        return self.oidc_client_audience or self.oidc_client_id


settings = Settings()
