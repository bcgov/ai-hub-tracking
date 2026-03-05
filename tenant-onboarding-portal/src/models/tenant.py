"""Tenant data model – Pydantic models for form data and validation."""

from __future__ import annotations

import re
from typing import Any

from pydantic import BaseModel, field_validator


class TenantFormData(BaseModel):
    """Simplified tenant form data captured from the onboarding portal."""

    # Section 1: Project Identity
    project_name: str
    display_name: str
    ministry: str
    department: str = ""

    # Section 2: AI Services (toggles)
    openai_enabled: bool = True
    ai_search_enabled: bool = False
    document_intelligence_enabled: bool = False
    speech_services_enabled: bool = False
    cosmos_db_enabled: bool = False
    storage_account_enabled: bool = True
    key_vault_enabled: bool = False

    # Section 3: OpenAI Model Selection
    model_families: list[str] = ["gpt-4.1", "gpt-4o", "embeddings"]
    capacity_tier: str = "standard"

    # Section 4: Policies & Auth
    apim_auth_mode: str = "subscription_key"
    rate_limiting_enabled: bool = True
    tokens_per_minute: int = 1000
    pii_redaction_enabled: bool = True
    usage_logging_enabled: bool = True

    # Section 5: Team
    admin_emails: list[str] = []

    @field_validator("project_name")
    @classmethod
    def validate_project_name(cls, v: str) -> str:
        if v != v.strip().lower():
            raise ValueError("Project name must be lowercase alphanumeric with hyphens, min 3 chars")
        v = v.strip().lower()
        if not re.match(r"^[a-z0-9][a-z0-9-]*[a-z0-9]$", v) or len(v) < 3:
            raise ValueError("Project name must be lowercase alphanumeric with hyphens, min 3 chars")
        return v

    @field_validator("admin_emails")
    @classmethod
    def validate_admin_emails(cls, v: list[str]) -> list[str]:
        cleaned = []
        for email in v:
            email = email.strip().lower()
            if email and not email.endswith("@gov.bc.ca"):
                raise ValueError(f"Admin email must be @gov.bc.ca: {email}")
            if email:
                cleaned.append(email)
        return cleaned

    @classmethod
    def from_form(cls, form_data: dict[str, Any]) -> TenantFormData:
        """Parse raw HTML form data into the model."""
        # Checkboxes come as "on"/"off" or absent
        def checkbox(key: str, default: bool = False) -> bool:
            val = form_data.get(key, "")
            if isinstance(val, bool):
                return val
            return val == "on" if val else default

        # Multi-select comes as comma-separated or repeated keys
        model_families_raw = form_data.get("model_families", "gpt-4.1,gpt-4o,embeddings")
        if isinstance(model_families_raw, str):
            model_families = [f.strip() for f in model_families_raw.split(",") if f.strip()]
        else:
            model_families = list(model_families_raw)

        admin_emails_raw = form_data.get("admin_emails", "")
        if isinstance(admin_emails_raw, str):
            admin_emails = [e.strip() for e in admin_emails_raw.split(",") if e.strip()]
        else:
            admin_emails = list(admin_emails_raw)

        return cls(
            project_name=form_data.get("project_name", ""),
            display_name=form_data.get("display_name", ""),
            ministry=form_data.get("ministry", ""),
            department=form_data.get("department", ""),
            openai_enabled=checkbox("openai_enabled", True),
            ai_search_enabled=checkbox("ai_search_enabled"),
            document_intelligence_enabled=checkbox("document_intelligence_enabled"),
            speech_services_enabled=checkbox("speech_services_enabled"),
            cosmos_db_enabled=checkbox("cosmos_db_enabled"),
            storage_account_enabled=checkbox("storage_account_enabled", True),
            key_vault_enabled=checkbox("key_vault_enabled"),
            model_families=model_families,
            capacity_tier=form_data.get("capacity_tier", "standard"),
            apim_auth_mode=form_data.get("apim_auth_mode", "subscription_key"),
            rate_limiting_enabled=checkbox("rate_limiting_enabled", True),
            tokens_per_minute=int(form_data.get("tokens_per_minute", 1000)),
            pii_redaction_enabled=checkbox("pii_redaction_enabled", True),
            usage_logging_enabled=checkbox("usage_logging_enabled", True),
            admin_emails=admin_emails,
        )
