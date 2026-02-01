#!/bin/bash
set -euo pipefail

# =============================================================================
# Purge AI Foundry (Cognitive Services) Account
# Waits for soft-delete to complete before purging
# =============================================================================
# Usage:
#   purge-ai-foundry.sh --name <name> --resource-group <rg> --location <region> --subscription <sub>
#     [--timeout 10m] [--interval 15s]
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
  cat << EOF
Usage: $0 --name <name> --resource-group <rg> --location <region> --subscription <sub> [--timeout 10m] [--interval 15s]

Options:
  --name             AI Foundry (Cognitive Services) account name
  --resource-group   Resource group name
  --location         Azure region
  --subscription     Subscription ID
  --timeout          Max wait time for soft-delete (default: 10m)
  --interval         Poll interval (default: 15s)
EOF
  exit 1
}

parse_duration_seconds() {
  local value="$1"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$value"
    return 0
  fi
  if [[ "$value" =~ ^([0-9]+)(s|m|h)$ ]]; then
    local number="${BASH_REMATCH[1]}"
    local unit="${BASH_REMATCH[2]}"
    case "$unit" in
      s) echo "$number" ;;
      m) echo $((number * 60)) ;;
      h) echo $((number * 3600)) ;;
    esac
    return 0
  fi
  return 1
}

NAME=""
RESOURCE_GROUP=""
LOCATION=""
SUBSCRIPTION=""
TIMEOUT="10m"
INTERVAL="15s"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      NAME="$2"; shift 2 ;;
    --resource-group)
      RESOURCE_GROUP="$2"; shift 2 ;;
    --location)
      LOCATION="$2"; shift 2 ;;
    --subscription)
      SUBSCRIPTION="$2"; shift 2 ;;
    --timeout)
      TIMEOUT="$2"; shift 2 ;;
    --interval)
      INTERVAL="$2"; shift 2 ;;
    -h|--help)
      usage ;;
    *)
      log_error "Unknown argument: $1"
      usage ;;
  esac
done

if [[ -z "$NAME" || -z "$RESOURCE_GROUP" || -z "$LOCATION" || -z "$SUBSCRIPTION" ]]; then
  log_error "Missing required arguments."
  usage
fi

if ! timeout_seconds=$(parse_duration_seconds "$TIMEOUT"); then
  log_error "Invalid --timeout value: $TIMEOUT (use formats like 600, 10m, 30s, 1h)"
  exit 1
fi

if ! interval_seconds=$(parse_duration_seconds "$INTERVAL"); then
  log_error "Invalid --interval value: $INTERVAL (use formats like 15s, 30s, 1m)"
  exit 1
fi

log_info "Waiting for soft-delete: name=$NAME location=$LOCATION timeout=$TIMEOUT interval=$INTERVAL"
start_ts=$(date +%s)
end_ts=$((start_ts + timeout_seconds))
delete_requested=false

while true; do
  if az cognitiveservices account show \
      --name "$NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --subscription "$SUBSCRIPTION" \
      -o none 2>/dev/null; then
    provisioning_state=$(az cognitiveservices account show \
      --name "$NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --subscription "$SUBSCRIPTION" \
      --query "properties.provisioningState" \
      -o tsv 2>/dev/null || echo "")

    if [[ -n "$provisioning_state" ]]; then
      log_info "Account still active (provisioningState=$provisioning_state). Waiting..."
    else
      log_info "Account still active. Waiting..."
    fi

    # If deletion has not started, request delete once to ensure it begins
    if [[ "$delete_requested" == "false" && "$provisioning_state" != "Deleting" ]]; then
      log_warning "Account still active and not deleting. Requesting delete..."
      if az cognitiveservices account delete \
          --name "$NAME" \
          --resource-group "$RESOURCE_GROUP" \
          --subscription "$SUBSCRIPTION" \
          -o none 2>/dev/null; then
        delete_requested=true
        log_info "Delete request submitted. Waiting for soft-delete..."
      else
        log_warning "Delete request failed or is not permitted. Waiting for soft-delete..."
      fi
    fi
  else
    deleted_count=$(az cognitiveservices account list-deleted \
      --subscription "$SUBSCRIPTION" \
      --query "[?name=='${NAME}' && location=='${LOCATION}'] | length(@)" \
      -o tsv 2>/dev/null || echo "0")

    if [[ "$deleted_count" =~ ^[0-9]+$ ]] && [[ "$deleted_count" -gt 0 ]]; then
      log_info "Soft-deleted account detected. Proceeding to purge."
      break
    fi

    log_warning "Account not found and not in soft-deleted list. Assuming already purged."
    exit 0
  fi

  now_ts=$(date +%s)
  if (( now_ts >= end_ts )); then
    log_error "Timed out waiting for soft-delete (timeout: $TIMEOUT)."
    exit 1
  fi

  sleep "$interval_seconds"
done

log_info "Purging AI Foundry account..."
az cognitiveservices account purge \
  --name "$NAME" \
  --location "$LOCATION" \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$SUBSCRIPTION" \
  -o none

log_success "Purge completed."
