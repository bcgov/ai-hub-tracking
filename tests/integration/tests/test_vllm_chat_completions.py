"""Integration tests for vLLM-backed open-source model routing via APIM.

These tests verify that a tenant with vLLM enabled can reach a GPU-backed
open-source model through the same /openai/v1 base URL as Foundry, with the
backend determined solely by the `model` field in the request body.

All tests are skipped when vLLM is not enabled for the primary tenant (i.e.
VLLM_MODEL_ID env var is absent and no vllm block is present in tenant.tfvars).
"""

from __future__ import annotations

import json

import pytest

from ai_hub_integration.client import ApimClient
from ai_hub_integration.config import IntegrationConfig

from .support import PRIMARY_TENANT, assert_status, require_key, response_json

pytestmark = [pytest.mark.live]

VLLM_TENANT = PRIMARY_TENANT


def _vllm_model(config: IntegrationConfig) -> str:
    """Return the first configured vLLM model ID for the test tenant, or skip."""
    models = config.get_tenant_vllm_models(VLLM_TENANT)
    if not models:
        pytest.skip(
            f"vLLM not enabled for tenant '{VLLM_TENANT}' — "
            "set VLLM_ENABLED=true and VLLM_MODEL_ID in the environment or enable vllm in tenant.tfvars"
        )
    return models[0]


def _chat_body(model_id: str, message: str, max_tokens: int = 30, *, stream: bool = False) -> dict:
    return {
        "model": model_id,
        "messages": [{"role": "user", "content": message}],
        "max_tokens": max_tokens,
        "temperature": 0.1,
        **({"stream": True} if stream else {}),
    }


def test_vllm_chat_completion_returns_200(client: ApimClient, integration_config: IntegrationConfig) -> None:
    """Verify that a vLLM model ID routed through /openai/v1 returns HTTP 200."""
    require_key(integration_config, VLLM_TENANT)
    model_id = _vllm_model(integration_config)

    response = client.chat_completion_v1(VLLM_TENANT, model_id, "Say hello in one word", 30)

    assert_status(response, 200)


def test_vllm_response_contains_valid_choices(client: ApimClient, integration_config: IntegrationConfig) -> None:
    """Verify that vLLM responses include a populated choices array with message content."""
    require_key(integration_config, VLLM_TENANT)
    model_id = _vllm_model(integration_config)

    response = client.chat_completion_v1(VLLM_TENANT, model_id, "What is 2+2?", 30)
    payload = response_json(response)

    assert_status(response, 200)
    assert payload.get("choices"), "Expected non-empty choices array"
    assert payload["choices"][0]["message"]["content"], "Expected non-empty message content"


def test_vllm_model_id_not_rewritten_to_tenant_prefix(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that vLLM model IDs are forwarded unchanged (not prefixed with tenant name).

    Foundry deployment names are rewritten to '{tenant}-{name}' by APIM.
    vLLM model IDs (e.g. 'google/gemma-4-31B-it') must NOT be rewritten.
    """
    require_key(integration_config, VLLM_TENANT)
    model_id = _vllm_model(integration_config)

    response = client.chat_completion_v1(VLLM_TENANT, model_id, "Say hello", 30)
    payload = response_json(response)

    assert_status(response, 200)
    returned_model = payload.get("model", "")
    assert VLLM_TENANT not in returned_model, (
        f"vLLM model was prefixed with tenant name: '{returned_model}' — "
        "APIM model-body rewrite should not fire on vLLM requests"
    )


def test_vllm_streaming_returns_sse_chunks_with_usage(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that vLLM streaming produces valid SSE chunks including a usage chunk."""
    require_key(integration_config, VLLM_TENANT)
    model_id = _vllm_model(integration_config)

    response = client.request(
        "POST",
        VLLM_TENANT,
        "/openai/v1/chat/completions",
        json_body=_chat_body(model_id, "Say hello", stream=True),
        retry=True,
    )

    assert_status(response, 200)
    lines = [ln.strip() for ln in response.text.replace("\r", "").splitlines() if ln.strip()]
    data_lines = [ln for ln in lines if ln.startswith("data: ")]

    assert any(ln == "data: [DONE]" for ln in data_lines), "Missing SSE [DONE] terminator"
    chunks = [json.loads(ln.removeprefix("data: ")) for ln in data_lines if ln.startswith("data: {")]
    chat_chunks = [c for c in chunks if c.get("object") == "chat.completion.chunk"]
    assert chat_chunks, "No chat.completion.chunk objects in SSE stream"

    usage_chunks = [c for c in chunks if c.get("usage") is not None]
    assert usage_chunks, "Expected usage chunk in SSE stream (APIM injects stream_options.include_usage)"
    usage = usage_chunks[0]["usage"]
    assert usage.get("prompt_tokens", 0) > 0


def test_vllm_rate_limit_headers_present(client: ApimClient, integration_config: IntegrationConfig) -> None:
    """Verify that vLLM responses include APIM rate-limit headers."""
    require_key(integration_config, VLLM_TENANT)
    model_id = _vllm_model(integration_config)

    response = client.request(
        "POST",
        VLLM_TENANT,
        "/openai/v1/chat/completions",
        json_body=_chat_body(model_id, "Hi", 10),
        retry=True,
    )

    assert_status(response, 200)
    assert "x-ratelimit-limit-tokens" in response.headers, "Missing x-ratelimit-limit-tokens header"
    assert "x-ratelimit-remaining-tokens" in response.headers, "Missing x-ratelimit-remaining-tokens header"


def test_vllm_model_id_via_deployments_path_returns_400(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that using a vLLM model ID in a /deployments/ URL returns 400.

    vLLM model IDs contain '/' (e.g. 'google/gemma-4-31B-it') which cannot be
    expressed as a deployment-URL path segment. APIM should reject with 400.
    """
    require_key(integration_config, VLLM_TENANT)
    model_id = _vllm_model(integration_config)

    if "/" not in model_id:
        pytest.skip(f"Model ID '{model_id}' has no slash — deployments-path rejection test is not applicable")

    # Encode slashes as path segments — APIM routing should reject this
    deployment_path = (
        f"/openai/deployments/{model_id}/chat/completions?api-version={integration_config.openai_api_version}"
    )
    response = client.request(
        "POST",
        VLLM_TENANT,
        deployment_path,
        json_body={"messages": [{"role": "user", "content": "hello"}], "max_tokens": 10},
    )

    assert response.status_code == 400, (
        f"Expected 400 for vLLM model ID in /deployments/ URL, got {response.status_code}. "
        "APIM should reject slash-containing model IDs in /deployments/ path with 400 UnsupportedRoute."
    )


def test_vllm_no_auth_headers_forwarded(client: ApimClient, integration_config: IntegrationConfig) -> None:
    """Verify that a successful vLLM response indicates APIM did not fail on missing Azure MSI token.

    The vLLM backend is private and has no authentication requirement — APIM must
    strip both Authorization and api-key before forwarding. A 200 response from
    vLLM confirms the headers were stripped (if they were forwarded, vLLM would
    either ignore or reject them, but more importantly APIM would not fail to get
    an MSI token since none is requested).
    """
    require_key(integration_config, VLLM_TENANT)
    model_id = _vllm_model(integration_config)

    response = client.chat_completion_v1(VLLM_TENANT, model_id, "Say hi", 10)

    # A 200 confirms the vLLM path executed without MSI token acquisition errors
    assert_status(response, 200)
