#!/bin/bash
set -euo pipefail

# Upload SSL Certificate to App Gateway via Azure Key Vault
#
# Imports PFX into Key Vault, configures RBAC, and attaches the KV reference
# to the Application Gateway. Supports auto-rotation via versionless secret IDs.
#
# Usage:
#   ./upload-cert-keyvault.sh [options]
#   ./upload-cert-keyvault.sh --env prod --pfx path/to/cert.pfx --vault-name mykv
#   ./upload-cert-keyvault.sh -i                          # Interactive mode
#
# Options:
#   -i, --interactive       Run in interactive mode (prompt for all inputs)
#   -e, --env ENV           Environment: test or prod (required)
#   -p, --pfx FILE          Path to the PFX certificate file (required)
#   -w, --password PASS     PFX password (omit for passwordless PFX; prompted if -i)
#   -v, --vault-name NAME   Key Vault name (required)
#   -n, --cert-name NAME    Certificate name in KV and App GW (default: api-{env}-cert)
#   -g, --resource-group RG App Gateway resource group (default: ai-services-hub-{env})
#   --gateway-name NAME     App Gateway name (default: ai-services-hub-{env}-appgw)
#   --identity-name NAME    Managed identity name (default: ai-services-hub-{env}-appgw-identity)
#   --skip-rbac             Skip RBAC role assignment (if already configured)
#   --setup-https           Also create HTTPS listener + routing rules
#   --dry-run               Show what would be done without making changes
#   -h, --help              Display help and exit

# ─── Defaults ────────────────────────────────────────────────────────────────
INTERACTIVE=false
ENV=""
PFX_FILE=""
PFX_PASSWORD=""
VAULT_NAME=""
CERT_NAME=""
RESOURCE_GROUP=""
GATEWAY_NAME=""
IDENTITY_NAME=""
SKIP_RBAC=false
SETUP_HTTPS=false
DRY_RUN=false

# ─── Environment → Domain mapping ───────────────────────────────────────────
declare -A DOMAIN_MAP=(
  [test]="test.aihub.gov.bc.ca"
  [prod]="aihub.gov.bc.ca"
)

# ─── Colours ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ─── Help ────────────────────────────────────────────────────────────────────
display_help() {
  sed -n '3,28p' "$0" | sed 's/^# \?//'
  exit 0
}

# ─── Parse arguments ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--interactive)    INTERACTIVE=true; shift ;;
    -e|--env)            ENV="$2"; shift 2 ;;
    -p|--pfx)            PFX_FILE="$2"; shift 2 ;;
    -w|--password)       PFX_PASSWORD="$2"; shift 2 ;;
    -v|--vault-name)     VAULT_NAME="$2"; shift 2 ;;
    -n|--cert-name)      CERT_NAME="$2"; shift 2 ;;
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --gateway-name)      GATEWAY_NAME="$2"; shift 2 ;;
    --identity-name)     IDENTITY_NAME="$2"; shift 2 ;;
    --skip-rbac)         SKIP_RBAC=true; shift ;;
    --setup-https)       SETUP_HTTPS=true; shift ;;
    --dry-run)           DRY_RUN=true; shift ;;
    -h|--help)           display_help ;;
    *)                   err "Unknown option: $1"; display_help ;;
  esac
done

# ─── Gather inputs ──────────────────────────────────────────────────────────

# Environment
if [[ -z "$ENV" ]]; then
  if [[ "$INTERACTIVE" == false ]]; then
    err "Environment is required. Use --env test|prod or -i for interactive."
    exit 1
  fi
  echo -e "\nSelect environment:"
  select ENV in test prod; do
    [[ -n "$ENV" ]] && break
    echo "Invalid selection. Try again."
  done
fi

if [[ "$ENV" != "test" && "$ENV" != "prod" ]]; then
  err "Invalid environment: $ENV (must be test or prod)"
  exit 1
fi

DOMAIN="${DOMAIN_MAP[$ENV]}"
RESOURCE_GROUP="${RESOURCE_GROUP:-ai-services-hub-${ENV}}"
GATEWAY_NAME="${GATEWAY_NAME:-ai-services-hub-${ENV}-appgw}"
IDENTITY_NAME="${IDENTITY_NAME:-ai-services-hub-${ENV}-appgw-identity}"
CERT_NAME="${CERT_NAME:-api-${ENV}-cert}"

# Key Vault name
if [[ -z "$VAULT_NAME" ]]; then
  if [[ "$INTERACTIVE" == false ]]; then
    err "Key Vault name is required. Use --vault-name NAME or -i for interactive."
    exit 1
  fi
  echo -e "\nEnter the Key Vault name:"
  read -r VAULT_NAME
