#!/usr/bin/env bash
# =============================================================================
# APIM SUBSCRIPTION KEY ROTATION SCRIPT
# =============================================================================
# Rotates APIM subscription keys for all enabled tenants using an
# alternating primary/secondary pattern:
#
#   Week 1: Regenerate SECONDARY key
#     - Tenants continue using PRIMARY (still valid, untouched)
#     - New SECONDARY stored in hub Key Vault for tenants to fetch when ready
#
#   Week 2: Regenerate PRIMARY key
#     - Tenants continue using SECONDARY (regenerated last week, still valid)
#     - New PRIMARY stored in hub Key Vault for tenants to fetch when ready
#
#   ...alternates indefinitely. One key is ALWAYS valid.
#
# All keys are stored in a centralized hub Key Vault with tenant-prefixed
# secret names: {tenant}-apim-primary-key, {tenant}-apim-secondary-key,
# {tenant}-apim-rotation-metadata. This scales to 1000+ tenants.
#
# Usage (GHA or local):
#   ./rotate-apim-keys.sh --environment <env> --config-dir <path> [--dry-run] [--verbose]
#
# Config resolution order:
#   1. params/{env}/shared.tfvars  (rotation_enabled, rotation_interval_days)
#   2. Naming convention            (resource group, APIM, hub KV from APP_NAME + env)
#   3. Environment variables         (APP_NAME, RESOURCE_GROUP, APIM_NAME, HUB_KEYVAULT_NAME)
#   4. Azure CLI discovery           (fallback when convention + env vars are absent)
#
# In GHA there is no terraform.tfvars; set APP_NAME as a workflow-level env var
# and the script derives everything else from convention + shared.tfvars.
#
# Prerequisites:
#   - Azure CLI authenticated (az login / OIDC)
#   - jq installed
# =============================================================================

set -euo pipefail

# =============================================================================
# CONFIGURATION
# =============================================================================
SCRIPT_NAME="$(basename "$0")"
LOG_PREFIX="[key-rotation]"

# Defaults
DRY_RUN=false
VERBOSE=false
FORCE=false
ENVIRONMENT=""
CONFIG_DIR=""

# Resolved at runtime
RESOURCE_GROUP=""
APIM_NAME=""
HUB_KEYVAULT_NAME=""
ROTATION_INTERVAL_DAYS=7

# =============================================================================
# LOGGING
# =============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m'

log_info()  { echo -e "${GRAY}$(date -u +'%Y-%m-%dT%H:%M:%SZ')${NC} ${BLUE}${LOG_PREFIX} [INFO]${NC}  $*"; }
log_success() { echo -e "${GRAY}$(date -u +'%Y-%m-%dT%H:%M:%SZ')${NC} ${GREEN}${LOG_PREFIX} [SUCCESS]${NC} $*"; }
log_warn()  { echo -e "${GRAY}$(date -u +'%Y-%m-%dT%H:%M:%SZ')${NC} ${YELLOW}${LOG_PREFIX} [WARN]${NC}  $*" >&2; }
log_error() { echo -e "${GRAY}$(date -u +'%Y-%m-%dT%H:%M:%SZ')${NC} ${RED}${LOG_PREFIX} [ERROR]${NC} $*" >&2; }
log_debug() { if [[ "${VERBOSE}" == "true" ]]; then echo -e "${GRAY}$(date -u +'%Y-%m-%dT%H:%M:%SZ')${NC} ${GRAY}${LOG_PREFIX} [DEBUG]${NC} $*"; fi; }

iso_utc_now() {
    date -u +'%Y-%m-%dT%H:%M:%SZ'
}

