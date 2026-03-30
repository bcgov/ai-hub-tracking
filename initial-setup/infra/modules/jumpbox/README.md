# Azure Bastion and Jumpbox VM

This module deploys an Azure Linux VM (Jumpbox) with Azure Bastion for secure, browser-based access to private Azure resources.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Portal (HTTPS)                         │
│                    https://portal.azure.com                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Bastion (Standard SKU)                 │
│                    AzureBastionSubnet /26                       │
│                    Public IP: Standard SKU                      │
│                    Native client tunneling enabled              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ SSH (Port 22)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Jumpbox VM (Dedicated B-series)              │
│                    Ubuntu 24.04 LTS (CLI Only)                  │
│                    2 vCPU / 4 GB RAM (Standard_B2als_v2)        │
│                    Azure CLI, GitHub CLI, Terraform, Docker     │
│                    SSH Access via Bastion                       │
│                    jumpbox-subnet /28                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              │ Private Endpoints
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│              Azure PaaS Services (Private Access)               │
│    • Azure OpenAI    • Cosmos DB    • Azure AI Search           │
│    • Document Intelligence    • Key Vault                       │
└─────────────────────────────────────────────────────────────────┘
```

## Features

- **Dedicated B-series VM**: Cost-effective burstable compute with consistent availability (no evictions)
- **Ubuntu 24.04 LTS**: Latest LTS release (Noble Numbat) with long-term support until 2034
- **CLI-Only**: Lightweight setup with essential DevOps tools (no desktop environment)
- **Pre-installed Tools**: Azure CLI, GitHub CLI, Terraform, kubectl, Docker
- **Azure Bastion**: Secure SSH access without public IP on VM (Standard SKU with native CLI tunneling)
- **Entra ID SSH Login**: Optional Microsoft Entra ID (AAD) authentication via `AADSSHLoginForLinux` VM extension — no SSH keys required
- **Managed Identity**: Access Azure services without storing credentials
- **Auto-generated SSH Keys**: Keys stored in Azure and locally
- **Random Admin Username**: 12-char alphanumeric username for added security
- **Auto-Shutdown**: VM automatically shuts down at 7 PM PST daily
- **Auto-Start**: VM automatically starts at 8 AM PST Monday-Friday (Python3 Automation Runbook)

## VM Schedule

The Jumpbox VM has automatic scheduling to minimize costs:

| Action | Time | Days | Mechanism |
|--------|------|------|-----------|
| **Auto-Shutdown** | 7:00 PM PST | Daily (including weekends) | Azure DevTest Labs Schedule |
| **Auto-Start** | 8:00 AM PST | Monday - Friday only | Azure Automation Runbook (Python3) |

### Schedule Details

- **Weekdays (Mon-Fri)**: VM runs from 8 AM to 7 PM PST (11 hours)
- **Weekends (Sat-Sun)**: VM stays OFF (no auto-start on weekends)
- **Time Zone**: Pacific Standard Time (PST/PDT)

### Manual Override

If you need the VM outside scheduled hours:

```bash
# Start VM manually via Azure CLI
az vm start --resource-group <rg-name> --name <vm-name>

# Stop VM manually
az vm deallocate --resource-group <rg-name> --name <vm-name>
```

Or via Azure Portal:
1. Navigate to **Virtual Machines** → Select your Jumpbox
2. Click **Start** or **Stop** button

## Connecting to the Jumpbox VM

### Via Azure CLI with Entra ID (Recommended)

When Entra ID login is enabled (`enable_entra_login = true`), you can SSH using your Entra identity without any SSH keys:

```bash
# Login to Azure CLI
az login

# SSH via Bastion using Entra ID authentication
az network bastion ssh \
  --name <bastion-name> \
  --resource-group <rg-name> \
  --target-resource-id <vm-resource-id> \
  --auth-type AAD

# Or tunnel a port for local SSH client access
az network bastion tunnel \
  --name <bastion-name> \
  --resource-group <rg-name> \
  --target-resource-id <vm-resource-id> \
  --resource-port 22 \
  --port 2222
