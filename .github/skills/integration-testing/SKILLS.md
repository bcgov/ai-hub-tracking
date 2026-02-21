---
name: Integration Testing
description: Guidance for writing and running bats-core integration tests against APIM, App Gateway, and AI services in ai-hub-tracking.
---

# Integration Testing Skills

Use this skill profile when creating, modifying, or debugging integration tests in this repo.

## Use When
- Writing new bats test suites or adding tests to existing `.bats` files
- Modifying test helpers, config loading, or assertion patterns
- Debugging test failures in CI or local runs
- Extending the test runner (`run-tests.sh`) with new options or suites

## Do Not Use When
- Changing APIM policy behavior without updating tests (use API Management first, then come here)
- Modifying Terraform infrastructure (use IaC Coder)
- Reviewing changes without implementation (use IaC Code Reviewer)

## Input Contract
Required context before making test changes:
- Which tenant(s), API paths, and expected backend behaviors are under test
- Feature flags that gate the behavior (e.g., `document_intelligence_enabled`, `pii_redaction_enabled`)
- Whether test requires App Gateway (`skip_if_no_appgw`) or specific subscription keys

## Output Contract
Every test change should deliver:
- Well-structured `@test` blocks with descriptive names following `"TENANT: Behavior statement"` convention
- Proper skip guards for missing keys, disabled features, or App Gateway absence
- Assertions using existing helper functions (`assert_status`, `assert_contains`, `json_get`)
- No hardcoded URLs, keys, or model names — use config variables

## Scope
- Test framework: **bats-core** (Bash Automated Testing System)
- Test files: `tests/integration/*.bats`
- Shared helpers: `tests/integration/test-helper.bash`, `tests/integration/config.bash`
- Test runner: `tests/integration/run-tests.sh`
- Standalone scripts: `tests/integration/verify-key-rotation.sh`, `tests/integration/test-apim-keys-quick.sh`

## Test Suites

| File | Focus |
|---|---|
| `chat-completions.bats` | OpenAI chat API, multi-model, multi-tenant |
| `document-intelligence.bats` | Document Intelligence JSON/async, Operation-Location rewrite |
| `document-intelligence-binary.bats` | WAF custom rule for binary uploads (requires App GW) |
| `pii-redaction.bats` | PII redaction in responses (tenant-specific enable/disable) |
| `pii-coverage.bats` | Language Service 5-doc limit detection (fail-closed vs fail-open) |
| `pii-chunking.bats` | Large payload chunking for PII (2k, 15k, 30k payloads) |
| `subscription-key-header.bats` | `Ocp-Apim-Subscription-Key` header variant |
| `app-gateway.bats` | App Gateway health, TLS, routing |
| `apim-key-rotation.bats` | `/internal/apim-keys` endpoint, Key Vault rotation metadata |
| `tenant-user-management.bats` | Tenant user management RBAC |

## File Structure Pattern

Every `.bats` file follows this structure:

```bats
#!/usr/bin/env bats
load 'test-helper'

# Optional: per-file skip guard (defined locally, not centralized)
skip_if_no_key() {
    local key
    key=$(get_subscription_key "$1")
    if [[ -z "${key}" ]]; then
        skip "No subscription key for tenant: $1"
    fi
}

# Optional: runs once before all tests in this file
setup_file() {
    # One-time setup (e.g., parse shared.tfvars for feature flags)
}

# Runs before every @test
setup() {
    setup_test_suite
}

@test "TENANT: Descriptive behavior statement" {
    skip_if_no_key "wlrs-water-form-assistant"

    response=$(chat_completion "wlrs-water-form-assistant" "${DEFAULT_MODEL}" "prompt" 10)
    parse_response "${response}"
    assert_status "200" "${RESPONSE_STATUS}"
}
```

### Key conventions:
- `load 'test-helper'` — loads both `test-helper.bash` and `config.bash` (transitive)
- `setup()` always calls `setup_test_suite` — checks prerequisites and loads config
- `setup_file()` is optional, for one-time expensive setup
- `skip_if_no_key` is **defined per-file** (not centralized) — copy the pattern from existing suites
- Test names follow `"TENANT: Behavior statement"` format

## Config Loading (3-Tier Priority)

1. **Environment variables** — if `APIM_GATEWAY_URL` + subscription keys are already set, used as-is
2. **Terraform outputs** — `deploy-terraform.sh output <env>` extracts stack-aggregated outputs
3. **shared.tfvars parsing** — `load_shared_tfvars_config()` parses HCL for App Gateway settings

### Key Config Variables

