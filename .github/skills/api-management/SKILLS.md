---
name: API Management
description: Guidance for APIM policies, routing, and backend configuration in ai-hub-tracking.
---

# API Management Skills

Use this skill profile when creating or modifying APIM policies and routing behavior.

## Use When
- Updating APIM inbound/backend/outbound policy logic in the shared template
- Adding, changing, or debugging feature-flag-driven backend routing
- Modifying APIM auth/header behavior, rate limiting, or rewrite logic

## Do Not Use When
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

## Policy Locations
- There is **one shared policy template** for all tenants:
  `infra-ai-hub/params/apim/api_policy.xml.tftpl`
- It is rendered per-tenant in `stacks/apim/locals.tf` via `templatefile()` (not `file()`).
- All routing sections are conditional — enabled/disabled per tenant via `tenant.tfvars` feature flags (e.g., `openai_enabled`, `speech_services_enabled`, `document_intelligence_enabled`, `ai_search_enabled`, `storage_enabled`, `key_rotation_enabled`).
- There are **no per-tenant XML files**. Do not create `tenants/{tenant}/api_policy.xml` files.

## Routing Rules (Current Pattern)
All routes live inside a single `<choose>` block in the inbound section. Routes are conditionally included:

| Route | Path condition | Feature flag |
|---|---|---|
| Key rotation internal endpoint | path ends with `internal/apim-keys` | `key_rotation_enabled` |
| Document Intelligence | path contains `documentintelligence`, `formrecognizer`, or `documentmodels` | `document_intelligence_enabled` |
| OpenAI | path contains `openai` | `openai_enabled` (auto-set when `model_deployments` is non-empty) |
| Speech STT | path contains `speech/recognition` or `/stt/` | `speech_services_enabled` |
| Speech TTS | path contains `cognitiveservices/voices`, `cognitiveservices/v1`, or `speech/synthesis` | `speech_services_enabled` |
| AI Search | path contains `ai-search` | `ai_search_enabled` |
| Storage | path contains `storage` | `storage_enabled` |
| Default | all other paths | always present — returns **404 JSON** |

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
- A fallback `<llm-token-limit>` handles unrecognized deployment names.
- If `model_deployments` is empty, a single subscription-level token limit applies.
- Emit `x-ratelimit-remaining-tokens` header for observability.
- Controlled by `rate_limiting_enabled` flag.
- **Rate limiting MUST be scoped to OpenAI paths only** (wrapped in `<when condition="@(context.Request.Url.Path.ToLower().Contains(&quot;openai&quot;))">"`). Token counting is meaningless for DocInt/Speech/Search/Storage, and `estimate-prompt-tokens="true"` on large binary payloads (e.g., 500KB base64 images) causes APIM to hang reading/estimating the body before forwarding — resulting in curl timeouts (status 28) on the upstream caller.

## OpenAI Deployment Name Rewriting
- Client sends a short name (e.g., `gpt-4.1-mini`); the backend expects a tenant-prefixed name (e.g., `wlrs-gpt-4.1-mini`).
- The inbound policy rewrites `/openai/deployments/{name}/...` → `/openai/deployments/{tenant_name}-{name}/...` via `<rewrite-uri>`.

## Outbound Policies
- **Document Intelligence** (`document_intelligence_enabled`): rewrites the `Operation-Location` response header to replace the backend `cognitiveservices.azure.com` URL with the App Gateway URL. This is required for async (202) polling to work through the gateway.
- **OpenAI usage logging** (`usage_logging_enabled`): calls the `openai-usage-logging` fragment on OpenAI responses.

## Document Intelligence: Model Performance
- **`prebuilt-layout`**: Fast (~10-20s for a 500KB JPG on S0 tier). Extracts text, tables, and structure.
- **`prebuilt-invoice`**: Very slow (~90-150s for the same file on S0 tier). Performs field extraction, table parsing, and key-value analysis on top of layout. Cold-start variance adds 20-40s.
- Each tenant gets its own dedicated DocInt Cognitive Services account (S0, 15 TPS quota).
- **CI tests use `prebuilt-layout`** for async flow validation because `prebuilt-invoice` exceeds reliable CI timeout thresholds. The `prebuilt-invoice` model should be validated manually or via longer-running scheduled tests.

## Backend Section
- OpenAI requests use `buffer-request-body="true"` (required for PII redaction and token inspection).
- All other requests use `buffer-request-body="false"`.
- Timeout is configured per-tenant via `backend_timeout_seconds` (default: 300s).

## Error Handling
- For unmatched paths, return structured JSON errors with HTTP 404.
- Keep error messages consistent across tenants.
- Key rotation endpoint returns 405 for non-GET methods and 502 with detail if Key Vault reads fail.

## Policy Template: set-backend-service Must Use Static IDs

**Never** use a dynamic C# expression as the `backend-id` attribute of `<set-backend-service>`:

```xml
<!-- BAD: portal tile renderer fails on this; entire policy falls back to showing only <base /> -->
<set-variable name="speechBackendId" value="@{ ... return &quot;${tenant_name}-speech-stt&quot;; }" />
<set-backend-service backend-id="@((string)context.Variables[&quot;speechBackendId&quot;])" />
```

