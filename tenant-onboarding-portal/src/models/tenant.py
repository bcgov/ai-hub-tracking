"""Tenant data model – Pydantic models for form data and validation.

The :class:`TenantFormData` model is the single data contract between the
HTML form submitted by users and the rest of the portal backend (tfvars
generator, Table Storage, admin review).

Validation rules
----------------
``project_name``
    Must be strictly lowercase, alphanumeric with hyphens, at least 3
    characters.  The check intentionally rejects any value that is not
    *already* normalised to avoid silently swallowing user mistakes (e.g.
    an uppercase name that would be lowercased and silently accepted).

``admin_emails``
    Each email must end with ``@gov.bc.ca``.  Commas are accepted as
    delimiters when values arrive from an HTML ``<textarea>``.
"""

from __future__ import annotations

import re
from typing import Any

from pydantic import BaseModel, field_validator


class TenantFormData(BaseModel):
    """Simplified tenant configuration collected from the onboarding portal.

    This model captures the ~15 key decisions a BCGov team needs to make.
    The :mod:`src.services.tfvars_generator` module expands these decisions
    into a full ~270-line ``tenant.tfvars`` HCL file for each environment
    (dev / test / prod) using sensible defaults.

    Attributes
    ----------
    project_name:
        Unique, immutable identifier used as the Terraform resource name and
        Azure resource name prefix.  Must be lowercase alphanumeric + hyphens.
    display_name:
        Human-readable project name shown in the portal and in tfvars comments.
    ministry:
        BC Government ministry abbreviation (e.g. ``"WLRS"``, ``"HLTH"``).
    department:
        Optional sub-department or branch name.
    openai_enabled:
        Whether to provision an Azure OpenAI service for this tenant.
    ai_search_enabled:
        Whether to provision an Azure AI Search service.
    document_intelligence_enabled:
        Whether to provision an Azure Document Intelligence (Form Recognizer).
    speech_services_enabled:
        Whether to provision Azure Speech Services.
    cosmos_db_enabled:
        Whether to provision an Azure Cosmos DB account.
    storage_account_enabled:
        Whether to provision an Azure Storage Account.
    key_vault_enabled:
        Whether to provision an Azure Key Vault.
    model_families:
        List of model family keys (see :data:`src.models.form_schema.MODEL_FAMILIES`)
        to deploy under the tenant's OpenAI account.
    capacity_tier:
        Multiplier key for model deployment capacity
        (see :data:`src.models.form_schema.CAPACITY_TIERS`).
    apim_auth_mode:
        Authentication mode enforced at the APIM gateway layer
        (``"subscription_key"`` or ``"oauth2"``).
    rate_limiting_enabled:
        Whether the APIM rate-limiting policy is active.
    tokens_per_minute:
        TPM budget enforced by the APIM rate-limiting policy.
    pii_redaction_enabled:
        Whether the APIM PII-redaction policy is active.
    usage_logging_enabled:
        Whether the APIM usage-logging policy is active.
    admin_emails:
        List of @gov.bc.ca emails seeded as admins in the tenant's user
        management configuration.
    """

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
        """Validate and return the project name.

        Rejects the value before any lowercasing so that uppercase input
        surfaces as a validation error rather than being silently normalised.
        The regex enforces the Azure resource-naming subset: lowercase letters,
        digits, and hyphens, with alphanumeric start and end characters.

        Parameters
        ----------
        v:
            Raw project_name string from the form submission.

        Returns
        -------
        str
            The validated (already-lowercase) project name.

        Raises
        ------
        ValueError
            If the value contains uppercase letters, leading/trailing
            whitespace, invalid characters, or is fewer than 3 characters.
        """
        if v != v.strip().lower():
            raise ValueError("Project name must be lowercase alphanumeric with hyphens, min 3 chars")
        v = v.strip().lower()
        if not re.match(r"^[a-z0-9][a-z0-9-]*[a-z0-9]$", v) or len(v) < 3:
            raise ValueError("Project name must be lowercase alphanumeric with hyphens, min 3 chars")
        return v

    @field_validator("admin_emails")
    @classmethod
    def validate_admin_emails(cls, v: list[str]) -> list[str]:
        """Validate that all admin email addresses belong to the BC Gov domain.

        Parameters
        ----------
        v:
            List of raw email strings.  May contain empty strings which are
            silently dropped.

        Returns
        -------
        list[str]
            Normalised (lowercased, stripped) list of valid @gov.bc.ca emails.

        Raises
        ------
        ValueError
            If any non-empty email does not end with ``@gov.bc.ca``.
        """
        cleaned = []
        for email in v:
            email = email.strip().lower()
            if email and not email.endswith("@gov.bc.ca"):
                raise ValueError(f"Admin email must be @gov.bc.ca: {email}")
            if email:
                cleaned.append(email)
        return cleaned

    @classmethod
    def from_form(cls, form_data: dict[str, Any]) -> "TenantFormData":
        """Parse raw HTML multipart form data into a validated model instance.

        HTML forms submit data in a flat key-value format with several
        edge cases that this method handles:

        * **Checkboxes** — present as the string ``"on"`` when checked, or
          absent entirely when unchecked.  Boolean fields use a helper that
          normalises this to ``True`` / ``False``.
        * **Multi-select / comma-separated fields** — ``model_families`` and
          ``admin_emails`` can arrive as a comma-delimited string (from a
          ``<textarea>`` or hidden input) or as a list (from a multi-select
          ``<select multiple>`` element).

        Parameters
        ----------
        form_data:
            Dict from ``await request.form()`` — keys are field names,
            values are strings or lists of strings.

        Returns
        -------
        TenantFormData
            A fully validated model instance.

        Raises
        ------
        pydantic.ValidationError
            If any field fails its validator (e.g. uppercase project_name,
            non-@gov.bc.ca email).
        """
        def checkbox(key: str, default: bool = False) -> bool:
            """Return True when an HTML checkbox value is 'on' or already True."""
            val = form_data.get(key, "")
            if isinstance(val, bool):
                return val
            return val == "on" if val else default

        # model_families: comma-separated string or repeated select values
        model_families_raw = form_data.get("model_families", "gpt-4.1,gpt-4o,embeddings")
        if isinstance(model_families_raw, str):
            model_families = [f.strip() for f in model_families_raw.split(",") if f.strip()]
        else:
            model_families = list(model_families_raw)

        # admin_emails: comma/newline-separated string or list
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
