from __future__ import annotations

import json
import os
import socket
import ssl
from pathlib import Path
from urllib.parse import urlsplit

import pytest
import requests

from ai_hub_integration.client import ApimClient
from ai_hub_integration.config import IntegrationConfig

PRIMARY_TENANT = "ai-hub-admin"
LOW_QUOTA_TENANT = "nr-dap-fish-wildlife"
CROSS_KEY_TARGET_MODEL = "gpt-5-mini"

SAMPLE_PDF_BASE64 = "JVBERi0xLjQKMSAwIG9iago8PAovVHlwZSAvQ2F0YWxvZwovUGFnZXMgMiAwIFIKPj4KZW5kb2JqCjIgMCBvYmoKPDwKL1R5cGUgL1BhZ2VzCi9LaWRzIFszIDAgUl0KL0NvdW50IDEKPJ4KZW5kb2JqCjMgMCBvYmoKPDwKL1R5cGUgL1BhZ2UKL1BhcmVudCAyIDAgUgovTWVkaWFCb3ggWzAgMCA2MTIgNzkyXQovQ29udGVudHMgNCAwIFIKL1Jlc291cmNlcwo8PAovRm9udAo8PAovRjEgNSAwIFIKPj4KPj4KPj4KZW5kb2JqCjQgMCBvYmoKPDwKL0xlbmd0aCA0NAo+PgpzdHJlYW0KQlQKL0YxIDEyIFRmCjEwMCA3MDAgVGQKKFRlc3QgRG9jdW1lbnQpIFRqCkVUCmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iago8PAovVHlwZSAvRm9udAovU3VidHlwZSAvVHlwZTEKL0Jhc2VGb250IC9IZWx2ZXRpY2EKPJ4KZW5kb2JqCnhyZWYKMCA2CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAwOSAwMDAwMCBuIAowMDAwMDAwMDU4IDAwMDAwIG4gCjAwMDAwMDAxMTUgMDAwMDAgbiAKMDAwMDAwMDI4MCAwMDAwMCBuIAowMDAwMDAwMzczIDAwMDAwIG4gCnRyYWlsZXIKPDwKL1NpemUgNgovUm9vdCAxIDAgUgo+PgpzdGFydHhyZWYKNDQ4CiUlRU9G"

MISTRAL_OCR_SAMPLE_PDF_BASE64 = SAMPLE_PDF_BASE64


def require_key(config: IntegrationConfig, tenant: str) -> None:
    if not config.get_subscription_key(tenant):
        pytest.skip(f"No subscription key for tenant: {tenant}")


def require_appgw(config: IntegrationConfig) -> None:
    if not config.appgw_deployed:
        pytest.skip(f"App Gateway is not deployed for TEST_ENV={config.environment}")


def deployed_chat_models(config: IntegrationConfig, tenant: str) -> list[str]:
    models = config.get_tenant_chat_models(tenant)
    if not models:
        pytest.skip(f"No chat models found for tenant: {tenant}")
    return models


def deployed_deployments_chat_models(config: IntegrationConfig, tenant: str) -> list[str]:
    models = config.get_tenant_deployments_chat_models(tenant)
    if not models:
        pytest.skip(f"No deployment-route chat models found for tenant: {tenant}")
    return models


def response_json(response: requests.Response) -> dict:
    if not response.text:
        return {}
    sanitized = response.text.replace("[REDACTED_PHONE]", "0")
    return json.loads(sanitized)


def assert_status(response: requests.Response, expected: int) -> None:
    if response.status_code == 429 and os.getenv("SKIP_ON_RATE_LIMIT", "false").lower() == "true":
        pytest.skip("Rate limited (429) - skipping test")
    assert response.status_code == expected, response.text


def direct_request(
    url: str,
    *,
    method: str = "GET",
    headers: dict[str, str] | None = None,
    json_body: dict | None = None,
    data: str | bytes | None = None,
    timeout: int = 30,
) -> requests.Response:
    return requests.request(method, url, headers=headers, json=json_body, data=data, timeout=timeout)


def operation_location(response: requests.Response) -> str:
    return response.headers.get("Operation-Location") or response.headers.get("operation-location") or ""


def document_intelligence_accessible(client: ApimClient, config: IntegrationConfig, tenant: str) -> bool:
    require_key(config, tenant)
    return client.document_intelligence_accessible(tenant)


def is_azure_key_vault_uri(uri: str) -> bool:
    parsed = urlsplit(uri)
    hostname = parsed.hostname or ""
    return (
        parsed.scheme == "https"
        and parsed.path in {"", "/"}
        and not parsed.query
        and not parsed.fragment
        and (hostname == "vault.azure.net" or hostname.endswith(".vault.azure.net"))
    )


def get_server_certificate(hostname: str) -> dict:
    context = ssl.create_default_context()
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    with (
        socket.create_connection((hostname, 443), timeout=10) as sock,
        context.wrap_socket(sock, server_hostname=hostname) as tls_socket,
    ):
        cert = tls_socket.getpeercert()
    return cert


def ensure_test_file(path: Path) -> Path:
    if not path.exists():
        pytest.skip(f"Test fixture not found: {path}")
    return path
