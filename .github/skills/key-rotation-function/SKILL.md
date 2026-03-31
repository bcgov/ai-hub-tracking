---
name: key-rotation-function
description: Guidance for the APIM key rotation Container App Job — Python code, Docker container, GHA workflow, and Terraform module. Use when modifying rotation logic, container build, deployment config, or adding new rotation features.
---

# Key Rotation Skills

Use this skill profile when creating or modifying the APIM key rotation Container App Job — the Python application code, container image, GitHub Actions build workflow, or Terraform infrastructure module.

## Use When
- Modifying rotation logic (interval checks, slot alternation, error handling)
- Changing the Pydantic settings/models (`rotation/config.py`, `rotation/models.py`)
- Updating the Dockerfile or `pyproject.toml` dependencies
- Debugging key rotation failures (APIM SDK, Key Vault, Container App Job)
- Changing the GHA container build workflow (`.builds.yml`)
- Modifying the Terraform module (`modules/key-rotation-function/`)

## Do Not Use When
- Modifying APIM policies/routing (use [API Management](../api-management/SKILL.md))
- Changing network subnet allocation (use [Network](../network/SKILL.md))
- Working on App Gateway or WAF rules (use [App Gateway & WAF](../app-gateway/SKILL.md))

## Input Contract
Required context before changes:
- Current rotation flow (7-step pipeline in `runner.py`)
- Pydantic settings schema (`rotation/config.py`) — all env vars
- Which Azure SDKs are used (`apim.py`, `keyvault.py`)
- Container build pattern (multi-stage uv + Python slim base)

## Output Contract
Every change should deliver:
- Python code changes with type hints (Python 3.13+, `from __future__ import annotations`)
- Updated unit tests in `tests/` if logic changed
- Dependency upgrades should follow [Dependency Upgrades](../dependency-upgrades/SKILL.md); keep this skill's job-specific validation gates
- Ruff-clean code (`ruff check --fix . && ruff format .`)
- Docker build verification if `Dockerfile` or dependencies changed
- Terraform changes if infrastructure configuration affected

## External Documentation
- Use [External Docs Research](../external-docs/SKILL.md) as the single source of truth for external documentation workflow and fallback approval requirements.

## Code Locations

| Component | Location | Purpose |
|---|---|---|
| Entry point | `jobs/apim-key-rotation/main.py` | Standalone CLI, calls `run_rotation()` |
| Settings | `jobs/apim-key-rotation/rotation/config.py` | Pydantic Settings — all env vars |
| Models | `jobs/apim-key-rotation/rotation/models.py` | `RotationMetadata`, `RotationSummary`, `Slot` enum |
| APIM SDK ops | `jobs/apim-key-rotation/rotation/apim.py` | Discover tenants, regenerate keys, verify APIM |
| Key Vault ops | `jobs/apim-key-rotation/rotation/keyvault.py` | Read/write metadata + keys in hub KV |
| Orchestrator | `jobs/apim-key-rotation/rotation/runner.py` | 7-step per-tenant rotation + `run_rotation()` entry |
| Dockerfile | `jobs/apim-key-rotation/Dockerfile` | Multi-stage: uv builder → Python slim runtime |
| Dependencies | `jobs/apim-key-rotation/pyproject.toml` | uv-managed deps (azure-*, pydantic, pydantic-settings) |
| Unit tests | `jobs/apim-key-rotation/tests/` | pytest suite for models + runner logic |
| GHA workflow | `.github/workflows/.builds.yml` | Reusable workflow → GHCR image via `bcgov/action-builder-ghcr` (matrix entry) |
| Terraform module | `infra-ai-hub/modules/key-rotation-function/` | Container App Job, RBAC assignments |
| Stack wiring | `infra-ai-hub/stacks/key-rotation/main.tf` | Calls module with feature flag gate |

## Rotation Flow

