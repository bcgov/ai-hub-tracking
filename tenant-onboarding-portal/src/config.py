"""Pydantic Settings – loaded from environment variables."""

from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="PORTAL_", env_file=".env", extra="ignore")

    # --- App ---
    app_name: str = "AI Services Hub – Tenant Onboarding Portal"
    debug: bool = False
    secret_key: str = "change-me-in-production"
    allowed_hosts: str = "*"

    # --- Keycloak OIDC ---
    oidc_discovery_url: str = ""
    oidc_client_id: str = ""
    oidc_client_secret: str = ""
    oidc_redirect_uri: str = "/auth/callback"
    oidc_scope: str = "openid email profile"

    # --- Azure Table Storage ---
    table_storage_connection_string: str = ""
    table_storage_account_url: str = ""

    # --- Admin emails (comma-separated) ---
    admin_emails: str = ""

    @property
    def admin_email_list(self) -> list[str]:
        return [e.strip().lower() for e in self.admin_emails.split(",") if e.strip()]


settings = Settings()
