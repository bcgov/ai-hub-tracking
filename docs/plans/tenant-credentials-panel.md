# Plan: Tenant Credentials Panel

> Post-approval APIM key access and tenant-info proxy for tenant admins in the onboarding portal.

---

## Decisions

| # | Question | Decision |
|---|----------|----------|
| 1 | Who is a "tenant admin"? | Any user whose email appears in `FormData.admin_users` of the approved tenant record |
| 2 | How are keys displayed? | Copy-to-clipboard only — keys are **never rendered in the DOM** |
| 3 | Who calls the APIM `internal/tenant-info` endpoint? | Backend proxy — portal backend calls APIM, returns JSON to browser |
| 4 | Which secrets are exposed? | Primary key + secondary key + rotation metadata object |
| 5 | Does `listTenants` change? | Yes — return tenants where user is `SubmittedBy` OR in `admin_users` |

---

## Encryption Analysis

**Question:** Is application-layer encryption needed so network calls don't show keys in plain text in the browser DevTools Network tab?

**Answer: No — and it would be counterproductive.**

The browser DevTools Network tab shows all HTTPS responses after TLS decryption, by design. This is the same as what GitHub, Azure Portal, and AWS console do when displaying API keys: they never see the key in HTML, but it is visible in the network response.

Adding an extra encryption layer (e.g., AES-encrypting the JSON payload, then decrypting in JS) would not prevent this — the decryption key would also have to reach the browser, making it security theatre.

**Mitigations applied instead:**

| Mitigation | Effect |
|------------|--------|
| HTTPS (TLS 1.2+) | Protects keys in transit from all network observers |
| `Cache-Control: no-store` on `/credentials` response | Prevents caching in browser history, proxies, CDN |
| Copy-only UI (key never in `useState` or DOM) | Reduces XSS surface — key is used in `navigator.clipboard.writeText()` then discarded |
| Backend proxy for tenant-info | APIM primary key never leaves the server when fetching tenant metadata |
| Short-lived Managed Identity tokens | No long-lived credentials on the portal host |

This is consistent with industry-standard secrets management portal patterns (Azure Portal, GitHub, AWS IAM).

---

## Architecture

```
Browser (tenant admin)
  │
  │  GET /api/tenants/:name/credentials
  │  GET /api/tenants/:name/tenant-info?env=dev
  │
  ▼
Portal Backend (NestJS, App Service with System MI)
  │
  ├─── DefaultAzureCredential ──► Hub Key Vault (per env: dev/test/prod)
  │                                  secrets: {tenant}-apim-primary-key
  │                                           {tenant}-apim-secondary-key
  │                                           {tenant}-apim-rotation-metadata
  │
  └─── HTTP (api-key header) ──► App Gateway → APIM
                                    path: /{tenant}/internal/tenant-info
                                    (policy already exists — no APIM changes needed)
```

**Data flow — credentials endpoint:**
1. User's browser → Portal backend (authenticated session)
2. Backend verifies user is `SubmittedBy` or `admin_users` member, tenant is `approved`
3. Backend calls Hub Key Vault via Managed Identity to read 3 secrets
4. Backend returns `{ primary_key, secondary_key, rotation }` with `Cache-Control: no-store`
5. Frontend receives keys, passes directly to `navigator.clipboard.writeText()` — never stored in React state

**Data flow — tenant-info proxy:**
1. Same auth check
2. Backend reads `primary_key` from Hub KV (or reuses if already fetched in same request)
3. Backend calls `{APIM_GATEWAY_URL}/{tenant}/internal/tenant-info` with `api-key` header
4. Backend returns APIM JSON response to browser

---

## Implementation Phases

### Phase 1 — Backend: Settings + Key Vault Service

#### 1.1 Extend `PortalSettings` (`backend/src/types.ts`)

Add 6 new fields:

```typescript
hubKeyVaultUrlDev: string;
hubKeyVaultUrlTest: string;
hubKeyVaultUrlProd: string;
apimGatewayUrlDev: string;
apimGatewayUrlTest: string;
apimGatewayUrlProd: string;
```

#### 1.2 Wire env vars (`backend/src/config/settings.ts`)

