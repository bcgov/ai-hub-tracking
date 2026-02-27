# Network Module — Deep Reference

Supplementary detail for the [Network SKILL.md](../SKILL.md). Read the SKILL.md first for the operational overview.

---

## CIDR Offset Calculation Algorithm

Each infrastructure subnet calculates a fourth-octet offset within its /24 base. The offset depends on which preceding subnets are enabled (each /27 = 32 IPs).

### Key Locals

| Local | Purpose |
|---|---|
| `infra_space_idx` | Index of /24 used for APIM (0, 1, or 2 depending on address space count) |
| `infra_space_idx_2` | Index of /24 for AppGW/ACA/Func (same as `infra_space_idx` for 1–2 /24s; idx 3 for 4+) |
| `infra_base` | First 3 octets of the infra /24 (e.g., `10.0.1`) |
| `{subnet}_offset` | Fourth-octet offset within the infra /24 |
| `{subnet}_base` | Which /24 the subnet lives in (may differ from `infra_base` for 4+ /24s) |

### Offset Formula (1 × /24)

All subnets share one /24. PE is always at offset 0. Each subsequent subnet shifts by 32 for each enabled preceding subnet:

```
PE:    offset = 0                                         (always)
APIM:  offset = 32                                        (always 32, directly after PE)
AppGW: offset = 32 + (APIM ? 32 : 0)                     (32 or 64)
ACA:   offset = 32 + (APIM ? 32 : 0) + (AppGW ? 32 : 0) (32..96)
Func:  offset = 32 + (APIM ? 32 : 0) + (AppGW ? 32 : 0) + (ACA ? 32 : 0)
```

### Offset Formula (2 × /24s)

PE occupies the entire first /24 as a PE pool (8 × /27). Infra subnets start at offset 0 in the second /24:

```
APIM:  offset = 0
AppGW: offset = (APIM ? 32 : 0)
ACA:   offset = (APIM ? 32 : 0) + (AppGW ? 32 : 0)
Func:  offset = (APIM ? 32 : 0) + (AppGW ? 32 : 0) + (ACA ? 32 : 0)
```

### Offset Formula (4+ × /24s)

PE occupies the first 2 /24s (16 × /27). APIM gets the third /24 at offset 0. AppGW/ACA/Func use the fourth /24:

```
APIM:  /24 #3, offset = 0
AppGW: /24 #4, offset = 0
ACA:   /24 #4, offset = (AppGW ? 32 : 0)
Func:  /24 #4, offset = (AppGW ? 32 : 0) + (ACA ? 32 : 0)
```

### Adding a New Offset

Template for the new subnet's offset local:

```hcl
# 1 /24: starts after PE (32) + all preceding
xxx_offset = local.num_address_spaces == 1 ? (
    32 +
    (var.apim_subnet.enabled ? 32 : 0) +
    (var.appgw_subnet.enabled ? 32 : 0) +
    (var.aca_subnet.enabled ? 32 : 0) +
    (var.func_subnet.enabled ? 32 : 0)
  ) : local.num_address_spaces >= 4 ? (
    # 4+ /24s: lives in /24 #4 after AppGW + ACA + Func
    (var.appgw_subnet.enabled ? 32 : 0) +
    (var.aca_subnet.enabled ? 32 : 0) +
    (var.func_subnet.enabled ? 32 : 0)
  ) : (
    # 2 /24s: lives in second /24 after APIM + AppGW + ACA + Func
    (var.apim_subnet.enabled ? 32 : 0) +
    (var.appgw_subnet.enabled ? 32 : 0) +
    (var.aca_subnet.enabled ? 32 : 0) +
    (var.func_subnet.enabled ? 32 : 0)
  )
```

---

## Visual Allocation Diagrams

### 1 × /24 — All Subnets Enabled

```
10.0.0.0/24
├── 10.0.0.0/27   (PE)       offset=0    always
├── 10.0.0.32/27  (APIM)     offset=32   if apim_subnet.enabled
├── 10.0.0.64/27  (AppGW)    offset=64   if appgw_subnet.enabled
├── 10.0.0.96/27  (ACA)      offset=96   if aca_subnet.enabled
├── 10.0.0.128/27 (Func)     offset=128  if func_subnet.enabled
└── 10.0.0.160–255 (unused)
```

### 2 × /24s — All Subnets Enabled

```
10.0.0.0/24 — PE pool
├── 10.0.0.0/27   (pe-subnet-0)
├── 10.0.0.32/27  (pe-subnet-1)
├── ...
└── 10.0.0.224/27 (pe-subnet-7)

10.0.1.0/24 — Infrastructure
├── 10.0.1.0/27   (APIM)     offset=0
├── 10.0.1.32/27  (AppGW)    offset=32
├── 10.0.1.64/27  (ACA)      offset=64
└── 10.0.1.96/27  (Func)     offset=96
```

