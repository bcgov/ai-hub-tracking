from __future__ import annotations

import pytest

from ai_hub_integration.client import ApimClient
from ai_hub_integration.config import IntegrationConfig

from .support import PRIMARY_TENANT, ensure_test_file, operation_location, require_appgw, require_key, response_json

pytestmark = [pytest.mark.live, pytest.mark.appgw]


def _wait_for_result(client: ApimClient, initial_response) -> dict:
    """Resolve a Document Intelligence response into the final JSON payload."""
    if initial_response.status_code == 200:
        return response_json(initial_response)

    assert initial_response.status_code == 202
    op_location = operation_location(initial_response)
    assert op_location, "Missing Operation-Location header in 202 response"
    final_response = client.wait_for_operation(
        PRIMARY_TENANT,
        client.extract_operation_path(PRIMARY_TENANT, op_location),
        60,
    )
    return response_json(final_response)


def test_ai_hub_admin_binary_upload_returns_200_or_202(
    client: ApimClient, integration_config: IntegrationConfig, test_form_jpg
) -> None:
    """Verify that binary uploads reach Document Intelligence without WAF rejection."""
    require_appgw(integration_config)
    require_key(integration_config, PRIMARY_TENANT)
    ensure_test_file(test_form_jpg)
    if not client.document_intelligence_accessible(PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")

    response = client.docint_analyze_binary(PRIMARY_TENANT, "prebuilt-layout", test_form_jpg)

    assert response.status_code != 403, "WAF blocked binary upload"
    assert response.status_code in {200, 202}


def test_ai_hub_admin_binary_upload_full_async_flow_validates_extracted_text(
    client: ApimClient, integration_config: IntegrationConfig, test_form_jpg
) -> None:
    """Verify that the async binary upload flow returns extracted document content."""
    require_appgw(integration_config)
    require_key(integration_config, PRIMARY_TENANT)
    ensure_test_file(test_form_jpg)
    if not client.document_intelligence_accessible(PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")

    payload = _wait_for_result(client, client.docint_analyze_binary(PRIMARY_TENANT, "prebuilt-layout", test_form_jpg))
    content = payload["analyzeResult"]["content"]

    assert content
    assert "Monthly Report" in content


def test_ai_hub_admin_pdf_content_type_upload_is_not_blocked_by_waf(
    client: ApimClient, integration_config: IntegrationConfig, test_form_jpg
) -> None:
    """Verify that PDF-content-type uploads are allowed through the WAF path."""
    require_appgw(integration_config)
    require_key(integration_config, PRIMARY_TENANT)
    ensure_test_file(test_form_jpg)
    if not client.document_intelligence_accessible(PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")

    response = client.docint_analyze_pdf(PRIMARY_TENANT, "prebuilt-layout", test_form_jpg)

    assert response.status_code != 403, "WAF blocked PDF content-type upload"
    assert response.status_code in {200, 202, 400}


def test_ai_hub_admin_multipart_upload_is_not_blocked_by_waf(
    client: ApimClient, integration_config: IntegrationConfig, test_form_jpg
) -> None:
    """Verify that multipart uploads are allowed through the WAF path."""
    require_appgw(integration_config)
    require_key(integration_config, PRIMARY_TENANT)
    ensure_test_file(test_form_jpg)
    if not client.document_intelligence_accessible(PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")

    response = client.docint_analyze_multipart(PRIMARY_TENANT, "prebuilt-layout", test_form_jpg)

    assert response.status_code != 403, "WAF blocked multipart upload"
    assert response.status_code in {200, 202, 400, 415}


def test_binary_upload_to_non_docintel_path_is_not_accepted(
    client: ApimClient, integration_config: IntegrationConfig, test_form_jpg
) -> None:
    """Verify that binary payloads sent to non-Document-Intelligence routes are rejected."""
    require_appgw(integration_config)
    require_key(integration_config, PRIMARY_TENANT)
    ensure_test_file(test_form_jpg)

    response = client.request(
        "POST",
        PRIMARY_TENANT,
        f"/openai/deployments/gpt-4.1-mini/chat/completions?api-version={integration_config.openai_api_version}",
        raw_body=test_form_jpg.read_bytes(),
        extra_headers={"Content-Type": "application/octet-stream"},
    )

    assert response.status_code not in {200, 202}


def test_ai_hub_admin_binary_upload_operation_location_uses_app_gateway_url(
    client: ApimClient, integration_config: IntegrationConfig, test_form_jpg
) -> None:
    """Verify that async binary uploads return an App Gateway-based operation URL."""
    require_appgw(integration_config)
    require_key(integration_config, PRIMARY_TENANT)
    ensure_test_file(test_form_jpg)
    if not client.document_intelligence_accessible(PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")

    response = client.docint_analyze_binary(PRIMARY_TENANT, "prebuilt-layout", test_form_jpg)
    if response.status_code != 202:
        pytest.skip(f"Non-202 response ({response.status_code}) - no Operation-Location to validate")

    op_location = operation_location(response)

    assert op_location
    assert "cognitiveservices.azure.com" not in op_location
    assert "azure-api.net" not in op_location
    assert integration_config.appgw_hostname in op_location