The Azure Portal visual designer cannot render policy tiles when `backend-id` is a C# expression. The policy **is stored and executes correctly at runtime**, but the portal displays only `<base />` for that API's inbound/backend sections — making it look like no policy is applied.

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

This applies to all backends, not just speech. Any time you need to choose a backend based on the request path, use separate `<when>` blocks with static IDs rather than a variable + dynamic expression.

## Change Checklist
- Add new backends to the **shared template** `params/apim/api_policy.xml.tftpl` behind a feature flag; expose the flag as a `templatefile()` variable in `stacks/apim/locals.tf`.
- Update the `X-Tenant-Id` header when copying policies for a new tenant.
- Verify routing conditions align to desired backend paths.
- Keep `set-backend-service` IDs aligned with APIM backend resources.
- **Use static `backend-id` strings** in all `<set-backend-service>` elements (never dynamic expressions).
- Use the correct MSI resource URL for each backend type (see Authentication table above).
- Avoid changes that bypass Landing Zone networking constraints.

## Testing Notes
- Validate routing for `/openai/*`, `/documentintelligence/*`, `/speech/recognition`, `/cognitiveservices/voices`, `/ai-search/*`, and `/storage/*`.
- Confirm tenant-prefixed deployment names (`{tenant}-{model}`) are correctly rewritten for OpenAI requests.
- Confirm MSI auth works per backend type; verify `api-key` is removed.
- Ensure non-matching paths return 404 JSON error.
- For Document Intelligence async ops, confirm `Operation-Location` header is rewritten to the App Gateway URL.
- Verify Speech backends receive `/stt/` or `/tts/` path prefix after the rewrite.

## Validation Gates (Required)
1. Route matrix check: each changed path resolves to exactly one intended backend.
2. Auth check: MSI resource/header behavior matches backend type table.
3. Guardrail check: no dynamic backend-id expressions in `set-backend-service`.
4. OpenAI check: deployment rewrite + rate limit scope remain OpenAI-only.
5. Error-path check: unmatched paths and key rotation failures still return structured errors.

## Route Validation Matrix Template
Use this table for every APIM change review/runbook:

| Request Path | Feature Flag | Expected Backend ID | Auth Mode | Expected Result |
|---|---|---|---|---|
| `/openai/...` | `openai_enabled` | `${tenant_name}-openai` | MSI (`cognitiveservices`) | 2xx/4xx from backend, not APIM 404 |
| `/documentintelligence/...` | `document_intelligence_enabled` | `${tenant_name}-document-intelligence` | MSI (`cognitiveservices`) | 2xx/202 with rewritten `Operation-Location` |
| `/speech/recognition...` | `speech_services_enabled` | `${tenant_name}-speech-stt` | backend credential | 2xx/4xx from speech backend |
| `/cognitiveservices/voices...` | `speech_services_enabled` | `${tenant_name}-speech-tts` | backend credential | 2xx/4xx from speech backend |
| `/ai-search/...` | `ai_search_enabled` | `${tenant_name}-ai-search` | MSI (`search.azure.com`) | 2xx/4xx from search backend |
| `/storage/...` | `storage_enabled` | `${tenant_name}-storage` | MSI (`storage.azure.com`) | 2xx/4xx from storage backend |
| unmatched path | n/a | none | n/a | APIM 404 JSON |

## Key Rotation

APIM subscription keys are rotated via `infra-ai-hub/scripts/rotate-apim-keys.sh`, scheduled daily by `.github/workflows/apim-key-rotation.yml`.

### Alternating Pattern
```
Rotation 1 (first):  Regenerate SECONDARY → tenants safe on PRIMARY
Rotation 2:          Regenerate PRIMARY   → tenants safe on SECONDARY
Rotation 3:          Regenerate SECONDARY → tenants safe on PRIMARY
...alternates indefinitely. One key is ALWAYS valid.
```

Default interval: 7 days (`ROTATION_INTERVAL_DAYS`).

### Hub Key Vault Secret Naming

All secrets are centralized in a single hub Key Vault with tenant-prefixed names:

| Secret | Content |
|---|---|
| `{tenant}-apim-primary-key` | Current primary subscription key |
| `{tenant}-apim-secondary-key` | Current secondary subscription key |
| `{tenant}-apim-rotation-metadata` | JSON metadata (see below) |

All secrets have a **90-day expiry** to satisfy Landing Zone policy.

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

`safe_slot` indicates which key tenants should currently use (the one **not** regenerated). Integration tests use this for Key Vault key fallback (`get_tenant_key_from_vault` in `test-helper.bash`).

## Failure Playbook
### Portal policy view shows only `<base />`
- Check for dynamic C# expression in `backend-id`; replace with static IDs in separate `<when>` blocks.

### OpenAI requests timeout on large payloads
- Confirm token limiting and prompt estimation are scoped to OpenAI paths only.

### DocInt async polling fails
- Verify `Operation-Location` rewrite is still active and points to App Gateway host.

### Key rotation failures
- Check `apim-key-rotation.yml` workflow logs for az CLI auth errors (OIDC token expiry).
- Verify hub Key Vault exists and OIDC identity has `Key Vault Secrets Officer` role.
- If a rotation is stuck, check `{tenant}-apim-rotation-metadata` for `last_rotated_slot` and manually verify which APIM slot is active.
