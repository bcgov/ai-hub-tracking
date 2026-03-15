"""
FastAPI application entry point for the PII Redaction Service.

Routes:
  GET /health    — liveness/readiness probe (no auth)
  POST /redact   — redact PII from a chat completion body

The Language API client is initialised once at startup (lifespan) and shared
across requests via a module-level singleton.
"""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.types import Message

from .config import Settings, get_settings
from .language_client import LanguageClient
from .logging_config import configure_logging
from .models import RedactionFailure, RedactionRequest, RedactionSuccess
from .orchestrator import orchestrate_redaction

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Module-level client holder (populated in lifespan)
# ---------------------------------------------------------------------------

_language_client: LanguageClient | None = None


def _decode_raw_body(raw_body: bytes) -> str:
    return raw_body.decode("utf-8", errors="replace")


def _get_client() -> LanguageClient:
    if _language_client is None:
        raise RuntimeError("Language client not initialised")
    return _language_client


# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    global _language_client

    settings: Settings = get_settings()
    configure_logging(settings.log_level)

    is_local = settings.environment.lower() == "local"
    if is_local and not settings.language_api_key:
        raise RuntimeError("PII_LANGUAGE_API_KEY is required when ENVIRONMENT=local")

    logger.info(
        "PII Redaction Service starting",
        extra={
            "environment": settings.environment,
            "auth_mode": "api_key" if is_local else "managed_identity",
            "language_endpoint": settings.language_endpoint,
            "max_docs_per_call": settings.max_docs_per_call,
            "max_concurrent_batches": settings.max_concurrent_batches,
            "max_batch_concurrency": settings.max_batch_concurrency,
        },
    )

    _language_client = LanguageClient(
        endpoint=settings.language_endpoint,
        api_version=settings.language_api_version,
        per_batch_timeout=settings.per_batch_timeout_seconds,
        api_key=settings.language_api_key if is_local else None,
    )
    async with _language_client:
        logger.info("Language client initialised — service ready")
        yield

    logger.info("PII Redaction Service shutting down")
    _language_client = None


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(
    title="PII Redaction Service",
    version="0.1.0",
    lifespan=lifespan,
    docs_url=None,  # Disable Swagger UI in production
    redoc_url=None,
)


@app.middleware("http")
async def _capture_redact_request_body(request: Request, call_next):
    if request.method == "POST" and request.url.path == "/redact":
        raw_body = await request.body()
        request.state.raw_body = _decode_raw_body(raw_body)
        request.state.raw_body_bytes = len(raw_body)

        async def receive() -> Message:
            return {"type": "http.request", "body": raw_body, "more_body": False}

        request._receive = receive

    return await call_next(request)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------


@app.get("/health", include_in_schema=False)
async def health() -> JSONResponse:
    return JSONResponse({"status": "healthy"})


@app.post(
    "/redact",
    response_model=RedactionSuccess,
    responses={422: {"model": RedactionFailure}, 413: {"model": RedactionFailure}, 503: {"model": RedactionFailure}},
)
async def redact(redaction_request: RedactionRequest) -> JSONResponse:
    """
    Redact PII entities from a chat completion payload.

    APIM forwards the full request body plus per-tenant PII configuration.
    Returns the redacted body on success, or an error descriptor on failure.

    HTTP status codes:
      200  — full coverage achieved
      422  — validation error (malformed request)
      413  — payload exceeds maximum batch count (payload-too-large)
      503  — redaction failed (timeout / Language API error / incomplete coverage)
    """
    settings = get_settings()
    client = _get_client()

    correlation_id = redaction_request.config.correlation_id
    logger.info(
        "Redaction request received",
        extra={
            "message_count": len(redaction_request.body.messages),
            "correlation_id": correlation_id,
        },
    )

    result = await orchestrate_redaction(
        request=redaction_request,
        client=client,
        settings=settings,
    )

    if isinstance(result, RedactionSuccess):
        logger.info(
            "Redaction succeeded",
            extra={
                "total_docs": result.diagnostics.total_docs,
                "total_batches": result.diagnostics.total_batches,
                "elapsed_ms": round(result.diagnostics.elapsed_ms, 1),
                "correlation_id": correlation_id,
            },
        )
        return JSONResponse(content=result.model_dump(), status_code=200)

    # RedactionFailure
    status_code = 413 if result.status == "payload-too-large" else 503
    logger.warning(
        "Redaction failed",
        extra={
            "error": result.error,
            "status_code": status_code,
            "correlation_id": correlation_id,
        },
    )
    return JSONResponse(content=result.model_dump(), status_code=status_code)


# ---------------------------------------------------------------------------
# Exception handler — surface unexpected errors as 503
# ---------------------------------------------------------------------------


@app.exception_handler(RequestValidationError)
async def _validation_exception_handler(request: Request, exc: RequestValidationError) -> JSONResponse:
    errors = exc.errors()
    raw_body = getattr(request.state, "raw_body", None)
    if raw_body is None:
        raw_body_bytes = await request.body()
        raw_body = _decode_raw_body(raw_body_bytes)
        raw_body_size = len(raw_body_bytes)
    else:
        raw_body_size = getattr(request.state, "raw_body_bytes", len(raw_body.encode("utf-8", errors="replace")))

    logger.debug(
        "Request validation failed (422)",
        extra={
            "path": str(request.url),
            "raw_body_bytes": raw_body_size,
            "errors": [{"loc": ".".join(str(p) for p in e["loc"]), "msg": e["msg"], "type": e["type"]} for e in errors],
        },
    )
    first_msg = errors[0]["msg"] if errors else "invalid request"
    failure = RedactionFailure(error=f"Request validation error: {first_msg}")
    return JSONResponse(content=failure.model_dump(), status_code=503)


@app.exception_handler(Exception)
async def _unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled exception", extra={"path": str(request.url)})
    failure = RedactionFailure(error="Internal server error")
    return JSONResponse(content=failure.model_dump(), status_code=503)
