#!/usr/bin/env bash
# =============================================================================
# bastion-proxy.sh — SOCKS5 proxy via Azure Bastion
# =============================================================================
#
# Creates a SOCKS5 proxy on your local machine by tunnelling through Azure
# Bastion to the jumpbox VM. All traffic routed through the proxy is resolved
# and forwarded by the jumpbox, giving access to private PaaS endpoints
# without a VPN.
#
# A single SOCKS5 port can forward traffic to ANY hostname the jumpbox can
# reach (CosmosDB, PostgreSQL, Redis, Azure OpenAI, AI Search, etc.).
# No per-service configuration is needed. See the jumpbox README for tool
# usage examples.
#
# PREREQUISITES
#   Azure CLI:         https://learn.microsoft.com/cli/azure/install-azure-cli
#   bastion extension: az extension add --name bastion
#   ssh extension:     az extension add --name ssh   (AAD auth only)
#   Standard SKU Azure Bastion with native tunnelling enabled
#   "Virtual Machine Administrator Login" RBAC role on the VM (AAD auth)
#
# IMPORTANT — BROWSER AUTHENTICATION
#   When the device code URL appears, open it in an Incognito / Private Browsing
#   window. If you use a regular browser tab, the browser may silently sign in
#   with a cached personal Microsoft account and authenticate as the wrong user.
#
#   Chrome/Edge: Ctrl+Shift+N  |  Firefox: Ctrl+Shift+P  |  Safari: Shift+⌘+N
#
# USAGE
#   ./scripts/bastion-proxy.sh -g <resource-group> -b <bastion-name> -v <vm-name>
#
# OPTIONS
#   -g, --resource-group    Resource group containing Bastion and VM   [required]
#   -b, --bastion-name      Name of the Azure Bastion host             [required]
#   -v, --vm-name           Name of the jumpbox VM                     [required]
#   -p, --port              Starting SOCKS5 port (default: 8228)       [optional]
#       --auth-type         AAD or ssh-key (default: AAD)              [optional]
#       --ssh-key           SSH private key path (ssh-key auth)        [optional]
#       --username          SSH username (ssh-key auth)                [optional]
#   -h, --help              Show this help and exit
#
# EXAMPLES
#   # Entra ID (AAD) auth — recommended:
#   ./scripts/bastion-proxy.sh -g tools-rg -b tools-bastion -v tools-jumpbox
#
#   # SSH key auth — break-glass fallback:
#   ./scripts/bastion-proxy.sh -g tools-rg -b tools-bastion -v tools-jumpbox \
#     --auth-type ssh-key \
#     --username <admin_username> \
#     --ssh-key ../sensitive/jumpbox_ssh_key.pem
#
#   # Derive names from Terraform outputs (run from initial-setup/infra/):
#   ./scripts/bastion-proxy.sh \
#     -g "$(terraform output -raw resource_group_name)" \
#     -b "$(terraform output -raw jumpbox_vm_name | sed 's/-jumpbox$/-bastion/')" \
#     -v "$(terraform output -raw jumpbox_vm_name)"
#
# =============================================================================

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────

SUBSCRIPTION_ID="eb733692-257d-40c8-bd7b-372e689f3b7f"
DEFAULT_SOCKS_PORT=8228
LOGIN_TIMEOUT=300   # max seconds to wait for device code login to complete

# ── Colours (only when writing to a terminal) ─────────────────────────────────

if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; RESET=''
fi

# ── Helpers ───────────────────────────────────────────────────────────────────

