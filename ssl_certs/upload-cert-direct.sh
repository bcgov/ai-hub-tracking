#!/bin/bash
set -euo pipefail

# Upload SSL Certificate Directly to App Gateway (No Key Vault)
#
# Uploads a PFX file directly to the Application Gateway's SSL certificate store.
# Optionally creates/updates the HTTPS listener and routing rules.
#
# Usage:
#   ./upload-cert-direct.sh [options]
#   ./upload-cert-direct.sh --env prod --pfx path/to/cert.pfx --password SECRET
#   ./upload-cert-direct.sh -i                          # Interactive mode
#
# Options:
#   -i, --interactive       Run in interactive mode (prompt for all inputs)
#   -e, --env ENV           Environment: test or prod (required)
#   -p, --pfx FILE          Path to the PFX certificate file (required)
#   -w, --password PASS     PFX password (prompted securely if omitted)
#   -n, --cert-name NAME    Certificate name in App GW (default: api-{env}-cert)
#   -g, --resource-group RG Resource group (default: ai-services-hub-{env})
#   --gateway-name NAME     App Gateway name (default: ai-services-hub-{env}-appgw)
#   --setup-https           Also create HTTPS listener + routing rules
#   --dry-run               Show what would be done without making changes
#   -h, --help              Display help and exit

# ─── Defaults ────────────────────────────────────────────────────────────────
INTERACTIVE=false
ENV=""
PFX_FILE=""
PFX_PASSWORD=""
CERT_NAME=""
RESOURCE_GROUP=""
GATEWAY_NAME=""
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
  sed -n '3,25p' "$0" | sed 's/^# \?//'
  exit 0
}

# ─── Parse arguments ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--interactive)   INTERACTIVE=true; shift ;;
    -e|--env)           ENV="$2"; shift 2 ;;
    -p|--pfx)           PFX_FILE="$2"; shift 2 ;;
    -w|--password)      PFX_PASSWORD="$2"; shift 2 ;;
    -n|--cert-name)     CERT_NAME="$2"; shift 2 ;;
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --gateway-name)     GATEWAY_NAME="$2"; shift 2 ;;
    --setup-https)      SETUP_HTTPS=true; shift ;;
    --dry-run)          DRY_RUN=true; shift ;;
    -h|--help)          display_help ;;
    *)                  err "Unknown option: $1"; display_help ;;
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
CERT_NAME="${CERT_NAME:-api-${ENV}-cert}"

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

# PFX password
if [[ -z "$PFX_PASSWORD" ]]; then
  if [[ "$INTERACTIVE" == false ]]; then
    echo -e "\nEnter the PFX password:"
  else
    echo -e "\nEnter the PFX password for $(basename "$PFX_FILE"):"
  fi
  read -rs PFX_PASSWORD
  echo ""
fi

# Setup HTTPS?
if [[ "$INTERACTIVE" == true && "$SETUP_HTTPS" == false ]]; then
  echo -e "\nAlso create HTTPS listener and routing rules? [y/N]"
  read -r ANSWER
  [[ "$ANSWER" =~ ^[Yy] ]] && SETUP_HTTPS=true
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "  Direct PFX Upload to App Gateway"
echo "═══════════════════════════════════════════════════════════"
info "Environment:    $ENV"
info "Domain:         $DOMAIN"
info "Resource Group: $RESOURCE_GROUP"
info "Gateway:        $GATEWAY_NAME"
info "Cert Name:      $CERT_NAME"
info "PFX File:       $PFX_FILE"
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

# Detect whether openssl pkcs12 supports the -legacy flag (needed for some PFX files with OpenSSL 3.x)
PKCS12_LEGACY_FLAG=""
if openssl pkcs12 -help 2>&1 | grep -q -- "-legacy"; then
  PKCS12_LEGACY_FLAG="-legacy"
fi

info "Validating PFX file..."
if ! openssl pkcs12 ${PKCS12_LEGACY_FLAG} -in "$PFX_FILE" -info -nokeys -passin "pass:${PFX_PASSWORD}" >/dev/null 2>&1; then
  err "Failed to read PFX file. Check the file and password."
  exit 1
fi
ok "PFX file is valid."

CERT_SUBJECT=$(openssl pkcs12 ${PKCS12_LEGACY_FLAG} -in "$PFX_FILE" -clcerts -nokeys -passin "pass:${PFX_PASSWORD}" 2>/dev/null | \
  openssl x509 -noout -subject 2>/dev/null | sed 's/subject=//')
CERT_EXPIRY=$(openssl pkcs12 ${PKCS12_LEGACY_FLAG} -in "$PFX_FILE" -clcerts -nokeys -passin "pass:${PFX_PASSWORD}" 2>/dev/null | \
  openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
info "Certificate subject: $CERT_SUBJECT"
info "Certificate expires: $CERT_EXPIRY"

info "Checking Azure CLI login..."
if ! az account show >/dev/null 2>&1; then
  err "Not logged in to Azure CLI. Run 'az login' first."
  exit 1
fi
ok "Azure CLI authenticated."

info "Checking App Gateway exists..."
if ! az network application-gateway show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$GATEWAY_NAME" \
  --query "name" -o tsv >/dev/null 2>&1; then
  err "App Gateway '$GATEWAY_NAME' not found in RG '$RESOURCE_GROUP'."
  exit 1
fi
ok "App Gateway found."

# ─── Upload certificate ─────────────────────────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
  warn "[DRY RUN] Would upload SSL cert '$CERT_NAME' to '$GATEWAY_NAME'"
else
  info "Uploading SSL certificate '$CERT_NAME'..."

  # Check if cert already exists
  EXISTING=$(az network application-gateway ssl-cert list \
    --resource-group "$RESOURCE_GROUP" \
    --gateway-name "$GATEWAY_NAME" \
    --query "[?name=='${CERT_NAME}'].name" -o tsv 2>/dev/null || true)

  if [[ -n "$EXISTING" ]]; then
    warn "Certificate '$CERT_NAME' already exists — updating..."
    az network application-gateway ssl-cert update \
      --resource-group "$RESOURCE_GROUP" \
      --gateway-name "$GATEWAY_NAME" \
      --name "$CERT_NAME" \
      --cert-file "$PFX_FILE" \
      --cert-password "$PFX_PASSWORD" \
      --output none
  else
    az network application-gateway ssl-cert create \
      --resource-group "$RESOURCE_GROUP" \
      --gateway-name "$GATEWAY_NAME" \
      --name "$CERT_NAME" \
      --cert-file "$PFX_FILE" \
      --cert-password "$PFX_PASSWORD" \
      --output none
  fi
  ok "SSL certificate uploaded."
fi

# ─── Setup HTTPS listener + routing (optional) ──────────────────────────────
if [[ "$SETUP_HTTPS" == true ]]; then
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
ok "Certificate upload complete!"
echo "═══════════════════════════════════════════════════════════"
echo ""
info "Verify in Azure Portal:"
info "  → Application Gateways → $GATEWAY_NAME → Listeners"
echo ""
if [[ "$SETUP_HTTPS" == false ]]; then
  warn "HTTPS listener was NOT configured. To add it:"
  warn "  Re-run with --setup-https, or configure manually in Portal."
  warn "  See ssl_certs/README.md § 'Adding HTTPS Routing After Initial Deploy'"
fi