```
Cron trigger fires → Container App Job starts → main.py
  └── run_rotation(settings)
       ├── Guard: rotation_enabled?
       ├── Guard: APIM instance exists?
       ├── Guard: Hub Key Vault reachable?
       ├── Discover tenant subscriptions (APIM SDK)
       ├── Filter to included tenants (INCLUDED_TENANTS whitelist)
       └── For each included tenant:
            1. Read rotation metadata from KV
            2. Check interval (skip if not due)
            3. Determine target slot (alternating primary/secondary)
            4. Regenerate target slot key (APIM SDK)
            5. Wait for propagation (10s)
            6. Read both keys → store in hub KV
            7. Update rotation metadata in KV
```

## Key Design Rules
- **Zero-secret operation**: Uses `DefaultAzureCredential` (Managed Identity in Azure, `az login` locally)
- **Alternating slots**: Secondary first, then primary, so one key is always valid (zero downtime)
- **Idempotent**: Cron fires daily but only rotates when `rotation_interval_days` has elapsed
- **Per-tenant opt-in**: Two-level toggle — global `rotation_enabled` AND per-tenant `key_rotation_enabled` in `apim_auth` must both be `true`. Tenants not opted in are excluded from rotation and from the APIM `/apim-keys` internal endpoint.
- **Safe empty whitelist**: Empty `INCLUDED_TENANTS` means **no tenants** (not all). The Container App Job is only deployed when at least one tenant is opted in.
- **Dry-run mode**: Set `DRY_RUN=true` to see what would happen without making changes
- **Naming convention**: Derived defaults (`{app_name}-{environment}-apim`, etc.) unless overridden
- **Pay-per-execution**: Container App Job with Consumption workload profile — no idle cost

## Environment Variables (Settings)

| Variable | Required | Default | Description |
|---|---|---|---|
| `ENVIRONMENT` | Yes | — | Target env (dev, test, prod) |
| `APP_NAME` | Yes | — | App name prefix |
| `SUBSCRIPTION_ID` | Yes | — | Azure subscription ID |
| `RESOURCE_GROUP` | No | `{app_name}-{environment}` | RG override |
| `APIM_NAME` | No | `{app_name}-{environment}-apim` | APIM instance override |
| `HUB_KEYVAULT_NAME` | No | `{app_name}-{environment}-hkv` | Hub KV override |
| `ROTATION_ENABLED` | No | `true` | Master toggle |
| `ROTATION_INTERVAL_DAYS` | No | `7` | Days between rotations (1–89) |
| `DRY_RUN` | No | `false` | Preview without changes |
| `INCLUDED_TENANTS` | No | `""` | Comma-separated tenant names (empty = none — safe default) |
| `SECRET_EXPIRY_DAYS` | No | `90` | KV secret expiry (max 90 for LZ policy) |

## Change Checklist
1. **Python code** — type hints, `from __future__ import annotations`, Pydantic v2 patterns
2. **Dependency upgrades** — follow [Dependency Upgrades](../dependency-upgrades/SKILL.md); never hand-edit `uv.lock`.
3. **Ruff** — `ruff check --fix . && ruff format .` (config in `pyproject.toml`)
4. **Tests** — `pytest` from `jobs/apim-key-rotation/`
5. **Docker** — `docker build -t apim-key-rotation:test .` if Dockerfile/deps changed
6. **Terraform** — `terraform fmt -recursive` and `terraform validate` if module changed

## Validation Gates (Required)
1. **Ruff clean**: No lint errors (`ruff check .`)
2. **Tests pass**: `pytest` succeeds
3. **Docker builds**: Image builds without errors
4. **Settings schema**: All new env vars added to `config.py` Settings class + `.env.example`
5. **Feature flag**: Job gated behind `rotation_enabled && apim_enabled && cae_enabled && tenants_opted_in` in `stacks/key-rotation/main.tf`

## Detailed References

For APIM SDK patterns, Key Vault secret naming conventions, Terraform module architecture, RBAC role assignments, and container build pipeline details, see [references/REFERENCE.md](references/REFERENCE.md).
