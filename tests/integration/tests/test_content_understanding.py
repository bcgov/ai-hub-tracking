"""Live coverage for Azure Content Understanding routed through APIM.

Content Understanding runs on a tenant-scoped Foundry (AIServices) account in
Canada Central. These tests read the tenant-info endpoint to discover whether
the primary tenant has the service enabled in the target environment and skip
otherwise, so the suite is safe to run in every environment.
"""

from __future__ import annotations

import base64

import pytest

from ai_hub_integration.client import ApimClient
from ai_hub_integration.config import IntegrationConfig

from .support import (
    PRIMARY_TENANT,
    ensure_test_file,
    operation_location,
    require_appgw,
    require_key,
    response_json,
)

pytestmark = [pytest.mark.live]

LAYOUT_ANALYZER = "prebuilt-layout"


@pytest.fixture(scope="module")
def cu_service(client: ApimClient, integration_config: IntegrationConfig) -> dict:
    """Return the tenant-info Content Understanding block, skipping when the service is disabled."""
    require_key(integration_config, PRIMARY_TENANT)
    response = client.request("GET", PRIMARY_TENANT, "/internal/tenant-info")
    assert response.status_code == 200, response.text
    service = response_json(response)["services"].get("content_understanding") or {}
    if not service.get("enabled"):
        pytest.skip("Content Understanding is not enabled for the primary tenant in this environment")
    return service


@pytest.fixture(scope="module")
def cu_defaults_applied(client: ApimClient, cu_service: dict) -> dict:
    """Apply the tenant's model-deployment defaults once (idempotent PATCH) before analyzing."""
    response = client.content_understanding_set_defaults(PRIMARY_TENANT, cu_service["model_deployments"])
    assert response.status_code == 200, response.text
    return response_json(response)


def _wait_for_cu_result(client: ApimClient, initial_response) -> dict:
    """Resolve an analyze request into its final result payload via the rewritten Operation-Location."""
    assert initial_response.status_code == 202, initial_response.text
    op_location = operation_location(initial_response)
    assert op_location, "Missing Operation-Location header in 202 response"
    op_path = client.extract_operation_path(PRIMARY_TENANT, op_location)
    final_response = client.wait_for_operation(PRIMARY_TENANT, op_path, 120)
    return response_json(final_response)


def test_defaults_patch_maps_prebuilt_aliases_to_tenant_deployments(
    client: ApimClient, cu_service: dict, cu_defaults_applied: dict
) -> None:
    """Verify the defaults PATCH is accepted and a follow-up GET reflects the tenant mapping."""
    response = client.content_understanding_get_defaults(PRIMARY_TENANT)
    assert response.status_code == 200, response.text

    deployments = response_json(response)["modelDeployments"]
    for alias, deployment in cu_service["model_deployments"].items():
        assert deployments.get(alias) == deployment


def test_analyze_returns_202_with_gateway_operation_location(
    client: ApimClient, integration_config: IntegrationConfig, cu_defaults_applied: dict, test_form_small_jpg
) -> None:
    """Verify async polling URLs point at the front door, not the private backend host."""
    require_appgw(integration_config)
    ensure_test_file(test_form_small_jpg)

    content = base64.b64encode(test_form_small_jpg.read_bytes()).decode("utf-8")
    response = client.content_understanding_analyze(PRIMARY_TENANT, LAYOUT_ANALYZER, content, "image/jpeg")

    assert response.status_code == 202, response.text
    op_location = operation_location(response)
    assert "/contentunderstanding/analyzerResults/" in op_location
    assert "cognitiveservices.azure.com" not in op_location
    assert "services.ai.azure.com" not in op_location
    assert "azure-api.net" not in op_location
    assert integration_config.appgw_hostname in op_location
    assert PRIMARY_TENANT in op_location


def test_full_async_layout_flow_extracts_expected_text_from_jpg(
    client: ApimClient, cu_defaults_applied: dict, test_form_jpg
) -> None:
    """Verify the JSON analyze flow completes and returns markdown with the expected form text."""
    ensure_test_file(test_form_jpg)

    content = base64.b64encode(test_form_jpg.read_bytes()).decode("utf-8")
    payload = _wait_for_cu_result(
        client, client.content_understanding_analyze(PRIMARY_TENANT, LAYOUT_ANALYZER, content, "image/jpeg")
    )

    assert payload["status"] == "Succeeded"
    markdown = "\n".join(item.get("markdown", "") for item in payload["result"]["contents"])
    assert "Monthly Report" in markdown


def test_analyze_binary_accepts_raw_image_upload(
    client: ApimClient, cu_defaults_applied: dict, test_form_small_jpg
) -> None:
    """Verify raw binary uploads pass WAF/APIM and reach the Content Understanding backend."""
    ensure_test_file(test_form_small_jpg)

    response = client.content_understanding_analyze_binary(
        PRIMARY_TENANT, LAYOUT_ANALYZER, test_form_small_jpg, "image/jpeg"
    )

    assert response.status_code == 202, response.text
    assert operation_location(response)