Read `PORTAL_HUB_KEYVAULT_URL_{DEV,TEST,PROD}` and `PORTAL_APIM_GATEWAY_URL_{DEV,TEST,PROD}`.
All default to `''` (empty = environment not configured / local dev).

```typescript
hubKeyVaultUrlDev: process.env.PORTAL_HUB_KEYVAULT_URL_DEV ?? '',
hubKeyVaultUrlTest: process.env.PORTAL_HUB_KEYVAULT_URL_TEST ?? '',
hubKeyVaultUrlProd: process.env.PORTAL_HUB_KEYVAULT_URL_PROD ?? '',
apimGatewayUrlDev: process.env.PORTAL_APIM_GATEWAY_URL_DEV ?? '',
apimGatewayUrlTest: process.env.PORTAL_APIM_GATEWAY_URL_TEST ?? '',
apimGatewayUrlProd: process.env.PORTAL_APIM_GATEWAY_URL_PROD ?? '',
```

#### 1.3 New `HubKeyVaultService` (`backend/src/services/hub-keyvault.service.ts`)

- `@Injectable()` NestJS service
- One `SecretClient` per configured KV URL (`DefaultAzureCredential`, from `@azure/keyvault-secrets`)
- Clients are instantiated lazily at startup (one per non-empty URL)
- Method: `getTenantApimKeys(tenantName: string, env: 'dev' | 'test' | 'prod'): Promise<ApimEnvCredentials | null>`
  - Reads 3 secrets: `{tenant}-apim-primary-key`, `{tenant}-apim-secondary-key`, `{tenant}-apim-rotation-metadata`
  - Returns `null` when either the KV URL for that env is not configured, or the secret does not exist
- Register in `AppModule`

#### 1.4 Add package dependency (`backend/package.json`)

```bash
npm install @azure/keyvault-secrets
```

`@azure/identity` is already present — no further auth changes.

---

### Phase 2 — Backend: Authorization + New Endpoints

#### 2.1 New types (`backend/src/types.ts`)

```typescript
export type HubEnv = 'dev' | 'test' | 'prod';

export interface ApimEnvCredentials {
  tenant_name: string;
  env: HubEnv;
  primary_key: string;
  secondary_key: string;
  rotation: Record<string, unknown> | null;
}

export interface ApimTenantInfoResponse {
  tenant: string;
  base_url: string;
  models: Array<{ name: string; deployment: string; capacity: number }>;
  services: Record<string, boolean>;
}
```

#### 2.2 `userIsTenantAdmin` helper (`app.controller.ts`)

```typescript
private userIsTenantAdmin(userEmail: string, tenant: TenantRecord): boolean {
  const adminUsers: string[] = (tenant.FormData as TenantFormData)?.admin_users ?? [];
  return adminUsers.map(e => e.toLowerCase()).includes(userEmail.toLowerCase());
}
```

#### 2.3 Update `listTenants` access

- Add `listAccessibleByUser(email)` to `TenantStoreService`:
  - Calls `listAllCurrent()`, filters in-memory for `SubmittedBy === email` (case-insensitive) OR `FormData.admin_users?.includes(email)` (case-insensitive)
  - Table Storage does not support querying within JSON blobs, so in-memory filtering is required

#### 2.4 Update `getTenant` access check

```typescript
// Before
if (tenant.SubmittedBy !== user.email && !isPortalAdmin) { throw new ForbiddenException(); }

// After
if (tenant.SubmittedBy !== user.email && !isPortalAdmin && !this.userIsTenantAdmin(user.email, tenant)) {
  throw new ForbiddenException();
}
```

#### 2.5 New endpoint: `GET /api/tenants/:name/credentials`

```
Auth:    requireLogin
Access:  SubmittedBy OR portal admin OR admin_users member
Status:  tenant.Status must be 'approved'
Query:   ?env=dev|test|prod  (required)
Returns: ApimEnvCredentials
Headers: Cache-Control: no-store
Errors:  403 if access denied, 409 if not approved, 503 if KV not configured for env
```

#### 2.6 New endpoint: `GET /api/tenants/:name/tenant-info`

