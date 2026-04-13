---
name: network
description: Guidance for the network module's subnet allocation, CIDR mapping, NSG rules, PE pool outputs, and delegation requirements in ai-hub-tracking. Use when adding subnets, modifying address allocation, changing NSG rules, updating PE pool logic, or debugging subnet delegation issues.
---

# Network Module Skills

Use this skill profile when creating or modifying subnet allocation, CIDR mapping, NSG rules, PE pool outputs, or delegation configuration in the network module.

## Use When
- Adding a new subnet type to the network module
- Modifying subnet allocation in `params/{env}/shared.tfvars`
- Changing or debugging NSG security rules for any subnet
- Debugging subnet delegation issues (VNet integration failures)
- Wiring a new subnet through the shared stack to a downstream stack
- Modifying PE pool outputs or downstream PE subnet selection logic

## Do Not Use When
- Modifying APIM policies/routing (use [API Management](../api-management/SKILL.md))
- Changing App Gateway rewrite rules or WAF custom rules (use [App Gateway & WAF](../app-gateway/SKILL.md))
- General Terraform module or workflow changes unrelated to networking (use [IaC Coder](../iac-coder/SKILL.md))

## Input Contract
Required context before changes:
- Current `subnet_allocation` map in `params/{env}/shared.tfvars` (see Allocation Model below)
- Target service's Azure-mandated delegation and minimum subnet size
- Which environments need the subnet

## Output Contract
Every network module change should deliver:
- CIDR entry in `params/{env}/shared.tfvars` `subnet_allocation` map
- NSG resource + subnet resource in `modules/network/main.tf` (if new subnet type)
- Outputs in `modules/network/outputs.tf`
- Shared stack wiring in `stacks/shared/main.tf` + `stacks/shared/outputs.tf`
- Consumer wiring in downstream stacks that read the new subnet outputs (for example, `infra-ai-hub/stacks/vllm/main.tf` for `vllm_aca_subnet_id`)
- Documentation updates in `infra-ai-hub/README.md` and `.github/skills/network/references/REFERENCE.md`; when the public contract changes, update `docs/_pages/terraform-reference.html` + `docs/terraform-reference.html`, and when secret/local-run guidance changes update `docs/_pages/workflows.html` + `docs/workflows.html`
- Repo quality gate from `infra-ai-hub/`: `terraform fmt -check -recursive && tflint --recursive`

## External Documentation
- Use [External Docs Research](../external-docs/SKILL.md) as the single source of truth for external documentation workflow and fallback approval requirements.

## Documentation Sync
- If the change adds, removes, renames, or materially reorganizes tracked files or directories, update the root `README.md` `Folder Structure` section in the same change. Do not add gitignored or local-only artifacts to that tree.
- Review the documentation sync matrix in [../../copilot-instructions.md](../../copilot-instructions.md) and update any area-specific README or docs pages it calls out for the touched subtree.
- For any `infra-ai-hub/modules/network` contract change, update `infra-ai-hub/README.md` (network allocations + module outputs) and `.github/skills/network/references/REFERENCE.md` in the same change.
- If the change affects the GPU Container Apps subnet contract (`vllm-aca-subnet`) or its downstream consumer, review `infra-ai-hub/stacks/vllm/README.md`.
- If the change affects the published Terraform contract or GitHub secret/local-run instructions, update both tracked docs-site source and published pages: `docs/_pages/terraform-reference.html` + `docs/terraform-reference.html` and/or `docs/_pages/workflows.html` + `docs/workflows.html`.

## Code Locations

| Component | Location | Purpose |
|---|---|---|
| CIDR mapping | `infra-ai-hub/modules/network/locals.tf` | Direct CIDR reads from `subnet_allocation`, PE pool derivation |
| Subnet variable | `infra-ai-hub/modules/network/variables.tf` | `subnet_allocation` map(map(string)) with validations |
| NSGs + subnets | `infra-ai-hub/modules/network/main.tf` | NSG resources, `azapi_resource` subnet definitions |
| Outputs | `infra-ai-hub/modules/network/outputs.tf` | Subnet IDs, CIDRs, NSG IDs, PE pool outputs |
| Shared stack wiring | `infra-ai-hub/stacks/shared/main.tf` → `module "network"` | Passes `subnet_allocation` to module |
| Shared stack outputs | `infra-ai-hub/stacks/shared/outputs.tf` | PE pool pass-through + backward-compat outputs |
| Per-env config | `infra-ai-hub/params/{env}/shared.tfvars` → `subnet_allocation` | Full CIDRs per subnet per address space |
| vLLM consumer | `infra-ai-hub/stacks/vllm/main.tf` | Reads `vllm_aca_subnet_id` and primary PE subnet from shared state |
| Tenant PE selection | `infra-ai-hub/stacks/tenant/locals.tf` | PE subnet resolution with 3-tier precedence |
| APIM PE selection | `infra-ai-hub/stacks/apim/locals.tf` | Pinned PE subnet resolution with fallback |

## Architecture

