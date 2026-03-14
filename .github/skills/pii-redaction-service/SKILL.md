---
name: pii-redaction-service
description: Guidance for the PII Redaction custom service — Python FastAPI app, Docker container, GHA build workflow, and Terraform module. Use when modifying redaction logic, batch orchestration, Language Service integration, Container App scaling, or Terraform wiring for the pii-redaction stack.
---

# PII Redaction Service Skills

Use this skill profile when creating or modifying the PII Redaction Service — the Python FastAPI application, container image, GitHub Actions build workflow, or Terraform infrastructure module and stack.

## Use When
- Modifying redaction logic or batch orchestration (`app/orchestrator.py`)
- Changing the Language Service client (`app/language_client.py`)
- Updating request/response models (`app/models.py`) or Pydantic settings (`app/config.py`)
- Updating the Dockerfile or `pyproject.toml` dependencies
- Debugging PII redaction failures (Language Service errors, Container App ingress, timeout budget)
- Changing the GHA container build workflow (`.builds.yml` matrix entry for this image)
- Modifying the Terraform module (`modules/pii-redaction-service/`) or stack (`stacks/pii-redaction/`)

## Do Not Use When
- Modifying APIM policies that route to this service (use [API Management](../api-management/SKILL.md))
- Changing network subnet allocation or NSG rules (use [Network](../network/SKILL.md))
- Working on App Gateway or WAF rules (use [App Gateway & WAF](../app-gateway/SKILL.md))
- Making Terraform-only changes unrelated to this service (use [IaC Coder](../iac-coder/SKILL.md))

## Input Contract
Required context before changes:
- Current request flow (`POST /redact` → orchestrator → language client → Language Service)
- Pydantic settings schema (`app/config.py`) — all env vars use the `PII_` prefix
- Timeout budget: `PII_TOTAL_PROCESSING_TIMEOUT_SECONDS` (55s default) < APIM backend timeout (60s)
- Container App constraints: internal-only ingress, SystemAssigned MI, Consumption workload profile

## Output Contract
Every change should deliver:
- Python code changes with type hints (Python 3.13+, `from __future__ import annotations`)
- Updated unit tests in `tests/` if logic changed
- Ruff-clean code (`ruff check --fix . && ruff format .`)
- Docker build verification if `Dockerfile` or dependencies changed
- Terraform changes if infrastructure configuration affected

## External Documentation
- Use [External Docs Research](../external-docs/SKILL.md) as the single source of truth for external documentation workflow and fallback approval requirements.

## Code Locations

| Component | Location | Purpose |
|---|---|---|
| Entry point | `pii-redaction-service/app/main.py` | FastAPI app, lifespan (LanguageClient init), `/health` + `/redact` routes |
| Settings | `pii-redaction-service/app/config.py` | Pydantic Settings — all env vars (`PII_` prefix) |
| Models | `pii-redaction-service/app/models.py` | `RedactionRequest`, `RedactionSuccess`, `RedactionFailure` |
| Language client | `pii-redaction-service/app/language_client.py` | Azure Language Service SDK wrapper (MI auth via `DefaultAzureCredential`) |
| Orchestrator | `pii-redaction-service/app/orchestrator.py` | Batching, sequential dispatch, rolling timeout budget enforcement |
| Logging config | `pii-redaction-service/app/logging_config.py` | Structured logging setup |
| Dockerfile | `pii-redaction-service/Dockerfile` | Multi-stage: uv builder → Python slim runtime |
| Dependencies | `pii-redaction-service/pyproject.toml` | uv-managed deps (azure-ai-textanalytics, fastapi, pydantic-settings) |
| Unit tests | `pii-redaction-service/tests/` | pytest suite for API routes and orchestrator logic |
| GHA workflow | `.github/workflows/.builds.yml` | Reusable workflow → GHCR image via `bcgov/action-builder-ghcr` (matrix entry) |
| Terraform module | `infra-ai-hub/modules/pii-redaction-service/` | Container App definition, RBAC (Cognitive Services User on Language Service) |
| Stack wiring | `infra-ai-hub/stacks/pii-redaction/main.tf` | Calls module with feature flag gate; outputs FQDN consumed by APIM stack |

## Request Flow

