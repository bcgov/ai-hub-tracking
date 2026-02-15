#!/usr/bin/env bash
# Quick test: call /internal/apim-keys and verify response
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-helper.bash"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m'

_ts() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }
log_info()    { echo -e "${GRAY}$(_ts)${NC} ${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GRAY}$(_ts)${NC} ${GREEN}[SUCCESS]${NC} $*"; }
log_warn()    { echo -e "${GRAY}$(_ts)${NC} ${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${GRAY}$(_ts)${NC} ${RED}[ERROR]${NC} $*"; }

# Environment/tenant configuration
TEST_ENV="${TEST_ENV:-test}"
TENANT_1="${TENANT_1:-${APIM_KEYS_TENANT_1:-wlrs-water-form-assistant}}"
TENANT_2="${TENANT_2:-${APIM_KEYS_TENANT_2:-sdpr-invoice-automation}}"

is_key_rotation_enabled() {
    local env="$1"
    local shared_tfvars="${SCRIPT_DIR}/../../infra-ai-hub/params/${env}/shared.tfvars"

    [[ -f "${shared_tfvars}" ]] || {
        echo "true"
        return
    }

    local parsed
    parsed=$(awk '
        /^[[:space:]]*apim[[:space:]]*=[[:space:]]*\{/ { in_apim=1 }
        in_apim && /^[[:space:]]*key_rotation[[:space:]]*=[[:space:]]*\{/ { in_key_rotation=1 }
        in_apim && in_key_rotation && /^[[:space:]]*rotation_enabled[[:space:]]*=/ {
            line=$0
            sub(/#.*/, "", line)
            gsub(/[[:space:]]/, "", line)
            split(line, kv, "=")
            print kv[2]
            exit
        }
        in_key_rotation && /^[[:space:]]*\}/ { in_key_rotation=0 }
        in_apim && !in_key_rotation && /^[[:space:]]*\}/ { in_apim=0 }
    ' "${shared_tfvars}" | tr '[:upper:]' '[:lower:]')

    if [[ "${parsed}" == "false" ]]; then
        echo "false"
    else
        echo "true"
    fi
}

if [[ "$(is_key_rotation_enabled "${TEST_ENV}")" != "true" ]]; then
    log_warn "APIM key rotation is disabled in params/${TEST_ENV}/shared.tfvars. Skipping quick test."
    exit 0
fi

cd "${SCRIPT_DIR}/../../infra-ai-hub"

# Get stack outputs
TF_OUTPUT_RAW=$(./scripts/deploy-terraform.sh output "${TEST_ENV}" 2>/dev/null)
TF_OUTPUT=$(echo "$TF_OUTPUT_RAW" | sed -n '/^{/,$p')

# Prefer App Gateway URL when deployed; otherwise use direct APIM URL
APPGW_URL=$(echo "$TF_OUTPUT" | jq -r '.appgw_url.value // empty')
APIM_URL=$(echo "$TF_OUTPUT" | jq -r '.apim_gateway_url.value // empty')
if [[ -n "$APPGW_URL" ]]; then
    APIM_GW="$APPGW_URL"
    BASE_KIND="App Gateway"
else
    APIM_GW="$APIM_URL"
    BASE_KIND="Direct APIM"
fi

if [[ -z "$APIM_GW" ]]; then
    log_error "Could not determine API base URL (appgw_url/apim_gateway_url missing)"
    exit 1
fi

T1_KEY=$(echo "$TF_OUTPUT" | jq -r --arg t "$TENANT_1" '.apim_tenant_subscriptions.value[$t].primary_key // empty')
T2_KEY=$(echo "$TF_OUTPUT" | jq -r --arg t "$TENANT_2" '.apim_tenant_subscriptions.value[$t].primary_key // empty')
HUB_KV=$(echo "$TF_OUTPUT" | jq -r '.apim_key_rotation_summary.value.hub_keyvault_name // empty')
export HUB_KEYVAULT_NAME="${HUB_KV}"

if [[ -z "$T1_KEY" ]] || [[ -z "$T2_KEY" ]]; then
    log_error "Missing tenant subscription keys in terraform output"
    log_error "  TENANT_1=${TENANT_1} key present? $([[ -n "$T1_KEY" ]] && echo yes || echo no)"
    log_error "  TENANT_2=${TENANT_2} key present? $([[ -n "$T2_KEY" ]] && echo yes || echo no)"
    exit 1
fi

log_info "Environment: $TEST_ENV"
log_info "Base URL Type: $BASE_KIND"
log_info "API Base URL: $APIM_GW"
log_info "Hub KV: ${HUB_KV:-not set}"
log_info "${TENANT_1} key: ${T1_KEY:0:8}..."
log_info "${TENANT_2} key: ${T2_KEY:0:8}..."
echo ""

echo "=== GET /internal/apim-keys for ${TENANT_1} ==="
RESP=$(curl -s -X GET "$APIM_GW/${TENANT_1}/internal/apim-keys" \
    -H "api-key: $T1_KEY" \
    -H "Content-Type: application/json" \
    --max-time 30 2>/dev/null)
STATUS=$(echo "${RESP}" | jq -r '.error.code // empty' 2>/dev/null || true)
if [[ "${STATUS}" == "401" ]]; then
    NEW_KEY=$(get_tenant_key_from_vault "${TENANT_1}" || true)
    if [[ -n "${NEW_KEY}" ]]; then
        T1_KEY="${NEW_KEY}"
        RESP=$(curl -s -X GET "$APIM_GW/${TENANT_1}/internal/apim-keys" \
            -H "api-key: $T1_KEY" \
            -H "Content-Type: application/json" \
            --max-time 30 2>/dev/null)
    fi
fi
echo "${RESP}" | jq .
echo ""

echo "=== GET /internal/apim-keys for ${TENANT_2} ==="
RESP=$(curl -s -X GET "$APIM_GW/${TENANT_2}/internal/apim-keys" \
    -H "api-key: $T2_KEY" \
    -H "Content-Type: application/json" \
    --max-time 30 2>/dev/null)
STATUS=$(echo "${RESP}" | jq -r '.error.code // empty' 2>/dev/null || true)
if [[ "${STATUS}" == "401" ]]; then
    NEW_KEY=$(get_tenant_key_from_vault "${TENANT_2}" || true)
    if [[ -n "${NEW_KEY}" ]]; then
        T2_KEY="${NEW_KEY}"
        RESP=$(curl -s -X GET "$APIM_GW/${TENANT_2}/internal/apim-keys" \
            -H "api-key: $T2_KEY" \
            -H "Content-Type: application/json" \
            --max-time 30 2>/dev/null)
    fi
fi
echo "${RESP}" | jq .
echo ""

echo "=== POST /internal/apim-keys (expect 405) ==="
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$APIM_GW/${TENANT_1}/internal/apim-keys" \
    -H "api-key: $T1_KEY" \
    -H "Content-Type: application/json" \
    --max-time 30 2>/dev/null)
echo "HTTP Status: $HTTP_STATUS"
echo ""

echo "=== No auth (expect 401) ==="
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X GET "$APIM_GW/${TENANT_1}/internal/apim-keys" \
    -H "Content-Type: application/json" \
    --max-time 30 2>/dev/null)
echo "HTTP Status: $HTTP_STATUS"
