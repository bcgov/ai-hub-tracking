# Copilot Preferences for ai-hub-tracking

## Task Completion

After completing tasks:
- ✅ DO: Provide brief confirmation in chat (1-2 sentences)
- ❌ DON'T: Create summary markdown files

---

## Quality Gate Enforcement (Non-Negotiable)

After **every** file edit or creation in a quality-gated directory, run the corresponding check **immediately** — do not wait until the end of the task:

| Directory | Command (run from that directory) |
|---|---|
| `pii-redaction-service/` | `uv run ruff check . && uv run ruff format --check .` |
| `jobs/apim-key-rotation/` | `uv run ruff check . && uv run ruff format --check .` |
| `tenant-onboarding-portal/backend/` | `npm run lint` |
| `tenant-onboarding-portal/frontend/` | `npm run lint` |
| `infra-ai-hub/` (any `.tf`) | `terraform fmt -check -recursive && tflint --recursive` |

**When adding a new quality gate** (pre-commit hook, postToolUse script, CI step): run the corresponding check against ALL existing files in scope first, fix any errors, then commit the gate. Never introduce a gate against code you haven't already validated.

**Before yielding back to the user** after any task that touched a quality-gated directory: run the check for that directory and show the output in the response. Do not assume the postToolUse hook ran — always run it explicitly.

---

## Lockfile Handling (Non-Negotiable)

- Hand-editing generated lockfiles is strictly prohibited. This includes `uv.lock`, `package-lock.json`, and any future generated dependency lockfile added to the repo.
- Change dependency versions in the owning manifest first (`pyproject.toml`, `package.json`, or equivalent), then regenerate the lockfile with the owning package manager.
- If the task or user instruction does not allow lockfile updates, do not edit the lockfile at all. State the limitation explicitly instead of patching the lockfile by hand.
- Never use manual patch edits to rewrite resolved package entries, hashes, or metadata inside a generated lockfile.

---

## Source Citations (Non-Negotiable)

Every recommendation, configuration value, or behavioral claim **must** be backed by a verifiable source: a file path in the repo, a Terraform resource attribute, a workflow step, an official doc link, or a direct tool output. Do not present inferred or assumed information as fact. If the source cannot be identified, say so explicitly and ask the user for clarification.

---

## No Assumptions

- Stick to facts derived from the codebase, tool outputs, or authoritative documentation.
- Do not guess at values, behaviors, or configurations — verify first using available tools.
- When context is ambiguous or incomplete, ask the user for clarification before proceeding.

---

## Documentation Sync (Non-Negotiable)

- When a change adds, removes, renames, or materially reorganizes tracked files or directories, update the root `README.md` `Folder Structure` section in the same change.
- The root tree must describe tracked repository content only. Do not list gitignored or local-only artifacts.
- If a touched subtree has its own tracked `README.md`, treat it as the default local source of truth for that subtree and update it when its documented structure, workflow, interface, or operator steps change.
- For docs-site content, update both the source page under `docs/_pages/` and the published page under `docs/` in the same change when the published docs are tracked.

Review and update the matching documents below before handoff:

| Changed area | Documentation to review/update |
|---|---|
| Repo top-level layout or shared folder layout | `README.md` |
| `.github/` hooks, skills, scripts, or workflows | `README.md`, `docs/_pages/workflows.html`, `docs/workflows.html`, `docs/README.md` |
| `docs/` site pages, partials, assets, or build scripts | `docs/README.md` and the affected `docs/_pages/*.html` + published `docs/*.html` pages |
| `infra-ai-hub/` modules, params, scripts, stacks, deployment topology, or tenant-visible service availability | `infra-ai-hub/README.md`, `infra-ai-hub/model-deployments.md`, `README.md`, `docs/_pages/services.html`, `docs/services.html`, and any affected docs under `docs/_pages/terraform*.html` + `docs/terraform*.html` |
| `initial-setup/` bootstrap flow or foundational infra layout | `initial-setup/README.md`, `README.md`, and any affected OIDC/setup docs under `docs/` |
| `tenant-onboarding-portal/` app layout, local run flow, or deployment behavior | `tenant-onboarding-portal/README.md`, `README.md`, and any affected workflow docs |
| `tests/integration/` layout, suite map, runner behavior, or datasets | `tests/integration/README.md`, `README.md` |
| `jobs/apim-key-rotation/` runtime, container, or workflow | `jobs/apim-key-rotation/README.md`, `README.md` |
| `pii-redaction-service/` runtime, API behavior, or deployment wiring | `pii-redaction-service/README.md`, `README.md`, and affected PII docs under `docs/` when user-visible behavior changes |
| `azure-proxy/` tunnel or proxy containers/scripts | `azure-proxy/chisel/README.md`, `azure-proxy/privoxy/README.md`, `README.md` |
| `ssl_certs/` certificate scripts or operational process | `ssl_certs/README.md`, `README.md` |

---

## Brief Status Format

Use this format for task completion:
✅ [Task Name] Complete

Change 1
Change 2
Verified: [confirmation]

---

## Skills-Based Work

This repo uses **skill profiles** to guide work. Use the appropriate skill profile based on the task:

