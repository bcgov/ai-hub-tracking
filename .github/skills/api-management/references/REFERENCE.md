# API Management — Detailed Reference

Supplementary reference for the [API Management skill](../SKILL.md). Load this file when you need detailed policy syntax, endpoint format specifics, key rotation internals, or failure playbooks.

## Global Policy Details (`global_policy.xml`)

The global policy applies to all APIs before the per-tenant API policy runs:

| Feature | Purpose |
|---|---|
| Real client IP extraction | Promotes `X-Forwarded-For` (set by AppGW) to `X-Real-Client-IP` for logging; falls back to `context.Request.IpAddress` when no AppGW |
| Correlation ID | Sets `x-ms-correlation-request-id` for distributed tracing |
| Token metrics | `azure-openai-emit-token-metric` scoped to `/openai/` paths only (**inbound-only policy** — cannot be used in outbound/on-error) |
| Outbound headers | `x-ms-request-id` and `x-ratelimit-remaining-tokens` on every response |
| Error handling | Structured JSON for 429 (rate limit), 503 (circuit breaker — not rewritten), and generic errors; scrubs internal Azure hostnames from error messages |

**What the global policy does NOT contain:**
- No subscription key normalization (handled by App Gateway rewrite rules)
- No `Ocp-Apim-Subscription-Key`/`Authorization: Bearer` → `api-key` header mapping

## OpenAI Endpoint Formats

APIM supports two OpenAI endpoint formats. Both are routed via the same `openai` path condition:

### `/deployments/` format (standard Azure OpenAI)
- Client sends: `/openai/deployments/gpt-4.1-mini/chat/completions`
- APIM rewrites to: `/openai/deployments/{tenant_name}-gpt-4.1-mini/chat/completions`
- Deployment name extracted from URL path via regex

### `/v1/` format (OpenAI-compatible)
- Client sends: `/openai/v1/chat/completions` with `"model": "gpt-4.1-mini"` in the request body
- URL forwarded as-is to Azure OpenAI (which handles `/openai/v1/` natively)
- Deployment name extracted from `model` field in request body using `Body.As<JObject>(preserveContent: true)`
- Model field is tenant-prefixed in the body: `gpt-4.1-mini` → `{tenant_name}-gpt-4.1-mini`
- Input validation: `/v1/` requests must have valid JSON body with `model` field (returns 400 otherwise)

### Deployment Name Extraction (Unified)
The `deploymentName` variable is set once in inbound and reused in outbound logging:
```
1. Try URL regex: /deployments/{name}/  → deploymentName = name
2. Fallback for /v1/: parse body model field → deploymentName = {tenant}-{model}
3. If neither matches → deploymentName = "unknown"
```

### Body Model Rewrite Ordering
The `/v1/` body model tenant-prefix rewrite (`set-body`) is placed **after** PII redaction `set-body` to avoid being overwritten. It uses a `StartsWith` guard to prevent double-prefixing.

## Mistral Endpoint Rules

Mistral routing is intentionally split by API surface:

- `Mistral-Large-3` chat traffic must use `/openai/v1/chat/completions`.
- Mistral document/OCR traffic must use `/providers/mistral/azure/ocr`.
- The legacy alias `/providers/mistral/models/{model}/chat/completions` is allowed only as a compatibility path for document models that APIM rewrites to `/providers/mistral/azure/ocr`.
- APIM must reject chat models on that alias with a client error instead of silently rewriting them.

Reasoning:
- Global token metrics (`azure-openai-emit-token-metric`) are scoped to `openai` paths only.
- Per-model token limiting (`llm-token-limit`) is also scoped to `openai` paths only.
- Allowing Mistral chat on a non-OpenAI alias creates inconsistent observability and quota enforcement.

## Outbound Policies

- **Document Intelligence** (`document_intelligence_enabled`): rewrites the `Operation-Location` response header to replace the backend `cognitiveservices.azure.com` URL with the App Gateway URL. This is required for async (202) polling to work through the gateway.
- **OpenAI usage logging — unified** (`usage_logging_enabled`): A single `<choose>` block fires for all OpenAI paths (streaming and non-streaming). It calls `openai-token-extraction` then `openai-usage-logging` fragments in sequence. Token extraction reads actual counts from the JSON response body (non-streaming) or from the SSE usage chunk (streaming, enabled by `stream_options.include_usage` injected inbound). Both modes emit a single `openai-usage` App Insights event with an `is-streaming` dimension for LAW query filtering.

