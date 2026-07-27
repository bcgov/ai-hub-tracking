from __future__ import annotations

import pytest

from ai_hub_integration.client import ApimClient
from ai_hub_integration.config import IntegrationConfig

from .support import MISTRAL_OCR_SAMPLE_PDF_BASE64, PRIMARY_TENANT, assert_status, require_key, response_json

pytestmark = [pytest.mark.live]

# The Mistral Document AI deployment is provisioned at minimal capacity until its quota strategy
# is defined, so throttling is expected noise rather than a regression. Only 429 is tolerated:
# a retired or removed model surfaces as 4xx/5xx and must keep failing loudly, because
# /internal/tenant-info reports Terraform config rather than live Foundry state and cannot
# detect it. mistral-document-ai-2505 retired on 2026-07-20 exactly this way.
THROTTLED_STATUS_CODES = frozenset({429})


def _tenant_info_payload(client: ApimClient) -> dict:
    """Fetch the tenant-info payload used to discover deployed Mistral models."""
    response = client.request("GET", PRIMARY_TENANT, "/internal/tenant-info")
    assert_status(response, 200)
    return response_json(response)


def _mistral_chat_model(payload: dict) -> str:
    """Return the deployed Mistral chat model name, if one is present."""
    for model in payload.get("models", []):
        if model.get("name") == "Mistral-Large-3":
            return model["name"]
    return ""


def _mistral_document_model(payload: dict) -> str:
    """Return the newest deployed Mistral OCR model name, if one is present.

    The names carry a `YYMM` release suffix, so the lexicographic maximum is the newest
    version. Selecting the newest rather than the first entry keeps the suite off older
    releases that Azure has since deprecated.
    """
    names = [
        name
        for model in payload.get("models", [])
        if (name := model.get("name", "")).startswith("mistral-document-ai-")
    ]
    return max(names, default="")


def test_ai_hub_admin_tenant_info_exposes_deployed_mistral_models(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that tenant info advertises deployed Mistral models when present."""
    require_key(integration_config, PRIMARY_TENANT)

    payload = _tenant_info_payload(client)
    mistral_count = len(
        [
            model
            for model in payload.get("models", [])
            if model.get("name") == "Mistral-Large-3" or model.get("name", "").startswith("mistral-document-ai-")
        ]
    )
    if mistral_count == 0:
        pytest.skip(f"No Mistral models deployed for {PRIMARY_TENANT}")

    assert payload["services"]["openai"]["enabled"] is True


def test_ai_hub_admin_deployed_mistral_chat_model_works_via_v1(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that the deployed Mistral chat model responds on the `/v1` route."""
    require_key(integration_config, PRIMARY_TENANT)

    payload = _tenant_info_payload(client)
    chat_model = _mistral_chat_model(payload)
    if not chat_model:
        pytest.skip(f"No Mistral chat model deployed for {PRIMARY_TENANT}")

    response = client.chat_completion_v1(PRIMARY_TENANT, chat_model, "Say hello in one short sentence.", 20)
    body = response_json(response)

    assert_status(response, 200)
    assert body["choices"][0]["message"]["content"]


def test_ai_hub_admin_mistral_chat_model_is_rejected_on_legacy_route(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that Mistral chat traffic is rejected on the deprecated legacy route."""
    require_key(integration_config, PRIMARY_TENANT)

    payload = _tenant_info_payload(client)
    chat_model = _mistral_chat_model(payload)
    if not chat_model:
        pytest.skip(f"No Mistral chat model deployed for {PRIMARY_TENANT}")

    response = client.request(
        "POST",
        PRIMARY_TENANT,
        f"/providers/mistral/models/{chat_model}/chat/completions",
        json_body={
            "model": chat_model,
            "messages": [{"role": "user", "content": "Hello"}],
            "max_tokens": 10,
        },
    )
    body = response_json(response)

    assert_status(response, 400)
    assert body["error"]["code"] == "InvalidMistralRoute"


def test_ai_hub_admin_deployed_mistral_document_model_accepts_ocr_requests(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that the deployed Mistral document model accepts OCR requests."""
    require_key(integration_config, PRIMARY_TENANT)

    payload = _tenant_info_payload(client)
    document_model = _mistral_document_model(payload)
    if not document_model:
        pytest.skip(f"No Mistral document model deployed for {PRIMARY_TENANT}")

    response = client.request(
        "POST",
        PRIMARY_TENANT,
        "/providers/mistral/azure/ocr",
        json_body={
            "model": document_model,
            "document": {
                "type": "document_url",
                "document_url": f"data:application/pdf;base64,{MISTRAL_OCR_SAMPLE_PDF_BASE64}",
            },
            "include_image_base64": False,
        },
        retry=True,
    )
    if response.status_code in THROTTLED_STATUS_CODES:
        pytest.skip(
            f"Mistral document model {document_model} is throttled (HTTP {response.status_code}); "
            "the deployment is provisioned at minimal capacity until its quota target is defined"
        )

    assert_status(response, 200)
    body = response_json(response)
    assert body["model"] == document_model
    assert isinstance(body["pages"], list)
    assert body["usage_info"]["doc_size_bytes"] > 0
    assert body["usage_info"]["pages_processed"] == len(body["pages"])
    assert body["usage_info"]["pages_processed_annotation"] >= 0
