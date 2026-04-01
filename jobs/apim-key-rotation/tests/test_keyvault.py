# =============================================================================
# Unit tests — Key Vault helper operations
# =============================================================================
from __future__ import annotations

import logging
from types import SimpleNamespace
from unittest.mock import MagicMock

import rotation.keyvault as keyvault_ops


class TestStoreKeyInVault:
    """Test subscription-key storage behavior."""

    def test_store_key_does_not_log_secret_identifier_or_value(
        self,
        monkeypatch,
        caplog,
    ) -> None:
        client = MagicMock()
        settings = SimpleNamespace(secret_expiry_days=30)

        monkeypatch.setattr(keyvault_ops, "_get_client", lambda _: client)
        caplog.set_level(logging.DEBUG, logger="apim-key-rotation.keyvault")

        keyvault_ops.store_key_in_vault(
            settings,
            "tenant-a-primary-key",
            "super-secret-value",
            tags={"tenant": "tenant-a"},
        )

        client.set_secret.assert_called_once()
        assert "tenant-a-primary-key" not in caplog.text
        assert "super-secret-value" not in caplog.text
        assert "Stored APIM subscription key in hub KV" in caplog.text