**Skill Maintenance:** When a change introduces new patterns, modules, routes, test suites, or other artifacts covered by a skill profile, update the relevant SKILL.md to reflect the change. If the change introduces an entirely new domain not covered by any existing skill, create a new skill folder under `.github/skills/<name>/` with a SKILL.md following the standard template (Use When, Do Not Use When, Input/Output Contract, External Documentation, Scope, Change Checklist, Validation Gates) and add a corresponding subsection here.

### [IaC Coder](./skills/iac-coder/SKILL.md)
Use when creating or modifying infrastructure code (Terraform, Bash, GitHub Actions).
- Terraform (>= 1.12.0) with Azure providers
- Azure Verified Modules (AVM)
- GitHub Actions workflows with OIDC
- Bash scripts for Terraform operations

### [Documentation](./skills/documentation/SKILL.md)
Use when creating or updating documentation under docs/.
- Static HTML pages and templates
- Shared partials and content
- Update procedures and content standards

### [API Management](./skills/api-management/SKILL.md)
Use when creating or modifying APIM policies and routing.
- Policy files under `infra-ai-hub/params/apim/`
- Routing rules and authentication
- Rate limiting and error handling
- No subscription key normalization (handled by App Gateway)

### [App Gateway & WAF](./skills/app-gateway/SKILL.md)
Use when creating or modifying App Gateway rewrite rules or WAF custom rules.
- Rewrite rules in `infra-ai-hub/stacks/shared/main.tf`
- WAF custom rules in `infra-ai-hub/stacks/shared/locals.tf`
- Subscription key normalization (Ocp-key, Bearer → api-key for APIM)
- Request security layers and rate limiting at WAF level

### [Key Rotation Function](./skills/key-rotation-function/SKILL.md)
Use when modifying the APIM key rotation Container App Job.
- Python job code under `jobs/apim-key-rotation/`
- Pydantic settings, rotation logic, APIM/KV SDK operations
- Dockerfile (multi-stage uv + python:3.13-slim), GHCR build workflow
- Terraform module under `infra-ai-hub/modules/key-rotation-function/`

### [Integration Testing](./skills/integration-testing/SKILL.md)
Use when creating, modifying, or debugging integration tests.
- Python/pytest suites under `tests/integration/tests/`
- Shared Python client/config/evaluation modules under `tests/integration/src/ai_hub_integration/`
- Retry logic, skip guards, async polling, and secure-tunnel grouping

### [AI Evaluation](./skills/ai-evaluation/SKILL.md)
Use when creating, modifying, or debugging Azure AI Evaluation SDK coverage.
- Judge-model configuration and evaluation thresholds
- Dataset-driven response scoring under `tests/integration/eval_datasets/`
- `run-evaluation.py` and pytest `ai_eval` coverage

### [Tenant Onboarding Portal](./skills/tenant-onboarding-portal/SKILL.md)
Use when modifying the tenant onboarding portal application.
- NestJS backend under `tenant-onboarding-portal/backend/src/`
- React/Vite frontend under `tenant-onboarding-portal/frontend/src/`
- Mock auth, Keycloak integration, Azure Table Storage, and Playwright E2E tests
- Local tooling, portal deployment workflow, and portal-specific docs

### [Network](./skills/network/SKILL.md)
Use when adding or modifying subnets, CIDR allocation, NSG rules, or delegation in the network module.
- Explicit `subnet_allocation` model (`map(map(string))`) in `infra-ai-hub/modules/network/locals.tf`
- NSG resources and azapi subnet definitions in `infra-ai-hub/modules/network/main.tf`
- PE subnet pool derivation and downstream PE selection (tenant 3-tier, APIM pinned)
- Subnet delegation requirements per Azure service

### [External Docs Research](./skills/external-docs/SKILL.md)
Use when researching authoritative external docs for platform behavior and versioned guidance.
- Repository-first validation, then Learn/Context7 lookup
- Upstash Context7 for non-Learn sources and targeted version/topic queries
- Explicit fallback approval required when Context7 has no documentation

### [PII Redaction Service](./skills/pii-redaction-service/SKILL.md)
Use when modifying the PII redaction custom service.
- Python FastAPI app under `pii-redaction-service/`
- Batch orchestration, Language Service integration, Container App scaling
- Dockerfile, GHCR build workflow, and Terraform module
- Terraform stack under `infra-ai-hub/stacks/pii-redaction/`

### [Dependency Upgrades](./skills/dependency-upgrades/SKILL.md)
Use when upgrading tracked Python or npm dependencies, regenerating lockfiles, responding to Dependabot or Renovate alerts, or updating repository dependency automation.
- `uv`-managed Python projects under `jobs/apim-key-rotation/`, `pii-redaction-service/`, and `tests/integration/`
- npm manifests and lockfiles under `tenant-onboarding-portal/backend/` and `tenant-onboarding-portal/frontend/`
- Dependency automation in `renovate.json`
- Validation gates from repo policy for touched package-managed directories
- Generated lockfiles must be regenerated through `uv` or `npm`; never hand-edit them

### [IaC Code Reviewer](./skills/iac-code-reviewer/SKILL.md)
Use this for reviewing Terraform, GitHub Actions, Bash scripts, and AVM changes.
- Review goals and severity levels
- Azure Landing Zone compliance (CRITICAL)
- Terraform standards with full checklists
- GitHub Actions and Bash standards
- Complete review checklist with severity assignments