iso_utc_plus_days() {
    local days="$1"
    local base_iso="${2:-}"

    if [[ -n "${base_iso}" ]]; then
        if out=$(date -u -d "${base_iso} + ${days} days" +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null); then
            echo "${out}"
            return 0
        fi

        if command -v python3 >/dev/null 2>&1; then
            python3 - "${base_iso}" "${days}" <<'PY'
import sys
from datetime import datetime, timedelta, timezone

base_iso = sys.argv[1]
days = int(sys.argv[2])
dt = datetime.fromisoformat(base_iso.replace("Z", "+00:00"))
target = dt + timedelta(days=days)
print(target.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
            return $?
        fi

        return 1
    fi

    if out=$(date -u -d "+${days} days" +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null); then
        echo "${out}"
        return 0
    fi

    if out=$(date -u -v+"${days}"d +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null); then
        echo "${out}"
        return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "${days}" <<'PY'
import sys
from datetime import datetime, timedelta, timezone

days = int(sys.argv[1])
target = datetime.now(timezone.utc) + timedelta(days=days)
print(target.strftime("%Y-%m-%dT%H:%M:%SZ"))
PY
        return $?
    fi

    return 1
}

iso_to_epoch() {
    local iso_ts="$1"

    if out=$(date -u -d "${iso_ts}" +%s 2>/dev/null); then
        echo "${out}"
        return 0
    fi

    if out=$(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "${iso_ts}" +%s 2>/dev/null); then
        echo "${out}"
        return 0
    fi

    if command -v python3 >/dev/null 2>&1; then
        python3 - "${iso_ts}" <<'PY'
import sys
from datetime import datetime

iso_ts = sys.argv[1]
dt = datetime.fromisoformat(iso_ts.replace("Z", "+00:00"))
print(int(dt.timestamp()))
PY
        return $?
    fi

    return 1
}

# =============================================================================
# USAGE
# =============================================================================
usage() {
    cat <<EOF
Usage: ${SCRIPT_NAME} [options]

Rotate APIM subscription keys for all enabled tenants.
Self-discovers APIM, hub Key Vault, and rotation config from tfvars files.

Required:
  --environment, -e <name>       Target environment (dev, test, prod)
  --config-dir, -c <path>        Path to infra-ai-hub directory (contains terraform.tfvars)

Optional:
  --dry-run                      Show what would happen without making changes
  --verbose                      Enable debug logging
    --force                        Rotate now even if interval has not elapsed
  --help, -h                     Show this help message

Examples:
  # Run from repo root (GHA or local)
  ${SCRIPT_NAME} --environment dev --config-dir infra-ai-hub --verbose

  # Dry run for prod
  ${SCRIPT_NAME} -e prod -c infra-ai-hub --dry-run --verbose

  # Local debugging (after az login)
  ${SCRIPT_NAME} -e dev -c ./infra-ai-hub --verbose --dry-run
EOF
    exit 0
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --environment|-e) ENVIRONMENT="$2"; shift 2 ;;
        --config-dir|-c)  CONFIG_DIR="$2"; shift 2 ;;
        --dry-run)        DRY_RUN=true; shift ;;
        --verbose)        VERBOSE=true; shift ;;
        --force)          FORCE=true; shift ;;
        --help|-h)        usage ;;
        *) log_error "Unknown argument: $1"; usage ;;
    esac
done

if [[ -z "${ENVIRONMENT}" ]] || [[ -z "${CONFIG_DIR}" ]]; then
    log_error "Missing required arguments: --environment and --config-dir"
    usage
fi

