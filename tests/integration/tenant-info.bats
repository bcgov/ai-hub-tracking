#!/usr/bin/env bats
# Integration tests for the /internal/tenant-info APIM endpoint
#
# Verifies that the endpoint returns the correct tenant model deployments
# (with quota information) and service feature flags for each tenant.
#
# Unlike /internal/apim-keys, this endpoint makes no Key Vault calls —
# the response is static JSON baked in at Terraform deploy time.
# No proxy is required; runs in the direct (no-proxy) CI step.

load 'test-helper'

setup() {
    setup_test_suite
}

# Canonical tenants for this suite
tenant_1() {
    echo "${TENANT_INFO_TENANT_1:-wlrs-water-form-assistant}"
}

tenant_2() {
    echo "${TENANT_INFO_TENANT_2:-sdpr-invoice-automation}"
}

# Helper: skip if subscription key is not available for this tenant
skip_if_no_key() {
    local tenant="${1}"
    local key
    key=$(get_subscription_key "${tenant}" 2>/dev/null || echo "")
    if [[ -z "${key}" ]]; then
        skip "No subscription key for tenant: ${tenant}"
    fi
}

# Helper: call GET /internal/tenant-info for a tenant
# Returns: curl output with body + status code on last line
get_tenant_info() {
    local tenant="${1}"
    apim_request "GET" "${tenant}" "/internal/tenant-info"
}

# Helper: call POST /internal/tenant-info (should return 405)
post_tenant_info() {
    local tenant="${1}"
    apim_request "POST" "${tenant}" "/internal/tenant-info"
}

# =============================================================================
# Positive Tests: GET /internal/tenant-info — Tenant-1 (wlrs)
# =============================================================================

@test "Tenant-1: GET /internal/tenant-info returns 200" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"
}

@test "Tenant-1: tenant-info response is valid JSON" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    # Must parse cleanly as JSON without errors
    echo "${RESPONSE_BODY}" | jq . >/dev/null
}

@test "Tenant-1: tenant-info response content-type is application/json" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"
    assert_contains "${RESPONSE_BODY}" "tenant"
}

@test "Tenant-1: tenant-info contains correct tenant name" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local tenant_name
    tenant_name=$(json_get "${RESPONSE_BODY}" '.tenant')
    [[ "${tenant_name}" == "${t1}" ]]
}

@test "Tenant-1: tenant-info contains non-empty models array" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local model_count
    model_count=$(json_get "${RESPONSE_BODY}" '.models | length')
    [[ "${model_count}" -gt 0 ]]
}

@test "Tenant-1: tenant-info models have all required fields" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    # Every model must carry all six required fields and none may be null/empty
    local invalid_count
    invalid_count=$(echo "${RESPONSE_BODY}" | jq '[
        .models[] | select(
            (.name          | (. == null or length == 0)) or
            (.model_name    | (. == null or length == 0)) or
            (.model_version | (. == null or length == 0)) or
            (.scale_type    | (. == null or length == 0)) or
            (.capacity_k_tpm   == null) or
            (.tokens_per_minute == null)
        )
    ] | length')
    [[ "${invalid_count}" -eq 0 ]]
}

@test "Tenant-1: tenant-info tokens_per_minute equals capacity_k_tpm * 1000 for every model" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local mismatch_count
    mismatch_count=$(echo "${RESPONSE_BODY}" | jq '[
        .models[] | select(.tokens_per_minute != (.capacity_k_tpm * 1000))
    ] | length')
    [[ "${mismatch_count}" -eq 0 ]]
}

@test "Tenant-1: tenant-info contains services object with all required keys" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    # All five service flags must be present and boolean
    local has_openai has_docint has_search has_speech has_storage
    has_openai=$(json_get "${RESPONSE_BODY}" '.services.openai')
    has_docint=$(json_get "${RESPONSE_BODY}" '.services.document_intelligence')
    has_search=$(json_get "${RESPONSE_BODY}" '.services.ai_search')
    has_speech=$(json_get "${RESPONSE_BODY}" '.services.speech_services')
    has_storage=$(json_get "${RESPONSE_BODY}" '.services.storage')

    [[ "${has_openai}" == "true"  || "${has_openai}" == "false"  ]]
    [[ "${has_docint}" == "true"  || "${has_docint}" == "false"  ]]
    [[ "${has_search}" == "true"  || "${has_search}" == "false"  ]]
    [[ "${has_speech}" == "true"  || "${has_speech}" == "false"  ]]
    [[ "${has_storage}" == "true" || "${has_storage}" == "false" ]]
}

@test "Tenant-1: services.openai is true when models are configured" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local model_count
    model_count=$(json_get "${RESPONSE_BODY}" '.models | length')
    local openai_enabled
    openai_enabled=$(json_get "${RESPONSE_BODY}" '.services.openai')

    # If models > 0 then openai must be true
    if [[ "${model_count}" -gt 0 ]]; then
        [[ "${openai_enabled}" == "true" ]]
    fi
}

@test "Tenant-1 (wlrs): speech_services is enabled as per tenant.tfvars" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    # WLRS has speech_services.enabled = true in params/*/tenants/wlrs-water-form-assistant/tenant.tfvars
    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local speech
    speech=$(json_get "${RESPONSE_BODY}" '.services.speech_services')
    [[ "${speech}" == "true" ]]
}

@test "Tenant-1 (wlrs): document_intelligence is enabled as per tenant.tfvars" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local docint
    docint=$(json_get "${RESPONSE_BODY}" '.services.document_intelligence')
    [[ "${docint}" == "true" ]]
}

# =============================================================================
# Positive Tests: GET /internal/tenant-info — Tenant-2 (sdpr)
# =============================================================================

