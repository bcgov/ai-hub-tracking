#!/usr/bin/env bash
# =============================================================================
# Manual verification: rotate keys and verify via APIM endpoint
# =============================================================================
# Steps:
#   1. Capture current keys from /internal/apim-keys for the configured tenant
#   2. Run the rotation script (force mode by default)
#   3. Call /internal/apim-keys again with one of the OLD keys (safe slot should still work)
#   4. Verify the rotated slot has a new key in the response
# =============================================================================
set -euo pipefail

# Environment/tenant configuration
TEST_ENV="${TEST_ENV:-dev}"
TENANT="${TENANT:-${APIM_KEYS_TENANT_1:-wlrs-water-form-assistant}}"
FORCE_ROTATION="${FORCE_ROTATION:-true}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $*"; }
log_fail()    { echo -e "${RED}[FAIL]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../../infra-ai-hub"

source "${SCRIPT_DIR}/test-helper.bash"

cd "${INFRA_DIR}"

# --- Step 0: Load terraform config ---
log_info "Loading terraform outputs..."
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
    log_fail "Could not determine API base URL (appgw_url/apim_gateway_url missing)"
    exit 1
fi

HUB_KV=$(echo "$TF_OUTPUT" | jq -r '.apim_key_rotation_summary.value.hub_keyvault_name // empty')
export HUB_KEYVAULT_NAME="${HUB_KV}"

T1_KEY=$(echo "$TF_OUTPUT" | jq -r --arg t "$TENANT" '.apim_tenant_subscriptions.value[$t].primary_key // empty')

if [[ -z "$T1_KEY" ]]; then
    log_fail "Missing primary subscription key for tenant '${TENANT}'"
    exit 1
fi

log_info "Environment: $TEST_ENV"
log_info "Base URL Type: $BASE_KIND"
log_info "API Base URL: $APIM_GW"
log_info "Hub KV: ${HUB_KV:-not set}"
log_info "${TENANT} current primary key: ${T1_KEY:0:8}..."

# Also get the secondary key from terraform output
T1_SECONDARY_KEY=$(echo "$TF_OUTPUT" | jq -r --arg t "$TENANT" '.apim_tenant_subscriptions.value[$t].secondary_key // empty')
if [[ -z "$T1_SECONDARY_KEY" ]]; then
    log_fail "Missing secondary subscription key for tenant '${TENANT}'"
    exit 1
fi

# --- Step 1: Capture pre-rotation keys from APIM endpoint ---
log_info ""
log_info "=== Step 1: Capture pre-rotation keys ==="
PRE_RESPONSE=$(curl -s -X GET "$APIM_GW/${TENANT}/internal/apim-keys" \
    -H "api-key: $T1_KEY" \
    -H "Content-Type: application/json" \
    --max-time 30 2>/dev/null)

PRE_ERR=$(echo "$PRE_RESPONSE" | jq -r '.error.code // empty' 2>/dev/null || true)
if [[ "$PRE_ERR" == "401" ]]; then
    log_warn "Primary key returned 401; attempting to refresh from Key Vault"
    NEW_PRIMARY=$(get_tenant_key_from_vault "${TENANT}" "primary" || true)
    if [[ -n "${NEW_PRIMARY}" ]]; then
        T1_KEY="${NEW_PRIMARY}"
        PRE_RESPONSE=$(curl -s -X GET "$APIM_GW/${TENANT}/internal/apim-keys" \
            -H "api-key: $T1_KEY" \
            -H "Content-Type: application/json" \
            --max-time 30 2>/dev/null)
    fi
fi

PRE_PRIMARY=$(echo "$PRE_RESPONSE" | jq -r '.primary_key')
PRE_SECONDARY=$(echo "$PRE_RESPONSE" | jq -r '.secondary_key')
PRE_ROTATION=$(echo "$PRE_RESPONSE" | jq -r '.rotation')
PRE_SLOT=$(echo "$PRE_RESPONSE" | jq -r '.rotation.last_rotated_slot')

log_info "Pre-rotation primary key:  ${PRE_PRIMARY:0:8}..."
log_info "Pre-rotation secondary key: ${PRE_SECONDARY:0:8}..."
log_info "Pre-rotation last_rotated_slot: $PRE_SLOT"
log_info "Pre-rotation metadata:"
echo "$PRE_ROTATION" | jq .

# --- Step 2: Run the rotation script ---
log_info ""
log_info "=== Step 2: Running key rotation script ==="
FORCE_ARG=""
if [[ "${FORCE_ROTATION}" == "true" ]]; then
    FORCE_ARG="--force"
fi

bash "${INFRA_DIR}/scripts/rotate-apim-keys.sh" \
    --environment "${TEST_ENV}" \
    --config-dir "${INFRA_DIR}" \
    ${FORCE_ARG} \
    --verbose 2>&1

log_info "Rotation script completed. Waiting 5s for propagation..."
sleep 5

# --- Step 3: Call APIM endpoint with one of the old keys (safe slot should work) ---
log_info ""
log_info "=== Step 3: Verify endpoint with an old key (safe slot) ==="
POST_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "$APIM_GW/${TENANT}/internal/apim-keys" \
    -H "api-key: $T1_KEY" \
    -H "Content-Type: application/json" \
    --max-time 30 2>/dev/null)

