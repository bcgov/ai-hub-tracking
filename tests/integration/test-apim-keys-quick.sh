#!/usr/bin/env bash
# Quick test: call /internal/apim-keys and verify response
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-helper.bash"

# Environment/tenant configuration
TEST_ENV="${TEST_ENV:-test}"
TENANT_1="${TENANT_1:-${APIM_KEYS_TENANT_1:-wlrs-water-form-assistant}}"
TENANT_2="${TENANT_2:-${APIM_KEYS_TENANT_2:-sdpr-invoice-automation}}"

cd "${SCRIPT_DIR}/../../infra-ai-hub"

# Get terraform outputs
TF_OUTPUT=$(terraform output -json 2>/dev/null)

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
    echo "Error: Could not determine API base URL (appgw_url/apim_gateway_url missing)" >&2
    exit 1
fi

T1_KEY=$(echo "$TF_OUTPUT" | jq -r --arg t "$TENANT_1" '.apim_tenant_subscriptions.value[$t].primary_key // empty')
T2_KEY=$(echo "$TF_OUTPUT" | jq -r --arg t "$TENANT_2" '.apim_tenant_subscriptions.value[$t].primary_key // empty')
HUB_KV=$(echo "$TF_OUTPUT" | jq -r '.apim_key_rotation_summary.value.hub_keyvault_name // empty')
export HUB_KEYVAULT_NAME="${HUB_KV}"

if [[ -z "$T1_KEY" ]] || [[ -z "$T2_KEY" ]]; then
    echo "Error: Missing tenant subscription keys in terraform output" >&2
    echo "  TENANT_1=${TENANT_1} key present? $([[ -n "$T1_KEY" ]] && echo yes || echo no)" >&2
    echo "  TENANT_2=${TENANT_2} key present? $([[ -n "$T2_KEY" ]] && echo yes || echo no)" >&2
    exit 1
fi

echo "Environment: $TEST_ENV"
echo "Base URL Type: $BASE_KIND"
echo "API Base URL: $APIM_GW"
echo "Hub KV: ${HUB_KV:-not set}"
echo "${TENANT_1} key: ${T1_KEY:0:8}..."
echo "${TENANT_2} key: ${T2_KEY:0:8}..."
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
