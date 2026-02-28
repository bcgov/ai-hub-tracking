# =============================================================================
# APIM Key Rotation — Container App Job (Custom Container with uv)
# =============================================================================
# Multi-stage build:
#   1. Build stage: uv resolves and installs dependencies
#   2. Runtime stage: Minimal Python image
#
# Runs as a Container App Job with cron trigger — the job executes main.py
# and exits. No Azure Functions runtime needed.
#
# Image hosted on GHCR: ghcr.io/<org>/apim-key-rotation:latest
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1: Build — install dependencies with uv
# ---------------------------------------------------------------------------
FROM ghcr.io/astral-sh/uv:0.6-python3.13-bookworm-slim AS builder

WORKDIR /build

# Copy dependency manifests first for layer caching
COPY pyproject.toml uv.lock ./

# Install dependencies into a virtual environment
RUN uv sync --no-dev --frozen --no-install-project

# Copy application code
COPY main.py ./
COPY rotation/ rotation/

# ---------------------------------------------------------------------------
# Stage 2: Runtime — Minimal Python image (no Functions runtime needed)
# ---------------------------------------------------------------------------
FROM python:3.13-slim-bookworm

# Suppress .pyc generation in container
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Copy the virtual environment from builder
COPY --from=builder /build/.venv /app/.venv

# Add venv to PATH
ENV PATH="/app/.venv/bin:$PATH" \
    VIRTUAL_ENV="/app/.venv"

# Copy application code
COPY --from=builder /build/main.py ./
COPY --from=builder /build/rotation/ rotation/

# Run the rotation entrypoint
CMD ["python", "main.py"]
