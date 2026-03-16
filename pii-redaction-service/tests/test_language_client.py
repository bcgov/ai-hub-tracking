from __future__ import annotations

import time
from unittest.mock import AsyncMock

import httpx
import pytest

from app.language_client import LanguageClient, LanguageServiceRetryError


def _success_payload(doc_id: str = "0_0") -> dict[str, object]:
    return {
        "results": {
            "documents": [{"id": doc_id, "redactedText": "[REDACTED]", "entities": []}],
            "errors": [],
        }
    }


@pytest.mark.asyncio
async def test_analyze_pii_retries_429_using_retry_after(monkeypatch: pytest.MonkeyPatch) -> None:
    # Given a transient 429 response with Retry-After guidance.
    async with LanguageClient(
        endpoint="https://example.cognitiveservices.azure.com",
        api_version="2024-11-01",
        api_key="test-key",
        transient_retry_attempts=2,
    ) as client:
        request = httpx.Request("POST", "https://example.cognitiveservices.azure.com/language/:analyze-text")
        client._http.post = AsyncMock(
            side_effect=[
                httpx.Response(429, headers={"Retry-After": "2"}, request=request),
                httpx.Response(200, json=_success_payload(), request=request),
            ]
        )
        sleep = AsyncMock()
        monkeypatch.setattr("app.language_client.asyncio.sleep", sleep)

        # When the client analyzes a document within the request deadline.
        result = await client.analyze_pii(
            documents=[{"id": "0_0", "text": "hello"}],
            request_deadline=time.monotonic() + 10,
        )

        # Then the client retries once, honors Retry-After, and returns success.
        assert result == _success_payload()
        sleep.assert_awaited_once_with(2.0)
        assert client._http.post.await_count == 2


@pytest.mark.asyncio
async def test_analyze_pii_retries_5xx_with_exponential_backoff(monkeypatch: pytest.MonkeyPatch) -> None:
    # Given transient 5xx responses before a successful retry.
    async with LanguageClient(
        endpoint="https://example.cognitiveservices.azure.com",
        api_version="2024-11-01",
        api_key="test-key",
        transient_retry_attempts=3,
        retry_backoff_base_seconds=1,
        retry_backoff_max_seconds=8,
    ) as client:
        request = httpx.Request("POST", "https://example.cognitiveservices.azure.com/language/:analyze-text")
        client._http.post = AsyncMock(
            side_effect=[
                httpx.Response(503, request=request),
                httpx.Response(502, request=request),
                httpx.Response(200, json=_success_payload(), request=request),
            ]
        )
        sleep = AsyncMock()
        monkeypatch.setattr("app.language_client.asyncio.sleep", sleep)

        # When the client analyzes a document within the request deadline.
        result = await client.analyze_pii(
            documents=[{"id": "0_0", "text": "hello"}],
            request_deadline=time.monotonic() + 10,
        )

        # Then exponential backoff is applied across retries before success.
        assert result == _success_payload()
        assert [call.args[0] for call in sleep.await_args_list] == [1, 2]
        assert client._http.post.await_count == 3


@pytest.mark.asyncio
async def test_analyze_pii_fails_when_retry_after_exceeds_remaining_budget(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    # Given a Retry-After value that exceeds the remaining request budget.
    async with LanguageClient(
        endpoint="https://example.cognitiveservices.azure.com",
        api_version="2024-11-01",
        api_key="test-key",
        transient_retry_attempts=2,
    ) as client:
        request = httpx.Request("POST", "https://example.cognitiveservices.azure.com/language/:analyze-text")
        client._http.post = AsyncMock(side_effect=[httpx.Response(429, headers={"Retry-After": "5"}, request=request)])
        sleep = AsyncMock()
        monkeypatch.setattr("app.language_client.asyncio.sleep", sleep)

        # When the client analyzes a document with too little remaining time.
        with pytest.raises(LanguageServiceRetryError, match="remained in the request budget"):
            await client.analyze_pii(
                documents=[{"id": "0_0", "text": "hello"}],
                request_deadline=time.monotonic() + 1,
            )

        # Then the client fails immediately instead of sleeping past the deadline.
        sleep.assert_not_awaited()


@pytest.mark.asyncio
async def test_analyze_pii_honors_retry_after_zero(monkeypatch: pytest.MonkeyPatch) -> None:
    # Given a 429 response with Retry-After: 0 (retry immediately).
    async with LanguageClient(
        endpoint="https://example.cognitiveservices.azure.com",
        api_version="2024-11-01",
        api_key="test-key",
        transient_retry_attempts=2,
        retry_backoff_base_seconds=5.0,
    ) as client:
        request = httpx.Request("POST", "https://example.cognitiveservices.azure.com/language/:analyze-text")
        client._http.post = AsyncMock(
            side_effect=[
                httpx.Response(429, headers={"Retry-After": "0"}, request=request),
                httpx.Response(200, json=_success_payload(), request=request),
            ]
        )
        sleep = AsyncMock()
        monkeypatch.setattr("app.language_client.asyncio.sleep", sleep)

        # When the client analyzes a document within the request deadline.
        result = await client.analyze_pii(
            documents=[{"id": "0_0", "text": "hello"}],
            request_deadline=time.monotonic() + 10,
        )

        # Then the client retries with zero delay (not exponential backoff).
        assert result == _success_payload()
        sleep.assert_awaited_once_with(0.0)
        assert client._http.post.await_count == 2


@pytest.mark.asyncio
async def test_analyze_pii_catches_httpx_timeout_exception() -> None:
    # Given the httpx client raises its own TimeoutException.
    async with LanguageClient(
        endpoint="https://example.cognitiveservices.azure.com",
        api_version="2024-11-01",
        api_key="test-key",
    ) as client:
        client._http.post = AsyncMock(
            side_effect=httpx.ReadTimeout("read timed out"),
        )

        # When the client analyzes a document.
        with pytest.raises(TimeoutError, match="Language API batch request timed out"):
            await client.analyze_pii(
                documents=[{"id": "0_0", "text": "hello"}],
                request_deadline=time.monotonic() + 10,
            )
