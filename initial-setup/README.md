# Initial Infrastructure Setup

This directory contains scripts and Terraform configurations for the one-time setup of Azure infrastructure and GitHub Actions OIDC authentication.

## ⚠️⚠️⚠️ Important: Run from Dev Machine Only If target module includes `jumpbox`⚠️⚠️⚠️

**This setup MUST be run from a local development machine, NOT from GitHub Actions.**
**Remember to login using incognito mode in browser with device code to avoid token expired weird issues**

### Why?

1. **Chicken-and-egg problem**: GitHub Actions needs OIDC credentials to authenticate to Azure, but we need to create those credentials first. The `initial-azure-setup.sh` script creates the managed identity and federated credentials that enable GitHub Actions to work.

2. **Security group membership**: The script adds the managed identity to the appropriate Entra ID security group. This requires owner permissions on the security group, which are typically held by project leads, not service principals.

3. **Interactive confirmation**: The Terraform deployment prompts for confirmation before creating resources, ensuring human oversight for foundational infrastructure.

4. **One-time setup**: This is a bootstrap process that only needs to run once per environment and adds the self hosted runner in `tools` environment. After completion, GitHub Actions handles all subsequent deployments.

5. **VM-Secret-Key**: The VM access is done if needed at all via bastion using ssh private key, which is another reason to run from dev machine who is owner of the subscription.

---

## Complete Setup Flow

The `initial-azure-setup.sh` script orchestrates the entire setup process:

```
initial-azure-setup.sh
        │
        ├── 1. Create User-Assigned Managed Identity
        ├── 2. Configure OIDC Federated Credentials
        ├── 3. Add Identity to Security Group
        ├── 4. Create Terraform State Storage Account
        ├── 5. Create GitHub Environment & Secrets (optional)

---

## Quick Start (Recommended)

Run the complete setup with a single command:

```bash
# Navigate to initial-setup directory
cd initial-setup

# Run the setup script for tools environment
./initial-azure-setup.sh \
  -g "ABCD-tools-networking" \
  -n "myapp-tools-identity" \
  -r "myorg/myrepo" \
  -e "tools" \
  -s "12345678-1234-1234-1234-123456789012" \
  --create-storage \
  --create-github-secrets
```

This will:
1. Create the managed identity and OIDC credentials
2. Set up the Terraform state storage account
3. Create GitHub environment and secrets

---

## Prerequisites

1. **Operating System** - Linux or macOS (Windows not supported)
2. **Access to Azure Landing Zone** - VNet must exist
3. **Security Group Ownership** - Must be owner of `DO_PuC_Azure_Live_{LicensePlate}_Contributor`
4. **terraform.tfvars** - Configuration file with your values (in `infra/` folder)

### Required Tools (Auto-Installed)

The `initial-azure-setup.sh` script automatically detects and installs missing tools on Linux and macOS:

| Tool | Required | Installation Method |
|------|----------|---------------------|
| **Azure CLI** | ✅ Yes | apt/yum/brew (depending on OS) |
| **Terraform** >= 1.12.0 | ✅ Yes | apt/yum/brew (depending on OS) |
| **GitHub CLI** | ❌ Optional | apt/yum/brew (for automatic secret creation) |

#### Installation Behavior

When you run `initial-azure-setup.sh`:

1. **Detection**: Script checks if each tool is already installed
2. **Prompting**: If a required tool is missing, you'll be prompted:
   ```
   Azure CLI not found. Install Azure CLI? (yes/no)
   ```
3. **Auto-Installation**: Responds to `yes` with automatic installation for your OS
4. **Graceful Fallback**: On unsupported systems, provides manual installation guidance

#### Supported Package Managers

**Linux:**
- `apt` (Debian/Ubuntu)
- `yum` (RedHat/CentOS/Fedora)
- `pacman` (Arch Linux)

**macOS:**
- `brew` (Homebrew)

If your system uses a different package manager, the script will exit with a link to manual installation instructions.

## Sample Terraform tfvars - placeholder values with $prefix must be replaced.
```hcl
# -----------------------------------------------------------------------------
# Terraform Variables Configuration
# -----------------------------------------------------------------------------

