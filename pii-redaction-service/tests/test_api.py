"""
Integration-style tests for the /redact endpoint using FastAPI TestClient.
The Language API client is mocked so no real Azure calls are made.
"""

from __future__ import annotations

from typing import Any
from unittest.mock import AsyncMock, patch

import pytest
from fastapi.testclient import TestClient

# ---------------------------------------------------------------------------
# Fixture: patch LanguageClient and Settings so no real Azure creds needed
# ---------------------------------------------------------------------------


MOCK_SETTINGS_ENV = {
    "PII_LANGUAGE_ENDPOINT": "https://mock.cognitiveservices.azure.com",
}


def _make_language_response(doc_ids: list[str]) -> dict[str, Any]:
    """Build a minimal Language API response for the given doc IDs."""
    return {
        "results": {
            "documents": [{"id": did, "redactedText": f"[REDACTED_{did}]"} for did in doc_ids],
            "errors": [],
        }
    }


@pytest.fixture()
def client(monkeypatch):
    for k, v in MOCK_SETTINGS_ENV.items():
        monkeypatch.setenv(k, v)

    # Reset cached settings singleton so env vars take effect
    import app.config as cfg_module

    cfg_module._settings = None

    from app.main import app as fastapi_app

    # Patch LanguageClient.analyze_pii to return a mock response
    with patch("app.main.LanguageClient") as MockClient:
        mock_instance = AsyncMock()
        mock_instance.__aenter__ = AsyncMock(return_value=mock_instance)
        mock_instance.__aexit__ = AsyncMock(return_value=None)
        mock_instance.analyze_pii = AsyncMock(return_value=_make_language_response(["0_0"]))
        MockClient.return_value = mock_instance

        with TestClient(fastapi_app, raise_server_exceptions=True) as c:
            yield c, mock_instance

    cfg_module._settings = None


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


class TestHealth:
    def test_health_returns_ok(self, client):
        c, _ = client
        response = c.get("/health")
        assert response.status_code == 200
        assert response.json()["status"] == "ok"


class TestRedact:
    _BASE_REQUEST = {
        "body": {
            "model": "gpt-4o",
            "messages": [
                {"role": "system", "content": "You are helpful."},
                {"role": "user", "content": "My name is John Smith."},
            ],
        },
        "config": {
            "fail_closed": False,
            "excluded_categories": [],
            "detection_language": "en",
            "scan_roles": ["user", "assistant", "tool"],
        },
    }

    def test_redact_success(self, client):
        c, mock_lc = client
        mock_lc.analyze_pii = AsyncMock(return_value=_make_language_response(["1_0"]))
        response = c.post("/redact", json=self._BASE_REQUEST)
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["full_coverage"] is True

    def test_system_message_not_sent_to_language_api(self, client):
        c, mock_lc = client
        captured_docs: list = []

        async def capture_analyze(documents, **kwargs):
            captured_docs.extend(documents)
            return _make_language_response([d["id"] for d in documents])

        mock_lc.analyze_pii = capture_analyze
        c.post("/redact", json=self._BASE_REQUEST)
        # Only the "user" message (index 1) should have been sent
        assert all("1_" in d["id"] for d in captured_docs)
        assert not any("0_" in d["id"] for d in captured_docs)

    def test_empty_messages_returns_success(self, client):
        c, mock_lc = client
        request = {**self._BASE_REQUEST, "body": {"model": "gpt-4o", "messages": []}}
        response = c.post("/redact", json=request)
        assert response.status_code == 200
        assert response.json()["diagnostics"]["total_docs"] == 0
