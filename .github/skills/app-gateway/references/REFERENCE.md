# App Gateway & WAF — Detailed Reference

Supplementary reference for the [App Gateway & WAF skill](../SKILL.md). Load this file when you need WAF design rationale, rewrite condition details, module architecture, or failure playbooks.

## Priority Design Pattern

The Allow-first + Block-remainder pattern is intentional:

```
Priorities 3-5:  Allow ALL authenticated requests (api-key, Ocp-key, Bearer)
Priority 10:     Block ALL unauthenticated requests to API paths
Priorities 11-25: Defence-in-depth Allow rules per service (+ OWASP bypasses)
Priorities 90-91: Rate limiting
```

**Why not use negation to detect absent headers?**
Azure WAF cannot reliably detect absent headers via negation — the engine skips absent-header conditions instead of evaluating them as non-matching. The correct pattern is: **Allow-first (p3/p4/p5) + Block-remainder (p10)**.

## Adding New Auth Header Types

When adding a new authentication header format:
1. Add a new Allow rule at the next available priority (e.g., p6) with the header match condition
2. Update `RateLimitUnauthenticated` (p91) to add a negation condition for the new header
3. Update the AppGW rewrite rules to map the new header → `api-key` for APIM
4. **Do NOT add normalization to APIM policies** — it will never execute for unauthenticated requests

## Adding New Service-Specific Allow Rules

Service-specific Allow rules (p11-25) exist for OWASP managed rule bypass and defence-in-depth:
1. Use priorities 11-25 range, always in api-key/Ocp-key pairs
2. These rules are technically redundant for authentication (p3-5 already Allow) but necessary to bypass OWASP false positives on specific content types (e.g., DocInt binary uploads, Speech SSML/XML)

## WAF Body Size Limits

| Setting | Default | Purpose |
|---|---|---|
| `request_body_enforcement` | `true` | Reject oversized bodies |
| `request_body_inspect_limit_in_kb` | `128` | How deep WAF inspects for threats |
| `max_request_body_size_kb` | `128` | Hard body size limit |
| `file_upload_limit_mb` | `100` | File upload limit |

CRS 3.2+ supports independent body enforcement: `request_body_enforcement=false` lets large payloads through while still inspecting up to `request_body_inspect_limit_in_kb` for threats.

## Bearer Token Rewrite Details

The `map-bearer-token-to-api-key` rule (sequence 95):
- **Condition 1** (`bearer_token_present`): `http_req_Authorization` matches `^Bearer (.+)$` (case-insensitive)
- **Condition 2** (`api_key_absent`): `http_req_api-key` does NOT match `.+` (negate=true)
- **Action**: Sets `api-key` header to `{http_req_Authorization_1}` (capture group 1 = token without "Bearer " prefix)
- The `api_key_absent` condition prevents overwriting when a client sends both `api-key` and `Authorization: Bearer`

## AppGW Server Variables

When referencing AppGW server variables in rewrite rules:
- `{http_req_HeaderName}` — request header value (use capture groups with `_1`, `_2` suffixes)
- `{var_host}` — original client hostname
- `{var_client_ip}` — original caller IP
- Azure AppGW variables require the `var_` prefix; `{client_ip}` alone is invalid

## Rewrite Rule Conditions

Conditions use regex matching against server variables:
- All conditions in a rule are AND-ed (all must match for the rule to fire)
- `negate = true` inverts the match (true when pattern does NOT match)
- `ignore_case = true` for case-insensitive matching
- Capture groups are referenced as `{variable_name_N}` where N is the group number

## Module Architecture

### WAF Policy Module (`modules/waf-policy/`)
- Creates `azurerm_web_application_firewall_policy`
- Accepts `custom_rules`, `managed_rule_sets`, `exclusions` as variables
- Rate-limit-specific fields (`rate_limit_duration`, `rate_limit_threshold`, `group_rate_limit_by`) are only set when `rule_type = "RateLimitRule"`
- Tags use `lifecycle { ignore_changes = [tags] }`

### App Gateway Module (`modules/app-gateway/`)
- Creates native `azurerm_application_gateway` (not AVM — AVM does not expose `lifecycle ignore_changes` for portal SSL cert uploads)
- Supports: HTTPS listeners, HTTP→HTTPS redirect, SSL via Key Vault or portal upload, rewrite rule sets, URL path maps, WAF configuration (inline or external policy)
- External WAF policy linked via `firewall_policy_id`
- Rewrite rule set is attached to the HTTPS routing rule
- SSL certificates use `lifecycle { ignore_changes = [ssl_certificate] }` to support portal-managed cert rotation
- User-assigned managed identity for Key Vault SSL cert access
- Diagnostic settings with `log_analytics_destination_type = "Dedicated"` (resource-specific tables)

### Wiring in `stacks/shared/`
- `locals.tf` defines `default_waf_custom_rules` and `default_waf_managed_rule_sets`
- `main.tf` passes these to `module "waf_policy"` and `module "app_gateway"`
- Per-env overrides possible via `appgw_config.custom_rules` in `params/{env}/shared.tfvars`
- AppGW is conditional: `count = local.appgw_config.enabled && local.apim_config.enabled ? 1 : 0`
- WAF policy is conditional: `count = local.appgw_config.enabled && lookup(local.appgw_config, "waf_policy_enabled", true) ? 1 : 0`

## Testing Notes

- WAF blocks are surfaced as HTTP 403 with Azure WAF body — test unauthenticated requests return 403
- Bearer token auth must pass through WAF (not 403) and reach APIM
- Rewrite rules can be verified by checking APIM receives expected headers (e.g., `api-key` is present)
- Test both `/deployments/` and `/v1/` paths through App Gateway
- Rate limit rules can be tested by exceeding thresholds from a single IP

## Failure Playbook

### Requests returning 403 unexpectedly
- Check WAF custom rule priority ordering — authenticated requests may be hitting `BlockUnauthenticatedApiPaths` (p10) before the Allow rule
- Verify the client's auth header format matches a WAF Allow rule pattern
- Check if a new auth header type was added without a corresponding WAF Allow rule

### Bearer token requests getting 401 from APIM
- Verify AppGW rewrite rule `map-bearer-token-to-api-key` (seq 95) is correctly extracting the token
- Check capture group reference: `{http_req_Authorization_1}` must match the regex group
- Confirm the `api_key_absent` condition is not incorrectly blocking the rewrite

### OWASP false positives on legitimate traffic
- Add service-specific Allow rules (p11-25) with content-type conditions to bypass OWASP
- Or add WAF exclusions via `waf_exclusions` in `appgw_config`

### Rate limiting too aggressive
- Adjust `rate_limit_threshold` in the relevant rule
- Check if `RateLimitUnauthenticated` (p91) is incorrectly matching authenticated requests (missing header negation)
