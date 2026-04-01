from __future__ import annotations

import math

import pytest

from ai_hub_integration.client import ApimClient
from ai_hub_integration.config import IntegrationConfig

from .support import PRIMARY_TENANT, direct_request, require_key, response_json

pytestmark = [pytest.mark.live]


@pytest.fixture(scope="module")
def tenant_info_response(client: ApimClient, integration_config: IntegrationConfig):
    require_key(integration_config, PRIMARY_TENANT)
    response = client.request("GET", PRIMARY_TENANT, "/internal/tenant-info")
    assert response.status_code == 200, response.text
    return response


@pytest.fixture(scope="module")
def tenant_info_payload(tenant_info_response) -> dict:
    return response_json(tenant_info_response)


def test_get_internal_tenant_info_returns_200(tenant_info_response) -> None:
    assert tenant_info_response.status_code == 200


def test_tenant_info_response_is_valid_json(tenant_info_payload: dict) -> None:
    assert isinstance(tenant_info_payload, dict)


def test_tenant_info_contains_correct_tenant_name(tenant_info_payload: dict) -> None:
    assert tenant_info_payload["tenant"] == PRIMARY_TENANT


def test_tenant_info_contains_non_empty_models_array(tenant_info_payload: dict) -> None:
    assert len(tenant_info_payload["models"]) > 0


def test_tenant_info_models_have_all_required_fields(tenant_info_payload: dict) -> None:
    for model in tenant_info_payload["models"]:
        assert model["name"]
        assert model["model_name"]
        assert model["model_version"]
        assert model["scale_type"]
        assert model["tokens_per_minute"] is not None
        assert model["apim_raw_tokens_per_minute"] is not None
        assert model["input_equivalent_tokens_per_minute"] is not None
        if model["capacity_unit"] == "PTU":
            assert model["capacity"] is not None
            assert model["input_tpm_per_ptu"] is not None
            assert model["output_tokens_to_input_ratio"] is not None
        else:
            assert model["capacity_k_tpm"] is not None


def test_tenant_info_rate_limit_metadata_matches_capacity_metadata(tenant_info_payload: dict) -> None:
    for model in tenant_info_payload["models"]:
        if model["capacity_unit"] == "PTU":
            expected_input = model["capacity"] * model["input_tpm_per_ptu"]
            expected_raw = math.floor(expected_input / model["output_tokens_to_input_ratio"])
            assert model["input_equivalent_tokens_per_minute"] == expected_input
            assert model["apim_raw_tokens_per_minute"] == expected_raw
            assert model["tokens_per_minute"] == expected_raw
        else:
            expected = model["capacity_k_tpm"] * 1000
            assert model["tokens_per_minute"] == expected
            assert model["apim_raw_tokens_per_minute"] == expected
            assert model["input_equivalent_tokens_per_minute"] == expected


def test_tenant_info_contains_services_object_with_required_keys(tenant_info_payload: dict) -> None:
    services = tenant_info_payload["services"]
    for service_name in ["openai", "document_intelligence", "ai_search", "speech_services", "storage"]:
        assert isinstance(services[service_name]["enabled"], bool)


def test_services_openai_is_true_when_models_are_configured(tenant_info_payload: dict) -> None:
    if tenant_info_payload["models"]:
        assert tenant_info_payload["services"]["openai"]["enabled"] is True


def test_document_intelligence_is_enabled_as_per_tenant_config(tenant_info_payload: dict) -> None:
    assert tenant_info_payload["services"]["document_intelligence"]["enabled"] is True


def test_speech_services_is_disabled_as_per_tenant_config(tenant_info_payload: dict) -> None:
    speech = tenant_info_payload["services"]["speech_services"]

    assert speech["enabled"] is False
    assert speech["stt_endpoint"] is None


def test_ai_search_is_disabled_as_per_tenant_config(tenant_info_payload: dict) -> None:
    assert tenant_info_payload["services"]["ai_search"]["enabled"] is False


