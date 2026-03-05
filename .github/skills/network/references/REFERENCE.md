# Network Module — Deep Reference

Supplementary detail for the [Network SKILL.md](../SKILL.md). Read the SKILL.md first for the operational overview.

---

## Subnet Allocation Model

The network module uses a single `subnet_allocation` variable of type `map(map(string))`. All CIDRs are explicit — there is **no offset computation or address-space-count-based derivation**.

### Variable Shape

```hcl
variable "subnet_allocation" {
  type = map(map(string))
  # Outer key = address space CIDR
  # Inner key = subnet name
  # Inner value = full subnet CIDR
}
```

### How CIDRs Are Resolved

In `modules/network/locals.tf`:

```hcl
# Flatten all subnets across address spaces into a single name → cidr map
subnet_cidrs = merge([
  for space_cidr, subnets in var.subnet_allocation : {
    for name, cidr in subnets : name => cidr
  }
]...)
```

Enabled flags are derived from subnet name existence:
```hcl
pe_enabled    = contains(keys(local.subnet_cidrs), "privateendpoints-subnet")
apim_enabled  = contains(keys(local.subnet_cidrs), "apim-subnet")
appgw_enabled = contains(keys(local.subnet_cidrs), "appgw-subnet")
aca_enabled   = contains(keys(local.subnet_cidrs), "aca-subnet")
```

### Validation Rules (in variables.tf)

1. `subnet_allocation` must contain at least one address space
2. All values must be valid CIDR notation (tested via `can(cidrhost(cidr, 0))`)
3. Subnet names must be one of: `privateendpoints-subnet`, `privateendpoints-subnet-<n>` (where `<n>` starts at 1), `apim-subnet`, `appgw-subnet`, `aca-subnet`
4. At least one `privateendpoints-subnet` must exist
5. Each subnet name appears in exactly one address space (no duplicates)

---

## PE Subnet Pool Derivation

All subnets with names starting with `privateendpoints-subnet` are collected into a pool:

```hcl
pe_subnet_names = sort([
  for name, _ in local.subnet_cidrs : name
  if startswith(name, "privateendpoints-subnet")
])

pe_subnet_pool = {
  for name in local.pe_subnet_names :
  name => { name = name, cidr = local.subnet_cidrs[name] }
}
```

Key behaviors:
- Pool keys are the actual subnet names (`privateendpoints-subnet`, `privateendpoints-subnet-1`, etc.)
- `pe_subnet_cidrs` is a sorted list of all PE CIDRs (used in NSG `destination_address_prefixes`)
- All pool entries have deployed `azapi_resource.pe_subnets` instances via `for_each`

### Pool Outputs

| Output | Type | Description |
|---|---|---|
| `private_endpoint_subnet_ids_by_key` | map(string) | PE key → resource ID (null for undeployed) |
| `private_endpoint_subnet_cidrs_by_key` | map(string) | PE key → CIDR string |
| `private_endpoint_subnet_keys_ordered` | list(string) | Sorted list of pool keys |
| `private_endpoint_subnet_pool` | map(object) | PE key → { name, cidr } |

---

## Visual Allocation Diagrams

### Dev — 1 × /24 (Current)

```
10.x.x.0/24
├── 10.x.x.0/27   (privateendpoints-subnet)  27 usable IPs
├── 10.x.x.32/27  (apim-subnet)              27 usable IPs
├── 10.x.x.64/27  (aca-subnet)               27 usable IPs
└── 10.x.x.96–255 (unused — reserved for appgw-subnet growth)
```

### Test — 2 × /24s (Current)

```
10.x.x.0/24 — PE space (dedicated)
└── 10.x.x.0/24  (privateendpoints-subnet)  251 usable IPs

10.x.x.0/24 — Workload space
├── 10.x.x.0/27   (apim-subnet)              27 usable IPs
├── 10.x.x.32/27  (appgw-subnet)             27 usable IPs
├── 10.x.x.64/27  (aca-subnet)               27 usable IPs
└── 10.x.x.96–255 (unused)
```

