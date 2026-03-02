# =============================================================================
# APIM discovery and key operations via Azure Management SDK
# =============================================================================
from __future__ import annotations

import logging

from azure.identity import DefaultAzureCredential
from azure.mgmt.apimanagement import ApiManagementClient

from rotation.config import Settings
from rotation.models import SubscriptionKeys, TenantSubscription

logger = logging.getLogger("apim-key-rotation.apim")


def _get_client(settings: Settings) -> ApiManagementClient:
    """Create an authenticated APIM management client."""
    credential = DefaultAzureCredential()
    return ApiManagementClient(credential, settings.subscription_id)


def discover_tenant_subscriptions(settings: Settings) -> list[TenantSubscription]:
    """Discover all APIM subscriptions whose display name ends with 'Subscription'.

    This mirrors the bash script convention:
    ``az rest ... | jq '.value[] | select(.properties.displayName | endswith("Subscription"))'``
    """
    client = _get_client(settings)
    subscriptions: list[TenantSubscription] = []

    for sub in client.subscription.list(settings.resource_group, settings.apim_name):
        display_name: str = sub.display_name or ""
        if not display_name.endswith("Subscription"):
            continue

        # Extract tenant name from the product scope
        # scope format: /subscriptions/.../products/<tenant-name>
        scope: str = sub.scope or ""
        tenant_name = scope.rsplit("/", 1)[-1] if "/" in scope else ""
        if not tenant_name:
            logger.warning("Skipping subscription '%s' — could not extract tenant from scope '%s'", sub.name, scope)
            continue

        subscriptions.append(
            TenantSubscription(
                subscription_name=sub.name or "",
                tenant_name=tenant_name,
            )
        )

    logger.info("Discovered %d tenant subscriptions in APIM '%s'", len(subscriptions), settings.apim_name)
    return subscriptions


def get_subscription_keys(settings: Settings, subscription_name: str) -> SubscriptionKeys:
    """Read current primary and secondary keys for an APIM subscription."""
    client = _get_client(settings)
    secrets = client.subscription.list_secrets(
        settings.resource_group,
        settings.apim_name,
        subscription_name,
    )
    return SubscriptionKeys(
        primary_key=secrets.primary_key or "",
        secondary_key=secrets.secondary_key or "",
    )


def regenerate_primary_key(settings: Settings, subscription_name: str) -> None:
    """Regenerate the primary key for an APIM subscription."""
    client = _get_client(settings)
    client.subscription.regenerate_primary_key(
        settings.resource_group,
        settings.apim_name,
        subscription_name,
    )
    logger.info("Regenerated PRIMARY key for subscription '%s'", subscription_name)


def regenerate_secondary_key(settings: Settings, subscription_name: str) -> None:
    """Regenerate the secondary key for an APIM subscription."""
    client = _get_client(settings)
    client.subscription.regenerate_secondary_key(
        settings.resource_group,
        settings.apim_name,
        subscription_name,
    )
    logger.info("Regenerated SECONDARY key for subscription '%s'", subscription_name)


def verify_apim_exists(settings: Settings) -> bool:
    """Check that the APIM instance exists in the resource group.

    Returns ``False`` if the instance doesn't exist (infra not yet deployed).
    """
    try:
        client = _get_client(settings)
        client.api_management_service.get(settings.resource_group, settings.apim_name)
        return True
    except Exception as exc:
        # ResourceNotFoundError or similar
        logger.info("APIM '%s' not found in '%s': %s", settings.apim_name, settings.resource_group, exc)
        return False
