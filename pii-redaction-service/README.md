# PII Redaction Service

A FastAPI microservice that handles PII redaction for all APIM-proxied chat requests. When PII redaction is enabled for a tenant, APIM routes every request to this service via `POST /redact`. The service manages all Language Service API interactions — APIM acts as a policy enforcement point only.

## Why it exists

Azure Language Service accepts a maximum of 5 documents and 5 000 characters per document in a single synchronous `/language/:analyze-text` call. Chat payloads routinely exceed these limits. This service handles word-boundary chunking, bounded concurrent batching, rolling deadlines, and transient retry/backoff for 429 and 5xx responses — keeping the APIM policy fragment thin and testable.

## Architecture

```
Client → App Gateway → APIM
                         │
                         └── POST /redact (this service)
                                  │
                                  ├── word-boundary chunking (5 000 chars)
                                  ├── bounded concurrent batches (max 5 docs × max 15 batches)
                                  ├── retry-after / exponential backoff for 429 and 5xx
                                  ├── asyncio deadline enforcement (85 s)
                                  ├── full-coverage check
                                  └── reassembled redacted body → APIM
```

## Limits

| Parameter | Value |
|---|---|
| Max chars per document | 5 000 |
| Max documents per Language API call | 5 |
| Max batches per request | 15 (→ 75 docs = rejects with 413) |
| Per-attempt Language API timeout | 10 s |
| Total processing timeout | 85 s (APIM 90 s surface) |
| 429 retry behavior | Honor `Retry-After`, otherwise exponential backoff |
| 5xx retry behavior | Exponential backoff |

## Local development

### Prerequisites

```bash
# Install uv if not already installed
pip install uv

# Create virtualenv and install dependencies
uv sync
```

### Environment setup

Copy `.env` and fill in your values:

```bash
cp .env.example .env
```

For local runs, set the following in `.env`:

```dotenv
PII_LANGUAGE_ENDPOINT=https://<your-language-service>.cognitiveservices.azure.com/
PII_ENVIRONMENT=local
PII_LANGUAGE_API_KEY=<your-api-key>
```

With `PII_ENVIRONMENT=local` the service skips `DefaultAzureCredential` and sends the key as `Ocp-Apim-Subscription-Key` directly to the Language API.

### Running the service

```powershell
# Basic — loads .env automatically
uv run --env-file .env uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

If you are behind a corporate HTTP proxy (e.g. Privoxy/Chisel on port 8118), set the proxy before running:

```powershell
$env:HTTPS_PROXY = "http://localhost:8118"
$env:HTTP_PROXY  = "http://localhost:8118"
$env:NO_PROXY    = "localhost,127.0.0.1"
uv run --env-file .env uvicorn app.main:app --host 127.0.0.1 --port 8000 --reload
```

`httpx` (used internally) picks up `HTTPS_PROXY`/`HTTP_PROXY` natively — no code changes needed.

### Testing

Use the `pii-test.http` file with the VS Code REST Client extension to hit the local endpoint. It includes health, basic PII, multi-turn, large-payload, and limit-breach scenarios.

```bash
# Unit / integration tests
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
| `PII_ENVIRONMENT` | | `Azure` | `Azure` uses Managed Identity; `local` uses API key auth |
| `PII_LANGUAGE_API_KEY` | ✅ when `local` | — | Language Service API key (local only) |
| `PII_LANGUAGE_API_VERSION` | | `2025-11-15-preview` | Language API version |
| `PII_PER_BATCH_TIMEOUT_SECONDS` | | `10` | Timeout per individual Language API attempt |
| `PII_TOTAL_PROCESSING_TIMEOUT_SECONDS` | | `85` | Overall deadline for the full request, including retries and backoff |
| `PII_TRANSIENT_RETRY_ATTEMPTS` | | `4` | Maximum retries for transient 429 and 5xx responses after the first attempt |
| `PII_RETRY_BACKOFF_BASE_SECONDS` | | `1` | Base delay for exponential backoff |
| `PII_RETRY_BACKOFF_MAX_SECONDS` | | `10` | Maximum exponential backoff delay when `Retry-After` is absent |
| `PII_MAX_CONCURRENT_BATCHES` | | `15` | Reject payloads requiring more than this many batches |
| `PII_MAX_BATCH_CONCURRENCY` | | `3` | Number of Language API batches processed concurrently |
| `PII_MAX_DOC_CHARS` | | `5000` | Max characters per Language API document |
| `PII_MAX_DOCS_PER_CALL` | | `5` | Max documents per Language API call |
| `PII_LOG_LEVEL` | | `INFO` | Log level (DEBUG/INFO/WARNING/ERROR) |

## API

### `GET /health`

Returns `{"status": "healthy"}` when the service is ready.

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

**Payload too large (413):** More batches required than `max_concurrent_batches`.

**Service unavailable (503):** Language API error, retry budget exhaustion, or total request timeout.

## Retry behavior

- `429 Too Many Requests`: the service honors `Retry-After`, `retry-after-ms`, or `x-ms-retry-after-ms` when present. If the service does not provide a retry hint, the client falls back to exponential backoff.
- `500-599`: the service retries with exponential backoff.
- All retries and backoff remain bounded by `PII_TOTAL_PROCESSING_TIMEOUT_SECONDS`, so a single redact request never exceeds the service's 85 second processing budget.

## Container image

Built via `.github/workflows/.builds.yml` and pushed to `ghcr.io/bcgov/ai-hub-tracking/pii-redaction-service`.

Deployed as a Container App (HTTP-triggered, internal ingress only) in the shared Container App Environment.

## Why REST Instead of the SDK

REST is the better fit for this service because the implementation needs tight control over batching, retries, and the overall APIM request budget.

### Comparison

| Factor | REST (`httpx`) | SDK (`azure-ai-textanalytics`) |
|---|---|---|
| Chunking control | Full control. `orchestrator.py` builds batches exactly as needed. | More abstraction around document handling and batching. |
| Retry control | Custom retry loop respects `request_deadline` and the APIM 90 second ceiling. | Built-in retries are not aware of the full request budget; they would still need to be overridden. |
| Timeout precision | Uses `asyncio.wait_for()` with `min(per_batch_timeout, remaining_budget)` per attempt. | Timeout handling is less precise for this deadline-driven flow. |
| Response parsing | Reads `response.json()` directly with no extra wrapper layer. | Returns SDK result objects that would need to be unwrapped back into the service's internal structures. |
| Dependencies | Keeps the stack lean: `httpx` plus `azure-identity`. | Adds another client layer and its supporting packages. |
| Async behavior | Native `httpx.AsyncClient` with explicit connection pooling. | Async client is available, but adds abstraction without solving the core batching problem. |
| API version control | Explicit `api-version=2025-11-15-preview` in the request URL. | API support is tied to the SDK version in use. |

### When the SDK Would Make Sense

- If the service needed several Language Service features through one shared client surface.
- If fine-grained request-budget control was not important.
- If the per-document wrapper overhead did not matter for the request path.

### What the Current REST Client Already Handles

| Concern | Current implementation |
|---|---|
| Authentication | `DefaultAzureCredential` in Azure, API key fallback for local development |
| Transient retry handling | Honors `Retry-After` for `429`, uses exponential backoff for `5xx` |
| Budget-aware timeouts | Caps each attempt against the remaining `request_deadline` |
| Connection management | Reuses a shared `httpx.AsyncClient` for pooling across requests |

For this service, the SDK would add abstraction, not capability. The REST client already implements the pieces that matter most to correctness and latency.