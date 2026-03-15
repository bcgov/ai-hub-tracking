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
        assert response.json()["status"] == "healthy"


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


# ---------------------------------------------------------------------------
# Shared helper — dynamic mock that returns [REDACTED_{id}] per document
# ---------------------------------------------------------------------------


async def _auto_redact(documents, **kwargs):
    """Auto-responding mock: returns [REDACTED_{id}] per input document."""
    return _make_language_response([d["id"] for d in documents])


# ---------------------------------------------------------------------------
# Reassembly tests
# ---------------------------------------------------------------------------


class TestReassembly:
    """Verify chunked messages are reassembled correctly after PII redaction."""

    def test_single_chunk_message(self, client):
        """Short message → one chunk → redacted text in correct position."""
        c, mock_lc = client
        mock_lc.analyze_pii = _auto_redact
        request = {
            "body": {
                "model": "gpt-4o",
                "messages": [{"role": "user", "content": "My name is John."}],
            },
            "config": {"scan_roles": ["user"]},
        }
        resp = c.post("/redact", json=request)
        assert resp.status_code == 200
        data = resp.json()
        assert data["full_coverage"] is True
        msgs = data["redacted_body"]["messages"]
        assert len(msgs) == 1
        assert msgs[0]["content"] == "[REDACTED_0_0]"
        assert msgs[0]["role"] == "user"

    def test_multi_chunk_message_concatenated(self, client):
        """Message exceeding max_doc_chars → chunks concatenated in order."""
        c, mock_lc = client
        mock_lc.analyze_pii = _auto_redact
        # Build content >5000 chars to force chunking (default max_doc_chars=5000)
        long_content = "word " * 1100  # ~5500 chars
        request = {
            "body": {
                "model": "gpt-4o",
                "messages": [{"role": "user", "content": long_content}],
            },
            "config": {"scan_roles": ["user"]},
        }
        resp = c.post("/redact", json=request)
        assert resp.status_code == 200
        data = resp.json()
        assert data["full_coverage"] is True
        assert data["diagnostics"]["total_docs"] > 1
        content = data["redacted_body"]["messages"][0]["content"]
        # Chunks are strictly ordered: 0_0, 0_1, …
        assert content.startswith("[REDACTED_0_0]")
        assert "[REDACTED_0_1]" in content

    def test_multiple_messages_each_redacted(self, client):
        """Each scannable message gets its own redacted content."""
        c, mock_lc = client
        mock_lc.analyze_pii = _auto_redact
        request = {
            "body": {
                "model": "gpt-4o",
                "messages": [
                    {"role": "user", "content": "Hello from user"},
                    {"role": "assistant", "content": "Hello from assistant"},
                    {"role": "user", "content": "Second user message"},
                ],
            },
            "config": {"scan_roles": ["user", "assistant"]},
        }
        resp = c.post("/redact", json=request)
        assert resp.status_code == 200
        msgs = resp.json()["redacted_body"]["messages"]
        assert len(msgs) == 3
        assert msgs[0]["content"] == "[REDACTED_0_0]"
        assert msgs[1]["content"] == "[REDACTED_1_0]"
        assert msgs[2]["content"] == "[REDACTED_2_0]"

    def test_skipped_roles_preserved_verbatim(self, client):
        """Messages with roles outside scan_roles pass through unchanged."""
        c, mock_lc = client
        mock_lc.analyze_pii = _auto_redact
        request = {
            "body": {
                "model": "gpt-4o",
                "messages": [
                    {"role": "system", "content": "You are helpful."},
                    {"role": "user", "content": "PII here"},
                ],
            },
            "config": {"scan_roles": ["user"]},
        }
        resp = c.post("/redact", json=request)
        assert resp.status_code == 200
        data = resp.json()
        msgs = data["redacted_body"]["messages"]
        assert msgs[0]["content"] == "You are helpful."  # unchanged
        assert msgs[1]["content"] == "[REDACTED_1_0]"  # redacted
        assert "system" in data["diagnostics"]["skipped_roles"]

    def test_extra_body_fields_preserved_in_output(self, client):
        """Top-level body fields (model, temperature) survive reassembly."""
        c, mock_lc = client
        mock_lc.analyze_pii = _auto_redact
        request = {
            "body": {
                "model": "gpt-4o",
                "messages": [{"role": "user", "content": "Hi"}],
                "temperature": 0.7,
                "max_tokens": 1000,
            },
            "config": {"scan_roles": ["user"]},
        }
        resp = c.post("/redact", json=request)
        assert resp.status_code == 200
        body = resp.json()["redacted_body"]
        assert body["model"] == "gpt-4o"
        assert body["temperature"] == 0.7
        assert body["max_tokens"] == 1000

    def test_message_order_preserved(self, client):
        """Output message order matches input regardless of scanning."""
        c, mock_lc = client
        mock_lc.analyze_pii = _auto_redact
        request = {
            "body": {
                "model": "gpt-4o",
                "messages": [
                    {"role": "system", "content": "System prompt"},
                    {"role": "user", "content": "First user"},
                    {"role": "assistant", "content": "First reply"},
                    {"role": "user", "content": "Second user"},
                ],
            },
            "config": {"scan_roles": ["user", "assistant"]},
        }
        resp = c.post("/redact", json=request)
        assert resp.status_code == 200
        msgs = resp.json()["redacted_body"]["messages"]
        assert [m["role"] for m in msgs] == ["system", "user", "assistant", "user"]
        assert msgs[0]["content"] == "System prompt"  # not scanned
        assert msgs[1]["content"] == "[REDACTED_1_0]"
        assert msgs[2]["content"] == "[REDACTED_2_0]"
        assert msgs[3]["content"] == "[REDACTED_3_0]"

    def test_null_content_message_passes_through(self, client):
        """Messages with null content are not scanned and pass through."""
        c, mock_lc = client
        mock_lc.analyze_pii = _auto_redact
        request = {
            "body": {
                "model": "gpt-4o",
                "messages": [
                    {"role": "assistant", "content": None},
                    {"role": "user", "content": "Hi"},
                ],
            },
            "config": {"scan_roles": ["user", "assistant"]},
        }
        resp = c.post("/redact", json=request)
        assert resp.status_code == 200
        msgs = resp.json()["redacted_body"]["messages"]
        assert msgs[0]["content"] is None
        assert msgs[1]["content"] == "[REDACTED_1_0]"

    def test_diagnostics_reflect_chunk_counts(self, client):
        """Diagnostics report correct total_docs and total_batches."""
        c, mock_lc = client
        mock_lc.analyze_pii = _auto_redact
        request = {
            "body": {
                "model": "gpt-4o",
                "messages": [
                    {"role": "user", "content": "msg1"},
                    {"role": "user", "content": "msg2"},
                    {"role": "user", "content": "msg3"},
                ],
            },
            "config": {"scan_roles": ["user"]},
        }
        resp = c.post("/redact", json=request)
        assert resp.status_code == 200
        diag = resp.json()["diagnostics"]
        assert diag["total_docs"] == 3
        assert diag["total_batches"] == 1  # 3 docs < max_docs_per_call (5)
        assert diag["elapsed_ms"] > 0

    def test_mixed_scanned_and_unscanned_with_chunking(self, client):
        """Mix of scanned/unscanned roles with one long message that chunks."""
        c, mock_lc = client
        mock_lc.analyze_pii = _auto_redact
        long_content = "word " * 1100  # >5000 chars → 2+ chunks
        request = {
            "body": {
                "model": "gpt-4o",
                "messages": [
                    {"role": "system", "content": "Be brief."},
                    {"role": "user", "content": long_content},
                    {"role": "assistant", "content": "Short reply."},
                ],
            },
            "config": {"scan_roles": ["user", "assistant"]},
        }
        resp = c.post("/redact", json=request)
        assert resp.status_code == 200
        data = resp.json()
        msgs = data["redacted_body"]["messages"]
        # System message unchanged
        assert msgs[0]["content"] == "Be brief."
        # Long user message was chunked and reassembled
        assert "[REDACTED_1_0]" in msgs[1]["content"]
        assert "[REDACTED_1_1]" in msgs[1]["content"]
        # Short assistant message → single chunk (index 2)
        assert msgs[2]["content"] == "[REDACTED_2_0]"
        assert data["diagnostics"]["total_docs"] >= 3  # at least 2 chunks from user + 1 assistant


