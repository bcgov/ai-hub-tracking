# vLLM Stack

Deploys a GPU-backed vLLM Container App (shared per hub environment) that serves
open-source models via an OpenAI-compatible API. Tenants access it through APIM
using the same `/openai/v1` base URL as Foundry — the `model=` field in the request
body selects the backend.

## Architecture

```
Tenant client
     │
     ▼  (api-key)
APIM /openai/v1/chat/completions
     │  model = "google/gemma-4-31B-it"
     │
     ▼  (no auth headers forwarded)
vLLM Container App (GPU)
  • Azure Container Apps (GPU workload profile: Consumption-GPU-NC24-A100)
  • Dedicated /27 subnet (vllm-aca-subnet) with Microsoft.App/environments delegation
  • Private endpoint for inbound access from APIM
  • HuggingFace token from Key Vault for model weight download
```

## Shared vs Per-Tenant

vLLM is **shared infrastructure** — one GPU Container Apps Environment per hub
environment. All tenants that have `vllm.enabled = true` route to the same vLLM
instance. Circuit-breaker isolation is maintained per tenant via separate APIM
backend entities (same FQDN, different names).

## State

- State key: `ai-services-hub/{env}/vllm.tfstate`
- Remote state consumed by: `apim` stack (reads `vllm_service.container_app_fqdn`)

## Deploy Ordering

Phase 3 (parallel with `foundry`, `pii-redaction`, `tenant-user-mgmt`). The `apim`
stack (Phase 3b) reads this stack's outputs via `data.terraform_remote_state.vllm` —
it must complete before APIM is planned.

The `deploy-scaled.sh` engine enforces this ordering automatically.

## Cold Start / Availability

`min_replicas = 0` (scale-to-zero) is the default to avoid continuous GPU billing.
Gemma 4 31B cold start is **5–10 minutes** after the first request. Operators can
override with `min_replicas = 1` in `params/{env}/shared.tfvars` when lower
first-token latency is required.

**Single-replica SLA note** - Azure Container Apps' published service-level
commitment for Container Apps is **99.95%** uptime. However, keeping one replica
warm only removes the scale-from-zero cold start; it does **not** make this vLLM
path zone-redundant or multi-replica. The current module creates the Container
Apps environment with `zone_redundancy_enabled = false`, and Microsoft guidance
for zone-redundant Container Apps requires a zone-redundant environment plus a
minimum replica count of at least two to distribute replicas across availability
zones.

**Sources**
- [SLA for Azure Container Apps](https://azure.microsoft.com/en-us/support/legal/sla/container-apps/v1_0/)
- [Service Level Agreements for Online Services (Microsoft Licensing)](https://www.microsoft.com/licensing/docs/view/service-level-agreements-sla-for-online-services?lang=1)
- [Reliability in Azure Container Apps - zone redundancy requirements](https://learn.microsoft.com/en-us/azure/reliability/reliability-azure-container-apps#requirements)
- [`../../modules/vllm-service/main.tf`](../../modules/vllm-service/main.tf) (`zone_redundancy_enabled = false`)

## Configuration

Enable the vLLM stack by uncommenting the `vllm` block in `params/{env}/shared.tfvars`.
Three model options are documented there — see [model-deployments.md](../../model-deployments.md#vllm-model-catalogue)
for memory estimates and licence details.

**Quick example (Phi-4 — no HF token, no quantization):**

```hcl
vllm = {
  enabled                    = true
  model_id                   = "microsoft/phi-4"
  max_model_len              = 32768
  model_cache_share_quota_gb = 40
}
```

**Quick example (Qwen3-32B-AWQ — Apache 2.0, INT4, full context):**

```hcl
vllm = {
  enabled                    = true
  model_id                   = "Qwen/Qwen3-32B-AWQ"
  quantization               = "awq"
  max_model_len              = 32768
  model_cache_share_quota_gb = 24
}
```

> **Switching models:** When `model_id` changes, update all tenant
> `vllm.models[*].model_id` values to the new ID or the
> `check "vllm_model_id_matches_deployed_model"` validation block will emit
> a warning at plan time.

Enable vLLM routing for a tenant in `params/{env}/tenants/{tenant}/tenant.tfvars`:

```hcl
vllm = {
  enabled = true
  models = [
    {
      model_id = "google/gemma-4-31B-it"
    }
  ]
}
```

## Inputs (from shared remote state)

| Output | Description |
|--------|-------------|
| `vllm_aca_subnet_id` | Subnet ID for the GPU Container Apps Environment |
| `private_endpoint_subnet_id` | Primary PE subnet for private endpoint placement |
| `log_analytics_workspace_id` | Workspace for diagnostics |
| `hub_keyvault_id` | Key Vault containing the HuggingFace token |

## Outputs

| Output | Description |
|--------|-------------|
| `vllm_service.container_app_fqdn` | Internal FQDN used as APIM backend URL |
| `vllm_service.openai_endpoint` | Full OpenAI-compatible endpoint URL |
| `vllm_service.model_id` | Model ID being served |
| `vllm_service.max_model_len` | Context window length |
| `vllm_service.workload_profile_type` | GPU workload profile name |

## ACR Note

The `vllm-service` module builds a custom container image via an `acr build`
provisioner. The hub ACR has `public_network_access_enabled = true`, so the
`acr build` provisioner task completes without requiring private network access
or Premium SKU. `admin_enabled = true` is still required for the Container App
to pull images using registry credentials.

## Known Limitations

**GPU workload profile drift** — The `null_resource.gpu_workload_profile` adds
the GPU workload profile if it is absent. It does not reconcile an existing
profile when `workload_profile_type` or `workload_profile_name` changes in
tfvars. To change the GPU profile, delete the existing profile from the CAE
manually (`az containerapp env workload-profile delete`) before re-running
`apply`, or replace the CAE resource.

**Model-cache storage public access** — `azurerm_storage_account.model_cache`
has `public_network_access_enabled = true`. The share requires the storage
access key for access (nested public access is blocked), but the Azure Files
SMB endpoint is reachable from the internet. A future iteration should add a
`privatelink.file.core.windows.net` private endpoint and set
`public_network_access_enabled = false` to align with the hub's private-only
PaaS pattern.

**vLLM backend is network-trusted with no application-layer auth** — The
Container App Environment's private endpoint is placed in the shared PE subnet.
Any workload with network reach to that subnet (e.g., a tenant jumpbox) can
call the vLLM endpoint directly without going through APIM, bypassing tenant
subscription auth, rate limits, PII redaction, and logging. Azure OpenAI
(Foundry) is subject to the same VNet-level trust but enforces its own API key
independently. To strengthen this, either scope the vLLM PE subnet NSG to allow
inbound only from the APIM subnet, or add an application-layer shared secret
header validated by a proxy sidecar.

**Secrets in Terraform state** — Two sensitive values are stored in the
azurerm backend state blob: the ACR admin password (`azurerm_container_registry.admin_password`)
and, when used, the Hugging Face token read from Key Vault. `sensitive = true`
hides these from CLI output but does not prevent them from appearing as
plaintext in the state blob. Restrict state-blob read access to the deployment
service principal and platform operators. A future iteration should use managed
identity for ACR pulls (replacing admin creds) and use a Key Vault-backed
Container App secret reference to avoid materialising the HF token in state.