# =============================================================================
# CONFIG DISCOVERY (shared.tfvars + naming convention — no terraform.tfvars needed)
# =============================================================================
discover_config() {
    local tfvars="${CONFIG_DIR}/terraform.tfvars"
    local shared_tfvars="${CONFIG_DIR}/params/${ENVIRONMENT}/shared.tfvars"

    # -------------------------------------------------------------------------
    # Config source precedence:
    #   shared.tfvars > naming convention > env vars > Azure CLI fallback
    # -------------------------------------------------------------------------
    local app_name="${APP_NAME:-}"

    if [[ -z "${app_name}" ]] && [[ -f "${tfvars}" ]]; then
        app_name=$(grep -oP 'app_name\s*=\s*"\K[^"]+' "${tfvars}" 2>/dev/null || echo "")
    fi

    RESOURCE_GROUP="${RESOURCE_GROUP:-}"
    if [[ -z "${RESOURCE_GROUP}" ]] && [[ -n "${app_name}" ]]; then
        RESOURCE_GROUP="${app_name}-${ENVIRONMENT}"
    fi

    if [[ -z "${RESOURCE_GROUP}" ]]; then
        log_error "Unable to resolve RESOURCE_GROUP. Provide RESOURCE_GROUP env var or app_name in ${tfvars}."
        exit 1
    fi
    log_debug "Resource group: ${RESOURCE_GROUP}"

    # Rotation toggle/interval: shared.tfvars when available, else env vars
    local rotation_enabled="${ROTATION_ENABLED:-false}"
    ROTATION_INTERVAL_DAYS="${ROTATION_INTERVAL_DAYS:-7}"

    if [[ -f "${shared_tfvars}" ]]; then
        rotation_enabled=$(grep -oP 'rotation_enabled\s*=\s*\K\w+' "${shared_tfvars}" 2>/dev/null || echo "${rotation_enabled}")
        ROTATION_INTERVAL_DAYS=$(grep -oP 'rotation_interval_days\s*=\s*\K\d+' "${shared_tfvars}" 2>/dev/null || echo "${ROTATION_INTERVAL_DAYS}")
    else
        log_warn "shared.tfvars not found at ${shared_tfvars}; using environment variables for rotation config"
    fi

    if [[ "${rotation_enabled}" != "true" ]]; then
        log_info "Rotation is disabled in ${shared_tfvars} (rotation_enabled = ${rotation_enabled})"
        log_info "Nothing to do. Exiting."
        exit 0
    fi
    log_debug "Rotation interval: ${ROTATION_INTERVAL_DAYS} days"

    # Discover APIM instance: env var → naming convention → Azure CLI fallback
    APIM_NAME="${APIM_NAME:-}"
    if [[ -z "${APIM_NAME}" ]] && [[ -n "${app_name}" ]]; then
        APIM_NAME="${app_name}-${ENVIRONMENT}-apim"
        log_debug "Derived APIM name from naming convention: ${APIM_NAME}"
    fi
    if [[ -z "${APIM_NAME}" ]]; then
        APIM_NAME=$(az apim list \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[0].name" -o tsv 2>/dev/null || echo "")
    fi

    if [[ -z "${APIM_NAME}" ]]; then
        log_error "No APIM instance found in resource group '${RESOURCE_GROUP}'"
        exit 1
    fi
    log_info "Discovered APIM: ${APIM_NAME}"

    # Discover hub Key Vault: env var → naming convention → Azure CLI fallback
    HUB_KEYVAULT_NAME="${HUB_KEYVAULT_NAME:-}"
    if [[ -z "${HUB_KEYVAULT_NAME}" ]] && [[ -n "${app_name}" ]]; then
        HUB_KEYVAULT_NAME="${app_name}-${ENVIRONMENT}-hkv"
        log_debug "Derived hub KV name from naming convention: ${HUB_KEYVAULT_NAME}"
    fi

    if [[ -z "${HUB_KEYVAULT_NAME}" ]]; then
        # Fallback: find any KV with "hub" in the name
        HUB_KEYVAULT_NAME=$(az keyvault list \
            --resource-group "${RESOURCE_GROUP}" \
            --query "[?contains(name, 'hub')].name" -o tsv 2>/dev/null | head -1)
    fi

    if [[ -z "${HUB_KEYVAULT_NAME}" ]]; then
        log_error "Hub Key Vault not found in resource group '${RESOURCE_GROUP}'"
        exit 1
    fi
    log_info "Discovered hub Key Vault: ${HUB_KEYVAULT_NAME}"
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# Get all APIM subscriptions for tenants (convention: display name ends with "Subscription")
# Returns lines in format: sub_id|tenant_name
# - sub_id: APIM subscription ID (GUID) used for API calls
# - tenant_name: extracted from product scope (e.g., "wlrs-water-form-assistant") used for KV secret naming
get_tenant_subscriptions() {
    az rest \
        --method GET \
        --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}/subscriptions?api-version=2024-05-01" \
    2>/dev/null | jq -r '.value[] | select(.properties.displayName | endswith("Subscription")) | .name + "|" + (.properties.scope | split("/") | last)' | sed 's/\r$//'
}

# Get subscription keys
get_subscription_details() {
    local sub_name="$1"
    az rest \
        --method POST \
        --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}/subscriptions/${sub_name}/listSecrets?api-version=2024-05-01" \
        2>/dev/null
}

# Regenerate primary key
regenerate_primary_key() {
    local sub_name="$1"
    az rest \
        --method POST \
        --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}/subscriptions/${sub_name}/regeneratePrimaryKey?api-version=2024-05-01" \
        2>/dev/null
}

# Regenerate secondary key
regenerate_secondary_key() {
    local sub_name="$1"
    az rest \
        --method POST \
        --url "https://management.azure.com/subscriptions/$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.ApiManagement/service/${APIM_NAME}/subscriptions/${sub_name}/regenerateSecondaryKey?api-version=2024-05-01" \
        2>/dev/null
}

