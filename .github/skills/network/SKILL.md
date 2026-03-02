---
name: network
description: Guidance for the network module's subnet allocation, CIDR calculations, NSG rules, and delegation requirements in ai-hub-tracking. Use when adding subnets, modifying address space allocation, changing NSG rules, or debugging subnet delegation issues.
---

# Network Module Skills

Use this skill profile when creating or modifying subnet allocation, CIDR calculations, NSG rules, or delegation configuration in the network module.

## Use When
- Adding a new subnet type to the network module
- Modifying CIDR allocation logic in `locals.tf`
- Changing or debugging NSG security rules for any subnet
- Debugging subnet delegation issues (VNet integration failures)
- Wiring a new subnet through the shared stack to a downstream stack

## Do Not Use When
- Modifying APIM policies/routing (use [API Management](../api-management/SKILL.md))
- Changing App Gateway rewrite rules or WAF custom rules (use [App Gateway & WAF](../app-gateway/SKILL.md))
- General Terraform module or workflow changes unrelated to networking (use [IaC Coder](../iac-coder/SKILL.md))

## Input Contract
Required context before changes:
- Current subnet allocation map (see Allocation Map below)
- Target service's Azure-mandated delegation and minimum subnet size
- VNet address space count for the target environment (1, 2, or 4+ /24s)
- Which environments enable the subnet (`params/{env}/shared.tfvars`)

## Output Contract
Every network module change should deliver:
- Variable, CIDR calculation, NSG, subnet resource, and outputs in `modules/network/`
- Shared stack wiring in `stacks/shared/main.tf` + `stacks/shared/outputs.tf`
- Feature flag in all three `params/{dev,test,prod}/shared.tfvars`
- `terraform fmt -recursive` on `modules/network/` and `stacks/shared/`

## External Documentation
- Use [External Docs Research](../external-docs/SKILL.md) as the single source of truth for external documentation workflow and fallback approval requirements.

## Code Locations

| Component | Location | Purpose |
|---|---|---|
| CIDR calculations | `infra-ai-hub/modules/network/locals.tf` | Subnet offset/base/CIDR derivations |
| Subnet variables | `infra-ai-hub/modules/network/variables.tf` | Subnet toggle objects (`enabled`, `name`, `prefix_length`) |
| NSGs + subnets | `infra-ai-hub/modules/network/main.tf` | NSG resources, `azapi_resource` subnet definitions |
| Outputs | `infra-ai-hub/modules/network/outputs.tf` | Subnet IDs, CIDRs, NSG IDs |
| Shared stack wiring | `infra-ai-hub/stacks/shared/main.tf` → `module "network"` | Maps `shared_config` to module variables |
| Shared stack outputs | `infra-ai-hub/stacks/shared/outputs.tf` | Exposes subnet IDs for cross-stack remote state |
| Per-env config | `infra-ai-hub/params/{env}/shared.tfvars` → `shared_config` | Feature flags per subnet type |

## Architecture

VNets are pre-provisioned by the BC Gov Landing Zone — the module only creates **subnets within existing VNets**. Subnets are created in the **shared stack** and consumed by downstream stacks via `data.terraform_remote_state.shared`.

All subnets use `azapi_resource` (not `azurerm_subnet`) because Landing Zone policy requires NSG at creation time — `azapi_resource` does this atomically.

## Current Subnet Allocation Map

| Subnet | Delegation | Allocation Order |
|---|---|---|
| PE | None (`privateEndpointNetworkPolicies = "Disabled"`) | Always first |
| APIM | `Microsoft.Web/serverFarms` | After PE |
| AppGW | None (dedicated, no delegation) | After APIM |
| ACA | `Microsoft.App/environments` | After AppGW |
| Func | `Microsoft.Web/serverFarms` | After ACA |

**Critical rules:**
- A subnet can only have **one** delegation — never share delegated subnets between services
- APIM and Functions both use `Microsoft.Web/serverFarms` but **must use separate subnets**
- AppGW subnet must have NO delegation

## Address Space Scenarios (Quick Reference)

| Scenario | PE | Infrastructure |
|---|---|---|
| 1 × /24 | /27 at offset 0 | Sequential /27s in same /24 after PE |
| 2 × /24s | Full first /24 as PE pool | Second /24 for infra |
| 4+ × /24s | First 2 /24s for PE pool | Third + fourth /24s for infra |

Each infra subnet's offset shifts by 32 for each enabled preceding subnet. See [references/REFERENCE.md](references/REFERENCE.md) for full CIDR calculation algorithm and visual diagrams.

## How to Add a New Subnet (Checklist)

1. **Variable** (`variables.tf`): Object with `enabled`, `name`, `prefix_length` — default `enabled = false`
2. **CIDR** (`locals.tf`): Add `xxx_offset`, `xxx_base`, `xxx_subnet_cidr` after last subnet in chain
3. **NSG + Subnet** (`main.tf`): NSG with `count`, `azapi_resource` with delegation + `depends_on` all preceding subnets
4. **Outputs** (`outputs.tf`): `xxx_subnet_id`, `xxx_subnet_cidr`, `xxx_nsg_id`
5. **Shared stack** (`stacks/shared/main.tf` + `outputs.tf`): Wire variable + expose output
6. **Env config**: Add `xxx_subnet_enabled = false` in all `params/{dev,test,prod}/shared.tfvars`
7. **Downstream stack**: Reference via `try(data.terraform_remote_state.shared.outputs.xxx_subnet_id, null)`

## Validation Gates (Required)
1. **CIDR overlap:** Walk offset formula for all 3 address space scenarios — no two subnets same CIDR
2. **Delegation:** Matches Azure requirement for the target service
3. **depends_on chain:** New subnet depends on ALL preceding subnets
4. **NSG at creation:** Included in `azapi_resource` body, not a separate association
5. **Shared stack output:** Subnet ID exposed for cross-stack consumption
6. **Feature flag:** Defaults to `enabled = false` in all environments
7. **Format:** `terraform fmt -recursive` on `modules/network/` and `stacks/shared/`

## Detailed References

For full CIDR calculation algorithm, visual allocation diagrams, NSG rule tables per subnet, `depends_on` chain details, AppGW route table special case, and common pitfalls, see [references/REFERENCE.md](references/REFERENCE.md).
