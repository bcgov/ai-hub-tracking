# =============================================================================
# APIM Key Rotation — Azure Functions (Custom Container with uv)
# =============================================================================
# Multi-stage build:
#   1. Build stage: uv resolves and installs dependencies
#   2. Runtime stage: Azure Functions Python image
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
COPY host.json function_app.py ./
COPY rotation/ rotation/

# ---------------------------------------------------------------------------
# Stage 2: Runtime — Azure Functions Python v4 base image
# Note: -slim variant unavailable for Python 3.13+; using standard base
# ---------------------------------------------------------------------------
FROM mcr.microsoft.com/azure-functions/python:4-python3.13

ENV AzureWebJobsScriptRoot=/home/site/wwwroot \
    AzureFunctionsJobHost__Logging__Console__IsEnabled=true \
    # Suppress .pyc generation in container
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /home/site/wwwroot

# Copy the virtual environment from builder
COPY --from=builder /build/.venv /home/site/wwwroot/.venv

# Fix venv Python symlink: builder has /usr/local/bin/python3, runtime uses /usr/bin/python3
RUN ln -sf "$(which python3)" /home/site/wwwroot/.venv/bin/python

# Add venv to PATH so the Functions host finds the packages
ENV PATH="/home/site/wwwroot/.venv/bin:$PATH" \
    VIRTUAL_ENV="/home/site/wwwroot/.venv"

# Copy application code
COPY --from=builder /build/host.json /build/function_app.py ./
COPY --from=builder /build/rotation/ rotation/