```
Auth:    requireLogin
Access:  same as credentials
Status:  tenant must be approved
Query:   ?env=dev|test|prod  (required)
Action:  fetch primary_key via HubKeyVaultService, call APIM proxy
         {PORTAL_APIM_GATEWAY_URL_{ENV}}/{tenantName}/internal/tenant-info
         with header: api-key: {primary_key}
Returns: APIM JSON response (forwarded)
Errors:  403, 409, 503 (if APIM URL not configured); APIM errors forwarded with original status
```

---

### Phase 3 — Frontend: Types + API Client

#### 3.1 New types (`frontend/src/types.ts`)

```typescript
export type HubEnv = 'dev' | 'test' | 'prod';

export interface TenantCredentialsResponse {
  tenant_name: string;
  env: HubEnv;
  primary_key: string;
  secondary_key: string;
  rotation: Record<string, unknown> | null;
}

export interface ApimTenantInfoResponse {
  tenant: string;
  base_url: string;
  models: Array<{ name: string; deployment: string; capacity: number }>;
  services: Record<string, boolean>;
}
```

#### 3.2 New API methods (`frontend/src/api.ts`)

```typescript
export async function getCredentials(tenantName: string, env: HubEnv): Promise<TenantCredentialsResponse> {
  return apiFetch(`/api/tenants/${tenantName}/credentials?env=${env}`);
}

export async function getApimTenantInfo(tenantName: string, env: HubEnv): Promise<ApimTenantInfoResponse> {
  return apiFetch(`/api/tenants/${tenantName}/tenant-info?env=${env}`);
}
```

---

### Phase 4 — Frontend: UI Components + TenantDetailPage

#### 4.1 `CredentialsPanel` component

Location: `frontend/src/components/ui.tsx` (or a new `CredentialsPanel.tsx` if preferred).

**Props:** `tenantName: string`

**Behaviour:**
- Renders 3 environment tabs: **Dev**, **Test**, **Prod**
- Active tab triggers lazy credential fetch (`getCredentials(tenantName, env)`) — only once per env per page load
- Two key rows per env: **Primary Key** / **Secondary Key**
  - Each has a "Copy" button (BCGov design system `<Button variant="secondary">`)
  - On click: `navigator.clipboard.writeText(key)`, key is **never placed in React state or DOM**
  - 2-second visual confirmation (checkmark icon) then resets
- Rotation metadata block: collapsible, shows `JSON.stringify(rotation, null, 2)` in a `<pre>` block
- Tenant-info sub-panel: separate expand/collapse toggle per env
  - Lazy-loads `getApimTenantInfo(tenantName, env)` on first expand
  - Shows: services table (enabled/disabled rows), models list (name + capacity), base URL
  - Loading spinner while fetching; inline error if APIM call fails (keys still shown — graceful degradation)
- Handles `403` with "You do not have permission to view credentials for this tenant"
- Handles `503` with "Credentials not available for this environment (not configured)"

#### 4.2 Update `TenantDetailPage`

- Evaluate `detail.tenant.Status === 'approved'` after load
- Insert `<CredentialsPanel tenantName={tenantName} />` after the summary section, before version history
- No conditional needed in the page — the panel owns its own 403/503 states

---

### Phase 5 — Infrastructure (`tenant-onboarding-portal/infra`)

#### 5.1 New variables (`infra/variables.tf`)

9 new variables — all default `""` (empty = env not wired up):

```hcl
# Hub Key Vault — per environment
variable "hub_keyvault_url_dev"  { type = string; default = "" }
variable "hub_keyvault_url_test" { type = string; default = "" }
variable "hub_keyvault_url_prod" { type = string; default = "" }

variable "hub_keyvault_id_dev"   { type = string; default = "" }
variable "hub_keyvault_id_test"  { type = string; default = "" }
variable "hub_keyvault_id_prod"  { type = string; default = "" }

# APIM/App Gateway URL — per environment
variable "apim_gateway_url_dev"  { type = string; default = "" }
variable "apim_gateway_url_test" { type = string; default = "" }
variable "apim_gateway_url_prod" { type = string; default = "" }
```

#### 5.2 App settings (`infra/main.tf`)

Add to the `app_settings` block (production and staging slot):

