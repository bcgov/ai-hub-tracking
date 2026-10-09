# GitHub PR Automation (on approval)

When an admin approves a tenant request in the portal, the backend opens a pull request in the infrastructure repository with the tenant's generated `tenant.tfvars` files. Submitting or updating a request does **not** touch GitHub — only the Approve button does.

Implementation: `src/services/github-ops.service.ts`, wired into `POST /api/admin/approve/:tenantName/:version` in `src/app.controller.ts`.

## Flow

1. Admin clicks **Approve** on `/admin/review/<tenant>/<version>`.
2. The backend loads that version's stored `GeneratedTfvars` (exactly what the admin reviewed).
3. Using the GitHub REST API (native `fetch`, no `git`/`gh` CLI needed) it:
   - creates or force-updates branch `tenant/<tenant>-<version>` from the base branch,
   - commits `infra-ai-hub/params/{dev,test,prod}/tenants/<tenant>/tenant.tfvars` in a single commit,
   - opens a PR against the base branch (or reuses an already-open PR for that branch),
   - applies the `tenant-onboarding` and `automated` labels (best-effort).
4. The PR URL, number, and branch are stored on the request (`PrUrl`, `PrNumber`, `BranchName`).
5. Only then is the request marked `approved`.

The PR is reviewed, planned, and merged through the normal GitHub workflow — the portal never merges or closes PRs. Rejecting a request does not touch GitHub, because no PR exists before approval.

## Failure and retry behaviour

- **GitHub not configured** (`PORTAL_GITHUB_TOKEN` or `PORTAL_GITHUB_REPO` empty): approval works as before and no PR is opened. A warning is logged.
- **GitHub call fails**: the approve endpoint returns `503`, the request stays `submitted`, and the admin can click Approve again.
- **Retries are idempotent**: the branch is force-updated, an open PR for the branch is reused, and a version that already has a recorded PR is not sent to GitHub again.

## Configuration

| Setting | Terraform variable | Purpose |
| --- | --- | --- |
| `PORTAL_GITHUB_TOKEN` | `github_token` (sensitive) | Token with **Contents** and **Pull requests** read/write on the repo |
| `PORTAL_GITHUB_REPO` | `github_repo` | Target repo, e.g. `bcgov/ai-hub-tracking` |
| `PORTAL_GITHUB_BASE_BRANCH` | `github_base_branch` | PR base branch (default `main`) |
| `PORTAL_GITHUB_API_URL` | via `extra_app_settings` | Override for GitHub Enterprise Server (default `https://api.github.com`) |

The deploy workflows (`portal-deploy*.yml`) do not pass these yet; add `TF_VAR_github_token` / `TF_VAR_github_repo` from GitHub Environment secrets/variables to enable the feature in a deployed portal.

## Token options

- **Fine-grained PAT** — quickest to set up, but tied to a person; prefer for dev only.
- **GitHub App** (recommended for production) — create an app in the BCGov org with `Contents: write`, `Pull requests: write`, and `Metadata: read`, install it on the repo, and supply an installation token as `PORTAL_GITHUB_TOKEN`. Installation tokens expire after one hour, so production use needs the backend to mint them from the app's private key (not yet implemented).
