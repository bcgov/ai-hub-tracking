---
name: dependency-upgrades
description: Guidance for upgrading tracked Python and npm dependencies in ai-hub-tracking. Use when updating pyproject.toml or package.json, regenerating uv.lock or package-lock.json through package managers, responding to Dependabot or Renovate dependency alerts, or adjusting dependency automation in renovate.json.
---

# Dependency Upgrades

Use this skill profile when changing dependency versions or dependency automation in this repo.

## Use When
- Updating Python dependencies in `jobs/apim-key-rotation/pyproject.toml` or `pii-redaction-service/pyproject.toml`
- Updating npm dependencies in `tenant-onboarding-portal/backend/package.json` or `tenant-onboarding-portal/frontend/package.json`
- Regenerating `uv.lock` or `package-lock.json` for one of the tracked application projects
- Responding to Dependabot alerts or other dependency/security upgrade tasks that map to tracked manifests or lockfiles
- Updating dependency automation in `renovate.json`

## Do Not Use When
- Upgrading Terraform modules, providers, or deployment workflow actions as part of broader infrastructure work (use [IaC Coder](../iac-coder/SKILL.md))
- Modifying application behavior beyond what is required to absorb a dependency change; use the relevant domain skill alongside this one
- Researching external upgrade guidance without first validating repository-local constraints (use [External Docs Research](../external-docs/SKILL.md))

## Input Contract
Required context before making dependency changes:
- Target package(s) and affected project(s)
- Package manager in use (`uv` or `npm`)
- Files in scope (`pyproject.toml` and `uv.lock`, or `package.json` and `package-lock.json`)
- Reason for the upgrade (`security advisory`, `bug fix`, `compatibility`, or `tooling`)
- Validation gates required for each touched directory

## Output Contract
Every change should deliver:
- Minimal version changes scoped to the affected project(s)
- Consistent manifest and lockfile updates when lockfiles are in scope
- Lockfile changes produced only by the owning package manager, never by manual file edits
- Validation evidence for each touched quality-gated directory, or explicit notes on any gate that could not be run
- Any required automation updates when the change affects `renovate.json` or CI install steps

## External Documentation
- Use [External Docs Research](../external-docs/SKILL.md) as the single source of truth for external package manager, advisory, and version guidance when repository files are not sufficient.

## Scope
- Python dependency projects:
  - `jobs/apim-key-rotation/pyproject.toml`
  - `jobs/apim-key-rotation/uv.lock`
  - `pii-redaction-service/pyproject.toml`
  - `pii-redaction-service/uv.lock`
- npm dependency projects:
  - `tenant-onboarding-portal/backend/package.json`
  - `tenant-onboarding-portal/backend/package-lock.json`
  - `tenant-onboarding-portal/frontend/package.json`
  - `tenant-onboarding-portal/frontend/package-lock.json`
- Dependency automation:
  - `renovate.json`
  - `.github/workflows/.lint.yml`

## Repository Dependency Surfaces
- `jobs/apim-key-rotation/` and `pii-redaction-service/` are `uv`-managed Python projects because each tracked project contains both `pyproject.toml` and `uv.lock`.
- `tenant-onboarding-portal/backend/` and `tenant-onboarding-portal/frontend/` are npm-managed projects because each tracked project contains both `package.json` and `package-lock.json`.
- `renovate.json` currently enables only `terraform`, `regex`, and `github-actions` managers.
- `.github/workflows/.lint.yml` currently installs portal dependencies with `npm ci --prefix tenant-onboarding-portal/frontend` and `npm ci --prefix tenant-onboarding-portal/backend`.

## Lockfile Rule
- Never hand-edit `uv.lock` or `package-lock.json`.
- Update the owning manifest first, then regenerate the lockfile with `uv` or `npm` when lockfile changes are in scope.
- If a task forbids lockfile updates, leave the lockfile unchanged and report the limitation explicitly.

## Change Checklist
1. Confirm the tracked manifest and lockfile pair for the affected project before editing.
2. Keep the version change scoped to the package(s) required by the task; do not opportunistically bump unrelated dependencies.
3. Never hand-edit a generated lockfile. Regenerate it with `uv` or `npm`, or leave it unchanged if the task forbids lockfile updates.
4. If `renovate.json` changes, keep manager names and `fileMatch` patterns aligned with tracked repository paths.
5. If portal dependency install behavior changes, review `.github/workflows/.lint.yml` because CI currently installs backend and frontend dependencies with `npm ci`.
6. Run the required validation gate for every touched quality-gated directory immediately after editing.
7. State explicitly when lockfiles are intentionally left unchanged, because the repository tracks lockfiles for all application projects covered by this skill.

## Validation Gates (Required)
1. `pii-redaction-service/`: `uv run ruff check . && uv run ruff format --check .`
2. `jobs/apim-key-rotation/`: `uv run ruff check . && uv run ruff format --check .`
3. `tenant-onboarding-portal/backend/`: `npm run lint`
4. `tenant-onboarding-portal/frontend/`: `npm run lint`
5. `renovate.json` or workflow-only changes: verify manager names, file paths, and install targets against tracked files in the repository.
6. If a gate cannot be run locally, state exactly what was not run and why.