### Prod — 4 × /24s (Target Contract)

```
10.x.x.0/24 — PE pool space 1
└── (privateendpoints-subnet)    256 IPs

10.x.x.0/24 — PE pool space 2
└── (privateendpoints-subnet-1)  256 IPs

10.x.x.0/24 — PE pool space 3
└── (privateendpoints-subnet-2)  256 IPs

10.x.x.0/24 — Workload space
├── (apim-subnet)   /27  32 IPs
├── (appgw-subnet)  /27  32 IPs
└── (aca-subnet)    /27  32 IPs
```

---

## Downstream PE Subnet Selection

### Tenant Stack (stacks/tenant/locals.tf)

`pe_subnet_key` is **mandatory** for every enabled tenant (validated in `variables.tf`).
Resolution is strict — invalid/missing key fails at plan time (no silent fallback):

```hcl
resolved_pe_subnet_id = {
  for key, config in local.enabled_tenants : key => local.pe_subnet_ids_by_key[config.pe_subnet_key]
}
```

Validation: Every enabled tenant must have `pe_subnet_key` set and it must match `privateendpoints-subnet(-<n>)?` pattern.

### APIM Stack (stacks/apim/locals.tf)

Pinned PE — no auto-balancing. Null key uses primary; explicit key must exist (no silent fallback):

```hcl
resolved_apim_pe_subnet_id = (
  var.apim_pe_subnet_key == null
  ? data.terraform_remote_state.shared.outputs.private_endpoint_subnet_id
  : data.terraform_remote_state.shared.outputs.private_endpoint_subnet_ids_by_key[var.apim_pe_subnet_key]
)
```

Variable: `apim_pe_subnet_key` (string, default `null`) in `stacks/apim/variables.tf`.

---

## NSG Rules Per Subnet

### PE Subnet NSG (`{prefix}-pe-nsg`)

Uses `destination_address_prefixes` (list) to cover all PE pool CIDRs.

| Priority | Direction | Purpose |
|---|---|---|
| 100+ | Inbound | Allow from each target VNet address space (dynamic, to PE pool CIDRs) |
| 200+ | Outbound | Allow to each target VNet address space (from PE pool CIDRs) |
| 300 | Inbound | Allow from source VNet (tools VNet, to PE pool CIDRs) |
| 301 | Outbound | Allow to source VNet (from PE pool CIDRs) |

### APIM Subnet NSG (`{prefix}-apim-nsg`)
| Priority | Direction | Purpose |
|---|---|---|
| 100 | Inbound | ApiManagement service tag (port 3443) |
| 110 | Inbound | AzureLoadBalancer |
| 400–499 | Inbound | External peered project VNets → APIM (443, dynamic, caller-assigned priority from `external_peered_projects`) |
| 100 | Outbound | Storage (443) |
| 110 | Outbound | AzureKeyVault (443) |
| 120 | Outbound | VirtualNetwork (443, PE access) |
| 130 | Outbound | AzureActiveDirectory (443) |
| 140 | Outbound | Internet (443) |

### AppGW Subnet NSG (`{prefix}-appgw-nsg`)
| Priority | Direction | Purpose |
|---|---|---|
| 100 | Inbound | HTTPS from Internet (443) |
| 120 | Inbound | GatewayManager (65200–65535) |
| 130 | Inbound | AzureLoadBalancer |

HTTP (80) intentionally blocked — no redirect provided.

### ACA Subnet NSG (`{prefix}-aca-nsg`)
| Priority | Direction | Purpose |
|---|---|---|
| 100 | Outbound | AzureContainerRegistry (443) |
| 110 | Outbound | AzureMonitor (443) |
| 120 | Outbound | AzureActiveDirectory (443) |
| 130 | Outbound | VirtualNetwork (443, PE access) |
| 200+ | Inbound | Allow from each target VNet address space (dynamic) |

---

## Subnet Resource Pattern Details

### Why azapi_resource (Not azurerm_subnet)

