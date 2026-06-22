# Bastion Proxy — local private-endpoint access (no VPN)

To reach private Azure endpoints (Key Vault, Cosmos DB, PostgreSQL, AI Services,
…) from your workstation, open a SOCKS5 tunnel through **Azure Bastion** to the
jumpbox. One local proxy port reaches anything the jumpbox can reach.

## We don't vendor the scripts — pull them from upstream

The `bastion-proxy.sh` / `bastion-proxy.ps1` scripts are **maintained by BC Gov**
in the same action that provisions our Bastion + jumpbox, under
[`bastion-consumer-scripts/`](https://github.com/bcgov/action-deployer-vm-bastion-alz/tree/v1.0.0/bastion-consumer-scripts).
Keeping a local copy only drifts from upstream, so fetch the raw script on demand
— **no clone required**. Pin to `v1.0.0` (the action version our workflows use).

> These scripts are for **local development only**. CI/CD provisions and locks the
> Bastion via [`.github/scripts/ensure-bastion.sh`](../../../../.github/scripts/ensure-bastion.sh),
> then opens its own tunnel via
> [`.github/scripts/open-bastion-tunnel.sh`](../../../../.github/scripts/open-bastion-tunnel.sh).

### Prerequisites

- **"Virtual Machine Administrator Login"** RBAC on the jumpbox (ask the platform
  team). Signing in to Azure is not enough on its own.
- The Azure CLI + `bastion`/`ssh` extensions — the script installs these if missing.

### macOS / Linux / Git Bash

```bash
# Fetch the script (pinned to the action version we deploy with)
curl -fsSL \
  https://raw.githubusercontent.com/bcgov/action-deployer-vm-bastion-alz/v1.0.0/bastion-consumer-scripts/bastion-proxy.sh \
  -o bastion-proxy.sh
chmod +x bastion-proxy.sh

# Run it. Our tools stack is named ai-hub-<env>: bastion RG ai-hub-bastion-tools,
# bastion ai-hub-bastion, jumpbox ai-hub-jumpbox. Port 8228 matches docker-compose.yml.
./bastion-proxy.sh \
  -g ai-hub-bastion-tools \
  -b ai-hub-bastion \
  -v ai-hub-jumpbox \
  -s <tools-subscription-id> \
  -t <tenant-id> \
  -p 8228
```

### Windows (PowerShell)

```powershell
iwr https://raw.githubusercontent.com/bcgov/action-deployer-vm-bastion-alz/v1.0.0/bastion-consumer-scripts/bastion-proxy.ps1 -OutFile bastion-proxy.ps1

.\bastion-proxy.ps1 `
  -ResourceGroup ai-hub-bastion-tools `
  -BastionName ai-hub-bastion `
  -VmName ai-hub-jumpbox `
  -SubscriptionId <tools-subscription-id> `
  -TenantId <tenant-id> `
  -Port 8228
```

Don't know the exact names? Discover them from Azure:

```bash
RG=ai-hub-bastion-tools
az network bastion list -g "$RG" --subscription <tools-subscription-id> --query '[0].name' -o tsv
az vm list            -g "$RG" --subscription <tools-subscription-id> --query '[0].name' -o tsv
```

Leave the terminal running — the tunnel stays up until you press **Ctrl+C** (or
the 12-hour Entra ID session expires). You'll see `SOCKS5 proxy ready on
localhost:8228`.

> If the off-hours cost-saving automation has deleted the Bastion, ask the
> platform team to run the `Create-BastionHost` runbook (or wait for the next
> deploy, which recreates it).

## Next: bridge HTTP → SOCKS with Privoxy

Terraform and the Azure CLI speak HTTP proxy, not SOCKS. Start Privoxy to bridge
`http://127.0.0.1:8118` → the Bastion SOCKS5 proxy — see
[`azure-proxy/privoxy/README.md`](../../../../azure-proxy/privoxy/README.md).

For the full upstream walkthrough (options, troubleshooting, how auth works) see
[upstream `bastion-proxy.md`](https://github.com/bcgov/action-deployer-vm-bastion-alz/blob/v1.0.0/bastion-consumer-scripts/bastion-proxy.md).