```hcl
PORTAL_HUB_KEYVAULT_URL_DEV  = var.hub_keyvault_url_dev
PORTAL_HUB_KEYVAULT_URL_TEST = var.hub_keyvault_url_test
PORTAL_HUB_KEYVAULT_URL_PROD = var.hub_keyvault_url_prod
PORTAL_APIM_GATEWAY_URL_DEV  = var.apim_gateway_url_dev
PORTAL_APIM_GATEWAY_URL_TEST = var.apim_gateway_url_test
PORTAL_APIM_GATEWAY_URL_PROD = var.apim_gateway_url_prod
```

#### 5.3 RBAC (`infra/main.tf`)

3 new role assignments — one per environment, gated on KV ID being set:

```hcl
resource "azurerm_role_assignment" "portal_mi_hub_kv_secrets_user_dev" {
  count                = var.hub_keyvault_id_dev != "" ? 1 : 0
  scope                = var.hub_keyvault_id_dev
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.portal.system_assigned_mi_principal_id
}

resource "azurerm_role_assignment" "portal_mi_hub_kv_secrets_user_test" {
  count                = var.hub_keyvault_id_test != "" ? 1 : 0
  scope                = var.hub_keyvault_id_test
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.portal.system_assigned_mi_principal_id
}

resource "azurerm_role_assignment" "portal_mi_hub_kv_secrets_user_prod" {
  count                = var.hub_keyvault_id_prod != "" ? 1 : 0
  scope                = var.hub_keyvault_id_prod
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.portal.system_assigned_mi_principal_id
}
```

When `enable_deployment_slot = true`, add matching assignments for the staging slot MI.

#### 5.4 Hub KV and APIM outputs reference

The portal Terraform infra needs nine values from the hub Terraform stacks. All are already declared as Terraform outputs — no hub-side changes required:

| Terraform output | Hub stack | State blob key |
|---|---|---|
| `hub_key_vault_id` | `infra-ai-hub/stacks/shared` | `ai-services-hub/{env}/shared.tfstate` |
| `hub_key_vault_uri` | `infra-ai-hub/stacks/shared` | `ai-services-hub/{env}/shared.tfstate` |
| `apim_gateway_url` | `infra-ai-hub/stacks/apim` | `ai-services-hub/{env}/apim.tfstate` |

These are **automatically queried from hub Terraform remote state** in the GHA pipeline before the portal Terraform apply runs — see **Phase 7** for the full workflow design. No manual `.tfvars` editing or hard-coded values are required.

> **Routing note:** `apim_gateway_url` from the APIM stack is the APIM gateway's direct (private) URL. Because the portal backend runs in the `tools` subscription (outside the hub private VNet), the `TF_VAR_apim_gateway_url_*` variables should carry the **App Gateway public URL** (`app_gateway_frontend_url` output in the shared stack) unless VNet peering between `tools` and hub is in place. Confirm routing architecture before wiring the value — substituting `app_gateway_frontend_url` from the shared stack in the collection step if needed.

---

### Phase 6 — Documentation

#### 6.1 `docs/_pages/apim-key-rotation.html`

Add new section: **"Portal Credential Access"**
- Explains that approved tenant admins can now view their APIM keys via the portal
- Describes Key Vault Secrets User RBAC grant to portal Managed Identity
- Notes that rotation metadata is also visible to indicate when the last rotation occurred

#### 6.2 `docs/_pages/services.html`

Add section describing the Credentials Panel from a tenant-admin perspective:
- What data is shown (Primary/Secondary keys, rotation metadata, tenant-info)
- How to copy keys (copy-only; value never displayed)
- The 3-environment tabs (dev/test/prod)

#### 6.3 `docs/_pages/technical-deep-dive.html`

Add sub-section on portal → hub KV integration architecture:
- Flow: portal MI → Key Vault Secrets User → hub KV secrets → returned to authenticated session
- Note: APIM `internal/apim-keys` and `internal/tenant-info` policies already existed — no APIM changes required

#### 6.4 Rebuild docs

Run `docs/build.sh` after updating `_pages/` sources to regenerate static HTML.

---

### Phase 7 — GHA Workflow Automation

