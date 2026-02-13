# AI-Hub
This is the central repo to track overall project with issues and github project linked for AI Services Hub.

## Documentation
📚 **[View Full Documentation](https://bcgov.github.io/ai-hub-tracking/)**

Comprehensive guides for OIDC setup, Terraform deployments, and Azure Landing Zone architecture.

**Quick Links**:
- [Local Development Deployment Guide](infra-ai-hub/README.md#local-development-deployment) - Deploy from your local machine using Chisel tunnel
- [Operational Playbooks](https://bcgov.github.io/ai-hub-tracking/playbooks.html) - Troubleshooting and runbooks
- [Terraform Modules](https://bcgov.github.io/ai-hub-tracking/terraform.html) - Terraform modules overview
- [PII Anonymization](https://bcgov.github.io/ai-hub-tracking/language-service-pii.html) - PII redaction via Azure Language Service
- [Document Intelligence](https://bcgov.github.io/ai-hub-tracking/document-intelligence.html) - OCR and document analysis

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
├── infra-ai-hub/                       # AI Hub project infrastructure (multi-tenant AI services)
│   ├── main.tf                         # Root module orchestration
│   ├── variables.tf                    # Input variable definitions
│   ├── outputs.tf                      # Output values
│   ├── providers.tf                    # Provider configuration
│   ├── backend.tf                      # Remote state configuration
│   ├── locals.tf                       # Tenant config processing and policy generation
│   ├── terraform.tfvars                # Shared variable values
│   ├── README.md                       # Deployment guide and module documentation
│   │
│   ├── modules/                        # Terraform modules for AI Hub infrastructure
│   │   ├── ai-foundry-hub/             # Azure AI Foundry Hub (central AI workspace)
│   │   ├── apim/                       # API Management (StandardV2, multi-tenant gateway)
│   │   ├── app-configuration/          # Azure App Configuration
│   │   ├── app-gateway/                # Application Gateway (WAF v2, SSL termination)
│   │   ├── container-app-environment/  # Container App Environment
│   │   ├── container-registry/         # Azure Container Registry
│   │   ├── dashboard/                  # Azure Dashboard
│   │   ├── defender/                   # Microsoft Defender for Cloud
│   │   ├── dns-zone/                   # Azure DNS Zone management
│   │   ├── foundry-project/            # AI Foundry tenant projects
│   │   ├── key-rotation-function/      # Automated APIM subscription key rotation
│   │   ├── network/                    # Virtual Network, subnets, private endpoints
│   │   ├── storage-account/            # Azure Storage Account
│   │   ├── tenant/                     # Per-tenant resources (AI Search, CosmosDB, Doc Intel, etc.)
│   │   ├── tenant-user-management/     # Entra ID user/group assignments per tenant
│   │   └── waf-policy/                 # Web Application Firewall custom rules
│   │
│   ├── params/                         # Environment and tenant configuration
│   │   ├── apim/                       # APIM policies and fragments
│   │   │   ├── api_policy.xml.tftpl    # Per-tenant API policy template
│   │   │   ├── global_policy.xml       # Global APIM policy
│   │   │   ├── landing_page_policy.xml # Landing page policy
│   │   │   └── fragments/              # Policy fragments (PII, auth, logging, routing)
│   │   ├── dev/                        # Dev environment config
│   │   ├── test/                       # Test environment config
│   │   └── prod/                       # Production environment config
│   │
│   ├── scripts/                        # Deployment and utility scripts
│   │   ├── deploy-terraform.sh         # Phased deployment (init, plan, apply with retry)
│   │   ├── extract-import-target.sh    # Extract Terraform import targets from errors
│   │   ├── purge-ai-foundry.sh         # Purge AI Foundry soft-deleted resources
│   │   └── wait-for-dns-zone.sh        # Wait for DNS zone propagation
│   │
│   ├── functions/                      # Azure Functions source code
│   │   └── key-rotation/               # APIM subscription key rotation function
│   │
│   └── tenant-user-mgmt/              # Separate Terraform workspace for tenant user management
│       ├── main.tf                     # Entra ID user/group assignments
│       └── README.md                   # Tenant user management documentation
│
├── tests/                              # Integration test suite
│   └── integration/                    # BATS-based integration tests
│       ├── chat-completions.bats       # OpenAI chat API tests
│       ├── document-intelligence.bats  # Document Intelligence API tests
│       ├── document-intelligence-binary.bats # Binary upload tests
│       ├── pii-redaction.bats          # PII redaction behavior tests
│       ├── pii-failure.bats            # PII fail-closed/fail-open tests
│       ├── subscription-key-header.bats # Auth and tenant isolation tests
│       ├── tenant-user-management.bats # User management tests
│       ├── test-helper.bash            # Shared test utilities
│       ├── config.bash                 # Test environment configuration
│       ├── run-tests.sh                # Test runner script
│       └── README.md                   # Test documentation
│
├── azure-proxy/                        # Docker configurations for secure proxy tunnel
│   ├── chisel/                         # Chisel tunnel server/client
│   └── privoxy/                        # Privoxy HTTP proxy
│
├── ssl_certs/                          # SSL certificate management scripts
│   ├── create-pfx.sh                   # Create PFX from cert+key
│   ├── csr-gen.sh                      # Generate certificate signing requests
│   ├── upload-cert-direct.sh           # Upload cert directly to App Gateway
│   ├── upload-cert-keyvault.sh         # Upload cert to Key Vault
│   ├── README.md                       # SSL certificate procedures
│   ├── test/                           # Test environment certificates
│   └── prod/                           # Production environment certificates
│
├── docs/                               # Static HTML documentation (GitHub Pages)
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
│   ├── cost.html                       # Cost analysis and optimization
│   ├── document-intelligence.html      # Document Intelligence setup and usage
│   ├── language-service-pii.html       # PII anonymization documentation
│   ├── technical-deep-dive.html        # Architecture deep dive
│   │
│   ├── _pages/                         # Source templates for HTML generation
│   │   ├── _template.html              # Base HTML template
│   │   └── [various .html files]       # Source files for each page
│   │
│   ├── _partials/                      # Shared HTML snippets
│   │   ├── header.html
│   │   └── footer.html
│   │
│   └── assets/                         # Images, CSS, JavaScript
│
├── .github/                            # GitHub Actions workflows and configuration
│   ├── workflows/                      # CI/CD automation
│   │   ├── .deployer.yml               # Reusable Terraform deployment workflow
│   │   ├── .deployer-using-secure-tunnel.yml # Deployment via Chisel tunnel
│   │   ├── .builds.yml                 # Reusable build workflow
│   │   ├── add-or-remove-module.yml    # Toggle infrastructure modules
│   │   ├── manual-dispatch.yml         # Manual deployment trigger
│   │   ├── pages.yml                   # Documentation deployment to GitHub Pages
│   │   ├── pr-open.yml                 # Pull request validation
│   │   └── schedule.yml                # Scheduled cleanup tasks
│   │
│   ├── instructions/                   # Coding guidelines and preferences
│   │   ├── copilot.instructions.md     # GitHub Copilot preferences and patterns
│   │   └── code-review.instructions.md # Code review guidelines for PRs
│   │
│   ├── skills/                         # Copilot skill profiles for specialized tasks
│   │   ├── iac-coder/                  # Infrastructure as Code authoring skills
│   │   ├── iac-code-reviewer/          # IaC code review skills
│   │   ├── api-management/             # APIM policy and routing skills
│   │   └── documentation/              # Documentation authoring skills
│   │
│   └── appmod/                         # Application modernization configs
│       └── appcat/                     # App CAT assessment configuration
│
├── sensitive/                          # Local credentials and secrets (git ignored)
│   └── [credentials, keys, tokens]     # Never commit to repository
│
├── renovate.json                       # Automated dependency updates configuration
├── test.http                           # HTTP request samples for API testing
├── .gitattributes                      # Git file handling rules (line endings, binary)
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

### `infra-ai-hub/`
Multi-tenant AI Services Hub infrastructure. Manages APIM gateway, AI Foundry, per-tenant resources (AI Search, CosmosDB, Document Intelligence, Speech Services), WAF, and APIM policy fragments (PII anonymization, authentication, usage logging, intelligent routing).

- **modules/**: 16 Terraform modules for all Azure resources
- **params/**: Environment configs (dev/test/prod) with per-tenant tfvars and APIM policy templates
- **scripts/**: Phased deployment script with import-on-conflict and retry logic
- **tenant-user-mgmt/**: Separate Terraform workspace for Entra ID user/group management

### `tests/`
BATS-based integration test suite for validating deployed infrastructure. Tests cover chat completions, document intelligence, PII redaction (fail-closed/fail-open), tenant isolation, binary uploads, and user management.

### `.github/`
GitHub Actions automation, contribution guidelines, and Copilot skill profiles.

- **workflows/**: CI/CD pipelines including reusable deployers, PR validation, scheduled tasks, and GitHub Pages publishing
- **instructions/**: Coding guidelines for Copilot and code review standards
- **skills/**: Specialized Copilot skill profiles for IaC authoring, code review, APIM policy management, and documentation

### `docs/`
Static HTML documentation generated from templates and scripts.

- Source files in `_pages/` are processed by `build.sh`
- `generate-tf-docs.sh` auto-generates Terraform module documentation
- Published to GitHub Pages via `pages.yml` workflow
- Includes architecture decisions, operational playbooks, cost analysis, PII documentation, and FAQs

### `azure-proxy/`
Docker configurations for the secure proxy tunnel used in local development deployments. Contains Chisel (TCP tunnel) and Privoxy (HTTP proxy) containers.

### `ssl_certs/`
SSL certificate management scripts and environment-specific certificate files. Includes CSR generation, PFX creation, and upload utilities for App Gateway and Key Vault.
