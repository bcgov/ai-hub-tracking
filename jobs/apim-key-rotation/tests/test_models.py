# =============================================================================
# Unit tests — Pydantic settings and models
# =============================================================================
from __future__ import annotations

import json

import pytest

from rotation.config import Settings
from rotation.models import RotationMetadata, RotationSummary, Slot, TenantRotationResult


class TestSettings:
    """Test Settings resolution from environment variables."""

    def test_defaults_derived_from_app_name_and_environment(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setenv("ENVIRONMENT", "dev")
        monkeypatch.setenv("APP_NAME", "ai-services-hub")
        monkeypatch.setenv("SUBSCRIPTION_ID", "00000000-0000-0000-0000-000000000000")

        s = Settings()  # type: ignore[call-arg]
        assert s.resource_group == "ai-services-hub-dev"
        assert s.apim_name == "ai-services-hub-dev-apim"
        assert s.hub_keyvault_name == "ai-services-hub-dev-hkv"

    def test_explicit_overrides(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setenv("ENVIRONMENT", "test")
        monkeypatch.setenv("APP_NAME", "ai-services-hub")
        monkeypatch.setenv("SUBSCRIPTION_ID", "00000000-0000-0000-0000-000000000000")
        monkeypatch.setenv("RESOURCE_GROUP", "custom-rg")
        monkeypatch.setenv("APIM_NAME", "custom-apim")
        monkeypatch.setenv("HUB_KEYVAULT_NAME", "custom-kv")

        s = Settings()  # type: ignore[call-arg]
        assert s.resource_group == "custom-rg"
        assert s.apim_name == "custom-apim"
        assert s.hub_keyvault_name == "custom-kv"

    def test_rotation_interval_validation(self, monkeypatch: pytest.MonkeyPatch) -> None:
        monkeypatch.setenv("ENVIRONMENT", "dev")
        monkeypatch.setenv("APP_NAME", "x")
        monkeypatch.setenv("SUBSCRIPTION_ID", "00000000-0000-0000-0000-000000000000")
        monkeypatch.setenv("ROTATION_INTERVAL_DAYS", "90")

        with pytest.raises(ValueError):
            Settings()  # type: ignore[call-arg]


class TestRotationMetadata:
    """Test RotationMetadata model."""

    def test_first_rotation_detected_when_slot_is_none(self) -> None:
        m = RotationMetadata()
        assert m.is_first_rotation is True

    def test_first_rotation_detected_when_last_at_is_never(self) -> None:
        m = RotationMetadata(last_rotated_slot=Slot.PRIMARY, last_rotation_at="never")
        assert m.is_first_rotation is True

    def test_not_first_rotation(self) -> None:
        m = RotationMetadata(
            last_rotated_slot=Slot.SECONDARY,
            last_rotation_at="2026-01-01T00:00:00Z",
            rotation_number=1,
        )
        assert m.is_first_rotation is False

    def test_round_trip_json(self) -> None:
        m = RotationMetadata(
            last_rotated_slot=Slot.PRIMARY,
            last_rotation_at="2026-02-01T09:00:00Z",
            next_rotation_at="2026-02-08T09:00:00Z",
            rotation_number=5,
            safe_slot=Slot.SECONDARY,
        )
        raw = m.model_dump_json()
        restored = RotationMetadata.model_validate(json.loads(raw))
        assert restored == m


class TestTenantRotationResult:
    """Test TenantRotationResult model."""

    def test_default_is_neither_rotated_nor_failed(self) -> None:
        r = TenantRotationResult(tenant_name="test-tenant")
        assert r.rotated is False
        assert r.failed is False
        assert r.skipped is False


class TestRotationSummary:
    """Test RotationSummary aggregation."""

    def test_empty_summary(self) -> None:
        s = RotationSummary(environment="dev")
        assert s.total == 0
        assert s.rotated == 0
        assert s.failed == 0
        assert s.tenants == []
