# syntax=docker/dockerfile:1.10
# =============================================================================
# PII Redaction Service — Multi-stage Docker build
# Stage 1: uv builder — installs dependencies into .venv
# Stage 2: slim runtime — copies .venv, runs as non-root appuser
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1: builder
# ---------------------------------------------------------------------------
FROM ghcr.io/astral-sh/uv:0.6-python3.13-bookworm-slim AS builder

WORKDIR /build

# Install dependencies first (layer-cached until lockfile changes)
COPY pyproject.toml uv.lock ./
RUN uv sync --no-dev --frozen --no-install-project

# Copy source and complete the install
COPY app/ ./app/
RUN uv sync --no-dev --frozen

# ---------------------------------------------------------------------------
# Stage 2: runtime
# ---------------------------------------------------------------------------
FROM python:3.13-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/app/.venv/bin:$PATH" \
    VIRTUAL_ENV="/app/.venv"

WORKDIR /app

# Copy the populated virtualenv from the builder stage
COPY --from=builder /build/.venv /app/.venv

# Copy application source
COPY --from=builder /build/app ./app

# Create non-root user and switch to it
RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --shell /bin/sh --no-create-home appuser && \
    chown -R appuser:appgroup /app

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "2"]