# Then in another terminal: ssh -p 2222 localhost
```

> **Prerequisites**: Requires Azure CLI with the `bastion` extension (`az extension add --name bastion`). Your Entra user or group must be in the `vm_admin_login_principal_ids` list for the `Virtual Machine Administrator Login` RBAC role.

### Via Azure Portal with SSH Key (Fallback)

1. Navigate to the [Azure Portal](https://portal.azure.com)
2. Go to **Virtual Machines** → Select your Jumpbox VM (`*-jumpbox`)
3. Click **Connect** → **Connect via Bastion**
4. Select **Connection Type**: **SSH**
5. Select **Authentication Type**: **SSH Private Key from Local File**
6. Enter username: Run `terraform output -raw admin_username` to get the value
7. Upload the private key from `sensitive/jumpbox_ssh_key.pem`
8. Click **Connect**

> **Finding Your Username**: The admin username is randomly generated for security. Get it from:
> ```bash
> # From Terraform output
> cd infra
> terraform output -raw admin_username
> ```

### Finding the SSH Private Key

The SSH private key is automatically generated and stored in two locations:

#### 1. Azure Portal (SSH Public Keys Resource)

1. Navigate to [Azure Portal](https://portal.azure.com)
2. Search for **"SSH public keys"** in the search bar
3. Find the key named `{app_name}-jumpbox-ssh-key`
4. The public key is displayed here
5. **Note**: The private key is only available at creation time

#### 2. Local File (Generated by Terraform)

The private key is saved locally at:
```
sensitive/jumpbox_ssh_key.pem
```

⚠️ **Security Notes**:
- This file is in `.gitignore` and should **NEVER** be committed to version control
- File permissions are set to `0600` (owner read/write only)
- Store securely and rotate keys periodically

#### 3. Terraform State (Break-Glass Retrieval)

If the local file is absent (e.g., infrastructure was deployed from GitHub Actions rather than a local machine), retrieve the private key directly from Terraform state:

```bash
cd initial-setup/infra

# Print the private key to stdout — redirect to a secure file
terraform output -raw jumpbox_ssh_private_key > /tmp/jumpbox_ssh_key.pem
chmod 0600 /tmp/jumpbox_ssh_key.pem

# Then connect via SSH through the Bastion tunnel:
# az network bastion tunnel --name <bastion> --resource-group <rg> \
#   --target-resource-id <vm-id> --resource-port 22 --port 2222 &
# ssh -i /tmp/jumpbox_ssh_key.pem -p 2222 <admin_username>@localhost
```

> ⚠️ This requires access to the Terraform remote state backend (Azure Storage). Treat the extracted key as sensitive — delete the local copy after use.

### Using the CLI Tools

After connecting via SSH through Bastion:

```bash
# Authenticate to Azure using managed identity
az login --identity

# Authenticate to GitHub
gh auth login

# Check Terraform version
terraform version

# Use kubectl
kubectl version --client

# Use Docker
docker --version
```

### Installed Software

| Software | Purpose |
|----------|---------|
| Azure CLI | Azure resource management |
| GitHub CLI (gh) | GitHub operations (PRs, issues, actions) |
| Terraform | Infrastructure as Code |
| kubectl | Kubernetes cluster management |
| Docker | Container runtime |
| Python 3 + pip + venv | Python development |
| Git | Version control |
| tmux | Terminal multiplexer |
| vim, htop, jq, curl, wget | Essential utilities |

## SOCKS5 Proxy for Private PaaS Access

The `bastion-proxy.sh` script creates a SOCKS5 proxy on your local machine by
tunnelling through Azure Bastion to the jumpbox VM. Once running, any tool that
supports SOCKS5 can reach private PaaS endpoints the jumpbox can see — no VPN
required, and **a single proxy port handles all endpoints simultaneously**.

### How It Works

```
Your machine  ──────────────────────────────────────────────────────────────▶
  │                                                                         │
  │  SOCKS5 (localhost:8228)                                                │
  ▼                                                                         │
