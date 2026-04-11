# AI-Hub
This is the central repo to track overall project with issues and github project linked for AI Services Hub.

## Documentation
📚 **[View Full Documentation](https://bcgov.github.io/ai-hub-tracking/)**

Comprehensive guides for OIDC setup, Terraform deployments, and Azure Landing Zone architecture.

**Quick Links**:
- [Local Development Deployment Guide](infra-ai-hub/README.md#local-development-deployment) - Deploy from your local machine using Chisel tunnel
- [Operational Playbooks](https://bcgov.github.io/ai-hub-tracking/playbooks.html) - Troubleshooting and runbooks
- [Terraform Modules](https://bcgov.github.io/ai-hub-tracking/terraform.html) - Terraform modules overview
- [PII Anonymization](https://bcgov.github.io/ai-hub-tracking/language-service-pii.html) - PII redaction via Azure AI Language PII detection
- [Document Intelligence](https://bcgov.github.io/ai-hub-tracking/document-intelligence.html) - OCR and document analysis

Platform note: this repo uses Azure AI Language only for PII detection. Text summarization, classification, sentiment, and other non-PII language workloads should be built on Azure AI Foundry model deployments instead.

## Tools & Installation

**Supported Platforms:** Linux and macOS

The `initial-setup/initial-azure-setup.sh` script automatically installs missing tools:

- **Azure CLI** - Authentication and Azure resource management
- **Terraform** >= 1.12.0 - Infrastructure as code
- **TFLint** - Terraform linting for Azure and Terraform best-practice checks
- **pre-commit** - Git hook framework to enforce Terraform checks before commit
- **GitHub CLI** (optional) - Automatic GitHub secret creation

The script detects your OS and package manager (apt, yum, brew) to install tools with interactive prompts. See [Initial Setup README](initial-setup/README.md) for detailed information.

## Terraform Linting and Pre-Commit

This repository enforces Terraform formatting and linting using pre-commit hooks.

1. Install `pre-commit` (for example: `pip install pre-commit`)
2. Install git hooks in this repository:

  ```bash
  pre-commit install
  ```

3. Run hooks manually at any time:

  ```bash
  pre-commit run --all-files
  ```

The configured Terraform hook runs:
- `terraform fmt -check`
- `tflint` checks for both `initial-setup/infra` and `infra-ai-hub`

## Folder Structure

This tree lists tracked repository content only. Local or gitignored artifacts such as `sensitive/`, `temp/`, `_tmp/`, `_bkp/`, `*.http`, `*.tfstate*`, and `terraform.tfvars` are intentionally omitted.

```text
ai-hub-tracking/                        # Repository root
├── .env.example                       # Example environment variables for local setup
├── .gitattributes                     # Git attributes and line-ending rules
├── .github/                           # Repo automation, guardrails, and Copilot guidance
│   ├── copilot-instructions.md         # Repo-wide Copilot operating rules
│   ├── hooks/                          # Pre/post-tool guardrails and automation
│   ├── scripts/                        # CI helper scripts
│   ├── skills/                         # Domain-specific Copilot skill profiles
│   └── workflows/                      # GitHub Actions workflows
├── .gitignore                         # Ignore rules for local and generated artifacts
├── .pre-commit-config.yaml            # Pre-commit hook configuration
├── azure-proxy/                       # Secure tunnel container definitions for local access
│   ├── chisel/                         # Chisel tunnel container and startup script
│   └── privoxy/                        # Privoxy container and entrypoint
├── docker-compose.yml                 # Local multi-container orchestration
├── docs/                              # Static documentation site source and published output
│   ├── _pages/                         # Source page templates
│   ├── _partials/                      # Shared header/footer templates
│   ├── assets/                         # Published static assets
│   ├── plans/                          # Documentation working notes
│   ├── README.md                       # Docs build and maintenance guide
│   ├── build.sh                        # Static site generator
│   ├── generate-search-index.js        # Search index generator
│   ├── generate-tf-docs.sh             # Terraform reference generator
│   └── [published HTML pages]          # Built site content committed to the repo
├── infra-ai-hub/                      # Main AI Hub Terraform workspace
│   ├── README.md                       # Infrastructure architecture and deployment guide
│   ├── model-deployments.md            # Tenant model inventory and quota notes
│   ├── modules/                        # Reusable Terraform modules
│   ├── params/                         # Environment config, tenant tfvars, and APIM templates
│   ├── scripts/                        # Deployment and recovery helpers
│   └── stacks/                         # Stack-based Terraform roots
├── initial-setup/                     # Bootstrap tooling and foundational infra setup
│   ├── initial-azure-setup.sh          # Bootstrap script for OIDC and foundational infra
│   ├── README.md                       # First-time setup guide
│   └── infra/                          # Foundational Terraform configuration
│       ├── backend.tf                  # Remote Terraform backend configuration
│       ├── deploy-terraform.sh         # Foundational infra deployment wrapper
│       ├── main.tf                     # Root bootstrap resources and module wiring
│       ├── modules/                    # Reusable bootstrap Terraform modules
│       ├── outputs.tf                  # Foundational infra outputs
│       ├── providers.tf                # Provider configuration
│       ├── scripts/                    # Bootstrap helper scripts
│       ├── variables.tf                # Input variable definitions
│       └── versions.tf                 # Terraform and provider version constraints
├── jobs/                              # Container App jobs source code
│   └── apim-key-rotation/             # APIM subscription key rotation job
│       ├── README.md                   # Developer guide for the rotation job
│       ├── Dockerfile                  # Container image build definition
│       ├── main.py                     # CLI entrypoint
│       ├── pyproject.toml              # Project metadata and dependencies
│       ├── rotation/                   # Rotation runtime package
│       ├── tests/                      # Unit tests
│       └── uv.lock                     # Resolved dependency lockfile
├── LICENSE                             # Repository license
├── pii-redaction-service/             # FastAPI service for PII redaction via Azure AI Language
│   ├── README.md                       # Service guide and operator notes
│   ├── Dockerfile                      # Container image build definition
│   ├── app/                            # FastAPI application package
│   ├── pyproject.toml                  # Project metadata and dependencies
│   └── tests/                          # Unit and service tests
├── README.md                           # Repository overview and operator guide
├── renovate.json                       # Dependency automation configuration
├── ssl_certs/                         # Certificate scripts and environment-specific material
│   ├── README.md                       # Certificate operations guide
│   ├── create-pfx.sh                   # Build PFX bundles from cert and key files
│   ├── csr-gen.sh                      # Generate CSRs and private keys
│   ├── upload-cert-direct.sh           # Upload certificates directly to App Gateway
│   ├── upload-cert-keyvault.sh         # Upload certificates through Key Vault
│   ├── prod/                           # Production certificate directory
│   └── test/                           # Test certificate directory
├── tenant-onboarding-portal/          # Tenant onboarding application workspace
│   ├── README.md                       # Portal architecture and local run guide
│   ├── backend/                        # NestJS API, tests, and deployment tooling
│   ├── frontend/                       # React/Vite single-page application
│   └── infra/                          # Portal Terraform configuration
└── tests/                             # Shared automated test workspace
    └── integration/                   # Python integration and evaluation project
        ├── README.md                   # Integration test documentation
        ├── eval_datasets/              # Evaluation datasets
        ├── pyproject.toml              # Project metadata and dependencies
        ├── run-evaluation.py           # Azure AI Evaluation CLI entrypoint
        ├── run-tests.py                # Pytest runner with suite aliases and grouping
        ├── run-tests.sh                # Shell wrapper around the Python runner
        ├── src/                        # Shared integration runtime modules
        ├── tests/                      # Live and unit pytest suites
        └── uv.lock                     # Resolved dependency lockfile
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
  - **gpu-vllm-aca**: Bootstrap module that deploys a private vLLM-based Gemma 4 endpoint on Azure Container Apps with a GPU consumption profile, mirrored ACR image, persistent Azure Files-backed Hugging Face cache, optional cache-only offline startup, and private endpoint (optional via `enable_gpu_vllm_aca`)
  - **github-runners-aca**: Self-hosted GitHub runners on Container Apps (optional via `github_runners_aca_enabled`)
  - **azure-proxy**: Secure tunnel (chisel) deployment used for proxying (optional via `enable_azure_proxy`)
  - **monitoring**: Log Analytics and Application Insights for observability

### `infra-ai-hub/`
Multi-tenant AI Services Hub infrastructure. Manages the stack-based Terraform deployment for APIM, AI Foundry, per-tenant resources, networking, WAF, and published model availability.

- **modules/**: Reusable Terraform modules for shared infra, tenant resources, PII redaction, vLLM service, and key rotation
- **params/**: Environment configs with per-tenant `tenant.tfvars` files plus shared APIM templates and fragments
- **scripts/**: Deployment helpers, import extraction, DNS wait logic, and Foundry cleanup tooling
- **stacks/**: Isolated Terraform roots for `shared`, `tenant`, `foundry`, `apim`, `tenant-user-mgmt`, `pii-redaction`, `vllm`, and `key-rotation`
- **model-deployments.md**: Current tenant model inventory, quota allocation notes, and vLLM pathway documentation

### `pii-redaction-service/`
Python FastAPI service used by APIM for fail-closed PII redaction via Azure AI Language. Contains the app runtime, tests, container packaging, and service-specific documentation.

### `tests/`
Python/pytest-based integration test suite for validating deployed infrastructure. Tests cover chat completions, document intelligence, PII redaction (fail-closed/fail-open), tenant isolation, binary uploads, and user management.

### `jobs/`
Container App Jobs source code. Contains the APIM key rotation job (`apim-key-rotation/`), a Python-based cron job that automatically rotates APIM subscription keys using an alternating primary/secondary pattern. Deployed as a custom container from GHCR via `.builds.yml`, with the Terraform module at `infra-ai-hub/modules/key-rotation-function/` and stack at `infra-ai-hub/stacks/key-rotation/`.

### `tenant-onboarding-portal/`
Tenant onboarding application workspace. The root now stays intentionally thin: `backend/` contains the NestJS API, Playwright and unit tests, Terraform, and deployment helpers; `frontend/` contains the React/Vite SPA; `README.md` explains local development and deployment behavior.

### `.github/`
GitHub Actions automation, Copilot guidance, and repository guardrails.

- **copilot-instructions.md**: Repo-wide operating rules for Copilot, including documentation sync requirements
- **hooks/**: Guard scripts for destructive-command checks and post-tool validation
- **scripts/**: CI helper scripts used by workflows
- **skills/**: Specialized Copilot skill profiles for infrastructure, docs, APIM, testing, and application work
- **workflows/**: CI/CD pipelines for Terraform, docs publishing, the portal app, container builds, and integration tests

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

## Developer Workflow (SDLC)

All infrastructure changes follow a promote-through-environments flow enforced by GitHub Actions:

1. **Branch** from `main` (e.g. `feat/add-tenant`, `fix/dns-ttl`)
2. **Open a PR** → automated lint, builds, and Terraform plan against `test`
3. **Merge to main** → semantic version tag + auto-apply to `test`
4. **Promote to prod** → manual dispatch with the semver tag, gated by environment approval

For the complete SDLC documentation — including stacked PRs, release PRs, concurrency strategy, and the full release process — see the **[Workflows Documentation](https://bcgov.github.io/ai-hub-tracking/workflows.html)**.