### Streaming Detection
The `isStream` context variable is set in inbound for OpenAI requests:
```csharp
var streamVal = body?["stream"];
if (streamVal != null) { return streamVal.Value<bool>(); }
```
This variable gates token extraction behavior inside `openai-token-extraction`:
- `isStream == false` → parse response as `JObject`, extract `usage.prompt_tokens` / `usage.completion_tokens` / `usage.total_tokens`
- `isStream == true` → read response body as string, regex-match `"prompt_tokens"\s*:\s*(\d+)` from the SSE usage chunk appended by `stream_options.include_usage`

### `stream_options.include_usage` Injection
For streaming requests, APIM injects `"stream_options": {"include_usage": true}` into the request body (inbound, after PII redaction and `/v1/` model-field rewrite). This causes Azure OpenAI to include a final SSE chunk before `[DONE]` with actual token counts:
```
data: {"choices":[],"usage":{"prompt_tokens":N,"completion_tokens":M,"total_tokens":P}}
data: [DONE]
```
The injection is guarded: if the client already sent `stream_options`, APIM skips injection to avoid overwriting. Supported by all API versions from `2024-08-01-preview` onward (current version: `2025-03-01-preview`).

### PTU Streaming 429 Pass-Through
PTU backends are deployed per-tenant (`{tenant_name}-openai-ptu`). If concurrent streaming requests exceed the tenant's PTU slice, Azure Foundry returns `429 Too Many Requests`. APIM's global outbound 429 handler passes this through with `Retry-After` and `x-should-retry: true`. Clients should implement retry logic using the `Retry-After` header. APIM does **not** perform pessimistic token reservation for streaming — Foundry enforces the hard cap natively.

## Document Intelligence: Model Performance

- **`prebuilt-layout`**: Fast (~10-20s for a 500KB JPG on S0 tier). Extracts text, tables, and structure.
- **`prebuilt-invoice`**: Very slow (~90-150s for the same file on S0 tier). Performs field extraction, table parsing, and key-value analysis on top of layout. Cold-start variance adds 20-40s.
- Each tenant gets its own dedicated DocInt Cognitive Services account (S0, 15 TPS quota).
- **CI tests use `prebuilt-layout`** for async flow validation because `prebuilt-invoice` exceeds reliable CI timeout thresholds.

## Backend Section

- OpenAI requests use `buffer-request-body="true"` (required for PII redaction and token inspection).
- All other requests use `buffer-request-body="false"`.
- Timeout is configured per-tenant via `backend_timeout_seconds` (default: 300s).

## APIM Policy Syntax: CSHTML/Razor Parser Rules

APIM's policy editor uses a CSHTML/Razor-based parser. **All `if`/`for`/`foreach` control flow blocks MUST use `{}` braces**, even for single-statement bodies:

```csharp
// BAD — APIM validation rejects braceless control flow
if (match.Success) return match.Groups[1].Value;

// GOOD — braces required
if (match.Success) { return match.Groups[1].Value; }
```

This applies to all C# expressions inside `value="@{ ... }"` blocks — `set-variable`, `set-body`, `set-header`, etc. The `az apimservice api policy set` ARM endpoint returns a silent parse error for braceless `if`, causing hard-to-debug deployment failures.

## Policy Template: set-backend-service Must Use Static IDs

**Never** use a dynamic C# expression as the `backend-id` attribute of `<set-backend-service>`:

```xml
<!-- BAD: portal tile renderer fails on this; entire policy falls back to showing only <base /> -->
<set-variable name="speechBackendId" value="@{ ... return &quot;${tenant_name}-speech-stt&quot;; }" />
<set-backend-service backend-id="@((string)context.Variables[&quot;speechBackendId&quot;])" />
```

The Azure Portal visual designer cannot render policy tiles when `backend-id` is a C# expression. The policy **is stored and executes correctly at runtime**, but the portal displays only `<base />` for that API's inbound/backend sections.

**Fix**: split conditional routing into separate `<when>` blocks, each using a static `backend-id` string:

```xml
<!-- GOOD: each <when> has a static backend-id; portal renders tiles correctly -->
<when condition="@(context.Request.Url.Path.ToLower().Contains(&quot;speech/recognition&quot;))">
    <set-backend-service backend-id="${tenant_name}-speech-stt" />
</when>
<when condition="@(context.Request.Url.Path.ToLower().Contains(&quot;cognitiveservices/voices&quot;))">
    <set-backend-service backend-id="${tenant_name}-speech-tts" />
</when>
```

## Testing Notes

- Validate routing for `/openai/*`, `/documentintelligence/*`, `/speech/recognition`, `/cognitiveservices/voices`, `/ai-search/*`, and `/storage/*`.
- Confirm tenant-prefixed deployment names (`{tenant}-{model}`) are correctly rewritten for OpenAI requests.
- Confirm MSI auth works per backend type; verify `api-key` is removed.
- Ensure non-matching paths return 404 JSON error.
- For Document Intelligence async ops, confirm `Operation-Location` header is rewritten to the App Gateway URL.
- Verify Speech backends receive `/stt/` or `/tts/` path prefix after the rewrite.
- For `/v1/` endpoints: verify model field is tenant-prefixed in request body, validate 400 errors for missing model / invalid JSON.
- For Bearer token auth: verify requests with `Authorization: Bearer <key>` are accepted (key mapping is done at App Gateway layer).

## Key Rotation

APIM subscription keys are rotated by a **Container App Job** (cron trigger) deployed as a custom container from GHCR. Source code is in `jobs/apim-key-rotation/`, with the Terraform module at `infra-ai-hub/modules/key-rotation-function/`. The job is gated by the `rotation_enabled` flag in `stacks/key-rotation/main.tf`.

### Alternating Pattern
```
Rotation 1 (first):  Regenerate SECONDARY → tenants safe on PRIMARY
Rotation 2:          Regenerate PRIMARY   → tenants safe on SECONDARY
Rotation 3:          Regenerate SECONDARY → tenants safe on PRIMARY
...alternates indefinitely. One key is ALWAYS valid.
```

Default interval: 7 days (`ROTATION_INTERVAL_DAYS`).

### Hub Key Vault Secret Naming

All subscription-key tenants have their APIM keys stored in the centralized hub Key Vault on first deploy (seeded by Terraform). Rotation metadata secrets are only created for rotation-opted tenants.

| Secret | Scope | Content |
|---|---|---|
| `{tenant}-apim-primary-key` | All subscription-key tenants | Current primary subscription key |
| `{tenant}-apim-secondary-key` | All subscription-key tenants | Current secondary subscription key |
| `{tenant}-apim-rotation-metadata` | Rotation-opted tenants only | JSON metadata (see below) |

All secrets have a **90-day expiry** to satisfy Landing Zone policy. Terraform uses `lifecycle { ignore_changes = [value] }` so existing secrets are never overwritten.

### Rotation Metadata Schema

Stored as JSON in `{tenant}-apim-rotation-metadata`:

```json
{
  "last_rotated_slot": "primary|secondary|none",
  "last_rotation_at": "2026-02-20T00:00:00Z",
  "next_rotation_at": "2026-02-27T00:00:00Z",
  "rotation_number": 5,
  "safe_slot": "secondary|primary"
}
```

`safe_slot` indicates which key tenants should currently use (the one **not** regenerated). Integration tests use this for Key Vault key fallback via `ApimClient.refresh_tenant_key_from_vault()` in the Python harness.

## Route Validation Matrix Template

Use this table for every APIM change review/runbook:

| Request Path | Feature Flag | Expected Backend ID | Auth Mode | Expected Result |
|---|---|---|---|---|
| `/openai/deployments/{model}/...` | `openai_enabled` | `${tenant_name}-openai` | MSI (`cognitiveservices`) | 2xx/4xx from backend, not APIM 404 |
| `/openai/v1/chat/completions` | `openai_enabled` | `${tenant_name}-openai` | MSI (`cognitiveservices`) | 2xx/4xx; model field tenant-prefixed in body |
| `/providers/mistral/models/Mistral-Large-3/chat/completions` | `openai_enabled` | none | n/a | 400 `InvalidMistralRoute`; instruct client to use `/openai/v1/chat/completions` |
| `/providers/mistral/azure/ocr` | `openai_enabled` | `${tenant_name}-openai` | MSI (`cognitiveservices`) | 2xx/4xx from Mistral OCR backend |
| `/documentintelligence/...` | `document_intelligence_enabled` | `${tenant_name}-docint` | MSI (`cognitiveservices`) | 2xx/202 with rewritten `Operation-Location` |
| `/speech/recognition...` | `speech_services_enabled` | `${tenant_name}-speech-stt` | backend credential | 2xx/4xx from speech backend |
| `/cognitiveservices/voices...` | `speech_services_enabled` | `${tenant_name}-speech-tts` | backend credential | 2xx/4xx from speech backend |
| `/ai-search/...` | `ai_search_enabled` | `${tenant_name}-ai-search` | MSI (`search.azure.com`) | 2xx/4xx from search backend |
| `/storage/...` | `storage_enabled` | `${tenant_name}-storage` | MSI (`storage.azure.com`) | 2xx/4xx from storage backend |
| unmatched path | n/a | none | n/a | APIM 404 JSON |

## Failure Playbook

### Streaming requests return 500 in outbound
- The outbound policy is likely trying to parse the SSE response as `JObject`. Ensure streaming requests are guarded by `isStream == true` and skip the `openai-usage-logging` fragment. Use inline `<trace>` for streaming observability instead.

### `azure-openai-emit-token-metric` rejected in outbound/on-error
- This policy is **inbound-only**. Azure rejects it in outbound or on-error sections. Token metrics for streaming are already emitted in inbound by the global policy — use `<trace>` for outbound streaming metadata logging.

### Portal policy view shows only `<base />`
- Check for dynamic C# expression in `backend-id`; replace with static IDs in separate `<when>` blocks.

### OpenAI requests timeout on large payloads
- Confirm token limiting and prompt estimation are scoped to OpenAI paths only.

### DocInt async polling fails
- Verify `Operation-Location` rewrite is still active and points to App Gateway host.

### Key rotation failures
- Check the Container App Job logs (Log Stream in Azure Portal or Log Analytics) for authentication or SDK errors.
- Verify hub Key Vault exists and the Container App Job's managed identity has `Key Vault Secrets Officer` role.
- If a rotation is stuck, check `{tenant}-apim-rotation-metadata` for `last_rotated_slot` and manually verify which APIM slot is active.

### Circuit breaker tripped (clients receiving `503` with `x-circuit-breaker-open: true`)
- Confirm it is a circuit breaker trip by checking the `x-circuit-breaker-open: true` response header (absent on backend 429 rate-limit pass-throughs from Azure OpenAI).
- The circuit trips on **5xx server errors only** — not on backend 429s. Failure thresholds: 3 errors/minute for AI service backends (OpenAI, DocInt, AI Search, Speech); 5 errors/minute for Storage.
- Backend 429s pass through `<outbound>` directly with the real `Retry-After` from Azure OpenAI — they do not open the circuit. This is correct for a single-backend-per-tenant deployment: unlike a [backend pool design](https://techcommunity.microsoft.com/blog/fasttrackforazureblog/using-azure-api-management-circuit-breaker-and-load-balancing-with-azure-openai-/4041003) where tripping on 429 routes to a healthy replica, there is no failover target here.
- 503 is semantically correct per [RFC 7231 §6.6.4](https://www.rfc-editor.org/rfc/rfc7231#section-6.6.4) (server-scoped unavailability). [RFC 6585 §4](https://www.rfc-editor.org/rfc/rfc6585#section-4) defines 429 as a client-scoped rate limit — a different condition.
- **SDK exception type:** The OpenAI Python SDK retries 503 automatically as `openai.InternalServerError` (not `RateLimitError`). Application code branching on `RateLimitError` will miss circuit-breaker trips. Rely on `x-circuit-breaker-open: true` to distinguish. See [openai-python retry logic](https://deepwiki.com/openai/openai-python/3.4-error-handling-and-retry-logic).
- The circuit auto-recovers after the `trip_duration` (PT1M = 60 seconds). Clients should respect the `Retry-After: 60` header.
- Check APIM Event Grid events for `Microsoft.ApiManagement.BackendCircuitBreakerOpened` / `BackendCircuitBreakerClosed` to correlate when tripping occurred.
- If the circuit trips repeatedly, investigate the underlying backend health in the Azure Portal (OpenAI / Document Intelligence / AI Search / Storage / Speech Services).