def test_post_internal_tenant_info_returns_405(client: ApimClient, integration_config: IntegrationConfig) -> None:
    require_key(integration_config, PRIMARY_TENANT)

    response = client.request("POST", PRIMARY_TENANT, "/internal/tenant-info")

    assert response.status_code == 405


def test_post_internal_tenant_info_returns_method_not_allowed_error(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    require_key(integration_config, PRIMARY_TENANT)

    response = client.request("POST", PRIMARY_TENANT, "/internal/tenant-info")
    payload = response_json(response)

    assert response.status_code == 405
    assert payload["error"]["code"] == "MethodNotAllowed"


def test_unauthenticated_request_to_internal_tenant_info_returns_401_or_403(
    integration_config: IntegrationConfig,
) -> None:
    response = direct_request(
        f"{integration_config.apim_gateway_url}/{PRIMARY_TENANT}/internal/tenant-info",
        method="GET",
        headers={"Content-Type": "application/json"},
        timeout=30,
    )

    assert response.status_code in {401, 403}


def test_tenant_info_contains_non_empty_base_url(tenant_info_payload: dict) -> None:
    base_url = tenant_info_payload["base_url"]

    assert base_url
    assert base_url.startswith("https://")
    assert base_url.endswith(f"/{PRIMARY_TENANT}")


def test_every_model_has_azure_openai_endpoint_fields(tenant_info_payload: dict) -> None:
    for model in tenant_info_payload["models"]:
        azure_openai = model["endpoints"]["azure_openai"]
        assert azure_openai["endpoint"]
        assert azure_openai["api_version"]
        assert azure_openai["url"]


def test_every_model_has_openai_compatible_endpoint_fields(tenant_info_payload: dict) -> None:
    for model in tenant_info_payload["models"]:
        openai_compatible = model["endpoints"]["openai_compatible"]
        assert openai_compatible["base_url"]
        assert openai_compatible["model"]
        assert openai_compatible["url"]


def test_azure_openai_url_contains_deployment_name_for_each_model(tenant_info_payload: dict) -> None:
    for model in tenant_info_payload["models"]:
        assert f"/deployments/{model['name']}/" in model["endpoints"]["azure_openai"]["url"]


def test_openai_compatible_model_matches_deployment_name(tenant_info_payload: dict) -> None:
    for model in tenant_info_payload["models"]:
        assert model["endpoints"]["openai_compatible"]["model"] == model["name"]


def test_openai_compatible_base_url_ends_with_openai_v1(tenant_info_payload: dict) -> None:
    for model in tenant_info_payload["models"]:
        assert model["endpoints"]["openai_compatible"]["base_url"].endswith("/openai/v1")


def test_enabled_openai_service_has_endpoint_urls(tenant_info_payload: dict) -> None:
    service = tenant_info_payload["services"]["openai"]
    if not service["enabled"]:
        pytest.skip("OpenAI service is disabled")

    endpoints = service["endpoints"]
    assert endpoints["azure_openai"].startswith("https://")
    assert endpoints["openai_compatible"].endswith("/openai/v1")
    assert endpoints["api_version"]


def test_enabled_document_intelligence_service_has_endpoint_and_example(tenant_info_payload: dict) -> None:
    service = tenant_info_payload["services"]["document_intelligence"]
    if not service["enabled"]:
        pytest.skip("Document Intelligence is disabled")

    assert service["endpoint"].startswith("https://")
    assert "documentintelligence" in service["example"]


def test_disabled_ai_search_only_exposes_enabled_false(tenant_info_payload: dict) -> None:
    assert tenant_info_payload["services"]["ai_search"]["enabled"] is False


def test_enabled_storage_service_has_endpoint_and_example(tenant_info_payload: dict) -> None:
    service = tenant_info_payload["services"]["storage"]
    if not service["enabled"]:
        pytest.skip("Storage service is disabled")

    assert service["endpoint"].endswith("/storage")
    assert "/storage/" in service["example"]