err()  { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
info() { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()   { echo -e "${GREEN}[ OK ]${RESET}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${RESET}  $*"; }

usage() {
  sed -n '/^# USAGE/,/^# =/p' "$0" | sed 's/^# \?//' | sed '/^=\{5,\}/d'
  exit 0
}

# ── Port utilities ────────────────────────────────────────────────────────────

is_port_in_use() {
  local port=$1
  if command -v ss &>/dev/null; then
    ss -tlnp 2>/dev/null | grep -qE ":${port}[[:space:]]"
  elif command -v lsof &>/dev/null; then
    lsof -iTCP:"$port" -sTCP:LISTEN &>/dev/null
  else
    nc -z 127.0.0.1 "$port" &>/dev/null
  fi
}

find_free_port() {
  local port=$1
  local limit=$((port + 50))
  while [[ $port -le $limit ]]; do
    if ! is_port_in_use "$port"; then
      echo "$port"
      return 0
    fi
    port=$((port + 1))
  done
  err "No free port found in range $1–$limit"
  exit 1
}

# ── Argument defaults ─────────────────────────────────────────────────────────

RESOURCE_GROUP=""
BASTION_NAME=""
VM_NAME=""
START_PORT=$DEFAULT_SOCKS_PORT
AUTH_TYPE="AAD"
SSH_KEY=""
SSH_USERNAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -g|--resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    -b|--bastion-name)   BASTION_NAME="$2";   shift 2 ;;
    -v|--vm-name)        VM_NAME="$2";        shift 2 ;;
    -p|--port)           START_PORT="$2";     shift 2 ;;
    --auth-type)         AUTH_TYPE="${2^^}";  shift 2 ;;  # normalise to uppercase
    --ssh-key)           SSH_KEY="$2";        shift 2 ;;
    --username)          SSH_USERNAME="$2";   shift 2 ;;
    -h|--help)           usage ;;
    *) err "Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Validate arguments ────────────────────────────────────────────────────────

[[ -z "$RESOURCE_GROUP" ]] && { err "--resource-group (-g) is required"; exit 1; }
[[ -z "$BASTION_NAME" ]]   && { err "--bastion-name (-b) is required";   exit 1; }
[[ -z "$VM_NAME" ]]        && { err "--vm-name (-v) is required";        exit 1; }

case "$AUTH_TYPE" in
  AAD) ;;
  SSH-KEY)
    AUTH_TYPE="ssh-key"
    [[ -z "$SSH_KEY" ]]      && { err "--ssh-key is required for --auth-type ssh-key";  exit 1; }
    [[ -z "$SSH_USERNAME" ]] && { err "--username is required for --auth-type ssh-key"; exit 1; }
    [[ ! -f "$SSH_KEY" ]]    && { err "SSH key file not found: $SSH_KEY";               exit 1; }
    ;;
  *)
    err "Unknown --auth-type '${AUTH_TYPE}'. Use 'AAD' or 'ssh-key'."
    exit 1
    ;;
esac

# ── Prerequisite checks ───────────────────────────────────────────────────────

info "Checking prerequisites..."

command -v az &>/dev/null || {
  err "Azure CLI (az) is not installed."
  err "Install: https://learn.microsoft.com/cli/azure/install-azure-cli"
  exit 1
}

if ! az extension show --name bastion &>/dev/null 2>&1; then
  info "Installing Azure CLI 'bastion' extension..."
  az extension add --name bastion --yes
fi

if [[ "$AUTH_TYPE" == "AAD" ]] && ! az extension show --name ssh &>/dev/null 2>&1; then
  info "Installing Azure CLI 'ssh' extension..."
  az extension add --name ssh --yes
fi

ok "Prerequisites satisfied"

# ── Authentication ────────────────────────────────────────────────────────────

info "Checking Azure CLI login status..."
if ! az account show &>/dev/null 2>&1; then
  echo ""
  info "Not logged in. Starting device code authentication..."
  echo ""
  warn "BROWSER TIP: Open the device code URL in an Incognito / Private Browsing"
  warn "             window to prevent the browser signing in as the wrong account."
  warn "             Chrome/Edge: Ctrl+Shift+N  |  Firefox: Ctrl+Shift+P"
  echo ""
  az login --use-device-code
  echo ""
  info "Waiting for login to complete..."
  ELAPSED=0
  until az account show &>/dev/null 2>&1; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    if [[ $ELAPSED -ge $LOGIN_TIMEOUT ]]; then
      err "Login timed out after ${LOGIN_TIMEOUT}s"
      exit 1
    fi
  done
else
  warn "Already logged in. Azure CLI sessions expire 12h after 'az login'."
  warn "Re-run this script if you encounter authentication errors."
