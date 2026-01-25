---
name: API Management
description: Guidance for APIM policies, routing, and backend configuration in ai-hub-tracking.
---

# API Management Skills

Use this skill profile when creating or modifying APIM policies and routing behavior.

## Policy Locations
- Per-tenant API policy files live under:
	`infra-ai-hub/params/apim/tenants/{tenant}/api_policy.xml`
- Policy files are loaded from `locals.tf` using `fileexists()` and `file()`.

## Routing Rules (Current Pattern)
- Route **Document Intelligence** requests when the path contains:
	`documentintelligence`, `formrecognizer`, or `documentmodels`.
- Route **OpenAI** requests when the path contains:
	`openai`.
- Default: return **404 Not Found** for unmatched paths.

## Authentication & Headers
- Use managed identity for backends with:
	`authentication-managed-identity` targeting `https://cognitiveservices.azure.com`.
- Set `Authorization` to the MSI bearer token.
- Remove any `api-key` header when using MSI.
- Always set `X-Tenant-Id` to the tenant name in the inbound policy.

## Rate Limiting
- Use token rate limiting to protect backends (LLM token limits).
- Emit remaining token headers for observability.

## Error Handling
- For unmatched paths, return structured JSON errors with HTTP 404.
- Keep error messages consistent across tenants.

## Change Checklist
- Update the `X-Tenant-Id` header when copying policies for a new tenant.
- Verify routing conditions align to desired backend paths.
- Keep `set-backend-service` IDs aligned with APIM backend resources.
- Avoid changes that bypass Landing Zone networking constraints.

## Testing Notes
- Validate routing for `/openai/*` and `/documentintelligence/*` paths.
- Confirm MSI auth works and `api-key` is removed.
- Ensure non-matching paths return 404 JSON error.
