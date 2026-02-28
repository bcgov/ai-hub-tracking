# =============================================================================
# Pydantic models for rotation state and results
# =============================================================================
from __future__ import annotations

from datetime import UTC, datetime
from enum import StrEnum

from pydantic import BaseModel, Field


class Slot(StrEnum):
    """APIM subscription key slot."""

    PRIMARY = "primary"
    SECONDARY = "secondary"
    NONE = "none"


class RotationMetadata(BaseModel):
    """Persisted in hub Key Vault as ``{tenant}-apim-rotation-metadata``."""

    last_rotated_slot: Slot = Slot.NONE
    last_rotation_at: str = "never"
    next_rotation_at: str = ""
    rotation_number: int = 0
    safe_slot: Slot = Slot.PRIMARY

    @property
    def is_first_rotation(self) -> bool:
        return self.last_rotated_slot == Slot.NONE or self.last_rotation_at == "never"


class SubscriptionKeys(BaseModel):
    """APIM subscription key pair."""

    primary_key: str
    secondary_key: str


class TenantSubscription(BaseModel):
    """Discovered APIM subscription for a tenant."""

    subscription_name: str = Field(description="APIM subscription resource name / ID")
    tenant_name: str = Field(description="Tenant name extracted from product scope")


class TenantRotationResult(BaseModel):
    """Result of rotating keys for a single tenant."""

    tenant_name: str
    rotated: bool = False
    skipped: bool = False
    failed: bool = False
    slot_rotated: Slot = Slot.NONE
    rotation_number: int = 0
    reason: str = ""


class RotationSummary(BaseModel):
    """Aggregate results from a full rotation run."""

    environment: str
    total: int = 0
    rotated: int = 0
    skipped: int = 0
    failed: int = 0
    dry_run: bool = False
    tenants: list[TenantRotationResult] = Field(default_factory=list)
    started_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    finished_at: datetime | None = None