# Read rotation metadata from hub Key Vault (tenant-prefixed secret name)
get_rotation_metadata() {
    local tenant_name="$1"
    local secret_name="${tenant_name}-apim-rotation-metadata"

    local secret_value
    local read_err
    read_err=$(az keyvault secret show \
        --vault-name "${HUB_KEYVAULT_NAME}" \
        --name "${secret_name}" \
        --query "value" -o tsv 2>&1) && secret_value="${read_err}" || {
        # Distinguish "not found" (first rotation) from actual errors
        if echo "${read_err}" | grep -qi "SecretNotFound\|not found"; then
            log_debug "No metadata secret found for ${tenant_name} — treating as first rotation"
            secret_value=""
        else
            log_warn "Failed to read rotation metadata from KV: ${secret_name}"
            log_warn "  ${read_err}"
            log_warn "  Treating as first rotation (may cause unexpected re-rotation)"
            secret_value=""
        fi
    }

    if [[ -z "${secret_value}" ]]; then
        # First rotation - no metadata yet
        echo '{"last_rotated_slot":"none","last_rotation_at":"never","rotation_number":0}'
    else
        echo "${secret_value}"
    fi
}

# Store rotation metadata in hub Key Vault
set_rotation_metadata() {
    local tenant_name="$1"
    local metadata_json="$2"
    local secret_name="${tenant_name}-apim-rotation-metadata"
    # Landing zone policy requires secrets to have a max validity period (90 days)
    local expires_on
    expires_on=$(iso_utc_plus_days 90) || {
        log_error "Failed to compute expiration timestamp for metadata secret"
        return 1
    }

    local err_output
    err_output=$(az keyvault secret set \
        --vault-name "${HUB_KEYVAULT_NAME}" \
        --name "${secret_name}" \
        --value "${metadata_json}" \
        --content-type "application/json" \
        --expires "${expires_on}" \
        --output none 2>&1) || {
        log_error "Failed to store rotation metadata in KV: ${secret_name}"
        log_error "  ${err_output}"
        return 1
    }
}

# Store a key in hub Key Vault (tenant-prefixed secret name)
store_key_in_vault() {
    local secret_name="$1"
    local key_value="$2"
    local tags="$3"  # space-separated key=value pairs
    # Landing zone policy requires secrets to have a max validity period (90 days)
    local expires_on
    expires_on=$(iso_utc_plus_days 90) || {
        log_error "Failed to compute expiration timestamp for secret: ${secret_name}"
        return 1
    }

    local -a tags_args=()
    if [[ -n "${tags}" ]]; then
        local -a tags_array=()
        read -r -a tags_array <<< "${tags}"
        tags_args=(--tags "${tags_array[@]}")
    fi

    local err_output
    err_output=$(az keyvault secret set \
        --vault-name "${HUB_KEYVAULT_NAME}" \
        --name "${secret_name}" \
        --value "${key_value}" \
        --content-type "text/plain" \
        "${tags_args[@]}" \
        --expires "${expires_on}" \
        --output none 2>&1) || {
        log_error "Failed to store key in KV: ${secret_name}"
        log_error "  ${err_output}"
        return 1
    }
}

