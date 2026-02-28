# Key Rotation Container App Job — Deep Reference

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
| `azurerm_container_app_job.rotation` | `{prefix}-rotation-job` | Cron-triggered Container App Job |

### RBAC Role Assignments

The job's system-assigned Managed Identity receives:

| Role | Scope | Reason |
|---|---|---|
| `Key Vault Secrets Officer` | Hub Key Vault | Read/write rotation metadata + subscription keys |
| `API Management Service Contributor` | APIM instance | Regenerate subscription keys via ARM |
| `Reader` | Resource Group | Resource discovery |

### Feature Flag Gate

The module is conditionally deployed in `stacks/key-rotation/main.tf`:

```hcl
module "key_rotation" {
  count  = local.rotation_enabled && local.apim_enabled && local.cae_enabled ? 1 : 0
  source = "../../modules/key-rotation-function"
  ...
}
```

Controlled by `rotation_enabled` in `params/{env}/key-rotation.tfvars` and `cae_config.enabled` in `params/{env}/shared.tfvars`.

---

## Container Build Pipeline

### Local Development

```bash
cd jobs/apim-key-rotation

# Run directly
python main.py

# Or build and run in Docker
docker build -t apim-key-rotation:test .
docker run --rm \
  -e ENVIRONMENT=dev \
  -e APP_NAME=ai-services-hub \
  -e SUBSCRIPTION_ID=<sub-id> \
  -e DRY_RUN=true \
  apim-key-rotation:test
```

### Multi-Stage Dockerfile

```
Stage 1: builder (uv + python3.13-bookworm-slim)
  → uv sync --no-dev --frozen --no-install-project
  → Copies pyproject.toml, uv.lock, main.py, rotation/

Stage 2: runtime (python:3.13-slim-bookworm)
  → Copies .venv from builder
  → Sets PATH to include .venv/bin
  → Copies application code
  → CMD: python main.py
```

### GitHub Actions Workflow

`.github/workflows/.builds.yml` is a **reusable workflow** (`workflow_call`) that builds all container images via a matrix strategy. The `jobs/apim-key-rotation` entry:
1. Uses `bcgov/action-builder-ghcr@v4.2.1` to build + push to GHCR
2. Triggers on changes to `jobs/apim-key-rotation/` or the workflow file itself
3. Called from `pr-open.yml` on PRs

Image path: `ghcr.io/<org>/ai-hub-tracking/jobs/apim-key-rotation:<tag>`

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
| `DefaultAzureCredential` error | Missing MI assignment or RBAC | Verify job MI has correct role assignments |
| APIM not found | Infra not deployed, or wrong `APIM_NAME` | Check `APP_NAME` / `ENVIRONMENT` combo |
| Key Vault unreachable | Private endpoint not configured, or NSG blocking | Verify ACA subnet NSG rules allow KV access |
| Secret expiry policy violation | `SECRET_EXPIRY_DAYS > 90` | Keep ≤ 90 (Landing Zone policy) |
| Job not running | Wrong cron expression or job disabled | Verify `cron_expression` in tfvars, check job status in portal |
