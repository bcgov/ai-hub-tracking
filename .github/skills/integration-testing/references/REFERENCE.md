# Integration Testing — Detailed Reference

Supplementary reference for the [Integration Testing skill](../SKILL.md). Load this file when you need detailed function signatures, retry logic, parsing patterns, or failure playbooks.

## Key Config Variables

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

## SSE (Server-Sent Events) Parsing

Azure OpenAI streaming responses use SSE format with `\r\n` line endings. When parsing SSE in bash:

### Critical: Strip `\r` before jq
SSE line endings are `\r\n`. On Linux (including GHA runners), `\r` is preserved and breaks jq parsing:
```bash
# BAD — jq receives {"id":"..."\r} → parse error (exit 2)
echo "${RESPONSE_BODY}" | grep '^data: {' | sed 's/^data: //' | jq -c '...'

# GOOD — strip \r first
echo "${RESPONSE_BODY}" | tr -d '\r' | grep '^data: {' | sed 's/^data: //' | jq -c '...'
```

### Critical: Avoid SIGPIPE under pipefail
`config.bash` enables `set -euo pipefail`. Piping jq output directly to `head -1` causes SIGPIPE when `head` closes the pipe early, which `pipefail` treats as a failure. Split the pipeline:
```bash
# BAD — SIGPIPE from head -1 propagates as pipeline failure
chunk=$(... | jq -c 'select(...)' | head -1)

# GOOD — collect all output first, then take first line
all_chunks=$(... | jq -c 'select(...)') || true
chunk=$(echo "${all_chunks}" | head -1)
```

### Azure OpenAI SSE first chunk
The first SSE data chunk from Azure OpenAI is `prompt_filter_results` (Azure-specific), NOT `chat.completion.chunk`. Filter with:
```bash
jq -c 'select(.object == "chat.completion.chunk")'
```

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
- **Stale env vars**: If `APIM_GATEWAY_URL` or subscription key env vars are set from a prior terminal session, `run-tests.sh` takes the "already loaded" fast path and skips terraform output loading. Clear stale vars before running: `unset APIM_GATEWAY_URL WLRS_SUBSCRIPTION_KEY SDPR_SUBSCRIPTION_KEY NRDAP_SUBSCRIPTION_KEY`.

### Rate limit (429) cascade
- Set `SKIP_ON_RATE_LIMIT=true` for non-critical test suites.
- Use `_with_retry` variants and stagger tenant requests.
