---
name: app-gateway
description: Guidance for Application Gateway rewrite rules, WAF custom rules, and request security layers in ai-hub-tracking. Use when modifying App Gateway rewrite rules, WAF custom rules, subscription key normalization, or SSL configuration.
---

# App Gateway & WAF Skills

Use this skill profile when creating or modifying Azure Application Gateway configuration, rewrite rules, or Web Application Firewall (WAF) custom rules.

## Use When
- Modifying App Gateway rewrite rules (header mapping, URL rewrites)
- Adding, changing, or debugging WAF custom rules (Allow, Block, RateLimit)
- Updating WAF managed rule sets, exclusions, or body size limits
- Debugging requests being blocked before reaching APIM
- Working on subscription key normalization (all key mapping happens at this layer)

## Do Not Use When
- Modifying APIM routing/policy logic only (use [API Management](../api-management/SKILL.md))
- Changing Terraform module structure/variables unrelated to AppGW/WAF behavior (use [IaC Coder](../iac-coder/SKILL.md))
- Editing docs-only pages under `docs/` (use [Documentation](../documentation/SKILL.md))

## Input Contract
Required context before changes:
- Current WAF rule priority map (see Priority Map below)
- Current rewrite rule sequence map (see Rewrite Rules below)
- Intended security behavior: which requests should be allowed/blocked
- Header normalization requirements for APIM subscription key validation

## Output Contract
Every AppGW/WAF change should deliver:
- WAF custom rule changes in `stacks/shared/locals.tf` (`default_waf_custom_rules`)
- Rewrite rule changes in `stacks/shared/main.tf` (inside `rewrite_rule_set`)
- Updated integration tests for App Gateway behavior in `tests/integration/tests/test_app_gateway.py`
- Confirmation that WAF priority ordering is correct (no gaps that create bypass windows)

## External Documentation
- Use [External Docs Research](../external-docs/SKILL.md) as the single source of truth for external documentation workflow and fallback approval requirements.

## Request Flow Architecture

Understanding the evaluation order is **critical**:

```
Client → WAF custom rules (priority-ordered) → App Gateway rewrite rules (sequence-ordered) → APIM
```

**Key implications:**
1. **WAF evaluates BEFORE App Gateway rewrite rules.** If a client sends `Authorization: Bearer <key>` or `Ocp-Apim-Subscription-Key: <key>`, the WAF sees the raw header — NOT the rewritten `api-key`. WAF must explicitly allow all three header types independently.
2. **App Gateway rewrites execute BEFORE APIM.** All header normalization (`Ocp-Apim-Subscription-Key` → `api-key`, `Authorization: Bearer` → `api-key`) is done here so APIM receives a valid `api-key` header.
3. **APIM validates the `api-key` header BEFORE policies execute.** The APIM API is configured with `subscription_key_parameter_names = { header = "api-key", query = "api-key" }` (in `stacks/apim/locals.tf`). Requests missing `api-key` are rejected with 401 before any APIM policy code runs. This is why all normalization must happen at the AppGW layer, not in APIM policies.

## Code Locations

| Component | Location | Purpose |
|---|---|---|
| WAF custom rules (defaults) | `infra-ai-hub/stacks/shared/locals.tf` → `default_waf_custom_rules` | Priority-ordered Allow/Block/RateLimit rules |
| WAF managed rule sets (defaults) | `infra-ai-hub/stacks/shared/locals.tf` → `default_waf_managed_rule_sets` | OWASP 3.2, Bot Manager 1.0 with rule overrides |
| AppGW rewrite rules | `infra-ai-hub/stacks/shared/main.tf` → `rewrite_rule_set` block in `module "app_gateway"` | Header mapping, forwarding metadata |
| WAF policy module | `infra-ai-hub/modules/waf-policy/` | Terraform module for `azurerm_web_application_firewall_policy` |
| App Gateway module | `infra-ai-hub/modules/app-gateway/` | Terraform module for `azurerm_application_gateway` |
| WAF module wiring | `infra-ai-hub/stacks/shared/main.tf` → `module "waf_policy"` | Connects locals to WAF module |
| AppGW module wiring | `infra-ai-hub/stacks/shared/main.tf` → `module "app_gateway"` | Connects WAF policy + rewrites to AppGW |
| Per-env overrides | `infra-ai-hub/params/{env}/shared.tfvars` → `appgw_config.custom_rules` | Optional env-specific overrides (default: uses `default_waf_custom_rules`) |

## WAF Custom Rules

### Priority Map (Current)

Azure WAF custom rule priorities must be **1–100** (inclusive). Evaluation order is lowest-priority-number first. Once a rule matches, no further rules are evaluated.

