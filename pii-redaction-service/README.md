# PII Redaction Service

A FastAPI microservice that externalises large-payload PII redaction from APIM into a dedicated Python container. APIM routes requests here when a chat payload requires more than 5 Language API documents (multi-message or chunked large messages).

## Why it exists

Azure Language Service accepts a maximum of 5 documents per synchronous `/language/:analyze-text` call. The existing APIM JINT inline-redaction path covers small payloads (≤ 5 docs) efficiently. When a payload has many messages or very long messages that chunk into more documents, APIM cannot call the Language API multiple times natively. This service handles sequential batching, rolling timeouts, and full-coverage verification transparently.

## Architecture

```
Client → App Gateway → APIM
                         │
                         ├── ≤5 docs  → inline Language API call (existing APIM path)
                         │
                         └── >5 docs  → POST /redact (this service)
                                              │
                                              ├── sequential batches (max 10)
                                              ├── asyncio deadline enforcement
                                              ├── word-boundary chunking (5 000 chars)
                                              └── full-coverage check
```

## Limits

| Parameter | Value |
|---|---|
| Max chars per document | 5 000 |
| Max documents per Language API call | 5 |
| Max sequential batches | 10 (→ 50 docs = rejects with 413) |
| Per-batch timeout | 10 s |
| Total processing timeout | 55 s (APIM 60 s surface) |

## Local development

```bash
# Install uv (https://github.com/astral-sh/uv)
pip install uv

# Create virtualenv and install dependencies
uv sync

# Copy and fill environment variables
cp .env.example .env
# Edit .env — set PII_LANGUAGE_ENDPOINT to your Language Service URL

# Run the service
uv run uvicorn app.main:app --reload --port 8000

# Run tests
uv run pytest
```

## Docker

```bash
# Build
docker build -t pii-redaction-service:local .

# Run (requires Azure credentials in environment or workload identity)
docker run --rm -e PII_LANGUAGE_ENDPOINT=https://... -p 8000:8000 pii-redaction-service:local
```

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `PII_LANGUAGE_ENDPOINT` | ✅ | — | Azure Language Service endpoint URL |
| `PII_LANGUAGE_API_VERSION` | | `2025-11-15-preview` | Language API version |
| `PII_PER_BATCH_TIMEOUT_SECONDS` | | `10` | Timeout per Language API batch call |
| `PII_TOTAL_PROCESSING_TIMEOUT_SECONDS` | | `55` | Overall deadline for all batches |
| `PII_MAX_SEQUENTIAL_BATCHES` | | `10` | Reject payloads requiring more than this many batches |
| `PII_MAX_DOC_CHARS` | | `5000` | Max characters per Language API document |
| `PII_MAX_DOCS_PER_CALL` | | `5` | Max documents per Language API call |
| `PII_LOG_LEVEL` | | `INFO` | Log level (DEBUG/INFO/WARNING/ERROR) |

## API

### `GET /health`

Returns `{"status": "ok"}` when the service is ready.

### `POST /redact`

Redacts PII from chat messages and returns the modified body.

**Request body:**

```json
{
  "body": {
    "model": "gpt-4o",
    "messages": [
      {"role": "user", "content": "My name is John Smith, SSN 123-45-6789"},
      {"role": "assistant", "content": "Got it!"}
    ]
  },
  "config": {
    "fail_closed": false,
    "excluded_categories": [],
    "detection_language": "en",
    "scan_roles": ["user", "assistant", "tool"],
    "correlation_id": "req-abc-123"
  }
}
```

**Success response (200):**

```json
{
  "status": "ok",
  "full_coverage": true,
  "redacted_body": { "model": "gpt-4o", "messages": [ ... ] },
  "diagnostics": { "total_docs": 1, "total_batches": 1, "elapsed_ms": 340 }
}
```

**Payload too large (413):** More batches required than `max_sequential_batches`.

**Service unavailable (503):** Language API error or timeout.

## Container image

Built via `.github/workflows/.builds.yml` and pushed to `ghcr.io/bcgov/ai-hub-tracking/pii-redaction-service`.

Deployed as a Container App (HTTP-triggered, internal ingress only) in the shared Container App Environment.
