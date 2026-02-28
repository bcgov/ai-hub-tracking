# =============================================================================
# Core rotation logic — orchestrates APIM key regeneration and KV storage
# =============================================================================
from __future__ import annotations

import logging
import time
from datetime import UTC, datetime

from rotation import apim as apim_ops
from rotation import keyvault as kv_ops
from rotation.config import Settings
from rotation.models import (
    RotationMetadata,
    RotationSummary,
    Slot,
    TenantRotationResult,
    TenantSubscription,
)

logger = logging.getLogger("apim-key-rotation.runner")


def _is_rotation_due(metadata: RotationMetadata, interval_days: int) -> bool:
    """Check whether enough time has elapsed since the last rotation."""
    if metadata.is_first_rotation:
        return True

    try:
        last_dt = datetime.fromisoformat(metadata.last_rotation_at.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return True

    elapsed = datetime.now(UTC) - last_dt
    return elapsed.total_seconds() >= interval_days * 86400


def _next_slot(last_slot: Slot) -> Slot:
    """Determine which slot to rotate next (alternating, secondary-first)."""
    if last_slot == Slot.SECONDARY:
        return Slot.PRIMARY
    return Slot.SECONDARY


def _safe_slot(slot_to_rotate: Slot) -> Slot:
    """The slot that remains untouched and is safe for tenants to use."""
    return Slot.PRIMARY if slot_to_rotate == Slot.SECONDARY else Slot.SECONDARY


def _iso_now() -> str:
    return datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def _iso_plus_days(days: int) -> str:
    from datetime import timedelta

    target = datetime.now(UTC) + timedelta(days=days)
    return target.strftime("%Y-%m-%dT%H:%M:%SZ")


def rotate_tenant(
    settings: Settings,
    tenant: TenantSubscription,
) -> TenantRotationResult:
    """Rotate keys for a single tenant subscription.

    This implements the same alternating primary/secondary pattern as the
    original bash script (``rotate-apim-keys.sh``).
    """
    result = TenantRotationResult(tenant_name=tenant.tenant_name)

    # Step 1: Read rotation metadata from hub KV
    metadata = kv_ops.get_rotation_metadata(settings, tenant.tenant_name)
    logger.info(
        "Tenant '%s' | last_slot=%s last_at=%s rotation_number=%d",
        tenant.tenant_name,
        metadata.last_rotated_slot.value,
        metadata.last_rotation_at,
        metadata.rotation_number,
    )

    # Step 2: Check interval
    if not _is_rotation_due(metadata, settings.rotation_interval_days):
        result.skipped = True
        result.reason = f"Interval not elapsed (last: {metadata.last_rotation_at})"
        logger.info("Tenant '%s' | skipped — %s", tenant.tenant_name, result.reason)
        return result

    # Step 3: Determine target slot
    slot_to_rotate = _next_slot(metadata.last_rotated_slot)
    safe = _safe_slot(slot_to_rotate)
    logger.info(
        "Tenant '%s' | rotating %s (tenants safe on %s)",
        tenant.tenant_name,
        slot_to_rotate.value,
        safe.value,
    )

    # Dry-run: log and return
    if settings.dry_run:
        result.skipped = True
        result.slot_rotated = slot_to_rotate
        result.reason = f"[DRY RUN] Would regenerate {slot_to_rotate.value} key"
        logger.info("Tenant '%s' | %s", tenant.tenant_name, result.reason)
        return result

    # Step 4: Regenerate the target slot
    try:
        if slot_to_rotate == Slot.PRIMARY:
            apim_ops.regenerate_primary_key(settings, tenant.subscription_name)
        else:
            apim_ops.regenerate_secondary_key(settings, tenant.subscription_name)
    except Exception as exc:
        result.failed = True
        result.reason = f"Key regeneration failed: {exc}"
        logger.error("Tenant '%s' | %s", tenant.tenant_name, result.reason)
        return result

    # Brief pause for APIM propagation
    if settings.key_propagation_wait_seconds > 0:
        logger.info("Waiting %ds for key propagation...", settings.key_propagation_wait_seconds)
        time.sleep(settings.key_propagation_wait_seconds)

    # Step 5: Read both keys after regeneration
    try:
        keys = apim_ops.get_subscription_keys(settings, tenant.subscription_name)
    except Exception as exc:
        result.failed = True
        result.reason = f"Failed to read keys after regeneration: {exc}"
        logger.error("Tenant '%s' | %s", tenant.tenant_name, result.reason)
        return result

    if not keys.primary_key or not keys.secondary_key:
        result.failed = True
        result.reason = "Empty key returned after regeneration"
        logger.error("Tenant '%s' | %s", tenant.tenant_name, result.reason)
        return result

    # Step 6: Store both keys in hub Key Vault
    now_iso = _iso_now()
    new_rotation_number = metadata.rotation_number + 1
    tags = {
        "updated-at": now_iso,
        "rotated": slot_to_rotate.value,
        "rotation-number": str(new_rotation_number),
    }

    try:
        kv_ops.store_key_in_vault(
            settings,
            f"{tenant.tenant_name}-apim-primary-key",
            keys.primary_key,
            tags=tags,
        )
        kv_ops.store_key_in_vault(
            settings,
            f"{tenant.tenant_name}-apim-secondary-key",
            keys.secondary_key,
            tags=tags,
        )
    except Exception as exc:
        result.failed = True
        result.reason = f"Failed to store keys in KV: {exc}"
        logger.error("Tenant '%s' | %s", tenant.tenant_name, result.reason)
        return result

    # Step 7: Update rotation metadata
    next_iso = _iso_plus_days(settings.rotation_interval_days)
    new_metadata = RotationMetadata(
        last_rotated_slot=slot_to_rotate,
        last_rotation_at=now_iso,
        next_rotation_at=next_iso,
        rotation_number=new_rotation_number,
        safe_slot=safe,
    )

    try:
        kv_ops.set_rotation_metadata(settings, tenant.tenant_name, new_metadata)
    except Exception as exc:
        result.failed = True
        result.reason = f"Failed to store rotation metadata: {exc}"
        logger.error("Tenant '%s' | %s", tenant.tenant_name, result.reason)
        return result

    result.rotated = True
    result.slot_rotated = slot_to_rotate
    result.rotation_number = new_rotation_number
    result.reason = f"Rotated {slot_to_rotate.value} (safe: {safe.value}), next: {next_iso}"
    logger.info("Tenant '%s' | %s", tenant.tenant_name, result.reason)
    return result


def run_rotation(settings: Settings) -> RotationSummary:
    """Run key rotation for all tenant subscriptions.

    Entry point called by the timer function.
    """
    summary = RotationSummary(environment=settings.environment, dry_run=settings.dry_run)

    # Guard: rotation disabled
    if not settings.rotation_enabled:
        logger.info("Rotation is disabled (ROTATION_ENABLED=false). Nothing to do.")
        return summary

    # Guard: verify APIM exists
    if not apim_ops.verify_apim_exists(settings):
        logger.info("APIM '%s' not found — infrastructure not yet deployed. Exiting.", settings.apim_name)
        return summary

    # Guard: verify hub KV reachable
    if not kv_ops.verify_keyvault_exists(settings):
        logger.info("Hub KV '%s' not reachable — infrastructure not yet deployed. Exiting.", settings.hub_keyvault_name)
        return summary

    # Discover tenant subscriptions
    tenants = apim_ops.discover_tenant_subscriptions(settings)
    if not tenants:
        logger.warning("No tenant subscriptions found in APIM '%s'", settings.apim_name)
        return summary

    # Rotate each tenant
    for tenant in tenants:
        result = rotate_tenant(settings, tenant)
        summary.tenants.append(result)
        summary.total += 1
        if result.rotated:
            summary.rotated += 1
        elif result.skipped:
            summary.skipped += 1
        elif result.failed:
            summary.failed += 1

    summary.finished_at = datetime.now(UTC)

    logger.info(
        "Rotation summary | env=%s total=%d rotated=%d skipped=%d failed=%d dry_run=%s",
        summary.environment,
        summary.total,
        summary.rotated,
        summary.skipped,
        summary.failed,
        summary.dry_run,
    )
    return summary
