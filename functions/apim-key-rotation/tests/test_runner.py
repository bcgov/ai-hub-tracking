# =============================================================================
# Unit tests — Rotation logic (runner module)
# =============================================================================
from __future__ import annotations

from datetime import UTC, datetime, timedelta
from unittest.mock import MagicMock, patch

from rotation.config import Settings
from rotation.models import RotationMetadata, Slot, TenantSubscription
from rotation.runner import _is_rotation_due, _next_slot, _safe_slot, rotate_tenant


class TestIsRotationDue:
    """Test interval-checking logic."""

    def test_first_rotation_always_due(self) -> None:
        m = RotationMetadata()
        assert _is_rotation_due(m, 7) is True

    def test_due_after_interval(self) -> None:
        past = (datetime.now(UTC) - timedelta(days=8)).strftime("%Y-%m-%dT%H:%M:%SZ")
        m = RotationMetadata(last_rotated_slot=Slot.PRIMARY, last_rotation_at=past, rotation_number=1)
        assert _is_rotation_due(m, 7) is True

    def test_not_due_before_interval(self) -> None:
        recent = (datetime.now(UTC) - timedelta(days=2)).strftime("%Y-%m-%dT%H:%M:%SZ")
        m = RotationMetadata(last_rotated_slot=Slot.PRIMARY, last_rotation_at=recent, rotation_number=1)
        assert _is_rotation_due(m, 7) is False


class TestSlotSelection:
    """Test alternating slot logic."""

    def test_first_rotation_targets_secondary(self) -> None:
        assert _next_slot(Slot.NONE) == Slot.SECONDARY

    def test_after_secondary_rotates_primary(self) -> None:
        assert _next_slot(Slot.SECONDARY) == Slot.PRIMARY

    def test_after_primary_rotates_secondary(self) -> None:
        assert _next_slot(Slot.PRIMARY) == Slot.SECONDARY

    def test_safe_slot_is_opposite(self) -> None:
        assert _safe_slot(Slot.PRIMARY) == Slot.SECONDARY
        assert _safe_slot(Slot.SECONDARY) == Slot.PRIMARY


class TestRotateTenant:
    """Test single-tenant rotation orchestration."""

    def _make_settings(self) -> Settings:
        """Create test settings without hitting env vars."""
        return Settings(
            environment="dev",
            app_name="test-app",
            subscription_id="00000000-0000-0000-0000-000000000000",
            rotation_interval_days=7,
            dry_run=False,
        )

    @patch("rotation.runner.kv_ops")
    @patch("rotation.runner.apim_ops")
    def test_skip_when_interval_not_elapsed(self, mock_apim: MagicMock, mock_kv: MagicMock) -> None:
        recent = (datetime.now(UTC) - timedelta(days=2)).strftime("%Y-%m-%dT%H:%M:%SZ")
        mock_kv.get_rotation_metadata.return_value = RotationMetadata(
            last_rotated_slot=Slot.PRIMARY,
            last_rotation_at=recent,
            rotation_number=1,
        )

        tenant = TenantSubscription(subscription_name="t1-sub", tenant_name="t1")
        result = rotate_tenant(self._make_settings(), tenant)

        assert result.skipped is True
        assert result.rotated is False
        mock_apim.regenerate_primary_key.assert_not_called()
        mock_apim.regenerate_secondary_key.assert_not_called()

    @patch("rotation.runner.kv_ops")
    @patch("rotation.runner.apim_ops")
    def test_dry_run_does_not_regenerate(self, mock_apim: MagicMock, mock_kv: MagicMock) -> None:
        mock_kv.get_rotation_metadata.return_value = RotationMetadata()

        settings = self._make_settings()
        settings.dry_run = True

        tenant = TenantSubscription(subscription_name="t1-sub", tenant_name="t1")
        result = rotate_tenant(settings, tenant)

        assert result.skipped is True
        assert "DRY RUN" in result.reason
        mock_apim.regenerate_primary_key.assert_not_called()
        mock_apim.regenerate_secondary_key.assert_not_called()

    @patch("rotation.runner.time")
    @patch("rotation.runner.kv_ops")
    @patch("rotation.runner.apim_ops")
    def test_successful_rotation(self, mock_apim: MagicMock, mock_kv: MagicMock, mock_time: MagicMock) -> None:
        # First rotation — metadata is default (none/never)
        mock_kv.get_rotation_metadata.return_value = RotationMetadata()
        mock_apim.get_subscription_keys.return_value = MagicMock(primary_key="pk-new", secondary_key="sk-new")

        tenant = TenantSubscription(subscription_name="t1-sub", tenant_name="t1")
        result = rotate_tenant(self._make_settings(), tenant)

        assert result.rotated is True
        assert result.slot_rotated == Slot.SECONDARY
        assert result.rotation_number == 1
        mock_apim.regenerate_secondary_key.assert_called_once_with(self._make_settings(), "t1-sub")
        mock_kv.store_key_in_vault.assert_called()
        mock_kv.set_rotation_metadata.assert_called_once()

    @patch("rotation.runner.kv_ops")
    @patch("rotation.runner.apim_ops")
    def test_failed_regeneration_marks_failed(self, mock_apim: MagicMock, mock_kv: MagicMock) -> None:
        mock_kv.get_rotation_metadata.return_value = RotationMetadata()
        mock_apim.regenerate_secondary_key.side_effect = RuntimeError("Azure error")

        tenant = TenantSubscription(subscription_name="t1-sub", tenant_name="t1")
        result = rotate_tenant(self._make_settings(), tenant)

        assert result.failed is True
        assert "regeneration failed" in result.reason
