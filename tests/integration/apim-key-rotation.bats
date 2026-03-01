#!/usr/bin/env bats
# Integration tests for the /internal/apim-keys APIM endpoint
# Verifies that the endpoint returns subscription keys and rotation metadata
# from the hub Key Vault for each tenant.

load 'test-helper'

setup_file() {
    # No file-level setup needed — the /internal/apim-keys endpoint is
    # available for ALL subscription-key tenants (decoupled from rotation).
    # Per-test skips are handled by skip_if_no_tenant_key.
    :
}

setup() {
    setup_test_suite
}

# Canonical tenants for this suite (resolved by config loader)
tenant_1() {
    echo "${APIM_KEYS_TENANT_1:-wlrs-water-form-assistant}"
}

tenant_2() {
    echo "${APIM_KEYS_TENANT_2:-sdpr-invoice-automation}"
}

# Helper: skip if tenant subscription key is not available
# The /internal/apim-keys endpoint is available for ALL subscription-key tenants
# (decoupled from per-tenant key_rotation_enabled since all keys are stored in KV)
skip_if_no_tenant_key() {
    local tenant="${1}"
    local key
    key=$(get_subscription_key "${tenant}" 2>/dev/null || echo "")

    if [[ -z "${key}" ]]; then
        skip "No subscription key for ${tenant}"
    fi
}

# Helper: call the /internal/apim-keys endpoint for a tenant
# Usage: get_apim_keys <tenant>
# Returns: response with body + status code (last line)
get_apim_keys() {
    local tenant="${1}"
    apim_request "GET" "${tenant}" "/internal/apim-keys"
}

# Helper: call the /internal/apim-keys endpoint using POST (should fail)
post_apim_keys() {
    local tenant="${1}"
    apim_request "POST" "${tenant}" "/internal/apim-keys"
}

# =============================================================================
# Positive Tests: GET /internal/apim-keys returns keys for each tenant
# =============================================================================

@test "Tenant-1: GET /internal/apim-keys returns 200" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_tenant_key "${t1}"

    response=$(get_apim_keys "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"
}

@test "Tenant-1: apim-keys response contains tenant name" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_tenant_key "${t1}"

    response=$(get_apim_keys "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local tenant_name
    tenant_name=$(json_get "${RESPONSE_BODY}" '.tenant')
    [[ "${tenant_name}" == "${t1}" ]]
}

@test "Tenant-1: apim-keys response contains non-empty primary_key" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_tenant_key "${t1}"

    response=$(get_apim_keys "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local primary_key
    primary_key=$(json_get "${RESPONSE_BODY}" '.primary_key')
    [[ -n "${primary_key}" ]] && [[ "${primary_key}" != "null" ]]
}

@test "Tenant-1: apim-keys response contains non-empty secondary_key" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_tenant_key "${t1}"

    response=$(get_apim_keys "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local secondary_key
    secondary_key=$(json_get "${RESPONSE_BODY}" '.secondary_key')
    [[ -n "${secondary_key}" ]] && [[ "${secondary_key}" != "null" ]]
}

@test "Tenant-1: apim-keys response contains rotation object" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_tenant_key "${t1}"

    response=$(get_apim_keys "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    # The rotation field is always present as a JSON object.
    # When key_rotation_enabled=true for the tenant: contains last_rotated_slot, safe_slot, etc.
    # When key_rotation_enabled=false: contains key_rotation_enabled=false + message.
    local rotation_raw
    rotation_raw=$(json_get "${RESPONSE_BODY}" '.rotation')
    [[ -n "${rotation_raw}" ]] && [[ "${rotation_raw}" != "null" ]]

    # Check for either rotation metadata fields or the disabled indicator
    # Note: jq's // treats false as falsy, so we convert booleans to strings
    local has_rotation_data
    has_rotation_data=$(json_get "${RESPONSE_BODY}" '.rotation.last_rotated_slot // (.rotation.key_rotation_enabled | tostring) // empty')
    [[ -n "${has_rotation_data}" ]]
}