Adds a `collect-hub-outputs` matrix job to both `portal-deploy.yml` and `merge-main.yml` that queries hub Terraform state before the portal Terraform apply runs. No secrets store, no manual variable management.

#### 7.1 Why a matrix job with env-embedded output keys

Each environment needs **its own GitHub Environment credentials** — the `dev`, `test`, and `prod` GitHub Environments each have a separate OIDC service principal with access to that environment's hub subscription. A `tools`-credentialed job cannot read state blobs from `dev`/`test`/`prod` subscriptions.

A GHA matrix job with `environment: ${{ matrix.env }}` correctly gates credentials per-env. The usual matrix output limitation — "last completed instance wins for shared keys" — is avoided here by **embedding the env into every output key name** in the bash step:

```bash
echo "hub_kv_${HUB_ENV}_id=..."   >> "$GITHUB_OUTPUT"   # e.g. hub_kv_dev_id
echo "hub_kv_${HUB_ENV}_url=..."  >> "$GITHUB_OUTPUT"   # e.g. hub_kv_dev_url
echo "apim_url_${HUB_ENV}=..."    >> "$GITHUB_OUTPUT"   # e.g. apim_url_dev
```

Because each matrix instance writes **different** keys (`hub_kv_dev_id` vs `hub_kv_test_id` vs `hub_kv_prod_id`), there is no collision — no instance overwrites another's values. The job-level `outputs:` block statically declares all 9 combinations upfront; GHA merges the 3 instances and all 9 keys are populated. Downstream jobs reference them as `needs.collect-hub-outputs.outputs.hub_kv_dev_id` etc. — fully deterministic.

#### 7.2 New job: `collect-hub-outputs` (matrix)

Add this job before the portal deploy job in both workflow files. The same secret and variable names are used in each env's GitHub Environment (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `STORAGE_ACCOUNT_NAME`) — confirmed in `.deployer-using-secure-tunnel.yml`.

```yaml
collect-hub-outputs:
  name: Collect hub Terraform outputs (${{ matrix.env }})
  runs-on: ubuntu-24.04
  strategy:
    matrix:
      env: [dev, test, prod]
  environment: ${{ matrix.env }}
  outputs:
    hub_kv_dev_id:   ${{ steps.collect.outputs.hub_kv_dev_id }}
    hub_kv_test_id:  ${{ steps.collect.outputs.hub_kv_test_id }}
    hub_kv_prod_id:  ${{ steps.collect.outputs.hub_kv_prod_id }}
    hub_kv_dev_url:  ${{ steps.collect.outputs.hub_kv_dev_url }}
    hub_kv_test_url: ${{ steps.collect.outputs.hub_kv_test_url }}
    hub_kv_prod_url: ${{ steps.collect.outputs.hub_kv_prod_url }}
    apim_url_dev:    ${{ steps.collect.outputs.apim_url_dev }}
    apim_url_test:   ${{ steps.collect.outputs.apim_url_test }}
    apim_url_prod:   ${{ steps.collect.outputs.apim_url_prod }}
  steps:
    - name: Login to Azure (OIDC)
      uses: azure/login@v2
      with:
        client-id:       ${{ secrets.AZURE_CLIENT_ID }}
        tenant-id:       ${{ secrets.AZURE_TENANT_ID }}
        subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    - name: Collect hub outputs
      id: collect
      env:
        BACKEND_STORAGE_ACCOUNT: ${{ vars.STORAGE_ACCOUNT_NAME }}
        BACKEND_CONTAINER: tfstate
        HUB_ENV: ${{ matrix.env }}
      run: |
        set -euo pipefail
        az storage blob download \
          --account-name "$BACKEND_STORAGE_ACCOUNT" \
          --container-name "$BACKEND_CONTAINER" \
          --name "ai-services-hub/${HUB_ENV}/shared.tfstate" \
          --auth-mode login --file /tmp/shared.tfstate --output none
        az storage blob download \
          --account-name "$BACKEND_STORAGE_ACCOUNT" \
          --container-name "$BACKEND_CONTAINER" \
          --name "ai-services-hub/${HUB_ENV}/apim.tfstate" \
          --auth-mode login --file /tmp/apim.tfstate --output none
        {
          echo "hub_kv_${HUB_ENV}_id=$(jq -r '.outputs.hub_key_vault_id.value'  /tmp/shared.tfstate)"
          echo "hub_kv_${HUB_ENV}_url=$(jq -r '.outputs.hub_key_vault_uri.value' /tmp/shared.tfstate)"
          # Substitute .outputs.app_gateway_frontend_url.value if routing via App GW instead of APIM directly
          echo "apim_url_${HUB_ENV}=$(jq -r '.outputs.apim_gateway_url.value'    /tmp/apim.tfstate)"
        } >> "$GITHUB_OUTPUT"
        rm -f /tmp/shared.tfstate /tmp/apim.tfstate
```