| Variable | Source | Description |
|---|---|---|
| `TEST_ENV` | env var / CLI | Target environment (`dev`, `test`, `prod`) |
| `APIM_GATEWAY_URL` | terraform output | Base URL for all API calls |
| `APPGW_DEPLOYED` | derived | `true` if App Gateway URL is non-empty |
| `APPGW_HOSTNAME` | shared.tfvars | App Gateway frontend hostname |
| `HUB_KEYVAULT_NAME` | terraform output | Hub Key Vault for key rotation fallback |
| `OPENAI_API_VERSION` | hardcoded | `2024-10-21` |
| `DOCINT_API_VERSION` | hardcoded | `2024-11-30` |
| `DEFAULT_MODEL` | hardcoded | `gpt-4.1-mini` |
| `TENANTS` | hardcoded array | `wlrs-water-form-assistant`, `sdpr-invoice-automation`, `nr-dap-fish-wildlife` |

Subscription keys are per-tenant: `WLRS_SUBSCRIPTION_KEY`, `SDPR_SUBSCRIPTION_KEY`, `NRDAP_SUBSCRIPTION_KEY`.

### Dynamic Model Loading
- `get_tenant_models <tenant>` — reads `infra-ai-hub/params/${env}/tenants/${tenant}/tenant.tfvars`, extracts `name = "..."` patterns
- `get_tenant_chat_models <tenant>` — filters out `*embedding*` and `*codex*` models

## Helper Functions Reference

### HTTP Request Wrappers
| Function | Auth Header | Retry | Use Case |
|---|---|---|---|
| `apim_request` | `api-key` | Auto-retry on 401 (vault refresh) | Standard API calls |
| `apim_request_ocp` | `Ocp-Apim-Subscription-Key` | Auto-retry on 401 | Legacy SDK testing |
| `apim_request_with_retry` | `api-key` | Exponential backoff (429/503/000) | Flaky or rate-limited endpoints |
| `apim_request_with_retry_ocp` | `Ocp-Apim-Subscription-Key` | Exponential backoff | Legacy + retry |

### High-Level API Calls
| Function | Purpose |
|---|---|
| `chat_completion` | Builds chat completion JSON, handles GPT-5 model differences |
| `chat_completion_ocp` | Same with `Ocp-Apim-Subscription-Key` header |
| `docint_analyze` | Document Intelligence analyze via JSON `base64Source` |
| `docint_analyze_file` | Reads file, base64-encodes, sends as WAF-safe JSON (returns full response with headers) |
| `docint_analyze_binary` | Sends file as `application/octet-stream` (tests WAF custom rule) |
| `docint_analyze_pdf` | Sends file as `application/pdf` |
| `docint_analyze_multipart` | Sends file as `multipart/form-data` |

### Response Parsing
| Function | Purpose |
|---|---|
| `parse_response` | Splits curl output into `RESPONSE_BODY` + `RESPONSE_STATUS` |
| `json_get` | Extracts jq path; sanitizes `[REDACTED_PHONE]` → `0` first |
| `extract_http_status` | Extracts HTTP status from full response headers |
| `extract_response_body` | Extracts body from full response (after blank line) |
| `extract_operation_path` | Strips gateway URL prefix from Operation-Location |

### Assertions
| Function | Purpose |
|---|---|
| `assert_status` | Compares expected vs actual HTTP status; auto-skips on 429 if `SKIP_ON_RATE_LIMIT=true` |
| `assert_contains` | Asserts substring presence |
| `assert_not_contains` | Asserts substring absence |
| `looks_like_pii` | Regex match for email, phone, SSN patterns |
| `is_redacted` | Checks for `*`, `[REDACTED]`, `XXXXX` markers |

### Async Polling
| Function | Purpose |
|---|---|
| `wait_for_operation` | Polls Document Intelligence operation path every 2s until `succeeded`/`completed`/`failed` or timeout |

### Key Vault Fallback
| Function | Purpose |
|---|---|
| `get_tenant_key_from_vault` | Refreshes key from Azure Key Vault using rotation metadata `safe_slot` |
| `refresh_tenant_key_from_vault` | Calls above and updates the env var via `set_subscription_key` |

## Retry Logic

`apim_request_with_retry` uses exponential backoff:
- **Max retries**: 5
- **Initial delay**: 5s, **multiplier**: 2x, **max delay**: 60s
- **Retries on**: `000` (transport failure), `429` (rate limit), `503` (transient)
- **Does NOT retry** `503` with `failure_reason=partial-redaction` (intentional PII coverage block)
- **429 delay**: uses `retry-after` from response body if available