fi

# Record authentication time and compute the 12h Entra ID session expiry.
# If already logged in, LOGIN_EPOCH is set to now (the original login time
# is not exposed by az CLI). Watch for auth errors if usage approaches 12h.
LOGIN_EPOCH=$(date +%s)
EXPIRE_EPOCH=$((LOGIN_EPOCH + 43200))
LOGIN_AT=$(date -d  "@${LOGIN_EPOCH}"  "+%H:%M %Z" 2>/dev/null \
        || date -r  "${LOGIN_EPOCH}"    "+%H:%M %Z" 2>/dev/null \
        || date                         "+%H:%M %Z")
EXPIRE_AT=$(date -d "@${EXPIRE_EPOCH}" "+%H:%M %Z" 2>/dev/null \
         || date -r  "${EXPIRE_EPOCH}"  "+%H:%M %Z" 2>/dev/null \
         || echo "12h from now")

ok "Authenticated to Azure CLI"

# ── Subscription ──────────────────────────────────────────────────────────────

info "Switching to subscription ${SUBSCRIPTION_ID}..."
az account set --subscription "$SUBSCRIPTION_ID"
SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
ok "Using: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"

# ── Resolve VM resource ID ────────────────────────────────────────────────────

info "Resolving VM '${VM_NAME}' in resource group '${RESOURCE_GROUP}'..."
VM_ID=$(az vm show \
  --name "$VM_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query id \
  --output tsv 2>/dev/null) || {
  err "VM '${VM_NAME}' not found in resource group '${RESOURCE_GROUP}'"
  exit 1
}
ok "VM found"

# ── VM running check ──────────────────────────────────────────────────────────

VM_STATE=$(az vm get-instance-view \
  --name "$VM_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "instanceView.statuses[?contains(code,'PowerState')].displayStatus | [0]" \
  --output tsv 2>/dev/null || echo "unknown")

if [[ "$VM_STATE" != "VM running" ]]; then
  warn "VM is not running (current state: ${VM_STATE:-unknown})"
  read -rp "  Start the VM now? [y/N]: " START_VM
  if [[ "${START_VM,,}" == "y" ]]; then
    info "Starting VM..."
    az vm start --name "$VM_NAME" --resource-group "$RESOURCE_GROUP"
    info "Waiting for VM to reach running state..."
    az vm wait \
      --name "$VM_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --custom "instanceView.statuses[?code=='PowerState/running']"
    ok "VM is running"
  else
    err "VM must be running to create a proxy tunnel. Exiting."
    exit 1
  fi
fi

# ── Bastion health check ──────────────────────────────────────────────────────

info "Checking Bastion host '${BASTION_NAME}'..."
BASTION_STATE=$(az network bastion show \
  --name "$BASTION_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "provisioningState" \
  --output tsv 2>/dev/null || echo "NotFound")

case "$BASTION_STATE" in
  Succeeded)
    ok "Bastion is ready"
    ;;
  Updating|Creating)
    info "Bastion is provisioning (state: ${BASTION_STATE}). Waiting..."
    while true; do
      sleep 15
      BASTION_STATE=$(az network bastion show \
        --name "$BASTION_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "provisioningState" \
        --output tsv 2>/dev/null)
      [[ "$BASTION_STATE" == "Succeeded" ]] && break
      if [[ "$BASTION_STATE" == "Failed" ]]; then
        err "Bastion provisioning failed. Check the Azure portal."
        exit 1
      fi
    done
    ok "Bastion is ready"
    ;;
  NotFound)
    err "Bastion '${BASTION_NAME}' not found in resource group '${RESOURCE_GROUP}'"
    exit 1
    ;;
  *)
    err "Bastion is in unexpected state: '${BASTION_STATE}'. Check the Azure portal."
    exit 1
    ;;
esac

# ── Port selection ────────────────────────────────────────────────────────────

SOCKS_PORT=$(find_free_port "$START_PORT")
if [[ "$SOCKS_PORT" -ne "$START_PORT" ]]; then
  warn "Port $START_PORT is in use. Using port $SOCKS_PORT instead."
