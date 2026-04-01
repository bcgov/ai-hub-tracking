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
| `PRIMARY_TENANT` | test helper constant | `ai-hub-admin` |
| `LOW_QUOTA_TENANT` | test helper constant | `nr-dap-fish-wildlife` |

Subscription keys are loaded per tenant from env vars or terraform outputs, most commonly `AI_HUB_ADMIN_SUBSCRIPTION_KEY` and `NRDAP_SUBSCRIPTION_KEY`.

### Dynamic Model Loading
- `IntegrationConfig.get_tenant_models(tenant)` reads `infra-ai-hub/params/<env>/tenants/<tenant>/tenant.tfvars`
- `IntegrationConfig.get_tenant_chat_models(tenant)` filters out `*embedding*` and `*codex*` models

## Helper Functions Reference

### HTTP Request Wrappers
| Function | Auth Header | Retry | Use Case |
|---|---|---|---|
| `ApimClient.request(..., auth_mode="api-key")` | `api-key` | Optional | Standard API calls |
| `ApimClient.request(..., auth_mode="bearer")` | `Authorization: Bearer` | Optional | App Gateway header-normalization coverage |
| `ApimClient.request(..., auth_mode="ocp")` | `Ocp-Apim-Subscription-Key` | Optional | Legacy header compatibility coverage |
| `ApimClient.request(..., retry=True)` | caller-selected | 429/503/transport | Flaky or rate-limited endpoints |

### High-Level API Calls
| Function | Purpose |
|---|---|
| `ApimClient.chat_completion()` | Builds deployment-route chat completion JSON and handles GPT-5 parameter differences |
| `ApimClient.chat_completion_v1()` | Same for `/openai/v1/chat/completions` |
| `ApimClient.docint_analyze()` | Document Intelligence analyze via JSON `base64Source` |
| `ApimClient.docint_analyze_file()` | Reads file, base64-encodes, and posts JSON |
| `ApimClient.docint_analyze_binary()` | Sends file as `application/octet-stream` |
| `ApimClient.docint_analyze_pdf()` | Sends file as `application/pdf` |
| `ApimClient.docint_analyze_multipart()` | Sends file as `multipart/form-data` |

### Response Parsing
| Function | Purpose |
|---|---|
| `response_json()` | Parses JSON and sanitizes `[REDACTED_PHONE]` → `0` first |
| `operation_location()` | Extracts the `Operation-Location` header |
| `ApimClient.extract_operation_path()` | Strips gateway URL prefix from Operation-Location |

### Assertions
| Function | Purpose |
|---|---|
| `assert_status()` | Compares expected vs actual HTTP status; auto-skips on 429 if `SKIP_ON_RATE_LIMIT=true` |
| `require_key()` | Skips when a tenant subscription key is unavailable |
| `require_appgw()` | Skips when App Gateway is not deployed |

### Async Polling
| Function | Purpose |
|---|---|
| `ApimClient.wait_for_operation()` | Polls Document Intelligence operation path every 2s until `succeeded`/`completed`/`failed` or timeout |

### Key Vault Fallback
| Function | Purpose |
|---|---|
| `ApimClient.refresh_tenant_key_from_vault()` | Refreshes a tenant key from Azure Key Vault using rotation metadata `safe_slot` |

## Retry Logic

`ApimClient.request(..., retry=True)` uses exponential backoff:
- **Max retries**: 5
- **Initial delay**: 5s, **multiplier**: 2x, **max delay**: 60s
- **Retries on**: transport failures, `429` (rate limit), `503` (transient)
- **Does NOT retry** `503` with `error.code = PiiRedactionFailed`
- **429 delay**: uses the `Retry-After` response header if present

## Document Intelligence Async Flow

```
1. Submit → `ApimClient.docint_analyze_file(tenant, model, file_path)`
2. Read   → `response.status_code` (`200` or `202`)
3. Header → `operation_location(response)`
4. Path   → `ApimClient.extract_operation_path(tenant, operation_url)`
5. Poll   → `ApimClient.wait_for_operation(tenant, path, 60)`
6. Assert → `response_json(response)["analyzeResult"]`
```

### Operation-Location Validation
- **Must contain** App Gateway hostname (`${APPGW_HOSTNAME}`)
- **Must NOT contain** `cognitiveservices.azure.com` (direct backend leak)
- **Must NOT contain** `azure-api.net` (direct APIM, bypasses App GW)

## GPT-5 Model Handling

`ApimClient.chat_completion()` and `.chat_completion_v1()` detect `gpt-5*` model names and adjust:
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

`response_json()` replaces `[REDACTED_PHONE]` with `0` before JSON parsing. This works around BC Gov DLP proxies that redact Unix timestamps in HTTP response bodies, breaking JSON structure.

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

### Critical: Preserve SSE line parsing in Python
The pytest harness parses SSE responses in Python instead of shell pipelines. Keep the equivalent safeguards:
```python
lines = [line.strip() for line in response.text.replace("\r", "").splitlines() if line.strip()]
data_lines = [line for line in lines if line.startswith("data: ")]
chunks = [json.loads(line.removeprefix("data: ")) for line in data_lines if line.startswith("data: {")]
```

Do not assume the first SSE chunk is a chat delta; filter on `object == "chat.completion.chunk"` before asserting content.

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
