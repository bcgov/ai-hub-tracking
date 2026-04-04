from __future__ import annotations

import json
import time

import pytest

from ai_hub_integration.client import ApimClient
from ai_hub_integration.config import IntegrationConfig, uses_max_completion_tokens

from .support import PRIMARY_TENANT, assert_status, deployed_chat_models, require_appgw, require_key, response_json

pytestmark = [pytest.mark.live]

RATE_LIMIT_TARGET_MODELS = (
    "gpt-5.1-chat",
    "o1",
    "o3-mini",
    "gpt-5-mini",
    "gpt-5.1-codex-mini",
    "o4-mini",
)


def _v1_body(model: str, message: str, max_tokens: int = 10, *, stream: bool = False) -> dict:
    """Build a request body for the OpenAI-compatible `/openai/v1` route."""
    body = {
        "model": model,
        "messages": [{"role": "user", "content": message}],
    }
    if uses_max_completion_tokens(model):
        body["max_completion_tokens"] = max_tokens
    else:
        body["max_tokens"] = max_tokens
        body["temperature"] = 0.7
    if stream:
        body["stream"] = True
    return body


def _deployment_path(config: IntegrationConfig) -> str:
    """Build the default deployment-route path used for parity checks."""
    return f"/openai/deployments/gpt-4.1-mini/chat/completions?api-version={config.openai_api_version}"


def _rate_limit_target_model(config: IntegrationConfig) -> str:
    """Return a low-quota `ai-hub-admin` model suitable for deterministic 429 coverage."""
    models = set(deployed_chat_models(config, PRIMARY_TENANT))
    for model in RATE_LIMIT_TARGET_MODELS:
        if model in models:
            return model
    pytest.skip("No low-quota ai-hub-admin chat model is deployed for deterministic 429 coverage")