```
APIM → POST /redact  (Container App internal ingress, VNet only)
  └── FastAPI route handler  (main.py)
       └── orchestrate_redaction(request, settings)
            ├── Guard: empty documents?
            ├── Split into batches  (max_docs_per_call=5, max_doc_chars=5000)
            └── For each batch  (concurrent, semaphore-bounded, up to max_concurrent_batches):
                 ├── LanguageClient.recognize_pii()  with per_batch_timeout
                 ├── Accumulate redacted text
                 └── Check rolling timeout  (total_processing_timeout_seconds)
  └── Returns RedactionSuccess | RedactionFailure
```

## Key Design Rules
- **Zero-secret operation**: Uses `DefaultAzureCredential` (Managed Identity in Azure, `az login` locally) — no API keys stored anywhere
- **VNet-only ingress**: Container App uses `external_enabled = true` on an internal CAE environment — accessible within the VNet (APIM, other VNet resources) but not from the public internet. `external_enabled = false` would restrict access to apps within the same CAE, blocking APIM entirely.
- **Stateless**: No shared state between requests; each `POST /redact` is fully independent
- **Timeout budget**: `PII_TOTAL_PROCESSING_TIMEOUT_SECONDS` (55s default) is always less than APIM's backend timeout (60s) to ensure clean error propagation before APIM times out
- **Batching limits**: Language Service enforces 5 documents per call and 5000 characters per document; the orchestrator enforces these limits before making any API calls
- **Concurrent batching**: Batches are processed with bounded concurrency (`max_batch_concurrency` semaphore, default 3) to maximise throughput while respecting the Language Service rate limits and rolling timeout budget
- **Fail-closed**: Timeouts and Language Service errors return `RedactionFailure` — the service never passes unredacted text through on error
- **Image refresh**: `terraform_data.image_refresh` in the Terraform module forces a re-pull when the `:latest` tag is used, because Terraform cannot detect mutable tag changes

## Environment Variables (Settings)

All variables use the `PII_` prefix (e.g., `PII_LANGUAGE_ENDPOINT`).

| Variable | Required | Default | Description |
|---|---|---|---|
| `PII_LANGUAGE_ENDPOINT` | Yes | — | Azure Language Service HTTPS endpoint URL |
| `PII_LANGUAGE_API_VERSION` | No | `2025-11-15-preview` | Language Service API version for PII recognition |
| `PII_PER_BATCH_TIMEOUT_SECONDS` | No | `10` | Timeout for each individual Language Service call (seconds) |
| `PII_TOTAL_PROCESSING_TIMEOUT_SECONDS` | No | `55` | Rolling total timeout across all batches — must be < APIM backend timeout |
| `PII_MAX_CONCURRENT_BATCHES` | No | `15` | Maximum number of batches allowed per request (413 if exceeded) |
| `PII_MAX_BATCH_CONCURRENCY` | No | `3` | Number of Language API calls allowed in flight simultaneously |
| `PII_MAX_DOC_CHARS` | No | `5000` | Maximum characters per document (Language Service hard limit) |
| `PII_MAX_DOCS_PER_CALL` | No | `5` | Maximum documents per Language API call (Language Service hard limit) |
| `PII_LOG_LEVEL` | No | `INFO` | Python logging level |

## Change Checklist
1. **Python code** — type hints, `from __future__ import annotations`, Pydantic v2 patterns
2. **Ruff (after every file edit)** — run `uv run ruff check . && uv run ruff format --check .` from `pii-redaction-service/` immediately after each file change, not just at the end. Fix before moving on.
3. **Tests** — `uv run pytest` from `pii-redaction-service/`
4. **Docker** — `docker build -t pii-redaction-service:test .` if Dockerfile or deps changed
5. **Terraform** — `terraform fmt -recursive` and `terraform validate` if module or stack changed
6. **Timeout budget** — verify `PII_TOTAL_PROCESSING_TIMEOUT_SECONDS` < APIM backend timeout if either value changes
7. **Settings schema** — new env vars added to both `config.py` Settings class and `.env.example`

## Validation Gates (Required)
1. **Ruff clean**: No lint errors (`ruff check .`)
2. **Tests pass**: `pytest` succeeds from `pii-redaction-service/`
3. **Docker builds**: Image builds without errors (if Dockerfile or `pyproject.toml` changed)
4. **Settings schema**: All new env vars present in `config.py` + `.env.example`
5. **Feature flag**: Stack gated behind `local.cae_config.enabled && try(local.pii_redaction_config.enabled, true)` in `stacks/pii-redaction/main.tf`
6. **Timeout invariant**: `PII_TOTAL_PROCESSING_TIMEOUT_SECONDS` ≤ (APIM backend timeout − 5s)