> **RBAC prerequisite:** Each env's OIDC service principal needs `Storage Blob Data Reader` on its own `tfstate` container (in its own storage account). The hub deployer workflows already read the same state blobs during `terraform init`, so this grant is likely already in place — confirm by checking the existing role assignment module for each hub env.

#### 7.3 Wire outputs into the portal deploy job

Update the `deploy` job in `portal-deploy.yml` (and `deploy-portal-tools` in `merge-main.yml`) to depend on `collect-hub-outputs` and forward its outputs as `TF_VAR_*`:

```yaml
# portal-deploy.yml
deploy:
  needs: [collect-hub-outputs]
  # ... rest unchanged ...
  steps:
    - name: Terraform apply
      env:
        # ... existing env vars unchanged ...
        TF_VAR_hub_keyvault_id_dev:   ${{ needs.collect-hub-outputs.outputs.hub_kv_dev_id }}
        TF_VAR_hub_keyvault_id_test:  ${{ needs.collect-hub-outputs.outputs.hub_kv_test_id }}
        TF_VAR_hub_keyvault_id_prod:  ${{ needs.collect-hub-outputs.outputs.hub_kv_prod_id }}
        TF_VAR_hub_keyvault_url_dev:  ${{ needs.collect-hub-outputs.outputs.hub_kv_dev_url }}
        TF_VAR_hub_keyvault_url_test: ${{ needs.collect-hub-outputs.outputs.hub_kv_test_url }}
        TF_VAR_hub_keyvault_url_prod: ${{ needs.collect-hub-outputs.outputs.hub_kv_prod_url }}
        TF_VAR_apim_gateway_url_dev:  ${{ needs.collect-hub-outputs.outputs.apim_url_dev }}
        TF_VAR_apim_gateway_url_test: ${{ needs.collect-hub-outputs.outputs.apim_url_test }}
        TF_VAR_apim_gateway_url_prod: ${{ needs.collect-hub-outputs.outputs.apim_url_prod }}
```

In `merge-main.yml` the existing `needs` for `deploy-portal-tools` already references `detect-portal-changes` — add `collect-hub-outputs` alongside it:

```yaml
# merge-main.yml
deploy-portal-tools:
  needs: [detect-portal-changes, collect-hub-outputs]
  if: needs.detect-portal-changes.outputs.portal_changed == 'true'
```

The `collect-hub-outputs` matrix job should **not** be gated on `portal_changed` — if it is skipped, GHA resolves its outputs as empty strings in downstream `needs` context, which would silently zero-out all nine `TF_VAR_*` values.

#### 7.4 State file references (confirmed)

| Hub stack | Storage account | Blob key |
|---|---|---|
| `infra-ai-hub/stacks/shared` | `vars.STORAGE_ACCOUNT_NAME` (per-env) | `ai-services-hub/{env}/shared.tfstate` |
| `infra-ai-hub/stacks/apim` | `vars.STORAGE_ACCOUNT_NAME` (per-env) | `ai-services-hub/{env}/apim.tfstate` |
| `tenant-onboarding-portal/infra` | `vars.STORAGE_ACCOUNT_NAME` (tools) | `portal/tools/terraform.tfstate` |

Each hub environment has its own storage account referenced via `vars.STORAGE_ACCOUNT_NAME` from the corresponding GitHub Environment. State keys are confirmed from `infra-ai-hub/scripts/deploy-terraform.sh`.

#### 7.5 No new secrets or variables needed

