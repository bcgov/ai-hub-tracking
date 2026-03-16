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
import time
from datetime import UTC, datetime
from email.utils import parsedate_to_datetime
from typing import Any

import httpx
from azure.identity import DefaultAzureCredential

logger = logging.getLogger(__name__)

_SCOPE = "https://cognitiveservices.azure.com/.default"


class LanguageServiceRetryError(RuntimeError):
    """Raised when a transient upstream response cannot be retried successfully."""


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
        transient_retry_attempts: int = 4,
        retry_backoff_base_seconds: float = 1.0,
        retry_backoff_max_seconds: float = 10.0,
        api_key: str | None = None,
    ) -> None:
        self._endpoint = endpoint.rstrip("/")
        self._api_version = api_version
        self._timeout = per_batch_timeout
        self._transient_retry_attempts = transient_retry_attempts
        self._retry_backoff_base_seconds = retry_backoff_base_seconds
        self._retry_backoff_max_seconds = retry_backoff_max_seconds
        self._api_key = api_key
        self._credential = DefaultAzureCredential() if api_key is None else None
        self._http: httpx.AsyncClient | None = None

    async def __aenter__(self) -> LanguageClient:
        """Open the shared HTTP client used for Language API requests."""
        self._http = httpx.AsyncClient(
            base_url=self._endpoint,
            timeout=httpx.Timeout(self._timeout),
            headers={"Content-Type": "application/json"},
        )
        return self

    async def __aexit__(self, *_: Any) -> None:
        """Close the shared HTTP client when the application shuts down."""
        if self._http:
            await self._http.aclose()

    async def _get_auth_headers(self) -> dict[str, str]:
        """Return either API-key or bearer-token headers for the next request."""
        if self._api_key is not None:
            return {"Ocp-Apim-Subscription-Key": self._api_key}
        assert self._credential is not None
        token = await asyncio.to_thread(self._credential.get_token, _SCOPE)
        return {"Authorization": f"Bearer {token.token}"}

    def _remaining_request_budget(self, request_deadline: float | None) -> float | None:
        """Return the remaining request budget in seconds, if a deadline was supplied."""
        if request_deadline is None:
            return None
        return max(0.0, request_deadline - time.monotonic())

    def _parse_retry_after_seconds(self, response: httpx.Response) -> float | None:
        """Parse Retry-After headers from Azure Language responses into seconds."""
        header_value = response.headers.get("x-ms-retry-after-ms") or response.headers.get("retry-after-ms")
        if header_value:
            try:
                return max(0.0, float(header_value) / 1000.0)
            except ValueError:
                logger.warning("Ignoring invalid retry-after-ms header", extra={"header_value": header_value})

        header_value = response.headers.get("Retry-After")
        if not header_value:
            return None

        try:
            return max(0.0, float(header_value))
        except ValueError:
            try:
                retry_at = parsedate_to_datetime(header_value)
                if retry_at.tzinfo is None:
                    retry_at = retry_at.replace(tzinfo=UTC)
                return max(0.0, (retry_at - datetime.now(UTC)).total_seconds())
            except (TypeError, ValueError):
                logger.warning("Ignoring invalid Retry-After header", extra={"header_value": header_value})
                return None

    def _get_exponential_backoff_delay(self, retry_number: int) -> float:
        """Calculate the capped exponential backoff delay for a retry attempt."""
        delay = self._retry_backoff_base_seconds * (2 ** (retry_number - 1))
        return min(delay, self._retry_backoff_max_seconds)

    def _get_retry_delay(self, response: httpx.Response, retry_number: int) -> float | None:
        """Return the retry delay for transient responses, or ``None`` if no retry applies."""
        if response.status_code == 429:
            return self._parse_retry_after_seconds(response) or self._get_exponential_backoff_delay(retry_number)
        if 500 <= response.status_code <= 599:
            return self._get_exponential_backoff_delay(retry_number)
        return None

    async def analyze_pii(
        self,
        documents: list[dict[str, str]],
        language: str = "en",
        excluded_categories: list[str] | None = None,
        request_deadline: float | None = None,
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
        retry_count = 0

        while True:
            remaining_budget = self._remaining_request_budget(request_deadline)
            if remaining_budget is not None and remaining_budget <= 0:
                raise TimeoutError("Request deadline exhausted before calling the Language API")

            request_timeout = self._timeout if remaining_budget is None else min(self._timeout, remaining_budget)

            try:
                response = await asyncio.wait_for(
                    self._http.post(
                        url,
                        json=payload,
                        headers=auth_headers,
                    ),
                    timeout=request_timeout,
                )
            except TimeoutError as exc:
                raise TimeoutError("Language API batch request timed out") from exc

            retry_delay = self._get_retry_delay(response, retry_count + 1)
            if retry_delay is None:
                response.raise_for_status()
                return response.json()

            if retry_count >= self._transient_retry_attempts:
                raise LanguageServiceRetryError(
                    f"Language API returned HTTP {response.status_code} after {retry_count + 1} attempt(s)"
                )

            remaining_budget = self._remaining_request_budget(request_deadline)
            if remaining_budget is not None and retry_delay >= remaining_budget:
                raise LanguageServiceRetryError(
                    "Language API returned HTTP "
                    f"{response.status_code} with retry delay {retry_delay:.1f}s but only "
                    f"{remaining_budget:.1f}s remained in the request budget"
                )

            retry_count += 1
            logger.warning(
                "Retrying transient Language API response",
                extra={
                    "status_code": response.status_code,
                    "retry_delay_seconds": round(retry_delay, 3),
                    "attempt": retry_count,
                    "max_retries": self._transient_retry_attempts,
                },
            )
            await asyncio.sleep(retry_delay)