fi

# PFX file
if [[ -z "$PFX_FILE" ]]; then
  if [[ "$INTERACTIVE" == false ]]; then
    err "PFX file is required. Use --pfx path/to/cert.pfx or -i for interactive."
    exit 1
  fi
  echo -e "\nEnter the path to the PFX certificate file:"
  read -r PFX_FILE
fi

if [[ ! -f "$PFX_FILE" ]]; then
  err "PFX file not found: $PFX_FILE"
  exit 1
fi

# PFX password (Key Vault import may or may not need it)
if [[ -z "$PFX_PASSWORD" && "$INTERACTIVE" == true ]]; then
  echo -e "\nEnter the PFX password (leave empty if passwordless):"
  read -rs PFX_PASSWORD
  echo ""
fi

# Setup HTTPS?
if [[ "$INTERACTIVE" == true && "$SETUP_HTTPS" == false ]]; then
  echo -e "\nAlso create HTTPS listener and routing rules? [y/N]"
  read -r ANSWER
  [[ "$ANSWER" =~ ^[Yy] ]] && SETUP_HTTPS=true
fi

# Skip RBAC?
if [[ "$INTERACTIVE" == true && "$SKIP_RBAC" == false ]]; then
  echo -e "\nSkip RBAC role assignment (already configured by Terraform)? [y/N]"
  read -r ANSWER
  [[ "$ANSWER" =~ ^[Yy] ]] && SKIP_RBAC=true
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Key Vault SSL Certificate Upload"
echo "═══════════════════════════════════════════════════════════"
info "Environment:    $ENV"
info "Domain:         $DOMAIN"
info "Resource Group: $RESOURCE_GROUP"
info "Gateway:        $GATEWAY_NAME"
info "Identity:       $IDENTITY_NAME"
info "Key Vault:      $VAULT_NAME"
info "Cert Name:      $CERT_NAME"
info "PFX File:       $PFX_FILE"
if [[ -n "$PFX_PASSWORD" ]]; then
  PFX_PASSWORD_STATUS="(set)"
else
  PFX_PASSWORD_STATUS="(empty/passwordless)"
fi
info "PFX Password:   $PFX_PASSWORD_STATUS"
info "Skip RBAC:      $SKIP_RBAC"
info "Setup HTTPS:    $SETUP_HTTPS"
info "Dry Run:        $DRY_RUN"
echo "═══════════════════════════════════════════════════════════"

if [[ "$INTERACTIVE" == true ]]; then
  echo -e "\nProceed? [y/N]"
  read -r CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy] ]]; then
    warn "Aborted."
    exit 0
  fi
fi

# ─── Validate prerequisites ─────────────────────────────────────────────────
info "Validating PFX file..."
PFX_PASS_ARG="pass:${PFX_PASSWORD}"
if ! openssl pkcs12 -in "$PFX_FILE" -info -nokeys -passin "$PFX_PASS_ARG" >/dev/null 2>&1; then
  err "Failed to read PFX file. Check the file and password."
  exit 1
fi
ok "PFX file is valid."

CERT_SUBJECT=$(openssl pkcs12 -in "$PFX_FILE" -clcerts -nokeys -passin "$PFX_PASS_ARG" 2>/dev/null | \
  openssl x509 -noout -subject 2>/dev/null | sed 's/subject=//') || true
