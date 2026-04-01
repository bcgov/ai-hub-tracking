from __future__ import annotations

import pytest

from ai_hub_integration.client import ApimClient
from ai_hub_integration.config import IntegrationConfig

from .support import (
    LOW_QUOTA_TENANT,
    PRIMARY_TENANT,
    assert_status,
    deployed_deployments_chat_models,
    direct_request,
    require_key,
    response_json,
)

pytestmark = [pytest.mark.live]


def _deployment_path(config: IntegrationConfig, model: str) -> str:
    """Build the deployment-route chat completion path for a model."""
    return f"/openai/deployments/{model}/chat/completions?api-version={config.openai_api_version}"


def test_ai_hub_admin_primary_model_responds_successfully(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that the primary admin chat model responds successfully."""
    require_key(integration_config, PRIMARY_TENANT)

    response = client.chat_completion(PRIMARY_TENANT, "gpt-4.1-mini", "Say hello", 10)

    assert_status(response, 200)


def test_ai_hub_admin_all_deployed_chat_models_connectivity(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that all deployment-route chat models connect without unexpected failures."""
    require_key(integration_config, PRIMARY_TENANT)
    models = deployed_deployments_chat_models(integration_config, PRIMARY_TENANT)

    passed = 0
    failed: list[str] = []
    for model in models:
        response = client.chat_completion(PRIMARY_TENANT, model, "Say hello", 10)
        if response.status_code == 200:
            passed += 1
        elif response.status_code in {400, 429}:
            continue
        else:
            failed.append(f"{model}({response.status_code})")

    assert not failed, f"Unexpected model failures: {', '.join(failed)}"
    assert passed > 0


def test_ai_hub_admin_chat_completion_returns_valid_json_with_choices(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that chat completions return a JSON payload containing choices."""
    require_key(integration_config, PRIMARY_TENANT)

    response = client.chat_completion(PRIMARY_TENANT, integration_config.default_model, "What is 2+2?")
    payload = response_json(response)

    assert_status(response, 200)
    assert len(payload["choices"]) > 0


def test_ai_hub_admin_chat_completion_includes_usage_metrics(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that successful chat completions include prompt and completion token usage."""
    require_key(integration_config, PRIMARY_TENANT)

    response = client.chat_completion(PRIMARY_TENANT, integration_config.default_model, "Hello")
    payload = response_json(response)

    assert_status(response, 200)
    assert payload["usage"]["prompt_tokens"] > 0
    assert payload["usage"]["completion_tokens"] > 0


def test_ai_hub_admin_chat_completion_handles_system_prompt(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that the deployment route accepts a system prompt in the message list."""
    require_key(integration_config, PRIMARY_TENANT)

    response = client.chat_completion(
        PRIMARY_TENANT,
        integration_config.default_model,
        "Hello",
        50,
        system_prompt="You are a helpful AI Hub admin assistant.",
    )

    assert_status(response, 200)


def test_ai_hub_admin_chat_completion_returns_correlation_id(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that successful chat responses include correlation or request identifiers."""
    require_key(integration_config, PRIMARY_TENANT)

    response = client.chat_completion(PRIMARY_TENANT, integration_config.default_model, "Hi", 10)

    assert_status(response, 200)
    assert response.headers.get("x-correlation-id") or response.headers.get("x-ms-request-id")


def test_invalid_subscription_key_returns_401_or_404(integration_config: IntegrationConfig) -> None:
    """Verify that an invalid subscription key is rejected on the deployment route."""
    url = (
        f"{integration_config.apim_gateway_url}/{PRIMARY_TENANT}"
        f"{_deployment_path(integration_config, integration_config.default_model)}"
    )
    response = direct_request(
        url,
        method="POST",
        headers={"api-key": "invalid-key-12345", "Content-Type": "application/json"},
        json_body={"messages": [{"role": "user", "content": "Hi"}], "max_tokens": 10},
    )

    assert response.status_code in {401, 404}


def test_missing_subscription_key_returns_auth_failure(integration_config: IntegrationConfig) -> None:
    """Verify that omitting the subscription key fails authentication."""
    url = (
        f"{integration_config.apim_gateway_url}/{PRIMARY_TENANT}"
        f"{_deployment_path(integration_config, integration_config.default_model)}"
    )
    response = direct_request(
        url,
        method="POST",
        headers={"Content-Type": "application/json"},
        json_body={"messages": [{"role": "user", "content": "Hi"}], "max_tokens": 10},
    )

    assert response.status_code in {401, 403, 404}


def test_invalid_tenant_returns_404_or_401(integration_config: IntegrationConfig) -> None:
    """Verify that requests targeting an invalid tenant route are rejected."""
    require_key(integration_config, PRIMARY_TENANT)
    url = (
        f"{integration_config.apim_gateway_url}/invalid-tenant"
        f"{_deployment_path(integration_config, integration_config.default_model)}"
    )
    response = direct_request(
        url,
        method="POST",
        headers={
            "api-key": integration_config.get_subscription_key(PRIMARY_TENANT),
            "Content-Type": "application/json",
        },
        json_body={"messages": [{"role": "user", "content": "Hi"}], "max_tokens": 10},
    )

    assert response.status_code in {401, 404}


def test_ai_hub_admin_invalid_model_returns_404(client: ApimClient, integration_config: IntegrationConfig) -> None:
    """Verify that a non-existent deployment name returns 404."""
    require_key(integration_config, PRIMARY_TENANT)

    response = client.chat_completion(PRIMARY_TENANT, "nonexistent-model", "Hello")

    assert_status(response, 404)


def test_ai_hub_admin_empty_messages_array_returns_400(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that an empty messages array is rejected with HTTP 400."""
    require_key(integration_config, PRIMARY_TENANT)

    response = client.request(
        "POST",
        PRIMARY_TENANT,
        _deployment_path(integration_config, integration_config.default_model),
        json_body={"messages": [], "max_tokens": 10},
    )

    assert_status(response, 400)


def test_ai_hub_admin_invalid_json_body_returns_400(client: ApimClient, integration_config: IntegrationConfig) -> None:
    """Verify that malformed JSON payloads are rejected on the deployment route."""
    require_key(integration_config, PRIMARY_TENANT)

    response = client.request(
        "POST",
        PRIMARY_TENANT,
        _deployment_path(integration_config, integration_config.default_model),
        raw_body="this is not valid json",
    )

    assert_status(response, 400)


def test_nr_dap_primary_model_responds_successfully(client: ApimClient, integration_config: IntegrationConfig) -> None:
    """Verify that the low-quota tenant's primary model responds successfully."""
    require_key(integration_config, LOW_QUOTA_TENANT)

    response = client.chat_completion(LOW_QUOTA_TENANT, "gpt-5-mini", "Say hello", 10)

    assert_status(response, 200)


def test_nr_dap_all_deployed_chat_models_connectivity(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that all low-quota deployment-route chat models connect without unexpected failures."""
    require_key(integration_config, LOW_QUOTA_TENANT)
    models = deployed_deployments_chat_models(integration_config, LOW_QUOTA_TENANT)

    passed = 0
    failed: list[str] = []
    for model in models:
        response = client.chat_completion(LOW_QUOTA_TENANT, model, "Say hello", 10)
        if response.status_code == 200:
            passed += 1
        elif response.status_code in {400, 429}:
            continue
        else:
            failed.append(f"{model}({response.status_code})")

    assert not failed, f"Unexpected NR-DAP model failures: {', '.join(failed)}"
    assert passed > 0