def _rate_limit_message(limit_tokens: int) -> str:
    """Build a large prompt that can exhaust a small TPM budget in a few calls."""
    word_count = max(1500, min(limit_tokens // 4, 16000))
    return " ".join(["token"] * word_count)


def _rate_limit_attempts(limit_tokens: int) -> int:
    """Return a bounded number of burst attempts needed to exhaust the model TPM window."""
    estimated_prompt_tokens = max(1500, min(limit_tokens // 4, 16000))
    return max(4, min(8, (limit_tokens // estimated_prompt_tokens) + 2))


def test_ai_hub_admin_v1_chat_completion_returns_200(client: ApimClient, integration_config: IntegrationConfig) -> None:
    """Verify that the `/openai/v1` chat route returns 200 for the primary model."""
    require_key(integration_config, PRIMARY_TENANT)

    response = client.chat_completion_v1(PRIMARY_TENANT, "gpt-4.1-mini", "Say hello in one word", 10)

    assert_status(response, 200)


def test_ai_hub_admin_v1_response_contains_valid_choices_array(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that `/v1` responses include a populated choices array."""
    require_key(integration_config, PRIMARY_TENANT)

    response = client.chat_completion_v1(PRIMARY_TENANT, "gpt-4.1-mini", "What is 2+2?", 10)
    payload = response_json(response)

    assert_status(response, 200)
    assert payload["choices"]
    assert payload["choices"][0]["message"]["content"]


def test_ai_hub_admin_v1_model_name_is_not_double_prefixed(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that `/v1` model names are not prefixed twice with the tenant name."""
    require_key(integration_config, PRIMARY_TENANT)

    response = client.chat_completion_v1(PRIMARY_TENANT, "gpt-4.1-mini", "Say hello", 10)
    payload = response_json(response)

    assert_status(response, 200)
    assert "ai-hub-admin-ai-hub-admin-" not in payload.get("model", "")


def test_ai_hub_admin_all_deployed_chat_models_work_via_v1(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that all chat-capable models work through the OpenAI-compatible route."""
    require_key(integration_config, PRIMARY_TENANT)
    models = deployed_chat_models(integration_config, PRIMARY_TENANT)

    passed = 0
    failed: list[str] = []
    for model in models:
        response = client.chat_completion_v1(PRIMARY_TENANT, model, "Say hello", 10)
        if response.status_code == 200:
            passed += 1
        elif response.status_code in {400, 429}:
            continue
        else:
            failed.append(f"{model}({response.status_code})")

    assert not failed, f"Unexpected /v1 failures: {', '.join(failed)}"
    assert passed > 0


def test_ai_hub_admin_streaming_v1_response_contains_sse_chunks(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that streaming `/v1` responses emit valid SSE chat chunks and a usage chunk."""
    require_key(integration_config, PRIMARY_TENANT)

    response = client.request(
        "POST",
        PRIMARY_TENANT,
        "/openai/v1/chat/completions",
        json_body=_v1_body("gpt-4.1-mini", "Say hello", 10, stream=True),
        retry=True,
    )
    lines = [line.strip() for line in response.text.replace("\r", "").splitlines() if line.strip()]
    data_lines = [line for line in lines if line.startswith("data: ")]

    assert_status(response, 200)
    assert len(data_lines) >= 2
    assert any(line == "data: [DONE]" for line in data_lines)

    chunks = [json.loads(line.removeprefix("data: ")) for line in data_lines if line.startswith("data: {")]
    chat_chunks = [chunk for chunk in chunks if chunk.get("object") == "chat.completion.chunk"]
    assert chat_chunks
    assert chat_chunks[0].get("model")
    assert "ai-hub-admin-ai-hub-admin" not in chat_chunks[0].get("model", "")

    # Verify APIM-injected stream_options.include_usage produced a usage chunk
    usage_chunks = [chunk for chunk in chunks if chunk.get("usage") is not None]
    assert usage_chunks, "Expected a usage chunk in the SSE stream (APIM injects stream_options.include_usage)"
    usage = usage_chunks[0]["usage"]
    assert usage.get("prompt_tokens", 0) > 0
    assert usage.get("completion_tokens", 0) > 0
    assert usage.get("total_tokens", 0) > 0


def test_ai_hub_admin_streaming_v1_usage_chunk_is_idempotent_when_client_sends_stream_options(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that explicitly sending stream_options.include_usage=true is idempotent with APIM injection.

    APIM only injects stream_options when the client has not already set the key, so this
    request should behave identically to APIM-injected usage and still return a usage chunk.
    """
    require_key(integration_config, PRIMARY_TENANT)

    body = _v1_body("gpt-4.1-mini", "Say hello", 10, stream=True)
    body["stream_options"] = {"include_usage": True}

    response = client.request(
        "POST",
        PRIMARY_TENANT,
        "/openai/v1/chat/completions",
        json_body=body,
        retry=True,
    )
    lines = [line.strip() for line in response.text.replace("\r", "").splitlines() if line.strip()]
    data_lines = [line for line in lines if line.startswith("data: ")]

    assert_status(response, 200)
    chunks = [json.loads(line.removeprefix("data: ")) for line in data_lines if line.startswith("data: {")]
    usage_chunks = [chunk for chunk in chunks if chunk.get("usage") is not None]
    assert usage_chunks, "Expected usage chunk even when client sends stream_options explicitly"
    usage = usage_chunks[0]["usage"]
    assert usage.get("prompt_tokens", 0) > 0
    assert usage.get("completion_tokens", 0) > 0


def test_ai_hub_admin_missing_model_field_returns_400(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that `/v1` requests without a model field are rejected."""
    require_key(integration_config, PRIMARY_TENANT)

    response = client.request(
        "POST",
        PRIMARY_TENANT,
        "/openai/v1/chat/completions",
        json_body={"messages": [{"role": "user", "content": "hello"}], "max_tokens": 10},
    )
    payload = response_json(response)

    assert_status(response, 400)
    assert payload["error"]["code"] == "MissingModel"


def test_ai_hub_admin_invalid_json_body_returns_400(client: ApimClient, integration_config: IntegrationConfig) -> None:
    """Verify that malformed `/v1` JSON payloads return HTTP 400."""
    require_key(integration_config, PRIMARY_TENANT)

    response = client.request("POST", PRIMARY_TENANT, "/openai/v1/chat/completions", raw_body="this is not valid json")

    assert_status(response, 400)


def test_ai_hub_admin_bearer_token_auth_returns_200_via_v1(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that Bearer authentication succeeds on the `/v1` route."""
    require_key(integration_config, PRIMARY_TENANT)
    require_appgw(integration_config)

    response = client.chat_completion_v1(PRIMARY_TENANT, "gpt-4.1-mini", "Say hello", 10, auth_mode="bearer")

    assert_status(response, 200)


def test_ai_hub_admin_bearer_token_auth_works_with_deployments_route(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that Bearer authentication still works on the deployments route."""
    require_key(integration_config, PRIMARY_TENANT)
    require_appgw(integration_config)

    response = client.chat_completion(PRIMARY_TENANT, "gpt-4.1-mini", "Say hello", 10, auth_mode="bearer")

    assert_status(response, 200)


def test_ai_hub_admin_deployments_route_still_returns_200(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that the deployments route remains functional alongside `/v1`."""
    require_key(integration_config, PRIMARY_TENANT)

    response = client.chat_completion(PRIMARY_TENANT, "gpt-4.1-mini", "Say hello", 10)

    assert_status(response, 200)


def test_ai_hub_admin_v1_and_deployments_report_identical_token_limits(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that `/v1` and deployments expose identical token-rate-limit headers."""
    require_key(integration_config, PRIMARY_TENANT)

    v1_response = client.request(
        "POST",
        PRIMARY_TENANT,
        "/openai/v1/chat/completions",
        json_body=_v1_body("gpt-4.1-mini", "Say hello", 5),
        retry=True,
    )
    v1_limit = int(v1_response.headers["x-ratelimit-limit-tokens"])
    assert v1_limit > 1000

    time.sleep(2)

    deployments_response = client.request(
        "POST",
        PRIMARY_TENANT,
        _deployment_path(integration_config),
        json_body={"messages": [{"role": "user", "content": "Say hello"}], "max_tokens": 5},
        retry=True,
    )
    deployments_limit = int(deployments_response.headers["x-ratelimit-limit-tokens"])

    assert deployments_limit > 1000
    assert v1_limit == deployments_limit


def test_ai_hub_admin_v1_eventually_returns_429_when_token_budget_is_exhausted(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that ai-hub-admin can trigger an APIM 429 with retry guidance on a low-quota model.

    The test deliberately targets a low-TPM admin model so it can exhaust the shared
    budget with a few large prompts and assert the OpenAI-compatible retry headers.
    """
    require_key(integration_config, PRIMARY_TENANT)

    model = _rate_limit_target_model(integration_config)
    probe_response = client.request(
        "POST",
        PRIMARY_TENANT,
        "/openai/v1/chat/completions",
        json_body=_v1_body(model, "rate limit probe", 64),
        retry=False,
    )

    assert_status(probe_response, 200)
    limit_header = probe_response.headers.get("x-ratelimit-limit-tokens")
    if not limit_header or not limit_header.isdigit():
        pytest.skip(f"No x-ratelimit-limit-tokens header exposed for {model}")

    limit_tokens = int(limit_header)
    if limit_tokens > 120000:
        pytest.skip(f"Selected model {model} exposes {limit_tokens} TPM; forcing 429 would be too noisy")

    burst_body = _v1_body(model, _rate_limit_message(limit_tokens), 64)
    statuses: list[int] = []
    for _ in range(_rate_limit_attempts(limit_tokens)):
        response = client.request(
            "POST",
            PRIMARY_TENANT,
            "/openai/v1/chat/completions",
            json_body=burst_body,
            retry=False,
        )
        statuses.append(response.status_code)

        if response.status_code == 429:
            payload = response_json(response)
            assert response.headers.get("Retry-After")
            assert response.headers.get("retry-after-ms")
            assert response.headers.get("x-should-retry") == "true"
            assert (payload.get("error") or {}).get("code") in {"429", "too_many_requests"}
            return

        assert response.status_code == 200, response.text

    pytest.fail(f"Expected a 429 for ai-hub-admin model {model} after exhausting {limit_tokens} TPM; saw {statuses}")
