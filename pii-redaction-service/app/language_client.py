"""
Azure Language Service client — wraps the PII recognition REST API using
DefaultAzureCredential (Managed Identity / CLI) in Azure, or API key auth
when running locally.

We call the REST API directly via httpx rather than the SDK to avoid the
per-document wrapper overhead and to control chunking ourselves.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Any

import httpx
from azure.identity import DefaultAzureCredential

logger = logging.getLogger(__name__)

_SCOPE = "https://cognitiveservices.azure.com/.default"


class LanguageClient:
    """
    Thin async wrapper around the Azure Language /analyze-text:piiDetection endpoint.

    One instance is created at startup and shared for the lifetime of the process.
    httpx.AsyncClient is used for connection pooling and timeout control.

    When ``api_key`` is provided the client sends it as the
    ``Ocp-Apim-Subscription-Key`` header instead of acquiring a bearer token
    via DefaultAzureCredential (local development mode).
    """

    def __init__(
        self,
        endpoint: str,
        api_version: str = "2025-11-15-preview",
        per_batch_timeout: int = 10,
        api_key: str | None = None,
    ) -> None:
        self._endpoint = endpoint.rstrip("/")
        self._api_version = api_version
        self._timeout = per_batch_timeout
        self._api_key = api_key
        self._credential = DefaultAzureCredential() if api_key is None else None
        self._http: httpx.AsyncClient | None = None

    async def __aenter__(self) -> LanguageClient:
        self._http = httpx.AsyncClient(
            base_url=self._endpoint,
            timeout=httpx.Timeout(self._timeout),
            headers={"Content-Type": "application/json"},
        )
        return self

    async def __aexit__(self, *_: Any) -> None:
        if self._http:
            await self._http.aclose()

    async def _get_auth_headers(self) -> dict[str, str]:
        if self._api_key is not None:
            return {"Ocp-Apim-Subscription-Key": self._api_key}
        assert self._credential is not None
        token = await asyncio.to_thread(self._credential.get_token, _SCOPE)
        return {"Authorization": f"Bearer {token.token}"}

    async def analyze_pii(
        self,
        documents: list[dict[str, str]],
        language: str = "en",
        excluded_categories: list[str] | None = None,
    ) -> dict[str, Any]:
        """
        POST to /language/:analyze-text with piiEntityRecognition task.

        ``documents`` must each have ``id`` and ``text`` keys.
        Returns the full API response JSON.
        """
        assert self._http is not None, "Client must be used as async context manager"

        auth_headers = await self._get_auth_headers()
        payload: dict[str, Any] = {
            "kind": "PiiEntityRecognition",
            "analysisInput": {
                "documents": [{"language": language, **doc} for doc in documents],
            },
            "parameters": {
                "domain": "none",
                "redactionPolicy": {"policyKind": "CharacterMask"},
            },
        }
        if excluded_categories:
            payload["parameters"]["excludePiiCategories"] = excluded_categories

        url = f"/language/:analyze-text?api-version={self._api_version}"
        response = await self._http.post(
            url,
            json=payload,
            headers=auth_headers,
        )
        response.raise_for_status()
        return response.json()