| Priority | Name | Type | Action | Purpose |
|---|---|---|---|---|
| 1 | `BlockNonCaUsGeo` | MatchRule | Block | Geo-block non-CA/US traffic |
| 3 | `AllowApiKeyHeaderRequests` | MatchRule | Allow | Allow requests with `api-key` header |
| 4 | `AllowOcpKeyHeaderRequests` | MatchRule | Allow | Allow requests with `Ocp-Apim-Subscription-Key` header (mapped to `api-key` by AppGW seq 90) |
| 5 | `AllowBearerTokenRequests` | MatchRule | Allow | Allow requests with `Authorization: Bearer` header (mapped to `api-key` by AppGW seq 95) |
| 10 | `BlockUnauthenticatedApiPaths` | MatchRule | Block | Block keyless requests to non-root paths |
| 11 | `AllowDocIntelFileUploads` | MatchRule | Allow | DocInt binary uploads (OWASP bypass) |
| 12 | `AllowDocIntelJsonWithApiKey` | MatchRule | Allow | DocInt JSON with api-key |
| 13 | `AllowDocIntelJsonWithOcpKey` | MatchRule | Allow | DocInt JSON with Ocp-key |
| 20 | `AllowOpenAiWithApiKey` | MatchRule | Allow | OpenAI with api-key |
| 21 | `AllowOpenAiWithOcpKey` | MatchRule | Allow | OpenAI with Ocp-key |
| 22 | `AllowAiSearchWithApiKey` | MatchRule | Allow | AI Search with api-key |
| 23 | `AllowAiSearchWithOcpKey` | MatchRule | Allow | AI Search with Ocp-key |
| 24 | `AllowSpeechWithApiKey` | MatchRule | Allow | Speech Services with api-key |
| 25 | `AllowSpeechWithOcpKey` | MatchRule | Allow | Speech Services with Ocp-key |
| 90 | `RateLimitPerSourceIP` | RateLimitRule | Block | 300 req/min per source IP |
| 91 | `RateLimitUnauthenticated` | RateLimitRule | Block | 2 req/min for fully unauthenticated requests |

## App Gateway Rewrite Rules

### Rewrite Rule Sequence Map (Current)

Rewrite rules execute in sequence order (lowest first). All rules belong to the `forward-original-host` rewrite rule set.

| Sequence | Name | Purpose |
|---|---|---|
| 90 | `map-ocp-apim-key-to-api-key` | Maps `Ocp-Apim-Subscription-Key` → `api-key` header |
| 95 | `map-bearer-token-to-api-key` | Extracts token from `Authorization: Bearer <token>` → `api-key` header |
| 100 | `add-x-forwarded-host` | Sets `X-Forwarded-Host` to `{var_host}` (original client hostname) |
| 110 | `add-x-forwarded-for` | Sets `X-Forwarded-For` to `{var_client_ip}` (original client IP) |

### Subscription Key Normalization (Critical)

All subscription key normalization happens at the App Gateway layer. APIM does **zero** normalization.

APIM is configured to validate the **`api-key` header** as its subscription key (via `subscription_key_parameter_names` in `stacks/apim/locals.tf`). All other auth headers must be mapped to `api-key` before reaching APIM.

**Supported client auth headers → APIM-expected header:**

| Client sends | AppGW rewrite | APIM receives |
|---|---|---|
| `api-key: <key>` | No rewrite needed | `api-key: <key>` (validates directly) |
| `Ocp-Apim-Subscription-Key: <key>` | Seq 90: copies value to `api-key` | `api-key: <key>` (validates via rewritten header) |
| `Authorization: Bearer <key>` | Seq 95: extracts token → `api-key` | `api-key: <key>` (validates via rewritten header) |

**Why at App Gateway and not APIM?**
APIM validates subscription keys *before* running any policy code. APIM looks for the `api-key` header specifically (configured via `subscription_key_parameter_names`). If a request arrives with only `Authorization: Bearer <key>` or `Ocp-Apim-Subscription-Key: <key>` (no `api-key`), APIM rejects it with 401 before any policy normalization could execute.

## Change Checklist

### WAF Custom Rules
- Verify priority ordering: no priority gaps that create bypass windows
- New Allow rules must be lower priority than `BlockUnauthenticatedApiPaths` (p10) if they protect new auth methods
- New service-specific Allow rules use the 11-25 range in api-key/Ocp-key pairs
- `RateLimitUnauthenticated` (p91) must include negation conditions for ALL supported auth headers
- Azure WAF RequestUri is path-only (e.g., `/resolve`), not the full URL — use `^/path` anchoring

### Rewrite Rules
- Assign sequences that maintain correct ordering (key mapping → metadata headers)
- Key normalization rewrites (90-95) must execute before metadata rewrites (100-110)
- Use `negate = true` conditions to avoid overwriting existing headers
- Test capture group references (`{http_req_Header_1}`) carefully

### General
- Run `terraform fmt -recursive` and `terraform validate` on `stacks/shared/`
- Update integration tests in `tests/integration/tests/test_app_gateway.py`
- Confirm no subscription key normalization was added to APIM policies

## Validation Gates (Required)
1. Priority check: all WAF custom rules have unique priorities in 1-100 range, ordered correctly
2. Auth coverage check: every supported auth header type has both a WAF Allow rule AND an AppGW rewrite rule
3. Rate-limit check: `RateLimitUnauthenticated` includes negation for all auth header types
4. Rewrite sequence check: key normalization rewrites execute before metadata rewrites
5. No-APIM-normalization check: subscription key mapping logic exists only at AppGW layer, not in APIM policies

## Detailed References

For WAF design rationale, rewrite condition details, bearer token internals, module architecture, and failure playbooks, see [references/REFERENCE.md](references/REFERENCE.md).
