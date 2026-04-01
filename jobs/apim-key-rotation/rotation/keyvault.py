# =============================================================================
# Hub Key Vault operations — read/write rotation metadata and keys
# =============================================================================
from __future__ import annotations

import json
import logging
from datetime import UTC, datetime, timedelta

from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

from rotation.config import Settings
from rotation.models import RotationMetadata

logger = logging.getLogger("apim-key-rotation.keyvault")


def _get_client(settings: Settings) -> SecretClient:
    """Create an authenticated Key Vault secret client for the hub KV."""
    credential = DefaultAzureCredential()
    vault_url = f"https://{settings.hub_keyvault_name}.vault.azure.net"
    return SecretClient(vault_url=vault_url, credential=credential)


def _secret_expiry(settings: Settings) -> datetime:
    """Compute the secret expiry timestamp (Landing Zone policy: max 90 days)."""
    return datetime.now(UTC) + timedelta(days=settings.secret_expiry_days)


# ---------------------------------------------------------------------------
# Rotation metadata
# ---------------------------------------------------------------------------


def get_rotation_metadata(settings: Settings, tenant_name: str) -> RotationMetadata:
    """Read ``{tenant}-apim-rotation-metadata`` from hub KV.

    Returns a default (first-rotation) metadata object if the secret doesn't exist.
    """
    client = _get_client(settings)
    secret_name = f"{tenant_name}-apim-rotation-metadata"

    try:
        secret = client.get_secret(secret_name)
        data = json.loads(secret.value or "{}")
        return RotationMetadata.model_validate(data)
    except Exception as exc:
        # ResourceNotFoundError or JSON parse error → treat as first rotation
        exc_name = type(exc).__name__
        if "NotFound" in exc_name or "ResourceNotFound" in str(exc):
            logger.debug("No metadata for tenant '%s' — treating as first rotation", tenant_name)
        else:
            logger.warning(
                "Failed to read metadata for '%s' (%s) — treating as first rotation",
                tenant_name,
                exc,
            )
        return RotationMetadata()


def set_rotation_metadata(settings: Settings, tenant_name: str, metadata: RotationMetadata) -> None:
    """Store ``{tenant}-apim-rotation-metadata`` in hub KV."""
    client = _get_client(settings)
    secret_name = f"{tenant_name}-apim-rotation-metadata"
    expires_on = _secret_expiry(settings)

    client.set_secret(
        secret_name,
        metadata.model_dump_json(),
        content_type="application/json",
        expires_on=expires_on,
    )
    logger.debug("Stored rotation metadata for '%s'", tenant_name)


# ---------------------------------------------------------------------------
# Subscription keys
# ---------------------------------------------------------------------------


def store_key_in_vault(
    settings: Settings,
    secret_name: str,
    key_value: str,
    *,
    tags: dict[str, str] | None = None,
) -> None:
    """Write a subscription key to hub KV with expiry and optional tags."""
    client = _get_client(settings)
    expires_on = _secret_expiry(settings)

    client.set_secret(
        secret_name,
        key_value,
        content_type="text/plain",
        expires_on=expires_on,
        tags=tags or {},
    )
    logger.debug("Stored APIM subscription key in hub KV")


def verify_keyvault_exists(settings: Settings) -> bool:
    """Check that the hub Key Vault is reachable.

    Returns ``False`` if the vault doesn't exist or is unreachable.
    """
    try:
        client = _get_client(settings)
        # List a single secret to verify connectivity / RBAC
        next(client.list_properties_of_secrets(max_page_size=1), None)
        return True
    except Exception as exc:
        logger.info("Hub Key Vault '%s' not reachable: %s", settings.hub_keyvault_name, exc)
        return False
