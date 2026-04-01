from __future__ import annotations

from tests.support import is_azure_key_vault_uri


def test_is_azure_key_vault_uri_accepts_expected_hostname() -> None:
    """Verify that a normal Azure Key Vault URI is accepted by the validator."""
    assert is_azure_key_vault_uri("https://ai-hub-kv.vault.azure.net/")


def test_is_azure_key_vault_uri_rejects_non_azure_hostname() -> None:
    """Verify that a hostname merely containing the suffix is rejected."""
    assert not is_azure_key_vault_uri("https://ai-hub-kv.vault.azure.net.example.com/")