VNets are pre-provisioned by the BC Gov Landing Zone — the module only creates **subnets within existing VNets**. Subnets are created in the **shared stack** and consumed by downstream stacks via `data.terraform_remote_state.shared`.

All subnets use `azapi_resource` (not `azurerm_subnet`) because Landing Zone policy requires NSG at creation time — `azapi_resource` does this atomically.

## Subnet Allocation Model (`subnet_allocation`)

The network module uses a single `subnet_allocation` variable of type `map(map(string))`:
- **Outer key** = address space CIDR (e.g., `"10.x.x.0/24"`)
- **Inner key** = subnet name (e.g., `"privateendpoints-subnet"`)
- **Inner value** = full subnet CIDR (e.g., `"10.x.x.0/27"`)

There is **no offset computation** — all CIDRs are explicit in tfvars. The module reads them directly via `merge()`.

### Known Subnet Names

| Subnet Name | Delegation | Purpose |
|---|---|---|
| `privateendpoints-subnet` | None (`privateEndpointNetworkPolicies = "Disabled"`) | Primary PE subnet |
| `privateendpoints-subnet-<n>` | None | Additional PE pool subnets (`<n>` starts at 1: `-1`, `-2`, ...) |
| `apim-subnet` | `Microsoft.Web/serverFarms` | APIM VNet injection |
| `appgw-subnet` | None (dedicated, no delegation) | Application Gateway |
| `aca-subnet` | `Microsoft.App/environments` | Container Apps Environment |
| `vllm-aca-subnet` | `Microsoft.App/environments` | Dedicated GPU vLLM Container Apps Environment |

### External VNet Peered Projects (`external_peered_projects`)

Optional map of external project names to their peered VNet config. When populated, the network module creates dynamic inbound NSG rules on the APIM subnet allowing direct HTTPS (443) traffic from these peered VNets — bypassing App Gateway. NSGs are stateful, so no outbound mirror rule is needed.

```hcl
external_peered_projects = {
  "forest-client" = { cidrs = ["10.x.x.0/20"],                   priority = 400 }
  "nr-data-hub"   = { cidrs = ["10.x.x.0/22", "10.x.x.0/22"], priority = 410 }
}
```

Priorities are caller-assigned (400–499) so adding/removing a project never shifts existing rules. Use gaps (400, 410, 420) for future growth.

**Critical rules:**
- A subnet can only have **one** delegation — never share delegated subnets between services
- AppGW subnet must have NO delegation
- Each subnet CIDR must fall within its parent address space

### Current Environment Allocations

**Dev** — 1 address space:
| Subnet | CIDR | Size |
|---|---|---|
| `privateendpoints-subnet` | `10.x.x.0/27` | 32 IPs |
| `apim-subnet` | `10.x.x.32/27` | 32 IPs |
| `aca-subnet` | `10.x.x.64/27` | 32 IPs |
| `vllm-aca-subnet` | `10.x.x.96/27` | 32 IPs |
| `appgw-subnet` | Not deployed | App Gateway disabled |

**Test** — 2 address spaces:
| Space | Subnet | CIDR | Size |
|---|---|---|---|
| PE space /24 | `privateendpoints-subnet` | `10.x.x.0/24` | 256 IPs (dedicated PE space) |
| Workload /24 | `apim-subnet` | `10.x.x.0/27` | 32 IPs |
| Workload /24 | `appgw-subnet` | `10.x.x.32/27` | 32 IPs |
| Workload /24 | `aca-subnet` | `10.x.x.64/27` | 32 IPs |
| Workload /24 | `vllm-aca-subnet` | `10.x.x.96/27` | 32 IPs |

**Prod** — 4 address spaces (placeholder CIDRs, not yet deployed):
| Space | Subnet | CIDR | Notes |
|---|---|---|---|
| Space 1 | `privateendpoints-subnet` | TBD /24 | PE pool space 1 |
| Space 2 | `privateendpoints-subnet-1` | TBD /24 | PE pool space 2 |
| Space 3 | `privateendpoints-subnet-2` | TBD /24 | PE pool space 3 |
| Space 4 | `apim-subnet` | `10.x.x.0/25` | Workload space |
| Space 4 | `appgw-subnet` | `10.x.x.128/26` | Workload space |
| Space 4 | `aca-subnet` | `10.x.x.192/27` | Shared Container Apps Environment |
| Space 4 | `vllm-aca-subnet` | `10.x.x.224/27` | Dedicated GPU vLLM Container Apps Environment |

## PE Subnet Pool

The network module automatically derives a PE pool from all subnets whose name starts with `privateendpoints-subnet`:
- Pool keys use the actual subnet names: `privateendpoints-subnet`, `privateendpoints-subnet-1`, `privateendpoints-subnet-2`, ...
- Primary PE subnet key is always `privateendpoints-subnet` (the original, suffix-free name)
- Pool outputs: `private_endpoint_subnet_ids_by_key`, `private_endpoint_subnet_cidrs_by_key`, `private_endpoint_subnet_keys_ordered`

### Downstream PE Consumption