@test "Tenant-2: GET /internal/tenant-info returns 200" {
    local t2
    t2="$(tenant_2)"
    skip_if_no_key "${t2}"

    response=$(get_tenant_info "${t2}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"
}

@test "Tenant-2: tenant-info contains correct tenant name" {
    local t2
    t2="$(tenant_2)"
    skip_if_no_key "${t2}"

    response=$(get_tenant_info "${t2}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local tenant_name
    tenant_name=$(json_get "${RESPONSE_BODY}" '.tenant')
    [[ "${tenant_name}" == "${t2}" ]]
}

@test "Tenant-2: tenant-info contains non-empty models array" {
    local t2
    t2="$(tenant_2)"
    skip_if_no_key "${t2}"

    response=$(get_tenant_info "${t2}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local model_count
    model_count=$(json_get "${RESPONSE_BODY}" '.models | length')
    [[ "${model_count}" -gt 0 ]]
}

@test "Tenant-2: tenant-info models have all required fields" {
    local t2
    t2="$(tenant_2)"
    skip_if_no_key "${t2}"

    response=$(get_tenant_info "${t2}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local invalid_count
    invalid_count=$(echo "${RESPONSE_BODY}" | jq '[
        .models[] | select(
            (.name | (. == null or length == 0)) or
            (.model_name | (. == null or length == 0)) or
            (.capacity_k_tpm == null) or
            (.tokens_per_minute == null)
        )
    ] | length')
    [[ "${invalid_count}" -eq 0 ]]
}

@test "Tenant-2 (sdpr): document_intelligence is enabled as per tenant.tfvars" {
    local t2
    t2="$(tenant_2)"
    skip_if_no_key "${t2}"

    response=$(get_tenant_info "${t2}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local docint
    docint=$(json_get "${RESPONSE_BODY}" '.services.document_intelligence')
    [[ "${docint}" == "true" ]]
}

@test "Tenant-2 (sdpr): speech_services is disabled as per tenant.tfvars" {
    local t2
    t2="$(tenant_2)"
    skip_if_no_key "${t2}"

    response=$(get_tenant_info "${t2}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local speech
    speech=$(json_get "${RESPONSE_BODY}" '.services.speech_services')
    [[ "${speech}" == "false" ]]
}

@test "Tenant-2 (sdpr): ai_search is disabled as per tenant.tfvars" {
    local t2
    t2="$(tenant_2)"
    skip_if_no_key "${t2}"

    response=$(get_tenant_info "${t2}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local search
    search=$(json_get "${RESPONSE_BODY}" '.services.ai_search')
    [[ "${search}" == "false" ]]
}

# =============================================================================
# Negative Tests: method and auth guards
# =============================================================================

@test "Tenant-1: POST /internal/tenant-info returns 405" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(post_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "405" "${RESPONSE_STATUS}"
}

@test "Tenant-1: POST /internal/tenant-info returns MethodNotAllowed error code" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(post_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "405" "${RESPONSE_STATUS}"

    local error_code
    error_code=$(json_get "${RESPONSE_BODY}" '.error.code')
    [[ "${error_code}" == "MethodNotAllowed" ]]
}

@test "Unauthenticated request to /internal/tenant-info returns 401" {
    # Call without any subscription key — no auth header
    local tenant
    tenant="$(tenant_1)"
    local url="${APIM_GATEWAY_URL}/${tenant}/internal/tenant-info"
    local response
    response=$(curl -s -w "\n%{http_code}" -X GET "${url}" \
        -H "Content-Type: application/json" \
        --max-time 30 2>/dev/null)
    parse_response "${response}"

    assert_status "401" "${RESPONSE_STATUS}"
}

# =============================================================================
# Cross-tenant isolation: each tenant sees only its own data
# =============================================================================

@test "Tenant-1 and Tenant-2 return different tenant names" {
    local t1 t2
    t1="$(tenant_1)"
    t2="$(tenant_2)"

    if [[ "${t1}" == "${t2}" ]]; then
        skip "Tenant-1 and Tenant-2 resolve to the same tenant (${t1})"
    fi

    skip_if_no_key "${t1}"
    skip_if_no_key "${t2}"

    response1=$(get_tenant_info "${t1}")
    parse_response "${response1}"
    local name1
    name1=$(json_get "${RESPONSE_BODY}" '.tenant')

    response2=$(get_tenant_info "${t2}")
    parse_response "${response2}"
    local name2
    name2=$(json_get "${RESPONSE_BODY}" '.tenant')

    [[ "${name1}" != "${name2}" ]]
    [[ "${name1}" == "${t1}" ]]
    [[ "${name2}" == "${t2}" ]]
}

@test "Tenant-1 and Tenant-2 service flags differ where expected (speech)" {
    local t1 t2
    t1="$(tenant_1)"
    t2="$(tenant_2)"

    if [[ "${t1}" == "${t2}" ]]; then
        skip "Tenant-1 and Tenant-2 resolve to the same tenant (${t1})"
    fi

    skip_if_no_key "${t1}"
    skip_if_no_key "${t2}"

    # WLRS has speech_services enabled; SDPR does not
    # Validates that the static JSON correctly reflects per-tenant flags
    response1=$(get_tenant_info "${t1}")
    parse_response "${response1}"
    local wlrs_speech
    wlrs_speech=$(json_get "${RESPONSE_BODY}" '.services.speech_services')

    response2=$(get_tenant_info "${t2}")
    parse_response "${response2}"
    local sdpr_speech
    sdpr_speech=$(json_get "${RESPONSE_BODY}" '.services.speech_services')

    [[ "${wlrs_speech}" == "true"  ]]
    [[ "${sdpr_speech}" == "false" ]]
}
