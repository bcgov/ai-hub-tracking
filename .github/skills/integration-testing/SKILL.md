---
name: integration-testing
description: Guidance for writing and running bats-core integration tests against APIM, App Gateway, and AI services in ai-hub-tracking. Use when writing bats test files, debugging test failures, or adding new integration test suites.
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

## External Documentation
- Use [External Docs Research](../external-docs/SKILL.md) as the single source of truth for external documentation workflow and fallback approval requirements.

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
| `app-gateway.bats` | App Gateway TLS, routing |
| `v1-chat-completions.bats` | OpenAI `/v1/` format, streaming SSE, Bearer token auth |
| `apim-key-rotation.bats` | `/internal/apim-keys` endpoint, Key Vault rotation metadata |
| `tenant-user-management.bats` | Tenant user management RBAC |
| `tenant-info.bats` | Tenant info endpoint, model deployments, and feature flags |
| `pii-failure.bats` | PII redaction failure scenarios, fail-closed 503 behavior |
| `mistral.bats` | Mistral chat and OCR routing via APIM |

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
Tests run via `.integration-tests-using-secure-tunnel.yml`. The workflow splits tests into two steps:
1. **No proxy** — all tests except `apim-key-rotation.bats` run **without** `HTTP_PROXY`/`HTTPS_PROXY` because APIM and App Gateway are public endpoints.
2. **With proxy** — only `apim-key-rotation.bats` runs through the chisel+privoxy tunnel because Hub Key Vault has `public_network_access_enabled=false` (private endpoint only).

Config is loaded from terraform outputs automatically.

### Running specific test files:
```bash
# Positional args after --env select specific .bats files
./run-tests.sh --env test v1-chat-completions.bats
./run-tests.sh --env test chat-completions.bats document-intelligence.bats
```

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

## Detailed References

For helper function signatures, config variables, retry logic, SSE parsing patterns, async flow details, and failure playbooks, see [references/REFERENCE.md](references/REFERENCE.md).
