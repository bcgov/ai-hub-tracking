"""
Application settings loaded from environment variables.
All settings use the PII_ prefix.
"""

from __future__ import annotations

from pydantic import model_validator
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

    # Language API version to target (required)
    language_api_version: str

    # Per-batch HTTP timeout in seconds (APIM per-call budget)
    per_batch_timeout_seconds: int = 10

    # Total processing timeout budget in seconds (must remain below APIM's 90s timeout)
    total_processing_timeout_seconds: int = 85

    # Maximum number of retries for transient 429/5xx responses after the first attempt.
    transient_retry_attempts: int = 4

    # Exponential backoff configuration used when Retry-After is absent or for 5xx responses.
    retry_backoff_base_seconds: float = 1.0
    retry_backoff_max_seconds: float = 10.0

    # Max Language API batches per request — reject with HTTP 413 if exceeded.
    # This is a request-size guard, not a time guarantee. The total request deadline
    # remains the authoritative upper bound when retries are in play.
    max_concurrent_batches: int = 15

    # Number of Language API calls allowed in flight simultaneously (Semaphore bound)
    max_batch_concurrency: int = 3

    # Azure Language API hard limits
    max_doc_chars: int = 5000
    max_docs_per_call: int = 5

    # Logging level (DEBUG | INFO | WARNING | ERROR)
    log_level: str = "INFO"

    @model_validator(mode="after")
    def validate_timeouts(self) -> Settings:
        """Enforce retry and timeout invariants required by the APIM budget."""
        if self.per_batch_timeout_seconds <= 0:
            raise ValueError("PII_PER_BATCH_TIMEOUT_SECONDS must be > 0")
        if self.total_processing_timeout_seconds <= 0:
            raise ValueError("PII_TOTAL_PROCESSING_TIMEOUT_SECONDS must be > 0")
        if self.total_processing_timeout_seconds > 85:
            raise ValueError("PII_TOTAL_PROCESSING_TIMEOUT_SECONDS must be <= 85 (APIM backend timeout is 90s)")
        if self.transient_retry_attempts < 0:
            raise ValueError("PII_TRANSIENT_RETRY_ATTEMPTS must be >= 0")
        if self.retry_backoff_base_seconds <= 0:
            raise ValueError("PII_RETRY_BACKOFF_BASE_SECONDS must be > 0")
        if self.retry_backoff_max_seconds <= 0:
            raise ValueError("PII_RETRY_BACKOFF_MAX_SECONDS must be > 0")
        if self.retry_backoff_base_seconds > self.retry_backoff_max_seconds:
            raise ValueError("PII_RETRY_BACKOFF_BASE_SECONDS must be <= PII_RETRY_BACKOFF_MAX_SECONDS")
        return self


_settings: Settings | None = None


def get_settings() -> Settings:
    """Return the cached settings instance, creating it on first access."""
    global _settings
    if _settings is None:
        _settings = Settings()  # type: ignore[call-arg]
    return _settings
