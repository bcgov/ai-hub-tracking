"""
Application settings loaded from environment variables.
All settings use the PII_ prefix.
"""

from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="PII_", case_sensitive=False)

    # Runtime environment: "Azure" (default) | "local"
    # When "local", API key auth is used instead of DefaultAzureCredential.
    environment: str = "Azure"

    # Azure Language Service endpoint (required)
    language_endpoint: str

    # API key for the Language Service — required when environment=local
    language_api_key: str | None = None

    # Language API version to target
    language_api_version: str = "2025-11-15-preview"

    # Per-batch HTTP timeout in seconds (APIM per-call budget)
    per_batch_timeout_seconds: int = 10

    # Total processing timeout budget in seconds (must be < APIM 60s timeout)
    total_processing_timeout_seconds: int = 55

    # Max Language API batches per request — reject with HTTP 413 if exceeded.
    # Ceiling formula: ceil(N / max_batch_concurrency) × per_batch ≤ total_budget
    # With concurrency=3 and per_batch=10s, budget=55s: ceil(N/3)×10 ≤ 55 → N ≤ 15
    max_concurrent_batches: int = 15

    # Number of Language API calls allowed in flight simultaneously (Semaphore bound)
    max_batch_concurrency: int = 3

    # Azure Language API hard limits
    max_doc_chars: int = 5000
    max_docs_per_call: int = 5

    # Logging level (DEBUG | INFO | WARNING | ERROR)
    log_level: str = "INFO"


_settings: Settings | None = None


def get_settings() -> Settings:
    global _settings
    if _settings is None:
        _settings = Settings()  # type: ignore[call-arg]
    return _settings
