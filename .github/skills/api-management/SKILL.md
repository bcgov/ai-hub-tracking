---
name: api-management
description: Guidance for APIM policies, routing, and backend configuration in ai-hub-tracking. Use when modifying APIM inbound/outbound policies, rate limiting, backend routing, or API key authentication.
---

# API Management Skills

Use this skill profile when creating or modifying APIM policies and routing behavior.

## Use When
- Updating APIM inbound/backend/outbound policy logic in the shared template
- Adding, changing, or debugging feature-flag-driven backend routing
- Modifying APIM rate limiting, PII redaction, or deployment name rewrite logic
- Adding or modifying the global policy (`global_policy.xml`)

## Do Not Use When
- Changing App Gateway rewrite rules or WAF custom rules (use [App Gateway & WAF](../app-gateway/SKILL.md))
- Changing infrastructure modules/workflows unrelated to APIM policy behavior
- Performing review-only tasks without implementation changes
- Editing docs-only pages under `docs/` with no policy change

## Input Contract
Required context before policy edits:
- Target tenant feature flags and intended route behavior
- Expected backend target(s), auth mode, and required headers
- Affected paths and expected status codes for success/failure cases

## Output Contract
Every APIM policy change should deliver:
- Shared-template updates only (`api_policy.xml.tftpl` + rendering vars where needed)
- Backward-compatible conditional routing (unless breaking change explicitly requested)
- Updated tests/validation notes for impacted routes
- Clear operator guidance for rollout and verification

## External Documentation
- Use [External Docs Research](../external-docs/SKILL.md) as the single source of truth for external documentation workflow and fallback approval requirements.

## Documentation Sync
- If the change adds, removes, renames, or materially reorganizes tracked files or directories, update the root `README.md` `Folder Structure` section in the same change. Do not add gitignored or local-only artifacts to that tree.
- Review the documentation sync matrix in [../../copilot-instructions.md](../../copilot-instructions.md) and update any area-specific README or docs pages it calls out for the touched subtree.

## Request Flow Architecture

APIM sits behind App Gateway in the request chain. Understanding this layering is critical:

```
Client → WAF (custom rules) → App Gateway (rewrite rules) → APIM global policy → APIM API policy → Backend
```

**Key implications:**
- **No subscription key normalization in APIM**. APIM is configured with `subscription_key_parameter_names = { header = "api-key", query = "api-key" }` (set in `stacks/apim/locals.tf`). This means APIM validates the `api-key` header *before* policies execute — requests missing `api-key` are rejected with 401 before any policy code runs. All key normalization (`Ocp-Apim-Subscription-Key` → `api-key`, `Authorization: Bearer` → `api-key`) is handled by App Gateway rewrite rules (see [App Gateway & WAF](../app-gateway/SKILL.md)).
- **Do not add key normalization logic to APIM policies** — it will never execute for requests missing the `api-key` header.
- The global policy (`global_policy.xml`) handles: client IP extraction, correlation IDs, and token metrics only.

## Policy Locations
- There is **one shared API policy template** for all tenants:
  `infra-ai-hub/params/apim/api_policy.xml.tftpl`
- There is **one global policy** for all APIs:
  `infra-ai-hub/params/apim/global_policy.xml`
- The API policy is rendered per-tenant in `stacks/apim/locals.tf` via `templatefile()` (not `file()`).
- All routing sections are conditional — enabled/disabled per tenant via `tenant.tfvars` feature flags (e.g., `openai_enabled`, `speech_services_enabled`, `document_intelligence_enabled`, `ai_search_enabled`, `storage_enabled`, `key_rotation_enabled`).
- There are **no per-tenant XML files**. Do not create `tenants/{tenant}/api_policy.xml` files.

> **PII integration test impact**: changes to `infra-ai-hub/params/apim/fragments/pii-anonymization.xml` or any PII-related section of `api_policy.xml.tftpl` **require** reviewing the Python integration harness under `tests/integration/tests/` and adding or updating scenario coverage when the error contract changes. The shared harness no longer keeps dedicated `pii-*.bats` suites. See [PII Redaction Service](../pii-redaction-service/SKILL.md) for service-specific validation guidance.