# Application Configuration
app_env  = "tools"
app_name = "ai-hub-deploy-utils"

# Azure Resource Configuration
location            = "Canada Central"
resource_group_name = "ai-hub-deploy-utils-tools"
# Virtual Network Configuration (existing VNet from platform team)
vnet_name                = "$licenseplate-tools-vwan-spoke" # Set via TF_VAR_vnet_name or GitHub secret
vnet_resource_group_name = "$licenseplate-tools-networking" # Set via TF_VAR_vnet_resource_group_name or GitHub secret
vnet_address_space       = "$address-space"          # Set via TF_VAR_vnet_address_space or GitHub secret

# Common Tags
common_tags = {
  Environment = "tools"
  Project     = "ai-hub-deploy-utils"
  ManagedBy   = "Terraform"
}


subscription_id = "$subscription_id"
tenant_id       = "$tenant_id$"
client_id       = "" , just set it to blank, since it will take user authz
use_oidc        = false # keep it false, since it is user authz

# -----------------------------------------------------------------------------
# GitHub Runners on Azure Container Apps
# -----------------------------------------------------------------------------
# These are set via TF_VAR_* environment variables in GitHub Actions
github_runners_aca_enabled      = true                                       # Enable in GitHub Actions workflow
github_organization             = "bcgov"                                    # Set via TF_VAR_github_organization
github_repository               = "ai-hub-tracking"                          # Set via TF_VAR_github_repository
github_runner_pat               = "$github_pat" # Set via TF_VAR_github_runner_pat (sensitive)
```
---

## Manual Terraform Deployment

If you skipped the infrastructure deployment during setup, or need to run it separately:

```bash
# 1. Navigate to infra directory
cd initial-setup/infra

# 2. Ensure terraform.tfvars is configured
# Edit terraform.tfvars with your values

# 3. Login to Azure (if not already)
az login

# 4. Initialize Terraform
./deploy-terraform.sh init

# 5. Preview changes
./deploy-terraform.sh plan

# 6. Apply changes
./deploy-terraform.sh apply
```

## Deploy Specific Modules

```bash
# Deploy only network module
./deploy-terraform.sh apply -target=module.network

# Deploy only bastion (for temporary access)
./deploy-terraform.sh apply -target=module.bastion

# Destroy bastion when done (save costs)
./deploy-terraform.sh destroy -target=module.bastion
```

## Directory Structure

```
initial-setup/infra/
├── deploy-terraform.sh     # Deployment wrapper script
├── main.tf                 # Root module and resource group
├── variables.tf            # Input variable definitions
├── outputs.tf              # Output values
├── providers.tf            # Provider configuration
├── backend.tf              # Remote state configuration
├── terraform.tfvars        # Variable values (not committed)
└── modules/
    ├── bastion/            # Azure Bastion host
    ├── github-runners-aca/ # Self-hosted GitHub runners
    ├── jumpbox/            # Development VM
    ├── azure-proxy/            # The Secure tunnel deployment using chisel
    └── network/            # Subnets and NSGs
```

## Backend State

Terraform state is stored in Azure Storage:
- **Resource Group**: Configured via `BACKEND_RESOURCE_GROUP`
- **Storage Account**: Configured via `BACKEND_STORAGE_ACCOUNT`
- **Container**: `tfstate`
- **Key**: `ai-hub-deploy-utils/tools/terraform.tfstate`

Backend values are injected via the deployment script using `-backend-config` flags.

## Environment Variables

The deployment script supports these environment variables:

| Variable | Description | Required |
|----------|-------------|----------|
| `TF_VAR_subscription_id` | Azure Subscription ID | If no tfvars |
| `TF_VAR_tenant_id` | Azure Tenant ID | If no tfvars |
| `TF_VAR_client_id` | Azure Client ID (OIDC) | If no tfvars |
| `ARM_USE_OIDC` | Use OIDC authentication | Optional |
| `CI` | Enable CI mode (auto-approve) | Optional |

## Related Documentation

- [Terraform Reference](../../docs/terraform.html) - Detailed module documentation
- [Workflows](../../docs/workflows.html) - GitHub Actions workflows
- [OIDC Setup](../../docs/oidc-setup.html) - Azure authentication setup
