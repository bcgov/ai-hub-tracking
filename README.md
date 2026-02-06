# AI-Hub-Utils
This is the central repo to track overall project with issues and github project linked for AI Services Hub.

## Documentation
📚 **[View Full Documentation](https://bcgov.github.io/ai-hub-tracking/)**

Comprehensive guides for OIDC setup, Terraform deployments, and Azure Landing Zone architecture.

**Quick Links**:
- [Local Development Deployment Guide](infra-ai-hub/README.md#local-development-deployment) - Deploy from your local machine using Chisel tunnel
- [Operational Playbooks](https://bcgov.github.io/ai-hub-tracking/playbooks.html) - Troubleshooting and runbooks
- [Terraform Modules](https://bcgov.github.io/ai-hub-tracking/terraform.html) - Terraform modules overview

## Tools & Installation

**Supported Platforms:** Linux and macOS

The `initial-setup/initial-azure-setup.sh` script automatically installs missing tools:

- **Azure CLI** - Authentication and Azure resource management
- **Terraform** >= 1.12.0 - Infrastructure as code
- **GitHub CLI** (optional) - Automatic GitHub secret creation

The script detects your OS and package manager (apt, yum, brew) to install tools with interactive prompts. See [Initial Setup README](initial-setup/README.md) for detailed information.

## Folder Structure

```
ai-hub-tracking/
│
├── initial-setup/                      # One-time setup for Azure infrastructure & GitHub Actions OIDC
│   ├── initial-azure-setup.sh          # Main setup script (auto-installs missing tools + manages OIDC setup)
│   ├── README.md                       # Setup instructions, tool installation details, and flow documentation
│   │
│   └── infra/                          # Terraform configurations for foundational infrastructure
│       ├── deploy-terraform.sh         # Deployment wrapper script (init, plan, apply, destroy)
│       ├── main.tf                     # Root module - resource group and module orchestration
│       ├── variables.tf                # Input variable definitions
│       ├── outputs.tf                  # Output values (resource IDs, endpoints)
│       ├── providers.tf                # Provider versions and features
│       ├── backend.tf                  # Remote state configuration
│       ├── terraform.tfvars            # Variable values (not committed, create locally)
│       │
│       └── modules/                    # Reusable Terraform modules
│           ├── network/                # Virtual Network, subnets, NSGs
│           ├── bastion/                # Azure Bastion for secure access
│           ├── jumpbox/                # Development VM with CLI tools
│           ├── github-runners-aca/     # Self-hosted GitHub runners on Container Apps
│           ├── azure-proxy/            # Secure tunnel (chisel) deployment used for proxying
│           └── monitoring/             # Log Analytics & Application Insights for observability
│
├── infra-ai-hub/                       # Separate infrastructure for AI Hub project
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── backend.tf
│   └── README.md
│
├── .github/                            # GitHub Actions workflows and configuration
│   ├── workflows/                      # CI/CD automation
│   │   ├── .deployer.yml               # Reusable Terraform deployment workflow
│   │   ├── bastion-add-or-remove.yml   # Manual Bastion lifecycle management
│   │   ├── pages.yml                   # Documentation deployment to GitHub Pages
│   │   └── schedule.yml                # Scheduled cleanup tasks
│   │
│   └── instructions/                   # Coding guidelines and preferences
│       ├── copilot.instructions.md     # GitHub Copilot preferences and patterns
│       ├── code-review.instructions.md # Code review guidelines for PRs
│       └── azure-networking.instructions.md # Azure Landing Zone networking rules
│
├── docs/                               # Static HTML documentation
│   ├── build.sh                        # Script to generate HTML from templates
│   ├── generate-tf-docs.sh             # Auto-generate Terraform module docs
│   ├── index.html                      # Home page
│   ├── terraform.html                  # Terraform modules and deployment guide
│   ├── workflows.html                  # GitHub Actions workflows documentation
│   ├── oidc-setup.html                 # OIDC authentication setup guide
│   ├── terraform-reference.html        # Auto-generated module reference
│   ├── decisions.html                  # Architectural decision records
│   ├── diagrams.html                   # Architecture diagrams
│   ├── playbooks.html                  # Operational playbooks
│   ├── faq.html                        # Frequently asked questions
│   │
│   ├── _pages/                         # Markdown sources for HTML generation
│   │   ├── _template.html              # Base HTML template
│   │   └── [various .html files]       # Source files for each page
│   │
│   ├── _partials/                      # HTML snippets
│   │   ├── header.html
│   │   └── footer.html
│   │
│   └── assets/                         # Images, CSS, JavaScript
│
├── sensitive/                          # Local credentials and secrets (git ignored)
│   └── [credentials, keys, tokens]     # Never commit to repository
│
├── renovate.json                       # Automated dependency updates configuration
├── .gitattributes                      # Git file handling rules (line endings, binary)
├── .gitignore                          # Files excluded from version control
├── LICENSE                             # Repository license
├── README.md                           # This file
```

## Directory Descriptions

### `initial-setup/`
Bootstrap directory for one-time environment setup. Contains the main setup automation script and foundational Terraform infrastructure.

- **initial-azure-setup.sh**: Orchestrates Azure infrastructure setup
  - Creates user-assigned managed identity with vault access for data plane requests
  - Configures OIDC federated credentials
  - Establishes Terraform state storage on azure blob.
  - Optionally deploys initial infrastructure via Terraform after user consent.
  
- **infra/**: Terraform configurations for foundational resources
  - **network**: VNet subnets, NSGs, security boundaries
  - **bastion**: Azure Bastion host for secure access (optional via `enable_bastion`)
  - **jumpbox**: Development VM with Azure/Kubernetes CLI tools (optional via `enable_jumpbox`)
  - **github-runners-aca**: Self-hosted GitHub runners on Container Apps (optional via `github_runners_aca_enabled`)
  - **azure-proxy**: Secure tunnel (chisel) deployment used for proxying (optional via `enable_azure_proxy`)
  - **monitoring**: Log Analytics and Application Insights for observability

### `.github/`
GitHub Actions automation and contribution guidelines.

- **workflows/**: Reusable CI/CD pipelines
  - `.deployer.yml`: Generic Terraform deployment workflow (used by other workflows)
  - Other workflows orchestrate specific deployment scenarios
  
- **instructions/**: Guidelines for contributors and Copilot
  - Review standards for infrastructure code
  - Terraform, Bash, GitHub Actions patterns specific to this repo
  - Azure Landing Zone compliance requirements

### `docs/`
Static HTML documentation generated from templates and scripts.

- Source files in `_pages/` are processed by `build.sh`
- `generate-tf-docs.sh` auto-generates Terraform module documentation
- Published to GitHub Pages via `pages.yml` workflow
- Includes architecture decisions, operational playbooks, and FAQs

### `infra-ai-hub/`
Separate Terraform workspace for AI Hub project infrastructure (independent from initial-setup).

**Notable changes on this branch:** Added `azure-proxy` and `monitoring` modules; several modules can now be toggled via `enable_*` variables (`enable_azure_proxy`, `enable_bastion`, `enable_jumpbox`, `github_runners_aca_enabled`). The deployment tooling (`deploy-terraform.sh`) gained automatic import-on-conflict and retry behavior, and `.github/workflows/deploy-using-self-hosted.yml` was removed in favour of the generic `.deployer.yml` workflow which now supports the new modules.

