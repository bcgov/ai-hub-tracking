# IaC Coder — Detailed Reference

Supplementary reference for the [IaC Coder skill](../SKILL.md). Load this file when you need file structure details, code patterns, workflow architecture, or tenant onboarding steps.

## File Structure (initial-setup)

```
initial-setup/
└── infra/
    ├── deploy-terraform.sh
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── providers.tf
    ├── backend.tf
    └── modules/
        └── <module>/
            ├── main.tf
            ├── variables.tf
            ├── outputs.tf
            └── providers.tf
```

## File Structure (infra-ai-hub)

```
infra-ai-hub/
├── terraform.tfvars
├── scripts/
│   └── deploy-terraform.sh
├── modules/
│   └── <module>/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── providers.tf
│       └── versions.tf
├── stacks/
│   └── <stack>/    (shared, tenant, apim, foundry, tenant-user-mgmt)
│       ├── backend.tf
│       ├── locals.tf
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── providers.tf
│       └── (no modules/ — stacks consume shared modules above)
└── params/
    ├── apim/       (policy templates)
    ├── dev/        (env-specific tfvars)
    ├── test/
    └── prod/
```

Most day-to-day work targets `infra-ai-hub/`. Stacks are isolated Terraform roots that share modules; params provide environment-specific variables.

## Resource Patterns

```hcl
resource "azurerm_resource_group" "example" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.common_tags
  lifecycle {
    ignore_changes = [tags]
  }
}

module "dependent" {
  source     = "./modules/dependent"
  depends_on = [module.network]
}
```

## Feature Toggles

```hcl
variable "feature_enabled" {
  type    = bool
  default = false
}

module "feature" {
  count  = var.feature_enabled ? 1 : 0
  source = "./modules/feature"
}
```

## Network Dependency Passing

```hcl
module "service" {
  vnet_id                    = module.network.vnet_id
  container_app_subnet_id    = module.network.container_apps_subnet_id
  private_endpoint_subnet_id = module.network.private_endpoint_subnet_id
  depends_on                 = [module.network]
}
```

## Backend Configuration
- Backend values are injected via `initial-setup/infra/deploy-terraform.sh` using `-backend-config` flags.
- Never hardcode storage account names or keys.

## GitHub Actions Conventions

- Use OIDC via `azure/login@v2` with client-id, tenant-id, subscription-id
- Pass secrets via `TF_VAR_*` environment variables
- Never hardcode or echo secrets
- Reusable workflows: name with `.` prefix and use `workflow_call` with typed inputs

```yaml
permissions:
  id-token: write
  contents: read

env:
  TF_VERSION: 1.12.2
  TF_LOG: ERROR
  CI: "true"
  ARM_USE_OIDC: "true"
```

## Workflow Architecture

All CI/CD follows a reusable workflow chain pattern:

```
Trigger workflow (pr-open.yml, merge-main.yml, manual-dispatch.yml)
├── .lint.yml (pre-commit, TFLint, conventional commits)
├── .builds.yml (Docker images → GHCR)
├── .deployer.yml (direct deploy for tools env)
│   └── outputs: proxy_url, proxy_auth (GPG-encrypted)
└── .deployer-using-secure-tunnel.yml (dev/test/prod)
    ├── Decrypts proxy_url/proxy_auth via GPG_PASSPHRASE
    ├── Starts chisel-client (SOCKS5 tunnel) + privoxy (HTTP proxy)
    ├── Sets HTTP_PROXY/HTTPS_PROXY=http://127.0.0.1:8118
    ├── Runs deploy-terraform.sh through the tunnel
    └── On success: .integration-tests-using-secure-tunnel.yml
```

**Secure tunnel purpose**: VNet-isolated resources (private endpoints) are unreachable from GitHub Actions runners. The tunnel routes data-plane traffic through a proxy deployed in the `tools` environment (Container App), while control-plane traffic (`management.azure.com`, `registry.terraform.io`, etc.) bypasses the proxy via `NO_PROXY`.

**Prod safeguard**: `manual-dispatch.yml` requires a semver git tag for prod apply.

## Bash Script Conventions

- Required header:
  ```bash
  #!/bin/bash
  set -euo pipefail
  ```
- Directory handling:
  ```bash
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ```
- CI mode:
  ```bash
  if [[ "${CI:-false}" == "true" ]]; then
      # Auto-approve, no interactive prompts
  fi
  ```

## Tenant Onboarding Workflow

To add a new tenant:

1. **Create tenant config**: `infra-ai-hub/params/{env}/tenants/{tenant-name}/tenant.tfvars`
   - Define the `tenant = { ... }` block with `enabled = true` and desired services
   - Tenant name must match `^[a-z0-9-]+$`
   - See existing tenants for the full config shape (key_vault, storage_account, ai_search, cosmos_db, document_intelligence, speech_services, openai with model_deployments)