az network bastion ssh ──▶ Azure Bastion ──▶ Jumpbox VM ──▶ Private endpoints
                            (authenticated)   (DNS resolver)
                                                              • CosmosDB
                                                              • PostgreSQL
                                                              • Redis
                                                              • Azure OpenAI
                                                              • AI Search
                                                              • Key Vault
```

The jumpbox resolves hostnames and forwards TCP traffic on your behalf. Because
SOCKS5 proxies DNS through the jumpbox, every private endpoint the jumpbox can
reach is instantly accessible through the one proxy port — no per-service
tunnel configuration is needed.

### Running the Proxy

> **Important — Incognito / Private Browsing required for device code login**
>
> When the terminal prints a device code URL (`https://microsoft.com/devicelogin`),
> open it in an **Incognito / Private Browsing** window. If you use a regular
> browser tab, the browser may silently sign in with a cached personal Microsoft
> account and authenticate as the wrong user.
>
> | Browser | Open Incognito / Private |
> |---------|-------------------------|
> | Chrome / Edge | `Ctrl+Shift+N` (Win/Linux) &nbsp; `⌘+Shift+N` (macOS) |
> | Firefox | `Ctrl+Shift+P` (Win/Linux) &nbsp; `⌘+Shift+P` (macOS) |
> | Safari | `⌘+Shift+N` |

```bash
# Prerequisites (one-time setup)
az extension add --name bastion
az extension add --name ssh   # AAD auth only

# Entra ID (AAD) auth — recommended
# Run from initial-setup/infra/
./scripts/bastion-proxy.sh \
  --resource-group <rg-name> \
  --bastion-name <app_name>-bastion \
  --vm-name <app_name>-jumpbox

# SSH key auth — break-glass fallback
./scripts/bastion-proxy.sh \
  --resource-group <rg-name> \
  --bastion-name <app_name>-bastion \
  --vm-name <app_name>-jumpbox \
  --auth-type ssh-key \
  --username $(terraform output -raw jumpbox_admin_username) \
  --ssh-key ../sensitive/jumpbox_ssh_key.pem
```

The script will:
1. Device-code `az login` if not already authenticated (open the URL in Incognito — see note above)
2. Switch to subscription `eb733692-257d-40c8-bd7b-372e689f3b7f`
3. Find an available SOCKS5 port starting at 8228 (tries next ports automatically if 8228 is in use)
4. Start the VM if it is stopped (prompts for confirmation)
5. Verify the Bastion host is in a healthy provisioning state (waits if still provisioning)
6. Open the Bastion tunnel and print the proxy address with session expiry time
7. Block until `Ctrl+C` — warns 1 hour before the 12h Entra ID session limit and stops automatically at expiry

### Configuring Tools to Use the Proxy

Set environment variables to route all tools through the proxy:

```bash
export HTTPS_PROXY=socks5://localhost:8228
export HTTP_PROXY=socks5://localhost:8228
```

Or use per-command flags. All examples below use the **same proxy port** regardless
of which PaaS endpoint you are targeting.

#### Azure CLI

```bash
HTTPS_PROXY=socks5://localhost:8228 az cosmosdb list --resource-group <rg>
HTTPS_PROXY=socks5://localhost:8228 az keyvault secret list --vault-name <kv>
```

#### curl

```bash
# --socks5-hostname ensures the hostname is resolved by the jumpbox (not locally)
curl --socks5-hostname localhost:8228 https://<account>.documents.azure.com/
curl --socks5-hostname localhost:8228 https://<account>.openai.azure.com/
```

#### PostgreSQL (psql)

```bash
# Via proxychains (Linux/macOS)
proxychains psql "host=<server>.postgres.database.azure.com port=5432 \
  dbname=<db> user=<user> sslmode=require"

# Or set PGPROXY via ~/.proxychains/proxychains.conf
```

#### Redis

```bash
proxychains redis-cli -h <account>.redis.cache.windows.net -p 6380 --tls
```

#### MongoDB / CosmosDB (Mongo API)

```bash
proxychains mongosh "mongodb://<account>.mongo.cosmos.azure.com:10255/..." \
  --tls --tlsAllowInvalidCertificates
```

