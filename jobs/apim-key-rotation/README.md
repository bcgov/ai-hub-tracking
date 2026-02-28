# APIM Key Rotation — Developer Guide

Local development guide for the APIM key rotation Container App Job.

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Python | >= 3.13 | [python.org](https://www.python.org/downloads/) |
| uv | >= 0.6 | `curl -LsSf https://astral.sh/uv/install.sh \| sh` or `pip install uv` |
| Azure CLI | latest | [Install Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) |
| Docker | latest | [Docker Desktop](https://www.docker.com/products/docker-desktop/) (for container builds) |

## Quick Start

```bash
cd jobs/apim-key-rotation

# 1. Install dependencies
uv sync

# 2. Configure environment variables
cp .env.example .env
# Edit .env with your values (set DRY_RUN=true for safety)

# 3. Login to Azure (needed for DefaultAzureCredential)
az login

# 4. Run the rotation
python main.py
```

## Project Structure

```
jobs/apim-key-rotation/
├── main.py                      # Standalone CLI entry point
├── pyproject.toml               # uv/pip dependencies + ruff config
├── Dockerfile                   # Multi-stage build (uv → python:3.13-slim)
├── .env.example                 # Environment variable template for local dev
├── .dockerignore
├── rotation/                    # Application package
│   ├── __init__.py
│   ├── config.py                # Pydantic Settings (env var mapping)
│   ├── models.py                # Data models (RotationMetadata, etc.)
│   ├── apim.py                  # APIM SDK operations
│   ├── keyvault.py              # Key Vault SDK operations
│   └── runner.py                # Orchestration logic (7-step rotation)
└── tests/                       # Unit tests
    ├── __init__.py
    ├── test_models.py
    └── test_runner.py
```

## Environment Variables

Set these before running `main.py`:

| Variable | Required | Default | Description |
|---|---|---|---|
| `ENVIRONMENT` | Yes | — | Environment name (`dev`, `test`, `prod`) |
| `APP_NAME` | Yes | — | Application name (e.g. `ai-services-hub`) |
| `SUBSCRIPTION_ID` | Yes | — | Azure subscription ID |
| `ROTATION_ENABLED` | No | `true` | Enable/disable rotation |
| `ROTATION_INTERVAL_DAYS` | No | `7` | Days between rotations per tenant |
| `DRY_RUN` | No | `false` | Log actions without making changes |
| `SECRET_EXPIRY_DAYS` | No | `90` | Key Vault secret expiry (≤ 90 for policy) |

### Required Azure RBAC (for your user identity)

When running locally, `DefaultAzureCredential` uses your `az login` identity. You need these roles on the target resources:

| Role | Scope | Purpose |
|---|---|---|
| API Management Service Contributor | APIM instance | List/regenerate subscription keys |
| Key Vault Secrets Officer | Hub Key Vault | Read/write secrets |
| Reader | Resource Group | Resource discovery |

## Running Locally

### Option 1: Direct Python (recommended)

```bash
cd jobs/apim-key-rotation

# Install dependencies
uv sync

# Set environment variables
export ENVIRONMENT=dev
export APP_NAME=ai-services-hub
export SUBSCRIPTION_ID=<your-sub-id>
export DRY_RUN=true

# Run the rotation
python main.py
```

> **Tip:** Always set `DRY_RUN=true` for local development. This logs what would happen without regenerating keys or writing to Key Vault.

### Option 2: Docker (recommended for container testing)

```bash
cd jobs/apim-key-rotation

# Build the image
docker build -t apim-key-rotation:test .

# Run with dry-run (container has no az login session)
docker run --rm \
  -e ENVIRONMENT=dev \
  -e APP_NAME=ai-services-hub \
  -e SUBSCRIPTION_ID=<your-sub-id> \
  -e DRY_RUN=true \
  apim-key-rotation:test
```

> **Note:** The container doesn't have access to your `az login` session. `DefaultAzureCredential` will fail for calls to Azure — use `DRY_RUN=true` for local container testing, or Option 1 for full integration work.

### Option 3: Python inline (debugging)

```bash
cd jobs/apim-key-rotation

# Install with dev dependencies
uv sync --dev

# Run the rotation directly (useful for debugging)
python -c "
from rotation.config import Settings
from rotation.runner import run_rotation
import os
os.environ.update({
    'ENVIRONMENT': 'dev',
    'APP_NAME': 'ai-services-hub',
    'SUBSCRIPTION_ID': '<your-sub-id>',
    'DRY_RUN': 'true',
})
settings = Settings()
summary = run_rotation(settings)
print(summary.model_dump_json(indent=2))
"
```

## Running Tests

```bash
cd jobs/apim-key-rotation

# Install dev dependencies
uv sync --dev

# Run all tests
pytest

# Run with verbose output
pytest -v

# Run a specific test file
pytest tests/test_runner.py

# Run a specific test class
pytest tests/test_runner.py::TestSlotSelection
```

## Linting & Formatting

Ruff is configured in `pyproject.toml` (line-length: 120, Python 3.13 target):

```bash
cd jobs/apim-key-rotation

# Check for lint errors
ruff check .

# Auto-fix lint errors
ruff check --fix .

# Format code
ruff format .
```

## Building the Container Image

```bash
cd jobs/apim-key-rotation

# Build
docker build -t apim-key-rotation:test .

# Verify it runs (dry-run mode)
docker run --rm \
  -e ENVIRONMENT=dev \
  -e APP_NAME=ai-services-hub \
  -e SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000 \
  -e DRY_RUN=true \
  apim-key-rotation:test
```

The Dockerfile uses a multi-stage build:
1. **Builder stage** (`uv:0.6-python3.13-bookworm-slim`): Resolves and installs dependencies
2. **Runtime stage** (`python:3.13-slim-bookworm`): Copies the venv and app code, runs `python main.py`

In CI, the image is built and pushed to GHCR by `.github/workflows/.builds.yml` (matrix entry) using `bcgov/action-builder-ghcr`.

## Debugging Tips

### Azure authentication errors
```bash
# Verify your login
az account show

# Re-login if needed
az login

# Verify you have the right subscription
az account set --subscription <your-sub-id>
```

### Dry-run mode
Always develop with `DRY_RUN=true`. The script will:
- Discover tenants (reads APIM)
- Read rotation metadata (reads Key Vault)
- Log which slots would be rotated
- **Skip** actual key regeneration and Key Vault writes

### Viewing rotation metadata
```bash
# Read a tenant's rotation metadata from Key Vault
az keyvault secret show \
  --vault-name <hub-kv-name> \
  --name <tenant-name>-apim-rotation-metadata \
  --query value -o tsv | python -m json.tool
```
