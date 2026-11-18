# Content Understanding Module

Creates a tenant-scoped Microsoft Foundry resource (`kind = AIServices`) that hosts
[Azure Content Understanding](https://learn.microsoft.com/azure/ai-services/content-understanding/overview),
plus the chat-completion and embedding model deployments that Content Understanding uses.

It is called from `modules/tenant` when `content_understanding.enabled = true`.

## Why a separate account per tenant

- **Region.** Content Understanding is region-restricted. Canada Central is on Microsoft's
  [supported-region list](https://learn.microsoft.com/azure/ai-services/content-understanding/language-region-support);
  Canada East (where the shared AI Foundry hub runs) is not (checked 2026-11-16).
- **Isolation.** Content Understanding defaults and custom analyzers are scoped to the account.
  A per-tenant account keeps tenants from sharing analyzers or defaults.
- **Cost.** The account and its model deployments live in the tenant resource group.

## What it creates

| Resource | Notes |
|---|---|
| Foundry account (AVM `avm-res-cognitiveservices-account` 0.7.1, kind `AIServices`) | Public network access disabled, local (key) auth disabled, system-assigned identity, custom subdomain = `name` |
| Model deployments (`cognitive_deployments`) | One per role: `completion`, optional `completion_mini`, `embedding`. Deployment name = model name |
| Private endpoint `pep-<name>` (subresource `account`) | Placed in `private_endpoint_location` (the VNet region). DNS zone group is Landing Zone policy-managed |
| Diagnostic setting `<name>-diag` | Only when `enable_diagnostics = true` |
| `null_resource.wait_for_dns` | Runs `scripts/wait-for-dns-zone.sh` when `scripts_dir` is set |

A `check` block warns (without failing the plan) when `location` is Canada East.

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `name` | string | — | Account name and custom subdomain (globally unique) |
| `location` | string | — | `Canada Central` or `Canada East` (validated) |
| `private_endpoint_location` | string | — | Region of the PE subnet's VNet |
| `resource_group_name` | string | — | Tenant resource group |
| `private_endpoint_subnet_id` | string | — | PE subnet |
| `sku` | string | `S0` | Only valid SKU for `AIServices` |
| `model_deployments` | map(object) | — | Keys `completion`, `embedding` (required), `completion_mini` (optional). Each: `model_name`, `model_version`, `scale_type` (default `GlobalStandard`), `capacity`, `version_upgrade_option` (default `OnceCurrentVersionExpired`) |
| `enable_diagnostics` | bool | `false` | Plan-time flag for the diagnostic setting |
| `log_analytics_workspace_id` | string | `null` | Diagnostics destination |
| `diagnostics` | object | `null` | `log_groups`, `log_categories`, `metric_categories` |
| `scripts_dir` | string | `""` | Shared scripts dir for the DNS wait |
| `private_endpoint_dns_wait` | object | `{}` | `timeout`, `poll_interval` |
| `tags` | map(string) | `{}` | Tags |

## Outputs

| Name | Description |
|---|---|
| `resource_id` | Account resource ID |
| `name` | Account name |
| `endpoint` | Account endpoint (APIM backend URL) |
| `location` | Account region |
| `principal_id` | System-assigned identity principal ID |
| `model_deployments` | Deployment name per role |
| `default_model_deployments` | `modelDeployments` map for `PATCH /contentunderstanding/defaults` |

## Model defaults

Content Understanding needs to know which deployments to use. The module computes the map, including the
prebuilt-analyzer aliases described in
[Models and deployments](https://learn.microsoft.com/azure/ai-services/content-understanding/concepts/models-deployments):

```json
{
  "modelDeployments": {
    "gpt-5.4": "gpt-5.4",
    "gpt-5.4-mini": "gpt-5.4-mini",
    "text-embedding-3-large": "text-embedding-3-large",
    "prebuilt-analyzer-completion": "gpt-5.4",
    "prebuilt-analyzer-completion-mini": "gpt-5.4-mini",
    "prebuilt-analyzer-embedding": "text-embedding-3-large"
  }
}
```

The defaults are a data-plane setting, and the account has public network access disabled, so Terraform
(running on GitHub-hosted runners) cannot set them. Apply them once per tenant through the gateway. The map is
published in the tenant-info endpoint (`services.content_understanding.model_deployments`):

```bash
curl -X PATCH "https://<gateway>/<tenant>/contentunderstanding/defaults?api-version=2025-11-01" \
  -H "api-key: <tenant APIM key>" \
  -H "Content-Type: application/merge-patch+json" \
  -d '{"modelDeployments": { ... }}'
```

`prebuilt-layout`, `prebuilt-read` and `prebuilt-digitalParse` do not need a language or embedding model
([Prebuilt analyzers](https://learn.microsoft.com/azure/ai-services/content-understanding/concepts/prebuilt-analyzers)).

## Data residency

Data at rest stays in the account's region. The model deployments use `GlobalStandard`, the only deployment type
available for these models in `canadacentral` (`az cognitiveservices model list -l canadacentral`, 2026-11-16), so
inference may be processed outside Canada. This matches the existing hub deployments in Canada East.