# Parse response
HTTP_STATUS=$(echo "$POST_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$POST_RESPONSE" | sed '$d')

if [[ "$HTTP_STATUS" == "401" ]]; then
    log_warn "Primary old key returned 401; trying secondary old key"
    POST_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "$APIM_GW/${TENANT}/internal/apim-keys" \
        -H "api-key: $T1_SECONDARY_KEY" \
        -H "Content-Type: application/json" \
        --max-time 30 2>/dev/null)
    HTTP_STATUS=$(echo "$POST_RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$POST_RESPONSE" | sed '$d')
fi

if [[ "$HTTP_STATUS" == "401" ]]; then
    log_warn "Both old keys returned 401; attempting Key Vault safe-slot fallback"
    NEW_SAFE_KEY=$(get_tenant_key_from_vault "${TENANT}" || true)
    if [[ -n "${NEW_SAFE_KEY}" ]]; then
        POST_RESPONSE=$(curl -s -w "\n%{http_code}" -X GET "$APIM_GW/${TENANT}/internal/apim-keys" \
            -H "api-key: $NEW_SAFE_KEY" \
            -H "Content-Type: application/json" \
            --max-time 30 2>/dev/null)
        HTTP_STATUS=$(echo "$POST_RESPONSE" | tail -n1)
        RESPONSE_BODY=$(echo "$POST_RESPONSE" | sed '$d')
    fi
fi

if [[ "$HTTP_STATUS" == "200" ]]; then
    log_success "APIM endpoint accessible with an old/safe key (HTTP $HTTP_STATUS)"
else
    log_fail "APIM endpoint returned HTTP $HTTP_STATUS with all key attempts"
    echo "$RESPONSE_BODY"
    exit 1
fi

POST_PRIMARY=$(echo "$RESPONSE_BODY" | jq -r '.primary_key')
POST_SECONDARY=$(echo "$RESPONSE_BODY" | jq -r '.secondary_key')
POST_SLOT=$(echo "$RESPONSE_BODY" | jq -r '.rotation.last_rotated_slot')
POST_ROTATION_NUM=$(echo "$RESPONSE_BODY" | jq -r '.rotation.rotation_number')

log_info "Post-rotation primary key:  ${POST_PRIMARY:0:8}..."
log_info "Post-rotation secondary key: ${POST_SECONDARY:0:8}..."
log_info "Post-rotation last_rotated_slot: $POST_SLOT"
log_info "Post-rotation rotation_number: $POST_ROTATION_NUM"
log_info "Post-rotation metadata:"
echo "$RESPONSE_BODY" | jq '.rotation'

# --- Step 4: Validate rotation results ---
log_info ""
log_info "=== Step 4: Validation ==="

PASS_COUNT=0
FAIL_COUNT=0

# Check that rotation metadata was updated
if [[ "$POST_SLOT" != "none" ]]; then
    log_success "last_rotated_slot changed from 'none' to '$POST_SLOT'"
    ((PASS_COUNT++))
else
    log_fail "last_rotated_slot still 'none' — rotation may not have happened"
    ((FAIL_COUNT++))
fi

# Check rotation number incremented
if [[ "$POST_ROTATION_NUM" -gt 0 ]]; then
    log_success "rotation_number incremented to $POST_ROTATION_NUM"
    ((PASS_COUNT++))
else
    log_fail "rotation_number still 0"
    ((FAIL_COUNT++))
fi

# Check which key was rotated
if [[ "$POST_SLOT" == "primary" ]]; then
    if [[ "$POST_PRIMARY" != "$PRE_PRIMARY" ]]; then
        log_success "Primary key was rotated (changed)"
        ((PASS_COUNT++))
    else
        log_fail "Primary key was NOT rotated (unchanged)"
        ((FAIL_COUNT++))
    fi
    if [[ "$POST_SECONDARY" == "$PRE_SECONDARY" ]]; then
        log_success "Secondary key was NOT touched (expected — safe slot)"
        ((PASS_COUNT++))
    else
        log_warn "Secondary key also changed (unexpected)"
        ((FAIL_COUNT++))
    fi
elif [[ "$POST_SLOT" == "secondary" ]]; then
    if [[ "$POST_SECONDARY" != "$PRE_SECONDARY" ]]; then
        log_success "Secondary key was rotated (changed)"
        ((PASS_COUNT++))
    else
        log_fail "Secondary key was NOT rotated (unchanged)"
        ((FAIL_COUNT++))
    fi
    if [[ "$POST_PRIMARY" == "$PRE_PRIMARY" ]]; then
        log_success "Primary key was NOT touched (expected — safe slot)"
        ((PASS_COUNT++))
    else
        log_warn "Primary key also changed (unexpected)"
        ((FAIL_COUNT++))
    fi
fi

echo ""
log_info "=== Summary ==="
log_info "Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
    log_fail "Some validations failed"
    exit 1
else
    log_success "All validations passed! Key rotation verified end-to-end."
fi