## Document Intelligence Async Flow

```
1. Submit → docint_analyze_file "tenant" "model" "file.jpg"
2. Parse  → extract_http_status (expect 202)
3. Header → extract Operation-Location URL
4. Path   → extract_operation_path (strip gateway prefix)
5. Poll   → wait_for_operation "tenant" "path" 60
6. Assert → json_get ".analyzeResult.content" / ".analyzeResult.pages"
```

### Operation-Location Validation
- **Must contain** App Gateway hostname (`${APPGW_HOSTNAME}`)
- **Must NOT contain** `cognitiveservices.azure.com` (direct backend leak)
- **Must NOT contain** `azure-api.net` (direct APIM, bypasses App GW)

## GPT-5 Model Handling

`chat_completion` detects `gpt-5*` model names and adjusts:
- Uses `max_completion_tokens` instead of `max_tokens`
- Does not set custom `temperature`
- This avoids 400 errors from GPT-5 API parameter validation

## WAF Considerations

- WAF inspects the first 128KB of request body
- Binary uploads (`application/octet-stream`) are blocked by WAF managed rules by default
- **Use JSON base64 encoding** via `docint_analyze_file` for standard tests
- `docint_analyze_binary`/`docint_analyze_pdf`/`docint_analyze_multipart` test WAF custom rules that allowlist specific content types
- Binary upload tests require App Gateway (`skip_if_no_appgw`)

## DLP Sanitization

`json_get` replaces `[REDACTED_PHONE]` with `0` before jq parsing. This works around BC Gov DLP proxies that redact Unix timestamps in HTTP response bodies, breaking JSON structure. Without this, `jq` fails on responses containing redacted numeric fields.

## Running Tests

### Via test runner (recommended):
```bash
# All tests against test environment
./tests/integration/run-tests.sh test

# Specific suites
./tests/integration/run-tests.sh test chat-completions.bats document-intelligence.bats

# Exclude slow suites
./tests/integration/run-tests.sh --exclude pii-chunking.bats,document-intelligence-binary.bats test

# Verbose output
./tests/integration/run-tests.sh -v test
```

### Direct bats (when debugging a single test):
```bash
cd tests/integration
bats --tap chat-completions.bats
```

### In CI:
Tests run via `.integration-tests-using-secure-tunnel.yml` through chisel+privoxy proxy to reach VNet-isolated resources. Config is loaded from terraform outputs automatically.

## Skip Patterns

| Pattern | When to use |
|---|---|
| `skip_if_no_key "tenant"` | Test requires a tenant subscription key |
| `skip_if_no_appgw` | Test requires App Gateway to be deployed |
| `skip "reason"` | Inline skip for conditionally disabled features |
| `SKIP_ON_RATE_LIMIT=true` | `assert_status` auto-skips on 429 instead of failing |

## Validation Gates (Required)
1. All new `@test` blocks follow the `"TENANT: Behavior"` naming convention
2. Skip guards present for tenant keys and optional infrastructure
3. No hardcoded URLs, keys, model names, or API versions — use config variables
4. Retry-safe: use `_with_retry` variants for endpoints prone to 429/503
5. Async flows use `wait_for_operation` with appropriate timeouts (60s default)
6. `bash -n tests/integration/*.bats` passes (syntax check)

## Failure Playbook

### Tests fail with 401 Unauthorized
- Key rotation may have invalidated the cached key. Check if `ENABLE_VAULT_KEY_FALLBACK=true` — the helper auto-retries once from Key Vault.
- If still failing, verify `safe_slot` in Key Vault rotation metadata matches the active APIM subscription key slot.

### Tests timeout on Document Intelligence
- `prebuilt-invoice` takes 90-150s on S0 tier. Use `prebuilt-layout` (~10-20s) for CI tests.
- Check `wait_for_operation` timeout — default 60s may be insufficient for invoice model.

### Tests show `[REDACTED_PHONE]` in JSON parse errors
- The DLP proxy is redacting timestamps. `json_get` handles this automatically. If you're using raw `jq`, pipe through `sed 's/\[REDACTED_PHONE\]/0/g'` first.

### All tests skip with "No subscription key"
- Terraform outputs may not be loaded. Check `run-tests.sh` config loading path.
- Verify `deploy-terraform.sh output <env>` returns valid JSON with `apim_tenant_subscriptions`.

### Rate limit (429) cascade
- Set `SKIP_ON_RATE_LIMIT=true` for non-critical test suites.
- Use `_with_retry` variants and stagger tenant requests.
