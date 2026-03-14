"""
Azure Language Service client — wraps the PII recognition REST API using
DefaultAzureCredential (Managed Identity in production, CLI/env in dev).

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
    """

    def __init__(
        self,
        endpoint: str,
        api_version: str = "2025-11-15-preview",
        per_batch_timeout: int = 10,
    ) -> None:
        self._endpoint = endpoint.rstrip("/")
        self._api_version = api_version
        self._timeout = per_batch_timeout
        self._credential = DefaultAzureCredential()
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

    async def _get_token(self) -> str:
        token = await asyncio.to_thread(self._credential.get_token, _SCOPE)
        return token.token

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

        token = await self._get_token()
        payload: dict[str, Any] = {
            "kind": "PiiEntityRecognition",
            "analysisInput": {
                "documents": [{"language": language, **doc} for doc in documents],
            },
            "parameters": {
                "domain": "none",
            },
        }
        if excluded_categories:
            payload["parameters"]["piiCategories"] = excluded_categories

        url = f"/language/:analyze-text?api-version={self._api_version}"
        response = await self._http.post(
            url,
            json=payload,
            headers={"Authorization": f"Bearer {token}"},
        )
        response.raise_for_status()
        return response.json()