### 4+ × /24s — All Subnets Enabled

```
10.0.0.0/24 — PE pool (part 1)
10.0.1.0/24 — PE pool (part 2)
10.0.2.0/24 — APIM (offset=0)
10.0.3.0/24 — Infrastructure
├── 10.0.3.0/27   (AppGW)    offset=0
├── 10.0.3.32/27  (ACA)      offset=32
└── 10.0.3.64/27  (Func)     offset=64
```

---

## PE Subnet Pool Calculation

For environments with multiple /24s, the PE space scales:

| Address Spaces | PE /24 Count | PE /27 Subnets | Notes |
|---|---|---|---|
| 1 | — | 1 (single PE /27) | PE shares the /24 with infra |
| 2 | 1 | 8 | Full first /24 as PE pool |
| 4+ | 2 | 16 | First two /24s as PE pool |

Tenant subnet names are generated dynamically: `{prefix}-pe-subnet-{N}`.

---

## NSG Rules Per Subnet

### PE Subnet NSG (`{prefix}-pe-nsg`)
| Priority | Direction | Purpose |
|---|---|---|
| 100+ | Inbound | Allow from each target VNet address space (dynamic) |
| 200+ | Outbound | Allow to each target VNet address space (dynamic) |
| 300 | Inbound | Allow from source VNet (tools VNet) |
| 301 | Outbound | Allow to source VNet |

### APIM Subnet NSG (`{prefix}-apim-nsg`)
| Priority | Direction | Purpose |
|---|---|---|
| 100 | Inbound | ApiManagement service tag (port 3443) |
| 110 | Inbound | AzureLoadBalancer |
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
| 200+ | Inbound | Allow from each target VNet address space (dynamic) |

### Func Subnet NSG (`{prefix}-func-nsg`)
| Priority | Direction | Purpose |
|---|---|---|
| 100 | Outbound | Storage (443, Functions runtime) |
| 110 | Outbound | AzureKeyVault (443) |
| 120 | Outbound | AzureActiveDirectory (443, MI auth) |
| 130 | Outbound | AzureMonitor (443, App Insights) |
| 140 | Outbound | VirtualNetwork (443, PE access) |

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
azapi_resource.pe_subnet
  └── azapi_resource.apim_subnet  (depends_on: [pe_subnet])
       └── azapi_resource.appgw_subnet  (depends_on: [pe_subnet, apim_subnet])
            └── azapi_resource.aca_subnet  (depends_on: [pe_subnet, apim_subnet, appgw_subnet])
                 └── azapi_resource.func_subnet  (depends_on: [pe, apim, appgw, aca])
```

Every subnet also includes `locks = [data.azurerm_virtual_network.target.id]`.

### Cross-Stack Consumption

```
shared stack (creates subnets)
  ├── apim stack     → PE subnet, APIM subnet, Func subnet
  ├── foundry stack  → PE subnet
  └── tenant stack   → PE subnet pool
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
| Wrong offset formula for 2 × /24 case | Subnet overlaps with existing subnet | Test offset for all 3 address space scenarios |
| Missing `depends_on` in subnet chain | ARM conflict on VNet, intermittent failures | Include ALL preceding subnets in `depends_on` |
| Using `azurerm_subnet` instead of `azapi_resource` | Landing Zone policy violation | Always use `azapi_resource` |
| Forgetting shared stack output | Downstream stack can't access subnet ID | Add output in `stacks/shared/outputs.tf` |
| Setting delegation on AppGW subnet | App Gateway rejects delegated subnets | AppGW subnet must have NO delegation |
| Not testing disabled-subnet scenarios | Offset calculations break when preceding subnet is off | Validate CIDR for enabled/disabled combos |

---

## Failure Playbook

| Symptom | Likely Cause | Fix |
|---|---|---|
| `SubnetMustNotHaveDelegation` | Delegation set on AppGW or PE subnet | Remove delegation from `azapi_resource` body |
| `SubnetDelegationCannotBeChanged` | Changing delegation on existing subnet | Delete + recreate (taint or `terraform destroy -target`) |
| `NetworkSecurityGroupNotAssociated` | Using `azurerm_subnet` without NSG in body | Switch to `azapi_resource` |
| `SubnetConflictWithOtherSubnet` | CIDR overlap from wrong offset | Walk offset formula for current address space count |
| `AnotherOperationInProgress` | Missing `depends_on` or `locks` | Add `depends_on` + VNet lock to subnet resource |
| `PrivateEndpointCannotBeCreatedInSubnet` | Subnet has delegation or missing PE policy | Use PE subnet with `privateEndpointNetworkPolicies = "Disabled"` |