#### Python / Node.js (environment variable approach)

```python
import os, httpx

# Set before making any requests
os.environ["HTTPS_PROXY"] = "socks5://localhost:8228"

client = httpx.Client()
resp = client.get("https://<account>.openai.azure.com/")
```

### Multiple Connections on One Port

SOCKS5 is a full proxy protocol — a single listener handles unlimited concurrent
connections to different hosts and ports. You do **not** need separate proxy
instances for each PaaS service. All of the following can run simultaneously
through `localhost:8228`:

| Target | Example host |
|--------|-------------|
| Azure OpenAI | `<account>.openai.azure.com` |
| CosmosDB | `<account>.documents.azure.com` |
| PostgreSQL Flexible Server | `<server>.postgres.database.azure.com` |
| Redis Cache | `<account>.redis.cache.windows.net` |
| Azure AI Search | `<account>.search.windows.net` |
| Key Vault | `<vault>.vault.azure.net` |
| APIM private endpoint | `<apim>.azure-api.net` |

### Using Different Ports for Multiple Sessions

If you need two simultaneous proxy sessions (e.g., different subscriptions), pass
`--port` to start the second instance on a different port:

```bash
# Session 1 (default port 8228)
./scripts/bastion-proxy.sh -g <rg> -b <bastion> -v <vm>

# Session 2 in a new terminal (auto-selects next free port after 8300)
./scripts/bastion-proxy.sh -g <rg> -b <bastion> -v <vm> --port 8300
```

## Auto-Start Implementation

The auto-start feature uses Azure Automation with a Python3 runbook:

- **Automation Account**: System-assigned managed identity with VM Contributor role
- **Runbook**: Python3 script using Azure REST API (no external package dependencies)
- **Schedule**: Weekday mornings at 8 AM PST (Monday-Friday)

The runbook uses the Azure Instance Metadata Service (IMDS) to obtain an access token, then calls the Azure Management REST API directly. This approach avoids Python package dependency issues in Azure Automation.

## VM Specifications

| Spec | Value |
|------|-------|
| **VM Size** | Standard_B2als_v2 |
| **vCPUs** | 2 |
| **Memory** | 4 GB |
| **Type** | Burstable (B-series) |
| **Priority** | Regular (dedicated, no evictions) |
| **OS Disk** | 64 GB Standard LRS |
| **Estimated Cost** | ~$30-40/month (with auto-shutdown schedule) |

> **Note**: B-series VMs are burstable, meaning they accumulate CPU credits when idle and can burst above baseline when needed. This is ideal for jumpbox workloads with variable usage.

## Subnet Allocation

| Subnet | CIDR | Purpose |
|--------|------|---------|
| jumpbox-subnet | x.x.x.144/28 | Jumpbox VM (11 usable IPs) |
| AzureBastionSubnet | x.x.x.192/26 | Azure Bastion (59 usable IPs) |

## Security

- **No Public IP**: The Jumpbox VM has no public IP address
- **Random Admin Username**: 12-character alphanumeric username generated at deployment (security by obscurity)
- **SSH Key Authentication**: Password authentication disabled, SSH keys required (Entra ID login available as alternative)
- **Entra ID RBAC**: When enabled, `Virtual Machine Administrator Login` role scoped to the VM for authorized principals
- **NSG Rules**: Only SSH (22) from Bastion subnet is allowed inbound
- **Private Subnet**: Default outbound access is disabled
- **Managed Identity**: VM can access Azure services without credentials
- **Auto-Generated SSH Keys**: Keys stored in Azure and saved locally to `sensitive/` folder

### Getting Credentials

```bash
# Get the admin username
terraform output -raw admin_username

# SSH private key location
terraform output -raw ssh_private_key_path
# Default: ../sensitive/jumpbox_ssh_key.pem
```

## Troubleshooting

### Bastion Connection Issues

1. Ensure NSG rules allow traffic between Bastion and VM subnets
2. Check that the VM is in "Running" state
3. Verify the username is correct

### VM Not Starting