# ---------------------------------------------------------------------------
# Body validation tests
# ---------------------------------------------------------------------------


class TestBodyValidation:
    """Verify request body validation rejects malformed payloads.

    Validation errors are converted to 503 by the RequestValidationError handler
    so that APIM treats them as service failures rather than client errors.
    """

    def test_missing_body_returns_503(self, client):
        c, _ = client
        resp = c.post("/redact", json={"config": {}})
        assert resp.status_code == 503

    def test_missing_messages_passes_through(self, client):
        c, _ = client
        resp = c.post("/redact", json={"body": {"model": "gpt-4o"}})
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

    def test_messages_not_a_list_returns_503(self, client):
        c, _ = client
        resp = c.post("/redact", json={"body": {"messages": "not a list"}})
        assert resp.status_code == 503

    def test_message_missing_role_returns_503(self, client):
        c, _ = client
        resp = c.post(
            "/redact",
            json={
                "body": {"messages": [{"content": "missing role field"}]},
            },
        )
        assert resp.status_code == 503

    def test_messages_is_null_returns_503(self, client):
        c, _ = client
        resp = c.post("/redact", json={"body": {"messages": None}})
        assert resp.status_code == 503

    def test_body_is_null_returns_503(self, client):
        c, _ = client
        resp = c.post("/redact", json={"body": None})
        assert resp.status_code == 503

    def test_invalid_json_returns_503(self, client):
        c, _ = client
        resp = c.post(
            "/redact",
            content=b"not valid json",
            headers={"content-type": "application/json"},
        )
        assert resp.status_code == 503

    def test_config_defaults_when_omitted(self, client):
        """Config field defaults are applied when config is not provided."""
        c, mock_lc = client
        mock_lc.analyze_pii = _auto_redact
        request = {"body": {"messages": [{"role": "user", "content": "Hi"}]}}
        resp = c.post("/redact", json=request)
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

    def test_empty_messages_succeeds_with_zero_docs(self, client):
        c, _ = client
        resp = c.post("/redact", json={"body": {"messages": []}})
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"
        assert data["diagnostics"]["total_docs"] == 0
