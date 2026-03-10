# Tenant Onboarding Portal

```text
tenant-onboarding-portal/
├── infra/
├── backend/
├── frontend/
└── README.md
```

`backend/` contains the NestJS API, unit and Playwright tests, deployment helpers, and portal-specific docs. `frontend/` contains the React/Vite SPA. `infra/` contains the Terraform that provisions the Azure App Service resources for the portal.

## Architecture

- The frontend authenticates through `/api/auth/config` and `/api/session`, then calls `/api/...` routes with bearer tokens.
- The backend owns API routes, auth validation, Azure Table Storage access, tfvars generation, and App Service runtime behavior.
- CI builds the frontend first, copies the bundle into `backend/frontend-dist/`, then deploys the backend package to App Service.

## Local Development

Prerequisites:

| Tool | Version |
|------|---------|
| Node.js | major version from `tenant-onboarding-portal/.node-version` |
| npm | bundled |

Start both local servers from the workspace root:

```bash
cd tenant-onboarding-portal
./backend/run-local.sh
```

Useful options:

```bash
./backend/run-local.sh --oidc
./backend/run-local.sh --storage
./backend/run-local.sh --port 9000
./backend/run-local.sh --frontend-port 5174
```

Default local behavior:

- Backend runs on `http://localhost:8000`
- Frontend runs on `http://localhost:5173`
- Vite proxies `/api` and `/healthz` to the backend
- When OIDC is disabled, `Bearer dev-token` resolves to a local admin identity

Minimal `.env` for mock-auth local runs lives in `backend/.env`:

```dotenv
PORTAL_OIDC_DISCOVERY_URL=
PORTAL_OIDC_CLIENT_ID=tenant-onboarding-portal
PORTAL_OIDC_ADMIN_ROLE=portal-admin
```

## Build And Test

```bash
cd tenant-onboarding-portal/frontend
npm test

cd tenant-onboarding-portal/backend
npm install
npm install --prefix ../frontend
npm run build:all
npm test
npm run e2e
npm run e2e:dev
```

## Terraform Deployment

The portal infra root includes a wrapper script similar to the main AI Hub Terraform deploy script:

```bash
cd tenant-onboarding-portal/infra
./deploy-terraform.sh plan dev
./deploy-terraform.sh apply tools --auto-approve
./deploy-terraform.sh apply tools --auto-approve --infra-only
```

Notes:

- The script supports `dev`, `test`, `prod`, and `tools`.
- `apply` is now the end-to-end deployment path: it provisions infra, packages the app, deploys it, runs health checks, and emits App Service outputs to `GITHUB_OUTPUT` when running in GitHub Actions.
- Use `--infra-only` when you want Terraform apply without packaging or App Service deployment.
- It still supports standalone commands such as `package-app`, `deploy-app`, `swap-slot`, and `health-check` for targeted local or debugging runs.
- It loads `terraform.tfvars` automatically when present, while forcing `app_env` from the environment argument.
- Remote backend settings come from `BACKEND_RESOURCE_GROUP`, `BACKEND_STORAGE_ACCOUNT`, and optionally `PORTAL_STATE_KEY` or `--state-key=...`.
- The shared Node version source is `tenant-onboarding-portal/.node-version`; GitHub Actions, local scripts, and the App Service runtime all derive from that file.
- App deployment commands accept `PORTAL_RESOURCE_GROUP`, `PORTAL_APP_SERVICE_NAME`, `PORTAL_APP_HOSTNAME`, `PORTAL_DEPLOY_ZIP`, and optionally `PORTAL_NODE_VERSION_FILE` as defaults.
- CI and workflow-style runs can continue to rely on `TF_VAR_*` and `ARM_USE_OIDC=true` environment variables.

## Project Structure

```text
tenant-onboarding-portal/
├── infra/
│   ├── main.tf
│   ├── variables.tf
│   └── ...
├── backend/
│   ├── src/
│   ├── tests/
│   ├── docs/
│   ├── scripts/
│   ├── package.json
│   └── run-local.sh
├── frontend/
│   ├── src/
│   └── package.json
└── README.md
```

## Deployment Workflows

Portal deployment now follows the same backend-root bundle pattern across workflows:

1. install backend dependencies from `tenant-onboarding-portal/backend`
2. install frontend dependencies from `tenant-onboarding-portal/frontend`
3. run `npm run build:all` in `backend/`
4. zip the backend app root, including the copied frontend bundle in `backend/frontend-dist/`
5. deploy to Azure App Service
6. verify `/healthz`

Workflow responsibilities:

- `pr-open.yml`: runs backend and frontend unit tests, runs Playwright against dev-mode backend and frontend servers, then provisions and deploys preview portal apps for pull requests
- `pr-close.yml`: destroys preview portal apps when a PR closes
- `merge-main.yml`: deploys the tools portal through the staging slot and swaps to production
- `portal-deploy.yml`: manually redeploys the tools portal with the same bundle path

## Storage And Security Notes

- No storage settings: in-memory store for local development and test runs
- Storage account URL or connection string configured: Azure Table Storage
- The API remains stateless and still validates issuer, signature, and optional audience claims
- Admin access still comes from the configured role or mock-auth user roles