CERT_EXPIRY=$(openssl pkcs12 -in "$PFX_FILE" -clcerts -nokeys -passin "$PFX_PASS_ARG" 2>/dev/null | \
  openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//') || true
info "Certificate subject: ${CERT_SUBJECT:-unknown}"
info "Certificate expires: ${CERT_EXPIRY:-unknown}"

info "Checking Azure CLI login..."
if ! az account show >/dev/null 2>&1; then
  err "Not logged in to Azure CLI. Run 'az login' first."
  exit 1
fi
CURRENT_SUB=$(az account show --query "name" -o tsv)
ok "Azure CLI authenticated (subscription: $CURRENT_SUB)."

info "Checking Key Vault '$VAULT_NAME' exists..."
KV_ID=$(az keyvault show --name "$VAULT_NAME" --query "id" -o tsv 2>/dev/null) || {
  err "Key Vault '$VAULT_NAME' not found. Check the name and your subscription."
  exit 1
}
ok "Key Vault found."

info "Checking App Gateway '$GATEWAY_NAME' exists..."
if ! az network application-gateway show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$GATEWAY_NAME" \
  --query "name" -o tsv >/dev/null 2>&1; then
  err "App Gateway '$GATEWAY_NAME' not found in RG '$RESOURCE_GROUP'."
  exit 1
fi
ok "App Gateway found."

# ─── Step 1: Import certificate into Key Vault ──────────────────────────────
echo ""
info "── Step 1/4: Import certificate into Key Vault ──"

if [[ "$DRY_RUN" == true ]]; then
  warn "[DRY RUN] Would import '$CERT_NAME' into Key Vault '$VAULT_NAME'"
else
  info "Importing certificate '$CERT_NAME' into Key Vault..."

  IMPORT_ARGS=(
    --vault-name "$VAULT_NAME"
    --name "$CERT_NAME"
    --file "$PFX_FILE"
  )
  [[ -n "$PFX_PASSWORD" ]] && IMPORT_ARGS+=(--password "$PFX_PASSWORD")

  az keyvault certificate import "${IMPORT_ARGS[@]}" --output none
  ok "Certificate imported into Key Vault."
fi

# ─── Step 2: Get versionless Secret ID ───────────────────────────────────────
echo ""
info "── Step 2/4: Retrieve versionless Secret ID ──"

if [[ "$DRY_RUN" == true ]]; then
  SECRET_ID="https://${VAULT_NAME}.vault.azure.net/secrets/${CERT_NAME}"
  warn "[DRY RUN] Would use secret ID: $SECRET_ID"
else
  # Get versioned ID, then strip the version to get versionless
  VERSIONED_ID=$(az keyvault secret show \
    --vault-name "$VAULT_NAME" \
    --name "$CERT_NAME" \
    --query "id" -o tsv)
  SECRET_ID="${VERSIONED_ID%/*}"
  ok "Versionless Secret ID: $SECRET_ID"
  info "(Using versionless ID enables auto-rotation)"
fi

# ─── Step 3: Ensure managed identity has Key Vault access ───────────────────
echo ""
info "── Step 3/4: Configure RBAC (Key Vault Secrets User) ──"

if [[ "$SKIP_RBAC" == true ]]; then
  info "Skipping RBAC — already configured (--skip-rbac or Terraform-managed)."
else
  info "Looking up managed identity '$IDENTITY_NAME'..."

  PRINCIPAL_ID=$(az identity show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$IDENTITY_NAME" \
    --query "principalId" -o tsv 2>/dev/null) || {
    err "Managed identity '$IDENTITY_NAME' not found in RG '$RESOURCE_GROUP'."
    err "The App Gateway identity is created by Terraform. Run 'terraform apply' first."
    exit 1
  }
  ok "Identity principal ID: $PRINCIPAL_ID"

  if [[ "$DRY_RUN" == true ]]; then
    warn "[DRY RUN] Would assign 'Key Vault Secrets User' to $PRINCIPAL_ID on $KV_ID"
  else
    info "Assigning 'Key Vault Secrets User' role..."

    # Check if assignment already exists
    EXISTING_ROLE=$(az role assignment list \
      --assignee "$PRINCIPAL_ID" \
      --scope "$KV_ID" \
      --role "Key Vault Secrets User" \
      --query "length(@)" -o tsv 2>/dev/null || echo "0")

    if [[ "$EXISTING_ROLE" -gt 0 ]]; then
      ok "Role assignment already exists — skipping."
    else
      az role assignment create \
        --assignee "$PRINCIPAL_ID" \
        --role "Key Vault Secrets User" \
        --scope "$KV_ID" \
        --output none
      ok "Role assignment created."
      info "Waiting 30s for RBAC propagation..."
      sleep 30
    fi
  fi
fi

# ─── Step 4: Attach Key Vault cert to App Gateway ───────────────────────────
echo ""
info "── Step 4/4: Attach certificate to App Gateway ──"

if [[ "$DRY_RUN" == true ]]; then
  warn "[DRY RUN] Would attach KV cert '$CERT_NAME' (secret: $SECRET_ID) to '$GATEWAY_NAME'"
else
  info "Attaching Key Vault certificate to App Gateway..."

  EXISTING_CERT=$(az network application-gateway ssl-cert list \
    --resource-group "$RESOURCE_GROUP" \
    --gateway-name "$GATEWAY_NAME" \
    --query "[?name=='${CERT_NAME}'].name" -o tsv 2>/dev/null || true)

  if [[ -n "$EXISTING_CERT" ]]; then
    warn "Certificate '$CERT_NAME' already exists on App GW — updating..."
    az network application-gateway ssl-cert update \
      --resource-group "$RESOURCE_GROUP" \
      --gateway-name "$GATEWAY_NAME" \
      --name "$CERT_NAME" \
      --key-vault-secret-id "$SECRET_ID" \
      --output none
  else
    az network application-gateway ssl-cert create \
      --resource-group "$RESOURCE_GROUP" \
      --gateway-name "$GATEWAY_NAME" \
      --name "$CERT_NAME" \
      --key-vault-secret-id "$SECRET_ID" \
      --output none
  fi
  ok "Key Vault certificate attached to App Gateway."
fi

# ─── Setup HTTPS listener + routing (optional) ──────────────────────────────
if [[ "$SETUP_HTTPS" == true ]]; then
  echo ""
  info "── Optional: Configure HTTPS listener and routing ──"

  FEIP_NAME="${GATEWAY_NAME}-feip"
  HTTPS_PORT_NAME="${GATEWAY_NAME}-feport-https"
  HTTPS_LISTENER_NAME="${GATEWAY_NAME}-listener-https"
  HTTP_LISTENER_NAME="${GATEWAY_NAME}-listener-http"
  HTTPS_RULE_NAME="${GATEWAY_NAME}-rule-https"
  HTTP_RULE_NAME="${GATEWAY_NAME}-rule-http"
  BACKEND_POOL="${GATEWAY_NAME}-bepool-apim"
  BACKEND_SETTINGS="${GATEWAY_NAME}-httpsetting"
  REDIRECT_NAME="${GATEWAY_NAME}-redirect-https"

  if [[ "$DRY_RUN" == true ]]; then
    warn "[DRY RUN] Would create HTTPS listener '$HTTPS_LISTENER_NAME'"
    warn "[DRY RUN] Would create HTTPS routing rule '$HTTPS_RULE_NAME' (priority 100)"
    warn "[DRY RUN] Would create redirect '$REDIRECT_NAME' (HTTP → HTTPS)"
    warn "[DRY RUN] Would update HTTP rule '$HTTP_RULE_NAME' to redirect"
  else
    info "Creating HTTPS listener..."
    az network application-gateway http-listener create \
      --resource-group "$RESOURCE_GROUP" \
      --gateway-name "$GATEWAY_NAME" \
      --name "$HTTPS_LISTENER_NAME" \
      --frontend-ip "$FEIP_NAME" \
      --frontend-port "$HTTPS_PORT_NAME" \
      --ssl-cert "$CERT_NAME" \
      --host-name "$DOMAIN" \
      --output none 2>/dev/null || warn "HTTPS listener may already exist."
    ok "HTTPS listener created."

    info "Creating HTTPS routing rule..."
    az network application-gateway rule create \
      --resource-group "$RESOURCE_GROUP" \
      --gateway-name "$GATEWAY_NAME" \
      --name "$HTTPS_RULE_NAME" \
      --priority 100 \
      --http-listener "$HTTPS_LISTENER_NAME" \
      --address-pool "$BACKEND_POOL" \
      --http-settings "$BACKEND_SETTINGS" \
      --rule-type Basic \
      --output none 2>/dev/null || warn "HTTPS rule may already exist."
    ok "HTTPS routing rule created."

    info "Creating HTTP → HTTPS redirect..."
    az network application-gateway redirect-config create \
      --resource-group "$RESOURCE_GROUP" \
      --gateway-name "$GATEWAY_NAME" \
      --name "$REDIRECT_NAME" \
      --type Permanent \
      --target-listener "$HTTPS_LISTENER_NAME" \
      --include-path true \
      --include-query-string true \
      --output none 2>/dev/null || warn "Redirect config may already exist."
    ok "Redirect configuration created."

    info "Updating HTTP rule to redirect..."
    az network application-gateway rule update \
      --resource-group "$RESOURCE_GROUP" \
      --gateway-name "$GATEWAY_NAME" \
      --name "$HTTP_RULE_NAME" \
      --redirect-config "$REDIRECT_NAME" \
      --output none 2>/dev/null || warn "Could not update HTTP rule — may need manual update."
    ok "HTTP rule updated."
  fi
fi

# ─── Done ────────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
ok "Key Vault certificate setup complete!"
echo "═══════════════════════════════════════════════════════════"
echo ""
info "Resources configured:"
info "  Key Vault cert:     https://portal.azure.com/#@/resource${KV_ID}/certificates"
info "  App Gateway:        $GATEWAY_NAME"
info "  Secret ID:          $SECRET_ID"
echo ""
info "Certificate rotation:"
info "  Import a new cert version to Key Vault with the same name ('$CERT_NAME')."
info "  App GW auto-refreshes from the versionless secret ID within ~4 hours."
info "  To force: stop + start the App Gateway in Portal or CLI."
echo ""
if [[ "$SETUP_HTTPS" == false ]]; then
  warn "HTTPS listener was NOT configured. To add it:"
  warn "  Re-run with --setup-https, or configure manually in Portal."
  warn "  See ssl_certs/README.md § 'Adding HTTPS Routing After Initial Deploy'"
fi
