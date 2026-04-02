from __future__ import annotations

import base64
import json
import time
from pathlib import Path
from typing import Any

import requests
from azure.identity import AzureCliCredential, DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

from .config import IntegrationConfig, uses_max_completion_tokens

APIM_REQUEST_TIMEOUT_SECONDS = 120
MAX_RETRIES = 5
RETRY_DELAY_SECONDS = 5
BACKOFF_MULTIPLIER = 2
MAX_RETRY_DELAY_SECONDS = 60


class ApimClient:
    def __init__(self, config: IntegrationConfig) -> None:
        """Initialize an APIM client bound to the loaded integration configuration.

        The client owns a shared `requests.Session` so tests can reuse proxy
        configuration, connection pooling, and refreshed subscription keys across
        multiple live requests.
        """
        self.config = config
        self.session = requests.Session()
        self.session.trust_env = True
        self._credential = None
        self._secret_client = None

    def _build_url(self, tenant: str, path: str) -> str:
        """Build the absolute tenant-scoped APIM URL for a relative path."""
        return f"{self.config.apim_gateway_url.rstrip('/')}/{tenant}{path}"

    def _secret_service(self) -> SecretClient:
        """Create or reuse the Key Vault client used for key-refresh fallback.

        The method prefers `DefaultAzureCredential` without interactive browser
        fallback and uses `AzureCliCredential` when local developer auth is the
        only available option.
        """
        if self._secret_client is None:
            vault_url = f"https://{self.config.hub_keyvault_name}.vault.azure.net"
            try:
                credential = DefaultAzureCredential(exclude_interactive_browser_credential=True)
                credential.get_token("https://vault.azure.net/.default")
            except Exception:
                credential = AzureCliCredential()
            self._credential = credential
            self._secret_client = SecretClient(vault_url=vault_url, credential=credential)
        return self._secret_client

    def refresh_tenant_key_from_vault(self, tenant: str, preferred_slot: str | None = None) -> bool:
        """Refresh a tenant APIM key from Key Vault and update local config state.

        When rotation metadata is available, the helper probes the slot expected
        to be safe first and then falls back to the alternate slot.
        """
        if not self.config.enable_vault_key_fallback or not self.config.hub_keyvault_name:
            return False

        safe_slot = preferred_slot
        secret_service = self._secret_service()
        if not safe_slot:
            try:
                metadata_secret = secret_service.get_secret(f"{tenant}-apim-rotation-metadata")
                metadata = json.loads(metadata_secret.value)
                safe_slot = metadata.get("safe_slot")
            except Exception:
                safe_slot = None

        if safe_slot == "primary":
            candidates = [f"{tenant}-apim-primary-key", f"{tenant}-apim-secondary-key"]
        elif safe_slot == "secondary":
            candidates = [f"{tenant}-apim-secondary-key", f"{tenant}-apim-primary-key"]
        else:
            candidates = [f"{tenant}-apim-primary-key", f"{tenant}-apim-secondary-key"]

        for candidate in candidates:
            try:
                refreshed = secret_service.get_secret(candidate).value
            except Exception:
                continue
            if refreshed:
                self.config.set_subscription_key(tenant, refreshed)
                return True

        return False

    def _headers(self, tenant: str, auth_mode: str, extra_headers: dict[str, str] | None = None) -> dict[str, str]:
        """Build request headers for the selected tenant and authentication mode."""
        headers = {
            "Accept": "application/json",
        }
        key = self.config.get_subscription_key(tenant)
        if auth_mode == "api-key":
            headers["api-key"] = key
        elif auth_mode == "bearer":
            headers["Authorization"] = f"Bearer {key}"
        elif auth_mode == "ocp":
            headers["Ocp-Apim-Subscription-Key"] = key
        else:
            raise ValueError(f"Unsupported auth mode: {auth_mode}")

        if extra_headers:
            headers.update(extra_headers)
        return headers

    def request(
        self,
        method: str,
        tenant: str,
        path: str,
        *,
        auth_mode: str = "api-key",
        json_body: dict[str, Any] | None = None,
        raw_body: str | bytes | None = None,
        files: dict[str, Any] | None = None,
        extra_headers: dict[str, str] | None = None,
        timeout: int = APIM_REQUEST_TIMEOUT_SECONDS,
        retry: bool = False,
    ) -> requests.Response:
        """Send an APIM request with retry and key-refresh behavior.

        The method retries transient request failures, 429 responses, and most
        503 responses, while allowing a one-time Key Vault refresh when APIM
        rejects a cached key with 401.
        """
        url = self._build_url(tenant, path)
        headers = self._headers(tenant, auth_mode, extra_headers)
        if json_body is not None or (raw_body is not None and isinstance(raw_body, str)):
            headers.setdefault("Content-Type", "application/json")

        retries = 0
        current_delay = RETRY_DELAY_SECONDS
        refreshed_key_once = False

        while True:
            try:
                response = self.session.request(
                    method,
                    url,
                    headers=headers,
                    json=json_body,
                    data=raw_body,
                    files=files,
                    timeout=timeout,
                )
            except requests.RequestException as exc:
                if not retry or retries >= MAX_RETRIES:
                    raise RuntimeError(f"Request to {url} failed") from exc
                retries += 1
                time.sleep(current_delay)
                current_delay = min(current_delay * BACKOFF_MULTIPLIER, MAX_RETRY_DELAY_SECONDS)
                continue
            if response.status_code == 401 and not refreshed_key_once and self.refresh_tenant_key_from_vault(tenant):
                headers = self._headers(tenant, auth_mode, extra_headers)
                if json_body is not None or (raw_body is not None and isinstance(raw_body, str)):
                    headers.setdefault("Content-Type", "application/json")
                refreshed_key_once = True
                continue

            if not retry:
                return response

            if response.status_code == 429 and retries < MAX_RETRIES:
                retries += 1
                retry_after = response.headers.get("Retry-After")
                delay = int(retry_after) if retry_after and retry_after.isdigit() else current_delay
                time.sleep(delay)
                current_delay = min(current_delay * BACKOFF_MULTIPLIER, MAX_RETRY_DELAY_SECONDS)
                continue

            if response.status_code == 503 and retries < MAX_RETRIES:
                try:
                    payload = response.json()
                except ValueError:
                    payload = {}
                error_code = (payload.get("error") or {}).get("code") or ""
                if error_code != "PiiRedactionFailed":
                    retries += 1
                    time.sleep(current_delay)
                    current_delay = min(current_delay * BACKOFF_MULTIPLIER, MAX_RETRY_DELAY_SECONDS)
                    continue

            return response

    def chat_completion(
        self,
        tenant: str,
        model: str,
        message: str,
        max_tokens: int = 50,
        *,
        system_prompt: str | None = None,
        auth_mode: str = "api-key",
        stream: bool = False,
    ) -> requests.Response:
        """Call the deployment-based chat completions route for a tenant model."""
        messages: list[dict[str, str]] = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": message})
        body: dict[str, Any] = {"messages": messages}

        if uses_max_completion_tokens(model):
            body["max_completion_tokens"] = max_tokens
        else:
            body["max_tokens"] = max_tokens
            body["temperature"] = 0.7

        if stream:
            body["stream"] = True

        path = f"/openai/deployments/{model}/chat/completions?api-version={self.config.openai_api_version}"
        return self.request("POST", tenant, path, auth_mode=auth_mode, json_body=body, retry=True)

    def chat_completion_v1(
        self,
        tenant: str,
        model: str,
        message: str,
        max_tokens: int = 50,
        *,
        auth_mode: str = "api-key",
        stream: bool = False,
    ) -> requests.Response:
        """Call the OpenAI-compatible `/openai/v1/chat/completions` route."""
        body: dict[str, Any] = {
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
        return self.request(
            "POST",
            tenant,
            "/openai/v1/chat/completions",
            auth_mode=auth_mode,
            json_body=body,
            retry=True,
        )

    def document_intelligence_accessible(self, tenant: str) -> bool:
        """Probe whether Document Intelligence is reachable for a tenant.

        The probe treats 200, 202, and 400 as evidence that routing reached the
        backend, even if the sample payload itself is not valid for extraction.
        """
        response = self.docint_analyze(tenant, "prebuilt-layout", "dGVzdA==")
        return response.status_code in {200, 202, 400}

    def docint_analyze(self, tenant: str, model: str, base64_content: str) -> requests.Response:
        """Submit a JSON Document Intelligence analyze request using base64 input."""
        path = f"/documentintelligence/documentModels/{model}:analyze?api-version={self.config.docint_api_version}"
        body = {"base64Source": base64_content}
        return self.request("POST", tenant, path, json_body=body)

    def docint_analyze_ocp(self, tenant: str, model: str, base64_content: str) -> requests.Response:
        """Submit the same analyze request using the legacy OCP auth header."""
        path = f"/documentintelligence/documentModels/{model}:analyze?api-version={self.config.docint_api_version}"
        body = {"base64Source": base64_content}
        return self.request("POST", tenant, path, auth_mode="ocp", json_body=body)

    def docint_analyze_file(self, tenant: str, model: str, file_path: Path) -> requests.Response:
        """Read a local file, encode it as base64, and submit a JSON analyze request."""
        content = base64.b64encode(file_path.read_bytes()).decode("utf-8")
        return self.docint_analyze(tenant, model, content)

    def docint_analyze_binary(self, tenant: str, model: str, file_path: Path) -> requests.Response:
        """Upload a document as raw binary bytes for WAF and backend validation."""
        path = f"/documentintelligence/documentModels/{model}:analyze?api-version={self.config.docint_api_version}"
        return self.request(
            "POST",
            tenant,
            path,
            raw_body=file_path.read_bytes(),
            extra_headers={"Content-Type": "application/octet-stream"},
        )

    def docint_analyze_pdf(self, tenant: str, model: str, file_path: Path) -> requests.Response:
        """Upload a document while explicitly sending `application/pdf`."""
        path = f"/documentintelligence/documentModels/{model}:analyze?api-version={self.config.docint_api_version}"
        return self.request(
            "POST",
            tenant,
            path,
            raw_body=file_path.read_bytes(),
            extra_headers={"Content-Type": "application/pdf"},
        )

    def docint_analyze_multipart(self, tenant: str, model: str, file_path: Path) -> requests.Response:
        """Upload a document as multipart form data for path and WAF coverage."""
        path = f"/documentintelligence/documentModels/{model}:analyze?api-version={self.config.docint_api_version}"
        with file_path.open("rb") as handle:
            return self.request("POST", tenant, path, files={"file": handle})

    def extract_operation_path(self, tenant: str, operation_url: str) -> str:
        """Convert a fully-qualified operation URL into a tenant-relative path."""
        prefix = f"{self.config.apim_gateway_url.rstrip('/')}/{tenant}"
        return operation_url.removeprefix(prefix)

    def wait_for_operation(self, tenant: str, operation_path: str, max_wait_seconds: int = 60) -> requests.Response:
        """Poll an async operation until success, failure, or timeout."""
        deadline = time.time() + max_wait_seconds
        while time.time() < deadline:
            response = self.request("GET", tenant, operation_path)
            payload = response.json()
            status = payload.get("status")
            if status in {"succeeded", "completed"}:
                return response
            if status == "failed":
                raise AssertionError(f"Operation failed: {payload}")
            time.sleep(2)
        raise AssertionError(f"Operation timed out after {max_wait_seconds} seconds")


__all__ = ["ApimClient"]