## Routing Rules (Current Pattern)
All routes live inside a single `<choose>` block in the inbound section. Routes are conditionally included:

| Route | Path condition | Feature flag |
|---|---|---|
| APIM keys internal endpoint | path ends with `internal/apim-keys` | `apim_keys_endpoint_enabled` |
| Tenant info internal endpoint | path ends with `internal/tenant-info` | `tenant_info_enabled` (always `true`) |
| Document Intelligence | path contains `documentintelligence`, `formrecognizer`, or `documentmodels` | `document_intelligence_enabled` |
| OpenAI | path contains `openai` | `openai_enabled` (auto-set when `model_deployments` is non-empty) |
| Speech STT | path contains `speech/recognition` or `/stt/` | `speech_services_enabled` |
| Speech TTS | path contains `cognitiveservices/voices`, `cognitiveservices/v1`, or `speech/synthesis` | `speech_services_enabled` |
| AI Search | path contains `ai-search` | `ai_search_enabled` |
| Storage | path contains `storage` | `storage_enabled` |
| Default | all other paths | always present — returns **404 JSON** |

### Mistral Routing Rule
- Mistral chat models must be exposed only on the OpenAI-compatible path: `/openai/v1/chat/completions`.
- Do not allow or reintroduce chat aliases under `/providers/mistral/models/{model}/chat/completions`.
- `/providers/mistral/*` is reserved for Mistral OCR/document endpoints such as `/providers/mistral/azure/ocr`.
- This preserves OpenAI-only token metrics and token rate limiting, which are scoped to `openai` paths in both the global and API policies.

## Authentication & Headers
MSI target varies by backend type — do not assume `cognitiveservices.azure.com` universally:

| Backend | MSI resource | Notes |
|---|---|---|
| OpenAI / Document Intelligence | `https://cognitiveservices.azure.com` | Standard cognitive services MSI |
| AI Search | `https://search.azure.com` | |
| Storage | `https://storage.azure.com` | |
| Key Vault (key rotation) | `https://vault.azure.net` | Uses `kv-token` variable name |
| Speech (STT/TTS) | None — backend has credentials configured | Remove all incoming `Authorization` + `api-key` headers |

Always:
- Set `X-Tenant-Id` to the tenant name in the inbound policy.
- Delete `api-key` header for all MSI-authenticated backends.

## Rate Limiting
- Per-model rate limiting is the default: each `model_deployments` entry in `tenant.tfvars` gets its own `<llm-token-limit>` keyed by `{subscriptionId}-{modelName}`.
- Provisioned PTU models can use a dedicated APIM backend plus response-weighted `<rate-limit-by-key>` accounting for non-streaming traffic when the Foundry model weights completion tokens more heavily than prompt tokens.
- When using response-weighted PTU accounting, keep a conservative raw `<llm-token-limit>` fallback for streaming requests because APIM cannot reliably parse final SSE usage before the stream is returned.
- A fallback `<llm-token-limit>` handles unrecognized deployment names.
- If `model_deployments` is empty, a single subscription-level token limit applies.
- Emit `x-ratelimit-remaining-tokens` header for observability.
- Controlled by `rate_limiting_enabled` flag.
- **Rate limiting MUST be scoped to OpenAI paths only** (wrapped in `<when condition="@(context.Request.Url.Path.ToLower().Contains(&quot;openai&quot;))">"`). Token counting is meaningless for DocInt/Speech/Search/Storage, and `estimate-prompt-tokens="true"` on large binary payloads (e.g., 500KB base64 images) causes APIM to hang reading/estimating the body before forwarding — resulting in curl timeouts (status 28) on the upstream caller.

### PTU Backend Isolation and Concurrency

PTU capacity is deployed **per-tenant with isolated backends** rather than shared across tenants. For example, a 75 PTU pool is provisioned as 5 separate Azure Foundry/OpenAI deployments of 15 PTUs each — one per tenant (`{tenant_name}-openai-ptu` backend, set in `stacks/apim/locals.tf`). This has two key consequences for rate limiting and concurrency:

1. **Foundry is the authoritative enforcer**: When a tenant's concurrent streaming requests exceed their PTU slice, Azure Foundry returns `429 Too Many Requests`. APIM's existing 429 pass-through (`global_policy.xml` outbound) forwards these to clients with `Retry-After` and `x-should-retry: true`. No APIM-level pessimistic reservation or `max_tokens` deduction is needed.

2. **APIM rate limits are lightweight client-side guards**: `llm-token-limit` and `rate-limit-by-key` prevent obviously runaway requests from hitting the backend, but are not the authoritative concurrency cap. For concurrent spike scenarios, Foundry's native per-deployment quota enforcement is the safety net.

3. **PAYG follows the same pattern**: Azure OpenAI PAYG quota is per-resource. If a tenant's PAYG resource hits its TPM quota, Azure returns 429; APIM passes it through unchanged.

**Do not add pessimistic token reservation** (pre-deducting `max_tokens` from APIM counters before a response is returned). This trades real throughput for marginal protection that Foundry already provides, and was explicitly rejected in the architecture review.

## Error Handling
- For unmatched paths, return structured JSON errors with HTTP 404.
- Keep error messages consistent across tenants.
- Key rotation endpoint returns 405 for non-GET methods and 502 with detail if Key Vault reads fail.
- `/v1/` requests with invalid JSON body return 400 with `InvalidRequestBody` error code.
- `/v1/` requests missing the `model` field return 400 with `MissingModel` error code.
- Circuit breaker trips on **5xx backend failures only** (never 429). When the circuit opens, APIM emits **503 Service Unavailable** with `x-circuit-breaker-open: true`, `Retry-After`, `retry-after-ms`, and `x-should-retry: true`. 503 is semantically correct per [RFC 7231 §6.6.4](https://www.rfc-editor.org/rfc/rfc7231#section-6.6.4) (server-scoped unavailability) — it is not rewritten to 429. Backend 429s pass through `<outbound>` directly with the real `Retry-After` from the backend. The OpenAI Python SDK auto-retries 503 as `openai.InternalServerError`; use `x-circuit-breaker-open: true` to distinguish from real backend faults. See ADR-016.

## Change Checklist
- Add new backends to the **shared template** `params/apim/api_policy.xml.tftpl` behind a feature flag; expose the flag as a `templatefile()` variable in `stacks/apim/locals.tf`.
- Update the `X-Tenant-Id` header when copying policies for a new tenant.
- Verify routing conditions align to desired backend paths.
- For Mistral changes, keep chat traffic on `/openai/*` paths and reserve `/providers/mistral/*` for OCR/document endpoints only.
- Keep `set-backend-service` IDs aligned with APIM backend resources.
- **Use static `backend-id` strings** in all `<set-backend-service>` elements (never dynamic expressions).
- Use the correct MSI resource URL for each backend type (see Authentication table above).
- Avoid changes that bypass Landing Zone networking constraints.
- **Never add subscription key normalization to APIM policies** — App Gateway handles all header mapping.
- For `/v1/` changes, ensure `preserveContent: true` is used on all `Body.As<>()` calls.

## Validation Gates (Required)
1. Route matrix check: each changed path resolves to exactly one intended backend.
2. Auth check: MSI resource/header behavior matches backend type table.
3. Guardrail check: no dynamic backend-id expressions in `set-backend-service`.
4. OpenAI check: deployment rewrite + rate limit scope remain OpenAI-only.
5. Error-path check: unmatched paths and key rotation failures still return structured errors.
6. No-normalization check: APIM policies must not contain subscription key normalization logic.
7. Circuit breaker check: (a) circuit breaker `failure_condition` must only include 5xx status codes — never 429; (b) the global `on-error` 503 handler must keep status 503 (not rewrite it) and set `x-circuit-breaker-open: true`, `x-should-retry: true`, `Retry-After`, and `retry-after-ms`; (c) the global `outbound` 429 handler must set `x-should-retry: true` and `retry-after-ms` for backend rate-limit pass-through.

## Detailed References

For OpenAI endpoint formats, outbound policies, CSHTML parser rules, key rotation details, route validation matrix, and failure playbooks, see [references/REFERENCE.md](references/REFERENCE.md).
