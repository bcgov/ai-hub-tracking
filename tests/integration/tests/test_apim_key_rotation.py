from __future__ import annotations

import pytest

from ai_hub_integration.client import ApimClient
from ai_hub_integration.config import IntegrationConfig

from .support import assert_status, direct_request, require_key, response_json

pytestmark = [pytest.mark.live, pytest.mark.requires_proxy]


def _tenant_1(config: IntegrationConfig) -> str:
    return config.apim_keys_tenant_1


def _tenant_2(config: IntegrationConfig) -> str:
    return config.apim_keys_tenant_2


def test_tenant_1_get_internal_apim_keys_returns_200(client: ApimClient, integration_config: IntegrationConfig) -> None:
    if not integration_config.is_apim_key_rotation_enabled():
        pytest.skip("APIM key rotation is disabled in shared.tfvars")
    tenant = _tenant_1(integration_config)
    require_key(integration_config, tenant)

    response = client.request("GET", tenant, "/internal/apim-keys")

    assert_status(response, 200)


def test_tenant_1_apim_keys_contains_expected_fields(client: ApimClient, integration_config: IntegrationConfig) -> None:
    if not integration_config.is_apim_key_rotation_enabled():
        pytest.skip("APIM key rotation is disabled in shared.tfvars")
    tenant = _tenant_1(integration_config)
    require_key(integration_config, tenant)

    response = client.request("GET", tenant, "/internal/apim-keys")
    payload = response_json(response)

    assert_status(response, 200)
    assert payload["tenant"] == tenant
    assert payload["primary_key"]
    assert payload["secondary_key"]
    assert payload["rotation"] is not None
    assert payload["keyvault"]["uri"].endswith("vault.azure.net")
    assert payload["keyvault"]["primary_key_secret"] == f"{tenant}-apim-primary-key"
    assert payload["keyvault"]["secondary_key_secret"] == f"{tenant}-apim-secondary-key"


def test_tenant_2_get_internal_apim_keys_returns_200(client: ApimClient, integration_config: IntegrationConfig) -> None:
    if not integration_config.is_apim_key_rotation_enabled():
        pytest.skip("APIM key rotation is disabled in shared.tfvars")
    tenant = _tenant_2(integration_config)
    require_key(integration_config, tenant)

    response = client.request("GET", tenant, "/internal/apim-keys")
    payload = response_json(response)

    assert_status(response, 200)
    assert payload["tenant"] == tenant
    assert payload["primary_key"]
    assert payload["secondary_key"]
    assert payload["rotation"] is not None


def test_post_internal_apim_keys_returns_405(client: ApimClient, integration_config: IntegrationConfig) -> None:
    if not integration_config.is_apim_key_rotation_enabled():
        pytest.skip("APIM key rotation is disabled in shared.tfvars")
    tenant = _tenant_1(integration_config)
    require_key(integration_config, tenant)

    response = client.request("POST", tenant, "/internal/apim-keys")

    assert_status(response, 405)


def test_unauthenticated_internal_apim_keys_returns_401_or_403(integration_config: IntegrationConfig) -> None:
    if not integration_config.is_apim_key_rotation_enabled():
        pytest.skip("APIM key rotation is disabled in shared.tfvars")
    tenant = _tenant_1(integration_config)
    url = f"{integration_config.apim_gateway_url}/{tenant}/internal/apim-keys"

    response = direct_request(url, method="GET", headers={"Content-Type": "application/json"})

    assert response.status_code in {401, 403}


def test_tenant_1_and_tenant_2_return_different_primary_keys(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    if not integration_config.is_apim_key_rotation_enabled():
        pytest.skip("APIM key rotation is disabled in shared.tfvars")
    tenant_1 = _tenant_1(integration_config)
    tenant_2 = _tenant_2(integration_config)
    if tenant_1 == tenant_2:
        pytest.skip(f"Tenant-1 and Tenant-2 resolve to the same tenant ({tenant_1})")

    require_key(integration_config, tenant_1)
    require_key(integration_config, tenant_2)

    payload_1 = response_json(client.request("GET", tenant_1, "/internal/apim-keys"))
    payload_2 = response_json(client.request("GET", tenant_2, "/internal/apim-keys"))

    assert payload_1["primary_key"] != payload_2["primary_key"]