**Tenant stack** — `pe_subnet_key` is **mandatory** for every enabled tenant:
- **Explicit `pe_subnet_key` in tenant config** (`var.tenants[key].pe_subnet_key`) — **ALWAYS set**, validated at plan time
- Resolution is strict: invalid/missing key in the shared PE pool fails at plan time (no silent fallback)

Each tenant creates up to 5 PEs but 6 IPs total (Cosmos DB PE = 2 IPs: sql global + canadacentral regional endpoint). All PEs for a tenant land on the **same** subnet ("tenant affinity"). Storage Account has no PE (public access in Landing Zone).

Shared stack PEs always use the primary `privateendpoints-subnet` — consuming exactly **5 IPs**: AI Foundry Hub PE (3 IPs: cognitiveservices, openai, services.ai sub-resources), Language Service PE (1 IP), Hub Key Vault PE (1 IP).

### PE Subnet Assignment Strategy

**Principle: assign-on-first-deploy, sticky forever.** Changing `pe_subnet_key` after deployment destroys and recreates **all 5 tenant PEs** (service disruption + DNS re-propagation).

**Capacity math:**
- Each `/24` PE subnet holds ~251 usable IPs (Azure reserves 5)
- Each tenant consumes up to 6 PE IPs (Cosmos DB = 2) → ~41 tenants per `/24` subnet
- Shared stack consumes exactly 5 IPs on primary subnet: Foundry Hub 3 IPs (AIServices kind exposes cognitiveservices + openai + services.ai) + Language Service 1 IP + Hub KV 1 IP → reduces tenant capacity to ~41 on primary (246 ÷ 6)
- Prod has 3 PE subnets → theoretical max ~123 tenants

**Assignment rules for new tenants:**
1. Check current PE count per subnet (Azure Portal → subnet → Connected devices, or `az network vnet subnet show`)
2. Assign the subnet with the most remaining capacity
3. Record the key in the tenant's `pe_subnet_key` field — it is immutable after first apply
4. Dev/test environments have only 1 PE subnet → always `"privateendpoints-subnet"`

**Tenant onboarding prerequisite:**
Every new tenant tfvars **must** include `pe_subnet_key` inside the `tenant = { ... }` block. Terraform plan will fail validation if it is missing. Example:
```hcl
pe_subnet_key = "privateendpoints-subnet"    # or "privateendpoints-subnet-1", etc.
```

**APIM stack** — Pinned PE subnet:
1. Explicit `var.apim_pe_subnet_key` (if set, looks up from shared PE pool)
2. Fallback to primary `private_endpoint_subnet_id`

**Key-rotation / Foundry** — Out of PE pool scope (no PE subnet references).

## How to Add a New Subnet (Checklist)

1. **tfvars** (`params/{env}/shared.tfvars`): Add CIDR entry under `subnet_allocation` in the appropriate address space
2. **Enabled flag** (`modules/network/locals.tf`): Add `xxx_enabled = contains(keys(local.subnet_cidrs), "xxx-subnet")`
3. **CIDR local** (`modules/network/locals.tf`): Add `xxx_subnet_cidr = local.xxx_enabled ? local.subnet_cidrs["xxx-subnet"] : null`
4. **Validation** (`modules/network/variables.tf`): Add subnet name to allowed names list in validation block
5. **NSG + Subnet** (`modules/network/main.tf`): NSG with `count`, `azapi_resource` with delegation + `depends_on` all preceding subnets
6. **Outputs** (`modules/network/outputs.tf`): `xxx_subnet_id`, `xxx_subnet_cidr`, `xxx_nsg_id`
7. **Shared stack** (`stacks/shared/main.tf` + `outputs.tf`): Wire variable + expose output
8. **Downstream stacks**: Reference via `try(data.terraform_remote_state.shared.outputs.xxx_subnet_id, null)` and update any consuming stacks such as `stacks/vllm`
9. **Docs**: Update `infra-ai-hub/README.md`, `.github/skills/network/references/REFERENCE.md`, and any affected `docs/_pages/*.html` + published `docs/*.html` pages

## Validation Gates (Required)
1. **CIDR validity:** All values in `subnet_allocation` must be valid CIDRs (`can(cidrhost(cidr, 0))`)
2. **Subnet names:** Must match known names or `privateendpoints-subnet-<n>` pattern where `<n>` starts at 1
3. **PE requirement:** At least one `privateendpoints-subnet` must exist
4. **No duplicates:** Each subnet name appears in exactly one address space
5. **Delegation:** Matches Azure requirement for the target service
6. **depends_on chain:** New subnet depends on ALL preceding subnets
7. **NSG at creation:** Included in `azapi_resource` body, not a separate association
8. **Shared stack output:** Subnet ID exposed for cross-stack consumption
9. **Docs:** Skill/reference docs and any affected public docs are updated alongside the code change
10. **Quality gate:** `terraform fmt -check -recursive && tflint --recursive` from `infra-ai-hub/`

## Detailed References

For full CIDR calculation algorithm, visual allocation diagrams, NSG rule tables per subnet, `depends_on` chain details, AppGW route table special case, and common pitfalls, see [references/REFERENCE.md](references/REFERENCE.md).
