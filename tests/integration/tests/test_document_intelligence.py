from __future__ import annotations

import pytest

from ai_hub_integration.client import ApimClient
from ai_hub_integration.config import IntegrationConfig

from .support import (
    PRIMARY_TENANT,
    SAMPLE_PDF_BASE64,
    assert_status,
    direct_request,
    document_intelligence_accessible,
    ensure_test_file,
    operation_location,
    require_appgw,
    require_key,
    response_json,
)

pytestmark = [pytest.mark.live]


def _docint_path(config: IntegrationConfig, model: str) -> str:
    """Build the Document Intelligence analyze path for a model."""
    return f"/documentintelligence/documentModels/{model}:analyze?api-version={config.docint_api_version}"


def _wait_for_docint_result(client: ApimClient, tenant: str, initial_response) -> dict:
    """Resolve a Document Intelligence request into its final result payload."""
    if initial_response.status_code == 200:
        return response_json(initial_response)

    assert initial_response.status_code == 202, initial_response.text
    op_location = operation_location(initial_response)
    assert op_location, "Missing Operation-Location header in 202 response"
    op_path = client.extract_operation_path(tenant, op_location)
    final_response = client.wait_for_operation(tenant, op_path, 60)
    return response_json(final_response)


def test_ai_hub_admin_document_analysis_endpoint_returns_200_or_202(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that the analyze endpoint accepts a standard layout request."""
    require_key(integration_config, PRIMARY_TENANT)
    if not document_intelligence_accessible(client, integration_config, PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")

    response = client.docint_analyze(PRIMARY_TENANT, "prebuilt-layout", SAMPLE_PDF_BASE64)

    assert response.status_code in {200, 202}


def test_ai_hub_admin_document_analysis_returns_operation_location_or_direct_200(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that analysis returns either a direct success or an operation-location header."""
    require_key(integration_config, PRIMARY_TENANT)
    if not document_intelligence_accessible(client, integration_config, PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")

    response = client.docint_analyze(PRIMARY_TENANT, "prebuilt-layout", SAMPLE_PDF_BASE64)

    if response.status_code == 200:
        return

    assert response.status_code == 202
    assert operation_location(response)


def test_ai_hub_admin_operation_location_uses_app_gateway_url_not_backend_url(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that async Document Intelligence polling stays on the front-door hostname."""
    require_key(integration_config, PRIMARY_TENANT)
    require_appgw(integration_config)
    if not document_intelligence_accessible(client, integration_config, PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")

    response = client.docint_analyze(PRIMARY_TENANT, "prebuilt-layout", SAMPLE_PDF_BASE64)
    if response.status_code == 200:
        pytest.skip("Direct 200 response - no async operation")

    assert response.status_code == 202
    op_location = operation_location(response)
    assert op_location
    assert "cognitiveservices.azure.com" not in op_location
    assert "azure-api.net" not in op_location
    assert integration_config.appgw_hostname in op_location
    assert PRIMARY_TENANT in op_location


def test_ai_hub_admin_document_analysis_accepts_json_input(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that JSON base64 input is accepted by the analyze endpoint."""
    require_key(integration_config, PRIMARY_TENANT)
    if not document_intelligence_accessible(client, integration_config, PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")

    response = client.docint_analyze(PRIMARY_TENANT, "prebuilt-layout", SAMPLE_PDF_BASE64)

    assert response.status_code in {200, 202}


def test_ai_hub_admin_prebuilt_invoice_model_is_accessible(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that the prebuilt invoice model is reachable through the shared endpoint."""
    require_key(integration_config, PRIMARY_TENANT)
    if not document_intelligence_accessible(client, integration_config, PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")

    response = client.docint_analyze(PRIMARY_TENANT, "prebuilt-invoice", SAMPLE_PDF_BASE64)

    assert response.status_code in {200, 202, 400}


def test_ai_hub_admin_prebuilt_read_model_is_accessible(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that the prebuilt read model is reachable through the shared endpoint."""
    require_key(integration_config, PRIMARY_TENANT)
    if not document_intelligence_accessible(client, integration_config, PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")

    response = client.docint_analyze(PRIMARY_TENANT, "prebuilt-read", SAMPLE_PDF_BASE64)

    assert response.status_code in {200, 202}


def test_ai_hub_admin_full_async_flow_extracts_expected_text_from_jpg(
    client: ApimClient, integration_config: IntegrationConfig, test_form_jpg
) -> None:
    """Verify that the async JPG flow extracts expected text from the sample form."""
    require_key(integration_config, PRIMARY_TENANT)
    if not document_intelligence_accessible(client, integration_config, PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")
    ensure_test_file(test_form_jpg)

    payload = _wait_for_docint_result(
        client, PRIMARY_TENANT, client.docint_analyze_file(PRIMARY_TENANT, "prebuilt-layout", test_form_jpg)
    )
    content = payload["analyzeResult"]["content"]

    assert "Monthly Report" in content
    assert "Declaration" in content


def test_ai_hub_admin_async_flow_returns_valid_analyze_result_structure(
    client: ApimClient, integration_config: IntegrationConfig, test_form_jpg
) -> None:
    """Verify that async analysis returns the expected top-level result structure."""
    require_key(integration_config, PRIMARY_TENANT)
    if not document_intelligence_accessible(client, integration_config, PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")
    ensure_test_file(test_form_jpg)

    payload = _wait_for_docint_result(
        client, PRIMARY_TENANT, client.docint_analyze_file(PRIMARY_TENANT, "prebuilt-layout", test_form_jpg)
    )

    assert payload["status"] in {"succeeded", "completed"}
    assert len(payload["analyzeResult"]["pages"]) >= 1
    assert len(payload["analyzeResult"]["content"]) > 0


def test_ai_hub_admin_async_flow_extracts_multiple_expected_fields(
    client: ApimClient, integration_config: IntegrationConfig, test_form_jpg
) -> None:
    """Verify that the sample form yields several expected phrases after extraction."""
    require_key(integration_config, PRIMARY_TENANT)
    if not document_intelligence_accessible(client, integration_config, PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")
    ensure_test_file(test_form_jpg)

    payload = _wait_for_docint_result(
        client, PRIMARY_TENANT, client.docint_analyze_file(PRIMARY_TENANT, "prebuilt-layout", test_form_jpg)
    )
    content = payload["analyzeResult"]["content"]

    assert "Monthly Report" in content
    assert "Ministry of Social Development" in content
    assert "Since your last declaration" in content
    assert "Declare all income" in content
    assert "Declaration" in content


def test_ai_hub_admin_invalid_base64_returns_400(client: ApimClient, integration_config: IntegrationConfig) -> None:
    """Verify that invalid base64 payloads are rejected with HTTP 400."""
    require_key(integration_config, PRIMARY_TENANT)
    if not document_intelligence_accessible(client, integration_config, PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")

    response = client.docint_analyze(PRIMARY_TENANT, "prebuilt-layout", "not-valid-base64!!!")

    assert_status(response, 400)


def test_ai_hub_admin_empty_body_returns_400(client: ApimClient, integration_config: IntegrationConfig) -> None:
    """Verify that an empty JSON body is rejected by the analyze endpoint."""
    require_key(integration_config, PRIMARY_TENANT)
    if not document_intelligence_accessible(client, integration_config, PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")

    response = client.request("POST", PRIMARY_TENANT, _docint_path(integration_config, "prebuilt-layout"), json_body={})

    assert_status(response, 400)


def test_ai_hub_admin_invalid_model_returns_404(client: ApimClient, integration_config: IntegrationConfig) -> None:
    """Verify that an unknown Document Intelligence model name returns 404."""
    require_key(integration_config, PRIMARY_TENANT)
    if not document_intelligence_accessible(client, integration_config, PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")

    response = client.docint_analyze(PRIMARY_TENANT, "nonexistent-model", SAMPLE_PDF_BASE64)

    assert_status(response, 404)


def test_ai_hub_admin_document_analysis_without_subscription_key_returns_auth_failure(
    integration_config: IntegrationConfig,
) -> None:
    """Verify that unauthenticated analyze requests fail authorization."""
    url = f"{integration_config.apim_gateway_url}/{PRIMARY_TENANT}{_docint_path(integration_config, 'prebuilt-layout')}"
    response = direct_request(
        url,
        method="POST",
        headers={"Content-Type": "application/json"},
        json_body={"base64Source": SAMPLE_PDF_BASE64},
    )

    assert response.status_code in {401, 403, 404}


def test_ai_hub_admin_supported_api_version_is_accepted(
    client: ApimClient, integration_config: IntegrationConfig
) -> None:
    """Verify that the configured Document Intelligence API version is accepted."""
    require_key(integration_config, PRIMARY_TENANT)
    if not document_intelligence_accessible(client, integration_config, PRIMARY_TENANT):
        pytest.skip("Document Intelligence backend not accessible")

    response = client.docint_analyze(PRIMARY_TENANT, "prebuilt-layout", SAMPLE_PDF_BASE64)
    if response.status_code != 400:
        return

    body = response.text.lower()
    assert "api-version" not in body
