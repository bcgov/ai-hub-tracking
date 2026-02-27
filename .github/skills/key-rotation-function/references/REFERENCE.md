# Key Rotation Function — Deep Reference

Supplementary detail for the [Key Rotation Function SKILL.md](../SKILL.md). Read the SKILL.md first for the operational overview.

---

## APIM SDK Patterns

### Client Instantiation

All SDK operations use `DefaultAzureCredential` → Managed Identity in Azure, `az login` / `AzureCLICredential` locally:

```python
from azure.identity import DefaultAzureCredential
from azure.mgmt.apimanagement import ApiManagementClient

credential = DefaultAzureCredential()
client = ApiManagementClient(credential, subscription_id)
```

### Tenant Discovery

Tenants are discovered by listing APIM subscriptions whose `display_name` ends with `"Subscription"`. The tenant name is extracted from the subscription's product scope:

```
scope: /subscriptions/.../products/<tenant-name>
tenant_name = scope.rsplit("/", 1)[-1]
```

This mirrors the original bash script pattern:
```bash
az rest ... | jq '.value[] | select(.properties.displayName | endswith("Subscription"))'
```

### Key Regeneration

The SDK provides separate methods for primary/secondary:
- `client.subscription.regenerate_primary_key(rg, apim, sub_name)`
- `client.subscription.regenerate_secondary_key(rg, apim, sub_name)`

After regeneration, a 10-second propagation wait is observed before reading the new keys.

---

## Key Vault Secret Naming Conventions

| Secret Name | Content | Content Type |
|---|---|---|
| `{tenant}-apim-primary-key` | Current primary subscription key | `text/plain` |
| `{tenant}-apim-secondary-key` | Current secondary subscription key | `text/plain` |
| `{tenant}-apim-rotation-metadata` | JSON rotation state | `application/json` |

### Metadata JSON Structure

```json
{
  "last_rotated_slot": "secondary",
  "last_rotation_at": "2026-02-27T09:00:00Z",
  "next_rotation_at": "2026-03-06T09:00:00Z",
  "rotation_number": 5,
  "safe_slot": "primary"
}
```

### Secret Expiry

All secrets are written with `expires_on` set to `SECRET_EXPIRY_DAYS` (default: 90 days). This satisfies the Azure Landing Zone policy that Key Vault secrets must have an expiry date ≤ 90 days.

### Tags

Each key secret is tagged with:
- `updated-at`: ISO 8601 timestamp
- `rotated`: Which slot was rotated (`primary` or `secondary`)
- `rotation-number`: Incrementing counter

---

## Terraform Module Architecture

### Resources Created

| Resource | Name Pattern | Purpose |
|---|---|---|
| `azurerm_storage_account.func` | `{prefix}rotfn` (no hyphens) | Functions runtime storage |
| `azurerm_service_plan.func` | `{prefix}-rotation-plan` | Linux Consumption (Y1) |
| `azurerm_linux_function_app.rotation` | `{prefix}-rotation-fn` | The function app itself |

### RBAC Role Assignments

The function's system-assigned Managed Identity receives:

| Role | Scope | Reason |
|---|---|---|
| `Key Vault Secrets Officer` | Hub Key Vault | Read/write rotation metadata + subscription keys |
| `API Management Service Contributor` | APIM instance | Regenerate subscription keys via ARM |
| `Reader` | Resource Group | Resource discovery |

### Feature Flag Gate

The module is conditionally deployed in `stacks/apim/main.tf`:

```hcl
module "key_rotation_function" {
  count  = var.use_azure_functions ? 1 : 0
  source = "../../modules/key-rotation-function"
  ...
}
```

Controlled by `use_azure_functions` in `params/{env}/shared.tfvars` (currently `false` in all envs).

---

## Container Build Pipeline

### Local Development with Docker Compose

A `docker-compose.yml` in the function app directory runs both the function container and Azurite:

```bash
cd functions/apim-key-rotation
docker compose up --build
```

Services:
- **azurite**: Storage emulator (Blob/Queue/Table) — required for timer trigger lease management
- **function-app**: The function image built from `Dockerfile`, connected to Azurite via Docker networking

### Multi-Stage Dockerfile

```
Stage 1: builder (uv + python3.13-bookworm-slim)
  → uv sync --no-dev --frozen --no-install-project
  → Copies pyproject.toml, uv.lock, host.json, function_app.py, rotation/

Stage 2: runtime (mcr.microsoft.com/azure-functions/python:4-python3.13)
  → Copies .venv from builder
  → Fixes Python symlink (builder=/usr/local/bin, runtime=/usr/bin)
  → Sets PATH to include .venv/bin
  → Copies application code
```

### GitHub Actions Workflow

`.github/workflows/.builds.yml` is a **reusable workflow** (`workflow_call`) that builds all container images via a matrix strategy. The `functions/apim-key-rotation` entry:
1. Uses `bcgov/action-builder-ghcr@v4.2.1` to build + push to GHCR
2. Triggers on changes to `functions/apim-key-rotation/` or the workflow file itself
3. Called from `pr-open.yml` on PRs

Image path: `ghcr.io/<org>/ai-hub-tracking/functions/apim-key-rotation:<tag>`

---

## Alternating Slot Pattern

The rotation uses a zero-downtime strategy by alternating which key slot is regenerated:

```
Rotation 1: Regenerate SECONDARY (tenants safe on PRIMARY)
Rotation 2: Regenerate PRIMARY   (tenants safe on SECONDARY)
Rotation 3: Regenerate SECONDARY (tenants safe on PRIMARY)
...
```

Between rotations, tenants always have at least one valid key. The "safe slot" is stored in metadata so monitoring can verify tenants are using the untouched key.

---

## Error Handling Strategy

Each rotation step is wrapped in try/except. Failures are recorded per-tenant without aborting the entire run:

| Step Failure | Behaviour |
|---|---|
| Metadata read fails | Treats as first rotation (defaults) |
| Key regeneration fails | Marks tenant as `failed`, continues to next |
| Key read after regeneration returns empty | Marks tenant as `failed` |
| KV write fails | Marks tenant as `failed` |
| Metadata update fails | Marks tenant as `failed` |

The `RotationSummary` aggregates `total`, `rotated`, `skipped`, `failed` counts logged at the end.

---

## Failure Playbook

| Symptom | Likely Cause | Fix |
|---|---|---|
| All tenants skipped | Interval not elapsed, or `ROTATION_ENABLED=false` | Check `ROTATION_INTERVAL_DAYS` and metadata timestamps |
| `DefaultAzureCredential` error | Missing MI assignment or RBAC | Verify function MI has correct role assignments |
| APIM not found | Infra not deployed, or wrong `APIM_NAME` | Check `APP_NAME` / `ENVIRONMENT` combo |
| Key Vault unreachable | Private endpoint not configured, or NSG blocking | Verify VNet integration + func subnet NSG rules |
| Secret expiry policy violation | `SECRET_EXPIRY_DAYS > 90` | Keep ≤ 90 (Landing Zone policy) |
| Timer not firing | Wrong NCRONTAB syntax or host.json issue | Verify `ROTATION_CRON_SCHEDULE` is 6-part NCRONTAB |