2. **Deploy**: `deploy-terraform.sh apply {env}` auto-merges all tenant tfvars
3. **Stack order** (handled by `deploy-scaled.sh`):
   - Phase 1: `shared` (networking, hub resources)
   - Phase 2: `tenant` (per-tenant resources — runs in parallel across tenants)
   - Phase 3: `foundry` + `apim` + `tenant-user-mgmt` (concurrent)
4. **Update docs**: Update [Model Deployments](../../../infra-ai-hub/model-deployments.md) for the new tenant

`enabled_tenants` is computed via `for key, config in var.tenants : key => config if try(config.enabled, false)` — setting `enabled = false` disables without deletion.

## Related Tooling References

- **SSL certificates**: See `ssl_certs/README.md` for CSR generation, PFX creation, and cert upload workflows
- **Environment bootstrapping**: See `initial-setup/README.md` for OIDC identity setup and first-time provisioning
- **Azure proxy (chisel/privoxy)**: See `azure-proxy/` for the secure tunnel used in CI/CD

## Implementation Checklist

1. Check existing patterns in similar modules/workflows.
2. Use variables for all configurable values.
3. Ensure variable descriptions are present.
4. Keep changes minimal and consistent with repo patterns.
5. Make sure changes are also reflected in appropriate sections in [docs](../../../docs/)
6. **[MANDATORY]** When adding new tenants or modifying existing tenant model deployments, update the [Model Deployments & Quota Allocation](../../../infra-ai-hub/model-deployments.md) table for the affected environment(s).

## Running Deployments from Local Machine

1. Always use the deployment bash script over regular terraform commands
2. For deployments related to initial setup use this [script](../../../initial-setup/infra/deploy-terraform.sh)
3. For deployments related to infra-ai-hub use this [script](../../../infra-ai-hub/scripts/deploy-terraform.sh)

## Failure Playbook

### ⚠️ CRITICAL: AI Foundry Private Endpoint broken after purge+apply (`DeploymentNotFound` 404)

**Symptom:** All OpenAI inference integration tests fail with `DeploymentNotFound` (HTTP 404) even though:
- All model deployments exist and show `provisioningState: Succeeded`
- APIM backend URL is correct
- APIM managed identity has `Cognitive Services OpenAI User` on the hub
- `tests/test_tenant_info.py` and `tests/test_document_intelligence.py` pass (unrelated backends)

**Root cause:** The AI Foundry private endpoint (PE) is in a broken/inconsistent state. APIM can resolve the hub hostname but the PE is not correctly routing traffic. Azure returns `DeploymentNotFound` instead of a connectivity error, making it easy to misdiagnose as a deployment naming or RBAC issue.

**Most common trigger:** Manually purging the AI Foundry resource (or a full `terraform destroy` of the shared stack) then immediately re-applying. Even though Azure confirms PE deletion and PE recreation via the API, the PE's NIC/DNS binding can be stale for several minutes after Terraform reports success.

**Diagnosis:**
1. Rule out APIM/policy by checking if `tests/test_document_intelligence.py` passes (per-tenant DocInt resources, different backend) — if DocInt passes and OpenAI fails, the issue is hub PE, not APIM.
2. Check APIM MSI role: `az role assignment list --scope <hub_id> --assignee <apim_msi_principal_id> --query "[].roleDefinitionName"`
3. Check deployment state: `az cognitiveservices account deployment show ... --query "properties.provisioningState"`
4. If both are fine, **delete the Foundry private endpoint from the Azure portal** (or via `az network private-endpoint delete`) and re-apply to force a clean PE recreation.

**Fix:** Delete the private endpoint resource and re-apply the `shared` stack. Terraform will recreate it cleanly.

**Teardown script behaviour vs DNS propagation gap:**
- `deploy-scaled.sh destroy` **does** block until full completion: each phase uses `wait "${pids[$i]}"` and Terraform confirms every resource deleted via the Azure API before exiting.
- Destroy order: key-rotation → (foundry + apim + tenant-user-mgmt in parallel) → tenants → shared.
- **Gap:** There is no post-destroy sleep for Azure's private DNS propagation after PE deletion. A rapid `destroy` + `apply` of the `shared` stack can recreate the Foundry PE with a stale NIC/DNS binding. Add a manual wait of ~5 minutes between destroy and apply when working with Foundry PE recreation, or delete only the PE (not the whole hub) when possible.

---

### Terraform drift or noisy plans
- Re-check lifecycle blocks and `ignore_changes` intent before adding new ignores.
- Verify module input defaults and conditional counts are stable.

### Diagnostic settings not applying destination changes
- Follow the existing recreation pattern used in App Gateway diagnostics:
  - `replace_triggered_by` linked to a deterministic trigger resource
  - Trigger value change forces recreation when Azure in-place update is unreliable
- Do not replace this with ad-hoc taint/destroy instructions.

### OIDC/auth deployment failures
- Verify workflow has `id-token: write` and correct tenant/subscription/client IDs.
- Confirm no secrets are printed and credential flow still uses `ARM_USE_OIDC=true`.