Each collection job reuses the exact same credentials and storage variable names already present in the per-env deployer workflows: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `STORAGE_ACCOUNT_NAME`. Only the RBAC prerequisite in 7.2 may require a one-time verification.

---

## Relevant Files

| File | Change |
|------|--------|
| `backend/src/types.ts` | Add `HubEnv`, `ApimEnvCredentials`, `ApimTenantInfoResponse`; extend `PortalSettings` with 6 URL fields |
| `backend/src/config/settings.ts` | Read 6 new `PORTAL_*` env vars |
| `backend/src/services/hub-keyvault.service.ts` | **NEW** — `HubKeyVaultService` |
| `backend/src/storage/tenant-store.service.ts` | Add `listAccessibleByUser(email)` |
| `backend/src/app.controller.ts` | `userIsTenantAdmin()` helper; update `getTenant` guard; 2 new endpoints |
| `backend/src/app.module.ts` | Register `HubKeyVaultService` |
| `backend/package.json` | Add `@azure/keyvault-secrets` |
| `frontend/src/types.ts` | Add `HubEnv`, `TenantCredentialsResponse`, `ApimTenantInfoResponse` |
| `frontend/src/api.ts` | Add `getCredentials()`, `getApimTenantInfo()` |
| `frontend/src/components/ui.tsx` | Add `CredentialsPanel` component |
| `frontend/src/pages/TenantDetailPage.tsx` | Render `<CredentialsPanel />` after summary |
| `infra/variables.tf` | 9 new variables (3x KV URL, 3x KV ID, 3x APIM URL) |
| `infra/main.tf` | 6 app settings + 3 RBAC blocks (+ staging slot RBAC) |
| `docs/_pages/apim-key-rotation.html` | Portal credential access section |
| `docs/_pages/services.html` | Credentials panel user docs |
| `docs/_pages/technical-deep-dive.html` | Architecture sub-section |
| `.github/workflows/portal-deploy.yml` | Add `collect-hub-outputs` matrix job (`matrix.env: [dev, test, prod]`, each `environment: ${{ matrix.env }}`); add `needs` + 9 `TF_VAR_*` hub vars to `deploy` job |
| `.github/workflows/merge-main.yml` | Add `collect-hub-outputs` matrix job (unconditional); extend `deploy-portal-tools` `needs` + 9 `TF_VAR_*` hub vars |

---

## Verification

| Step | How |
|------|-----|
| Backend unit tests | Vitest: mock `SecretClient` in `HubKeyVaultService`; mock service in controller tests for both new endpoints |
| `listAccessibleByUser` tests | Unit test: records with matching `admin_users` are returned; case-insensitive; non-matching excluded |
| E2E (Playwright) | As tenant-admin user (mock auth), navigate to approved tenant; assert `CredentialsPanel` renders; click Copy on primary key; assert clipboard write called; expand tenant-info panel |
| Terraform plan | `cd tenant-onboarding-portal/infra && terraform plan` — verify 6 app settings + 3 RBAC `azurerm_role_assignment` resources appear |
| Manual smoke test | Deploy to dev with `hub_keyvault_url_dev` + `apim_gateway_url_dev` set; navigate to approved tenant as admin_users member; copy primary key; expand tenant-info panel and verify JSON renders |

---

## Scope Boundaries

**Included:**
- Portal backend Key Vault fetch (primary + secondary + rotation metadata)
- New `/credentials` and `/tenant-info` proxy endpoints (with per-env `?env=` query param)
- `listTenants` extended to include `admin_users` members
- Copy-only key UI with BCGov design system components
- Tenant-info collapsible sub-panel
- Per-environment infra: 9 Terraform variables, 6 app settings, 3 RBAC role assignments
- Documentation (3 pages + rebuild)

**Excluded:**
- APIM policy changes — `internal/apim-keys` and `internal/tenant-info` **already exist** in `api_policy.xml.tftpl`
- Key rotation triggering from the portal
- Changes to the approval workflow
- Modifying the hub Key Vault Terraform (secrets are already seeded there by the key rotation job)
- Application-layer encryption of key material in transit (HTTPS + `Cache-Control: no-store` is sufficient)