fi

# ── Print proxy connection details ────────────────────────────────────────────

echo ""
echo -e "  ${BOLD}${GREEN}SOCKS5 proxy ready on localhost:${SOCKS_PORT}${RESET}"
echo ""
echo -e "  ${BOLD}export HTTPS_PROXY=socks5://localhost:${SOCKS_PORT}${RESET}"
echo -e "  ${BOLD}export HTTP_PROXY=socks5://localhost:${SOCKS_PORT}${RESET}"
echo ""
echo -e "  Or per-command:  curl --socks5-hostname localhost:${SOCKS_PORT} <url>"
echo ""
echo -e "  ${BOLD}Session started :${RESET} ${LOGIN_AT}"
echo -e "  ${BOLD}Session expires :${RESET} ${EXPIRE_AT}  (Entra ID 12h limit)"
echo -e "  You will be warned 1 hour before expiry and the tunnel will stop at expiry."
echo ""
echo -e "  Connecting via Bastion (auth: ${AUTH_TYPE}). Press ${BOLD}Ctrl+C${RESET} to stop."
echo ""

# ── SSH options passed through to the underlying SSH process ──────────────────
#
# -D  SOCKS5 dynamic port forwarding on the chosen local port
# -N  do not execute a remote command (keep connection open for forwarding)
# -q  quiet mode (suppress banners and warnings)
# StrictHostKeyChecking=no   acceptable here: Bastion already provides mutual
#                            auth; the VM has no public surface to MITM
# ServerAliveInterval/Count  keep the tunnel alive through idle periods

SSH_OPTS="-D ${SOCKS_PORT} -N -q \
  -o StrictHostKeyChecking=no \
  -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3"

# ── Session expiry timer ──────────────────────────────────────────────────────────────
#
# Background process: warns 1h before the 12h Entra ID session limit and
# terminates the tunnel if the session expires.

_session_timer() {
  local expire_epoch=$1
  local parent_pid=$2
  local warned=false
  local warn_epoch=$((expire_epoch - 3600))   # 1h before expiry

  while true; do
    sleep 60
    local now
    now=$(date +%s)

    if [[ $now -ge $expire_epoch ]]; then
      echo "" >&2
      err "Azure CLI session has expired (12h limit). Stopping proxy." >&2
      err "Run the script again to re-authenticate." >&2
      kill -TERM "$parent_pid" 2>/dev/null || true
      return
    elif [[ $now -ge $warn_epoch && "$warned" == "false" ]]; then
      warned=true
      echo "" >&2
      warn "Azure CLI session expires in ~60 minutes. Restart the script soon." >&2
    fi
  done
}

# ── Cleanup handler ──────────────────────────────────────────────────────────────────────────────

TIMER_PID=""

cleanup() {
  local exit_code=$?
  [[ -n "${TIMER_PID}" ]] && kill "${TIMER_PID}" 2>/dev/null || true
  echo ""
  if [[ $exit_code -eq 0 || $exit_code -eq 130 ]]; then
    ok "SOCKS5 proxy stopped."
  else
    warn "SOCKS5 proxy exited with code $exit_code."
  fi
}
trap cleanup EXIT

# ── Start SOCKS5 proxy ────────────────────────────────────────────────────────
#
# az network bastion ssh establishes an SSH session through Azure Bastion.
# --ssh-args are forwarded to the underlying SSH client unchanged.
# The process blocks until the connection is closed (Ctrl+C).
# Start the session expiry timer in the background before the tunnel blocks.
_session_timer "$EXPIRE_EPOCH" "$$" &
TIMER_PID=$!
if [[ "$AUTH_TYPE" == "AAD" ]]; then
  az network bastion ssh \
    --name "$BASTION_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --target-resource-id "$VM_ID" \
    --auth-type "AAD" \
    -- $SSH_OPTS
else
  az network bastion ssh \
    --name "$BASTION_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --target-resource-id "$VM_ID" \
    --auth-type "ssh-key" \
    --username "$SSH_USERNAME" \
    --ssh-key "$SSH_KEY" \
    -- $SSH_OPTS
fi
