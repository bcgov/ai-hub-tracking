from __future__ import annotations

import socket

import pytest

from ai_hub_integration.client import ApimClient
from ai_hub_integration.config import IntegrationConfig

from .support import (
    CROSS_KEY_TARGET_MODEL,
    LOW_QUOTA_TENANT,
    PRIMARY_TENANT,
    SAMPLE_PDF_BASE64,
    direct_request,
    get_server_certificate,
    operation_location,
    require_appgw,
    require_key,
    response_json,
)

pytestmark = [pytest.mark.live, pytest.mark.appgw]


def test_custom_domain_resolves_and_returns_http_response(integration_config: IntegrationConfig) -> None:
    require_appgw(integration_config)

    response = direct_request(f"https://{integration_config.appgw_hostname}/", timeout=15)

    assert 200 <= response.status_code < 600


def test_tls_certificate_is_valid_and_matches_hostname(integration_config: IntegrationConfig) -> None:
    require_appgw(integration_config)

    cert = get_server_certificate(integration_config.appgw_hostname)

    assert cert


def test_chat_completion_routed_through_app_gateway_returns_200(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    require_appgw(integration_config)
    require_key(integration_config, PRIMARY_TENANT)

    response = client.chat_completion(PRIMARY_TENANT, integration_config.default_model, "Say hello", 10)
    payload = response_json(response)

    assert response.status_code == 200
    assert payload["choices"][0]["message"]["content"]


def test_document_intelligence_routed_through_app_gateway_returns_supported_status(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    require_appgw(integration_config)
    require_key(integration_config, PRIMARY_TENANT)

    response = client.docint_analyze(PRIMARY_TENANT, "prebuilt-layout", "dGVzdA==")

    assert response.status_code in {200, 202, 400}


def test_operation_location_uses_app_gateway_url_not_backend(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    require_appgw(integration_config)
    require_key(integration_config, PRIMARY_TENANT)

    response = client.docint_analyze(PRIMARY_TENANT, "prebuilt-layout", SAMPLE_PDF_BASE64)
    if response.status_code != 202:
        pytest.skip(f"Expected 202 for async operation, got {response.status_code}")

    op_location = operation_location(response)

    assert op_location
    assert "cognitiveservices.azure.com" not in op_location
    assert "azure-api.net" not in op_location
    assert integration_config.appgw_hostname in op_location


def test_request_without_subscription_key_returns_auth_failure(integration_config: IntegrationConfig) -> None:
    require_appgw(integration_config)

    response = direct_request(
        f"https://{integration_config.appgw_hostname}/{PRIMARY_TENANT}/openai/deployments/{integration_config.default_model}/chat/completions?api-version={integration_config.openai_api_version}",
        method="POST",
        headers={"Content-Type": "application/json"},
        json_body={"messages": [{"role": "user", "content": "hello"}]},
        timeout=10,
    )

    assert response.status_code in {401, 403, 404}


def test_unauthenticated_burst_traffic_is_rate_limited_or_denied(integration_config: IntegrationConfig) -> None:
    require_appgw(integration_config)

    statuses: list[int] = []
    for _ in range(15):
        response = direct_request(
            f"https://{integration_config.appgw_hostname}",
            method="POST",
            headers={"Content-Type": "application/json"},
            json_body={"messages": [{"role": "user", "content": "rate-limit-test"}], "max_tokens": 5},
            timeout=10,
        )
        statuses.append(response.status_code)
        assert response.status_code in {401, 403, 404, 429}

    assert any(code in {401, 403, 404, 429} for code in statuses)


def test_invalid_tenant_via_app_gateway_returns_404(integration_config: IntegrationConfig) -> None:
    require_appgw(integration_config)
    require_key(integration_config, PRIMARY_TENANT)

    response = direct_request(
        f"https://{integration_config.appgw_hostname}/nonexistent-tenant/openai/deployments/{integration_config.default_model}/chat/completions?api-version={integration_config.openai_api_version}",
        method="POST",
        headers={
            "api-key": integration_config.get_subscription_key(PRIMARY_TENANT),
            "Content-Type": "application/json",
        },
        json_body={"messages": [{"role": "user", "content": "hello"}]},
        timeout=10,
    )

    assert response.status_code == 404


def test_http_port_80_is_blocked_at_nsg(integration_config: IntegrationConfig) -> None:
    require_appgw(integration_config)

    with pytest.raises((OSError, TimeoutError)):
        socket.create_connection((integration_config.appgw_hostname, 80), timeout=10)


def test_v1_chat_completion_routed_through_app_gateway_returns_200(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    require_appgw(integration_config)
    require_key(integration_config, PRIMARY_TENANT)

    response = client.chat_completion_v1(PRIMARY_TENANT, "gpt-4.1-mini", "Say hello", 10)
    payload = response_json(response)

    assert response.status_code == 200
    assert payload["choices"][0]["message"]["content"]


def test_bearer_token_auth_through_app_gateway_returns_200(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    require_appgw(integration_config)
    require_key(integration_config, PRIMARY_TENANT)

    response = client.chat_completion(PRIMARY_TENANT, "gpt-4.1-mini", "Say hello", 10, auth_mode="bearer")

    assert response.status_code == 200


def test_bearer_token_v1_through_app_gateway_returns_200(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    require_appgw(integration_config)
    require_key(integration_config, PRIMARY_TENANT)

    response = client.chat_completion_v1(PRIMARY_TENANT, "gpt-4.1-mini", "Say hello", 10, auth_mode="bearer")
    payload = response_json(response)

    assert response.status_code == 200
    assert payload["choices"][0]["message"]["content"]


def test_request_with_only_bearer_token_is_not_blocked_by_waf(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    require_appgw(integration_config)
    require_key(integration_config, PRIMARY_TENANT)

    response = client.chat_completion_v1(PRIMARY_TENANT, "gpt-4.1-mini", "hello", 5, auth_mode="bearer")

    assert response.status_code != 403
    assert response.status_code == 200


def test_ai_hub_admin_key_cannot_access_nr_dap_apis_via_app_gateway(
    integration_config: IntegrationConfig,
) -> None:
    require_appgw(integration_config)
    require_key(integration_config, PRIMARY_TENANT)

    response = direct_request(
        f"https://{integration_config.appgw_hostname}/{LOW_QUOTA_TENANT}/openai/deployments/{CROSS_KEY_TARGET_MODEL}/chat/completions?api-version={integration_config.openai_api_version}",
        method="POST",
        headers={
            "api-key": integration_config.get_subscription_key(PRIMARY_TENANT),
            "Content-Type": "application/json",
        },
        json_body={"messages": [{"role": "user", "content": "hello"}], "max_tokens": 5},
        timeout=10,
    )

    assert response.status_code in {401, 403, 404}