1. Check VM state in Azure Portal
2. Click "Start" to start the VM
3. Check Azure Service Health for any regional outages
4. Verify the Automation Account runbook executed successfully (for auto-start issues)

### Desktop Not Loading

The GNOME desktop installation runs via `custom_data` script at first boot. Wait 5-10 minutes after initial deployment for installation to complete.

---

## Azure Bastion Cost Optimization

Azure Bastion Standard SKU runs a minimum of 2 scale units (instances), so the minimum hourly cost is always 2× the per-instance rate (~$0.397/hour × 2 = ~$0.794/hour in Canada Central). This cost applies even when idle. Here are strategies to reduce costs:

### Option 1: Delete and Recreate Bastion (Recommended)

**Delete Bastion when not needed:**

```bash
# Delete Bastion (keeps the subnet and NSG)
az network bastion delete \
  --name <bastion-name> \
  --resource-group <rg-name>

# Delete the Public IP (saves ~$3/month)
az network public-ip delete \
  --name <bastion-pip-name> \
  --resource-group <rg-name>
```

**Recreate when needed:**

```bash
# Create Public IP
az network public-ip create \
  --name <bastion-pip-name> \
  --resource-group <rg-name> \
  --location canadacentral \
  --sku Standard \
  --allocation-method Static

# Create Bastion (Standard SKU for CLI tunneling support)
az network bastion create \
  --name <bastion-name> \
  --resource-group <rg-name> \
  --location canadacentral \
  --vnet-name <vnet-name> \
  --public-ip-address <bastion-pip-name> \
  --sku Standard \
  --enable-tunneling true
```

### Option 2: Use Terraform Workspace Targeting

```bash
# Destroy only Bastion resources
cd infra
terraform destroy -target=module.bastion

# Recreate when needed
terraform apply -target=module.bastion
```

### Option 3: Automated Schedule with GitHub Actions

Create a scheduled workflow to delete Bastion at end of day:

```yaml
# .github/workflows/bastion-scheduler.yml
name: Bastion Cost Scheduler

on:
  schedule:
    # Delete at 7 PM PST (3 AM UTC next day)
    - cron: '0 3 * * *'
  workflow_dispatch:
    inputs:
      action:
        description: 'Action to perform'
        required: true
        default: 'delete'
        type: choice
        options:
          - delete
          - create

jobs:
  manage-bastion:
    runs-on: ubuntu-latest
    steps:
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      
      - name: Delete Bastion
        if: github.event.inputs.action == 'delete' || github.event_name == 'schedule'
        run: |
          az network bastion delete --name ${{ vars.BASTION_NAME }} --resource-group ${{ vars.RESOURCE_GROUP }} --yes || true
          az network public-ip delete --name ${{ vars.BASTION_PIP_NAME }} --resource-group ${{ vars.RESOURCE_GROUP }} || true
```

### Option 4: Use Bastion Developer SKU (Free)

If you only need basic access, consider using **Bastion Developer SKU**:
- **Cost**: Free (no hourly charges)
- **Limitation**: One VM connection at a time
- **No dedicated subnet required**

⚠️ **Note**: Developer SKU is not deployed via this module. It must be configured per-VM in the portal.

### Cost Comparison

| Resource | Hourly Cost | Monthly Cost (24/7) | Monthly (8AM-7PM M-F) |
|----------|-------------|---------------------|----------------------|
| Bastion Basic | ~$0.19 | ~$140 | ~$45 |
| Bastion Standard | ~$0.35 | ~$260 | ~$80 |
| Public IP (Standard) | ~$0.004 | ~$3 | ~$3 |
| **Total Basic** | - | ~$143 | ~$48 |

**Delete/Recreate Strategy**: If you only use Bastion 2 hours/day for testing, you'd pay ~$12/month instead of $143/month.

### When to Keep Bastion Running

- Multiple team members need VM access throughout the day
- You're actively debugging production issues
- You need immediate access without 5-minute deployment wait

### When to Delete Bastion

- Weekend/holiday periods
- After-hours (if using scheduled deletion)
- Project is in maintenance mode with infrequent access needs