| Approach | NSG Attachment | Landing Zone Compliant? |
|---|---|---|
| `azurerm_subnet` + `azurerm_subnet_network_security_group_association` | Two-step (gap between) | **No** — policy violation during gap |
| `azapi_resource` with `networkSecurityGroup.id` in body | Atomic (single PUT) | **Yes** |

### depends_on Chain

Subnets serialize on the VNet resource (Azure ARM locks). Each subnet must depend on ALL preceding subnets to avoid conflicts:

```
azapi_resource.private_endpoints_subnet
  └── azapi_resource.apim_subnet  (depends_on: [private_endpoints_subnet])
       └── azapi_resource.appgw_subnet  (depends_on: [private_endpoints_subnet, apim_subnet])
            └── azapi_resource.aca_subnet  (depends_on: [private_endpoints_subnet, apim_subnet, appgw_subnet])
```

Every subnet also includes `locks = [data.azurerm_virtual_network.target.id]`.

### Cross-Stack Consumption

```
shared stack (creates subnets, exposes PE pool outputs)
  ├── tenant stack   → PE subnet (via resolved_pe_subnet_id per tenant)
  ├── apim stack     → PE subnet (via resolved_apim_pe_subnet_id), APIM subnet
  ├── foundry stack  → Does not consume PE subnet
  └── key-rotation   → Does not consume PE subnet
```

---

## AppGW Route Table Special Case

The App Gateway subnet has resources no other subnet needs:

- **Route table** (`azurerm_route_table.appgw`) with `0.0.0.0/0 → Internet` route
- **BCGov internal route** (`142.34.0.0/16 → Internet`) to prevent asymmetric routing via ExpressRoute/VWAN hub
- Route table attached via `routeTable.id` in the `azapi_resource` body

No other subnet currently requires a route table.

---

## Common Pitfalls

| Pitfall | Consequence | Prevention |
|---|---|---|
| Reusing PE subnet for VNet integration | Deployment fails — PE subnet has no delegation | Always create a dedicated delegated subnet |
| Sharing a delegated subnet between services | Only one delegation per subnet — second service fails | Each service gets its own subnet |
| CIDR not within parent address space | Plan fails validation | Ensure inner CIDR falls within outer map key |
| Duplicate subnet name across address spaces | Terraform validation fails | Each name must appear exactly once |
| Missing `depends_on` in subnet chain | ARM conflict on VNet, intermittent failures | Include ALL preceding subnets in `depends_on` |
| Using `azurerm_subnet` instead of `azapi_resource` | Landing Zone policy violation | Always use `azapi_resource` |
| Forgetting shared stack output | Downstream stack can't access subnet ID | Add output in `stacks/shared/outputs.tf` |
| Setting delegation on AppGW subnet | App Gateway rejects delegated subnets | AppGW subnet must have NO delegation |
| Invalid PE key in tenant config | `coalesce` falls through to primary (safe) | Validate key existence in CI before apply |

---

## Failure Playbook

| Symptom | Likely Cause | Fix |
|---|---|---|
| `SubnetMustNotHaveDelegation` | Delegation set on AppGW or PE subnet | Remove delegation from `azapi_resource` body |
| `SubnetDelegationCannotBeChanged` | Changing delegation on existing subnet | Delete + recreate (taint or `terraform destroy -target`) |
| `NetworkSecurityGroupNotAssociated` | Using `azurerm_subnet` without NSG in body | Switch to `azapi_resource` |
| `SubnetConflictWithOtherSubnet` | CIDR overlap in `subnet_allocation` | Check CIDRs don't overlap within same address space |
| `AnotherOperationInProgress` | Missing `depends_on` or `locks` | Add `depends_on` + VNet lock to subnet resource |
| `PrivateEndpointCannotBeCreatedInSubnet` | Subnet has delegation or missing PE policy | Use PE subnet with `privateEndpointNetworkPolicies = "Disabled"` |
| Tenant PE uses wrong subnet | Invalid `pe_subnet_key` or missing pool output | Check tenant's `pe_subnet_key` in tfvars matches a key in shared PE pool outputs. Do NOT change it after first deploy — destroys/recreates all PEs |
