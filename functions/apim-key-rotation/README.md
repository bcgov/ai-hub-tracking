# APIM Key Rotation Function — Developer Guide

Local development guide for the APIM key rotation Azure Function.

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Python | >= 3.13 | [python.org](https://www.python.org/downloads/) |
| uv | >= 0.6 | `curl -LsSf https://astral.sh/uv/install.sh \| sh` or `pip install uv` |
| Azure Functions Core Tools | v4 | `npm i -g azure-functions-core-tools@4 --unsafe-perm true` |
| Azure CLI | latest | [Install Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) |
| Docker | latest | [Docker Desktop](https://www.docker.com/products/docker-desktop/) (for container builds) |

## Quick Start

```bash
cd functions/apim-key-rotation

# 1. Install dependencies
uv sync

# 2. Configure local settings
cp local.settings.json.example local.settings.json
# Edit local.settings.json with your Azure subscription details

# 3. Login to Azure (needed for DefaultAzureCredential)
az login

# 4. Run the function locally
func start
```

## Project Structure

```
functions/apim-key-rotation/
├── function_app.py              # Timer trigger entry point
├── host.json                    # Azure Functions host config
├── pyproject.toml               # uv/pip dependencies + ruff config
├── local.settings.json.example  # Template for local env vars
├── Dockerfile                   # Multi-stage build (uv → Azure Functions)
├── docker-compose.yml           # Local dev stack (function + Azurite)
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

## Local Settings

Copy the example and fill in your values:

```bash
cp local.settings.json.example local.settings.json
```

```json
{
    "IsEncrypted": false,
    "Values": {
        "FUNCTIONS_WORKER_RUNTIME": "python",
        "AzureWebJobsStorage": "UseDevelopmentStorage=true",
        "ENVIRONMENT": "dev",
        "APP_NAME": "ai-services-hub",
        "SUBSCRIPTION_ID": "<your-azure-subscription-id>",
        "ROTATION_ENABLED": "true",
        "ROTATION_INTERVAL_DAYS": "60",
        "ROTATION_CRON_SCHEDULE": "0 0 9 * * *",
        "DRY_RUN": "true"
    }
}
```

> **Tip:** Always set `DRY_RUN=true` for local development. This logs what would happen without regenerating keys or writing to Key Vault.

### Required Azure RBAC (for your user identity)

When running locally, `DefaultAzureCredential` uses your `az login` identity. You need these roles on the target resources:

| Role | Scope | Purpose |
|---|---|---|
| API Management Service Contributor | APIM instance | List/regenerate subscription keys |
| Key Vault Secrets Officer | Hub Key Vault | Read/write secrets |
| Reader | Resource Group | Resource discovery |

## Running Locally

### Option 1: Azure Functions Core Tools (recommended)

```bash
# From the function app directory
cd functions/apim-key-rotation

# Install dependencies
uv sync

# Start the function host
func start
```

The timer trigger won't fire immediately by default. To trigger manually, send an HTTP POST to the admin endpoint:

```bash
curl -X POST http://localhost:7071/admin/functions/rotate_keys \
  -H "Content-Type: application/json" \
  -d '{}'
```

### Option 2: Docker Compose (recommended for container testing)

A `docker-compose.yml` is included that runs the function app **and** Azurite (storage emulator) together — no extra containers to manage manually.

```bash
cd functions/apim-key-rotation

# Build and start both services
docker compose up --build

# Or run in the background
docker compose up --build -d

# Check logs to verify the function registered
docker compose logs function-app

# Stop and remove everything
docker compose down
```

The timer trigger fires **immediately on startup** (`RUN_ON_STARTUP=true` in the compose file) so you don't have to wait for the next cron tick. It will also continue to fire on the `ROTATION_CRON_SCHEDULE`.

To override the placeholder subscription ID, set the environment variable before starting:

```bash
export SUBSCRIPTION_ID=<your-azure-subscription-id>
docker compose up --build
```

> **Note:** The container doesn't have access to your `az login` session. `DefaultAzureCredential` will fail for calls to Azure — use `DRY_RUN=true` (the default) for local container testing, or Option 1 for full integration work.

### Option 3: Direct Python (tests only)

```bash
cd functions/apim-key-rotation

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
cd functions/apim-key-rotation

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
cd functions/apim-key-rotation

# Check for lint errors
ruff check .

# Auto-fix lint errors
ruff check --fix .

# Format code
ruff format .
```

## Building the Container Image

```bash
cd functions/apim-key-rotation

# Build
docker build -t apim-key-rotation:test .

# Verify it starts (this build has no Azurite — see "Option 2: Docker Compose"
# for a fully working local stack)
docker run --rm apim-key-rotation:test

# Or simply use docker compose which handles everything:
docker compose up --build
```

The Dockerfile uses a multi-stage build:
1. **Builder stage** (`uv:0.6-python3.13-bookworm-slim`): Resolves and installs dependencies
2. **Runtime stage** (`azure-functions/python:4-python3.13`): Copies the venv and app code

In CI, the image is built and pushed to GHCR by `.github/workflows/.builds.yml` (matrix entry) using `bcgov/action-builder-ghcr`.

## Debugging Tips

### Timer not firing locally
The timer trigger uses NCRONTAB format (6 parts: `sec min hour day month weekday`). To test immediately, use the admin endpoint (see Option 1 above).

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
Always develop with `DRY_RUN=true`. The function will:
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
