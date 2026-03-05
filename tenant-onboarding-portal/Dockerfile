# ---------------------------------------------------------------------------
# Stage 1 – dependency resolution (uv)
# ---------------------------------------------------------------------------
FROM ghcr.io/astral-sh/uv:0.6-python3.13-bookworm-slim AS builder

WORKDIR /app
COPY pyproject.toml ./

RUN uv venv /app/.venv \
    && uv pip install --python /app/.venv/bin/python -r pyproject.toml

COPY src/ ./src/

# ---------------------------------------------------------------------------
# Stage 2 – minimal runtime
# ---------------------------------------------------------------------------
FROM python:3.13-slim-bookworm

RUN groupadd --gid 1001 app \
    && useradd --uid 1001 --gid app --shell /bin/false app

WORKDIR /app

COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/src ./src/

ENV PATH="/app/.venv/bin:${PATH}" \
    PYTHONUNBUFFERED=1

USER app

EXPOSE 8000

CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8000"]