@test "Tenant-1: apim-keys response contains keyvault info" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_tenant_key "${t1}"

    response=$(get_apim_keys "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local kv_uri
    kv_uri=$(json_get "${RESPONSE_BODY}" '.keyvault.uri')
    [[ "${kv_uri}" == *"vault.azure.net"* ]]

    local primary_secret
    primary_secret=$(json_get "${RESPONSE_BODY}" '.keyvault.primary_key_secret')
    [[ "${primary_secret}" == "${t1}-apim-primary-key" ]]

    local secondary_secret
    secondary_secret=$(json_get "${RESPONSE_BODY}" '.keyvault.secondary_key_secret')
    [[ "${secondary_secret}" == "${t1}-apim-secondary-key" ]]
}

@test "Tenant-2: GET /internal/apim-keys returns 200" {
    local t2
    t2="$(tenant_2)"
    skip_if_no_tenant_key "${t2}"

    response=$(get_apim_keys "${t2}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"
}

@test "Tenant-2: apim-keys response contains correct tenant name" {
    local t2
    t2="$(tenant_2)"
    skip_if_no_tenant_key "${t2}"

    response=$(get_apim_keys "${t2}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local tenant_name
    tenant_name=$(json_get "${RESPONSE_BODY}" '.tenant')
    [[ "${tenant_name}" == "${t2}" ]]
}

@test "Tenant-2: apim-keys response contains non-empty keys" {
    local t2
    t2="$(tenant_2)"
    skip_if_no_tenant_key "${t2}"

    response=$(get_apim_keys "${t2}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local primary_key
    primary_key=$(json_get "${RESPONSE_BODY}" '.primary_key')
    [[ -n "${primary_key}" ]] && [[ "${primary_key}" != "null" ]]

    local secondary_key
    secondary_key=$(json_get "${RESPONSE_BODY}" '.secondary_key')
    [[ -n "${secondary_key}" ]] && [[ "${secondary_key}" != "null" ]]
}

@test "Tenant-2: apim-keys response contains rotation object" {
    local t2
    t2="$(tenant_2)"
    skip_if_no_tenant_key "${t2}"

    response=$(get_apim_keys "${t2}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    # Same check as Tenant-1: rotation object always present
    local rotation_raw
    rotation_raw=$(json_get "${RESPONSE_BODY}" '.rotation')
    [[ -n "${rotation_raw}" ]] && [[ "${rotation_raw}" != "null" ]]
}

# =============================================================================
# Negative Tests: Method not allowed, missing key
# =============================================================================

@test "Tenant-1: POST /internal/apim-keys returns 405" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_tenant_key "${t1}"

    response=$(post_apim_keys "${t1}")
    parse_response "${response}"

    assert_status "405" "${RESPONSE_STATUS}"
}

@test "Unauthenticated request to /internal/apim-keys returns 401 or 403" {

    # Call without any subscription key — use first available tenant path
    # WAF returns 403 for unauthenticated requests to non-root paths;
    # APIM returns 401 when the request reaches it without a key.
    local tenant
    tenant="$(tenant_1)"
    local url="${APIM_GATEWAY_URL}/${tenant}/internal/apim-keys"
    local response
    response=$(curl -s -w "\n%{http_code}" -X GET "${url}" \
        -H "Content-Type: application/json" \
        --max-time 30 2>/dev/null)
    parse_response "${response}"

    [[ "${RESPONSE_STATUS}" == "401" ]] || [[ "${RESPONSE_STATUS}" == "403" ]]
}

# =============================================================================
# Cross-tenant isolation: keys are tenant-specific
# =============================================================================

@test "Tenant-1 and Tenant-2 return different primary keys" {
    local t1
    local t2
    t1="$(tenant_1)"
    t2="$(tenant_2)"

    if [[ "${t1}" == "${t2}" ]]; then
        skip "Tenant-1 and Tenant-2 resolve to the same tenant (${t1})"
    fi

    skip_if_no_tenant_key "${t1}"
    skip_if_no_tenant_key "${t2}"

    response1=$(get_apim_keys "${t1}")
    parse_response "${response1}"
    local key1="${RESPONSE_BODY}"

    response2=$(get_apim_keys "${t2}")
    parse_response "${response2}"
    local key2="${RESPONSE_BODY}"

    local pk1
    pk1=$(json_get "${key1}" '.primary_key')
    local pk2
    pk2=$(json_get "${key2}" '.primary_key')

    # Keys should be different between tenants
    [[ "${pk1}" != "${pk2}" ]]
}