# Check if rotation is due based on last rotation timestamp
is_rotation_due() {
    local last_rotation_at="$1"
    local interval_days="$2"

    if [[ "${last_rotation_at}" == "never" ]]; then
        echo "true"
        return
    fi

    local last_epoch
    last_epoch=$(iso_to_epoch "${last_rotation_at}" 2>/dev/null || echo "0")
    local now_epoch
    now_epoch=$(date -u +%s)
    local diff_days=$(( (now_epoch - last_epoch) / 86400 ))

    if [[ ${diff_days} -ge ${interval_days} ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# =============================================================================
# MAIN ROTATION LOGIC
# =============================================================================

rotate_tenant_key() {
    local sub_name="$1"            # e.g., "wlrs-water-form-assistant-subscription"
    local tenant_name="$2"         # e.g., "wlrs-water-form-assistant"

    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "Processing tenant: ${tenant_name} (subscription: ${sub_name})"

    # Step 1: Read rotation metadata from hub KV
    local metadata
    metadata=$(get_rotation_metadata "${tenant_name}")
    local last_rotated_slot
    last_rotated_slot=$(echo "${metadata}" | jq -r '.last_rotated_slot')
    local last_rotation_at
    last_rotation_at=$(echo "${metadata}" | jq -r '.last_rotation_at')
    local rotation_number
    rotation_number=$(echo "${metadata}" | jq -r '.rotation_number')

    log_info "Last rotated slot: ${last_rotated_slot}"
    log_info "Last rotation: ${last_rotation_at}"
    log_info "Rotation number: ${rotation_number}"

    # Step 2: Check if rotation is due
    local due
    due=$(is_rotation_due "${last_rotation_at}" "${ROTATION_INTERVAL_DAYS}")
    if [[ "${due}" == "false" ]] && [[ "${FORCE}" != "true" ]]; then
        local next_rotation_at
        next_rotation_at=$(iso_utc_plus_days "${ROTATION_INTERVAL_DAYS}" "${last_rotation_at}" 2>/dev/null || echo "unknown")
        log_info "Rotation not yet due. Next rotation at: ${next_rotation_at}"
        # Exit code 2 means intentionally skipped (interval not elapsed).
        return 2
    fi

    if [[ "${FORCE}" == "true" ]] && [[ "${due}" == "false" ]]; then
        log_warn "FORCE enabled: rotating before interval elapsed"
    else
        log_info "Rotation is due - proceeding"
    fi

    # Step 3: Determine which slot to rotate THIS time (alternate from last)
    # Secondary-first policy:
    # - First rotation (last_rotated_slot=none): rotate secondary
    # - Then alternate: primary, secondary, primary, ...
    local slot_to_rotate
    if [[ "${last_rotated_slot}" == "secondary" ]]; then
        slot_to_rotate="primary"
    else
        slot_to_rotate="secondary"
    fi

    local safe_slot
    if [[ "${slot_to_rotate}" == "primary" ]]; then
        safe_slot="secondary"
    else
        safe_slot="primary"
    fi

    log_info "Slot to rotate: ${slot_to_rotate} (tenants safe on: ${safe_slot})"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_info "[DRY RUN] Would regenerate ${slot_to_rotate} key for ${sub_name}"
        log_info "[DRY RUN] Tenants continue using ${safe_slot} key (untouched)"
        log_info "[DRY RUN] Would store keys in hub KV: ${HUB_KEYVAULT_NAME}"
        log_info "[DRY RUN]   ${tenant_name}-apim-primary-key"
        log_info "[DRY RUN]   ${tenant_name}-apim-secondary-key"
        log_info "[DRY RUN]   ${tenant_name}-apim-rotation-metadata"
        return 0
    fi

    # Step 4: Regenerate the target slot
    log_info "Regenerating ${slot_to_rotate} key..."
    if [[ "${slot_to_rotate}" == "primary" ]]; then
        regenerate_primary_key "${sub_name}"
    else
        regenerate_secondary_key "${sub_name}"
    fi

    # Brief pause for APIM to propagate the new key
    log_info "Waiting 10 seconds for key propagation..."
    sleep 10

    # Step 5: Read both key values after regeneration
    local secrets
    secrets=$(get_subscription_details "${sub_name}")
    local new_primary_key
    if ! new_primary_key=$(echo "${secrets}" | jq -er '.primaryKey'); then
        log_error "Failed to extract primaryKey from subscription details for '${sub_name}'. Aborting without updating Key Vault."
        return 1
    fi
    if [[ -z "${new_primary_key}" || "${new_primary_key}" == "null" ]]; then
        log_error "primaryKey is empty for '${sub_name}'. Aborting without updating Key Vault."
        return 1
    fi

    local new_secondary_key
    if ! new_secondary_key=$(echo "${secrets}" | jq -er '.secondaryKey'); then
        log_error "Failed to extract secondaryKey from subscription details for '${sub_name}'. Aborting without updating Key Vault."
        return 1
    fi
    if [[ -z "${new_secondary_key}" || "${new_secondary_key}" == "null" ]]; then
        log_error "secondaryKey is empty for '${sub_name}'. Aborting without updating Key Vault."
        return 1
    fi

    # Step 6: Store BOTH keys in hub Key Vault (tenant-prefixed)
    local now_iso
    now_iso=$(iso_utc_now)
    local next_rotation_iso
    next_rotation_iso=$(iso_utc_plus_days "${ROTATION_INTERVAL_DAYS}") || {
        log_error "Failed to compute next rotation timestamp"
        return 1
    }
    local new_rotation_number=$(( rotation_number + 1 ))

    log_info "Storing keys in hub Key Vault (${HUB_KEYVAULT_NAME})..."

    store_key_in_vault \
        "${tenant_name}-apim-primary-key" \
        "${new_primary_key}" \
        "updated-at=${now_iso} rotated=${slot_to_rotate} rotation-number=${new_rotation_number}" || return 1

    store_key_in_vault \
        "${tenant_name}-apim-secondary-key" \
        "${new_secondary_key}" \
        "updated-at=${now_iso} rotated=${slot_to_rotate} rotation-number=${new_rotation_number}" || return 1

    # Step 7: Update rotation metadata in hub KV
    local new_metadata
    new_metadata=$(jq -n \
        --arg last_rotated_slot "${slot_to_rotate}" \
        --arg last_rotation_at "${now_iso}" \
        --arg next_rotation_at "${next_rotation_iso}" \
        --argjson rotation_number "${new_rotation_number}" \
        --arg safe_slot "${safe_slot}" \
        '{
            last_rotated_slot: $last_rotated_slot,
            last_rotation_at: $last_rotation_at,
            next_rotation_at: $next_rotation_at,
            rotation_number: $rotation_number,
            safe_slot: $safe_slot
        }')

    set_rotation_metadata "${tenant_name}" "${new_metadata}" || return 1

    log_info "Rotation complete for ${tenant_name}:"
    log_info "  Rotated slot: ${slot_to_rotate}"
    log_info "  Safe slot (tenants use): ${safe_slot}"
    log_info "  Rotation number: ${new_rotation_number}"
    log_info "  Next rotation: ${next_rotation_iso}"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    log_info "============================================================"
    log_info "APIM Subscription Key Rotation"
    log_info "============================================================"
    log_info "Environment:        ${ENVIRONMENT}"
    log_info "Config Dir:         ${CONFIG_DIR}"
    log_info "Dry Run:            ${DRY_RUN}"
    log_info "Force:              ${FORCE}"
    log_info "============================================================"

    # Verify Azure CLI is authenticated
    if ! az account show &>/dev/null; then
        log_error "Azure CLI is not authenticated. Run 'az login' first."
        exit 1
    fi

    # Verify jq is available
    if ! command -v jq &>/dev/null; then
        log_error "jq is required but not installed."
        exit 1
    fi

    # Self-discover APIM, hub KV, and rotation config from tfvars
    discover_config

    log_info "Resource Group:     ${RESOURCE_GROUP}"
    log_info "APIM Name:          ${APIM_NAME}"
    log_info "Hub Key Vault:      ${HUB_KEYVAULT_NAME}"
    log_info "Rotation Interval:  ${ROTATION_INTERVAL_DAYS} days"
    log_info "============================================================"

    # Get all tenant subscriptions
    log_info "Discovering tenant subscriptions..."
    local subscriptions
    subscriptions=$(get_tenant_subscriptions)

    if [[ -z "${subscriptions}" ]]; then
        log_warn "No tenant subscriptions found in APIM '${APIM_NAME}'"
        exit 0
    fi

    local total=0
    local rotated=0
    local skipped=0
    local failed=0

    while IFS='|' read -r sub_name tenant_name; do
        # Normalize potential CRLF artifacts from CLI output on Windows runners
        sub_name="${sub_name//$'\r'/}"
        tenant_name="${tenant_name//$'\r'/}"

        total=$((total + 1))
        # sub_name = APIM subscription ID (GUID) for API calls
        # tenant_name = product name from scope (e.g., "wlrs-water-form-assistant") for KV secret naming

        if [[ -z "${tenant_name}" ]]; then
            log_error "Could not determine tenant name for subscription: ${sub_name}"
            failed=$((failed + 1))
            continue
        fi

        local status=0
        rotate_tenant_key "${sub_name}" "${tenant_name}" || status=$?
        if [[ ${status} -eq 0 ]]; then
            rotated=$((rotated + 1))
        elif [[ ${status} -eq 2 ]]; then
            skipped=$((skipped + 1))
            log_info "Skipped rotation for tenant: ${tenant_name} (not yet due)"
        else
            failed=$((failed + 1))
            log_error "Failed to rotate key for tenant: ${tenant_name}"
        fi
    done <<< "${subscriptions}"

    log_info "============================================================"
    log_info "ROTATION SUMMARY"
    log_info "============================================================"
    log_info "Total subscriptions: ${total}"
    log_info "Rotated:             ${rotated}"
    log_info "Skipped:             ${skipped}"
    log_info "Failed:              ${failed}"
    log_info "============================================================"

    if [[ ${failed} -gt 0 ]]; then
        log_error "${failed} rotation(s) failed. Check logs above for details."
        exit 1
    fi

    log_info "All rotations completed successfully."
}

main "$@"
