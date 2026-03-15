"""
Request / response models for the PII Redaction Service.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Inbound: APIM → Service
# ---------------------------------------------------------------------------


class Message(BaseModel):
    role: str
    content: str | None = None


class RequestBody(BaseModel):
    """Original OpenAI-compatible chat completion request body."""

    messages: list[Message] = Field(default_factory=list)
    # Additional top-level keys are preserved verbatim
    model_config = {"extra": "allow"}

    def model_extra_dict(self) -> dict[str, Any]:
        return self.model_extra or {}


class RedactionConfig(BaseModel):
    """Per-tenant PII policy knobs forwarded by APIM."""

    fail_closed: bool = False
    excluded_categories: list[str] = Field(default_factory=list)
    detection_language: str = "en"
    scan_roles: list[str] = Field(default_factory=lambda: ["user", "assistant", "tool"])
    correlation_id: str = ""


class RedactionRequest(BaseModel):
    body: RequestBody
    config: RedactionConfig = Field(default_factory=RedactionConfig)


# ---------------------------------------------------------------------------
# Outbound: Service → APIM
# ---------------------------------------------------------------------------


class Diagnostics(BaseModel):
    total_docs: int
    total_batches: int
    elapsed_ms: float
    entity_count: int = 0
    skipped_roles: list[str] = Field(default_factory=list)


class RedactionSuccess(BaseModel):
    status: str = "ok"
    full_coverage: bool = True
    redacted_body: dict[str, Any]
    diagnostics: Diagnostics


class RedactionFailure(BaseModel):
    status: str = "error"
    full_coverage: bool = False
    error: str
    diagnostics: Diagnostics | None = None
