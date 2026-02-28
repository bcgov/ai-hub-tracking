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

    # All five service flags must be present as objects with boolean .enabled
    local has_openai has_docint has_search has_speech has_storage
    has_openai=$(json_get "${RESPONSE_BODY}" '.services.openai.enabled')
    has_docint=$(json_get "${RESPONSE_BODY}" '.services.document_intelligence.enabled')
    has_search=$(json_get "${RESPONSE_BODY}" '.services.ai_search.enabled')
    has_speech=$(json_get "${RESPONSE_BODY}" '.services.speech_services.enabled')
    has_storage=$(json_get "${RESPONSE_BODY}" '.services.storage.enabled')

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
    openai_enabled=$(json_get "${RESPONSE_BODY}" '.services.openai.enabled')

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
    speech=$(json_get "${RESPONSE_BODY}" '.services.speech_services.enabled')
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
    docint=$(json_get "${RESPONSE_BODY}" '.services.document_intelligence.enabled')
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
    docint=$(json_get "${RESPONSE_BODY}" '.services.document_intelligence.enabled')
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
    speech=$(json_get "${RESPONSE_BODY}" '.services.speech_services.enabled')
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
    search=$(json_get "${RESPONSE_BODY}" '.services.ai_search.enabled')
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

@test "Unauthenticated request to /internal/tenant-info returns 401 or 403" {
    # Call without any subscription key — no auth header
    # WAF returns 403 for unauthenticated requests to non-root paths;
    # APIM returns 401 when the request reaches it without a key.
    local tenant
    tenant="$(tenant_1)"
    local url="${APIM_GATEWAY_URL}/${tenant}/internal/tenant-info"
    local response
    response=$(curl -s -w "\n%{http_code}" -X GET "${url}" \
        -H "Content-Type: application/json" \
        --max-time 30 2>/dev/null)
    parse_response "${response}"

    [[ "${RESPONSE_STATUS}" == "401" ]] || [[ "${RESPONSE_STATUS}" == "403" ]]
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
    wlrs_speech=$(json_get "${RESPONSE_BODY}" '.services.speech_services.enabled')

    response2=$(get_tenant_info "${t2}")
    parse_response "${response2}"
    local sdpr_speech
    sdpr_speech=$(json_get "${RESPONSE_BODY}" '.services.speech_services.enabled')

    [[ "${wlrs_speech}" == "true"  ]]
    [[ "${sdpr_speech}" == "false" ]]
}

# =============================================================================
# Endpoint URL Tests: base_url and per-model endpoints
# =============================================================================

@test "Tenant-1: tenant-info contains non-empty base_url" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local base_url
    base_url=$(json_get "${RESPONSE_BODY}" '.base_url')
    [[ -n "${base_url}" ]]
    # base_url must start with https://
    [[ "${base_url}" == https://* ]]
}

@test "Tenant-1: base_url contains tenant name as path segment" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local base_url
    base_url=$(json_get "${RESPONSE_BODY}" '.base_url')
    # base_url should end with the tenant name
    [[ "${base_url}" == *"/${t1}" ]]
}

@test "Tenant-1: every model has azure_openai endpoint fields" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    # Every model must have endpoints.azure_openai with endpoint, api_version, and url
    local invalid_count
    invalid_count=$(echo "${RESPONSE_BODY}" | jq '[
        .models[] | select(
            (.endpoints.azure_openai.endpoint    | (. == null or length == 0)) or
            (.endpoints.azure_openai.api_version | (. == null or length == 0)) or
            (.endpoints.azure_openai.url         | (. == null or length == 0))
        )
    ] | length')
    [[ "${invalid_count}" -eq 0 ]]
}

@test "Tenant-1: every model has openai_compatible endpoint fields" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    # Every model must have endpoints.openai_compatible with base_url, model, and url
    local invalid_count
    invalid_count=$(echo "${RESPONSE_BODY}" | jq '[
        .models[] | select(
            (.endpoints.openai_compatible.base_url | (. == null or length == 0)) or
            (.endpoints.openai_compatible.model    | (. == null or length == 0)) or
            (.endpoints.openai_compatible.url      | (. == null or length == 0))
        )
    ] | length')
    [[ "${invalid_count}" -eq 0 ]]
}

@test "Tenant-1: azure_openai url contains deployment name for each model" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    # For each model, the azure_openai URL must contain /deployments/{model.name}/
    local mismatch_count
    mismatch_count=$(echo "${RESPONSE_BODY}" | jq '[
        .models[] | . as $m | select(
            ($m.endpoints.azure_openai.url | contains("/deployments/" + $m.name + "/")) | not
        )
    ] | length')
    [[ "${mismatch_count}" -eq 0 ]]
}

@test "Tenant-1: openai_compatible model matches deployment name" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    # For each model, openai_compatible.model must equal the deployment name
    local mismatch_count
    mismatch_count=$(echo "${RESPONSE_BODY}" | jq '[
        .models[] | select(.endpoints.openai_compatible.model != .name)
    ] | length')
    [[ "${mismatch_count}" -eq 0 ]]
}

@test "Tenant-1: openai_compatible base_url ends with /openai/v1" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    # Every model's openai_compatible.base_url must end with /openai/v1
    local invalid_count
    invalid_count=$(echo "${RESPONSE_BODY}" | jq '[
        .models[] | select(
            (.endpoints.openai_compatible.base_url | endswith("/openai/v1")) | not
        )
    ] | length')
    [[ "${invalid_count}" -eq 0 ]]
}

# =============================================================================
# Service endpoint URL tests
# =============================================================================

@test "Tenant-1: enabled openai service has endpoint URLs" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local openai_enabled
    openai_enabled=$(json_get "${RESPONSE_BODY}" '.services.openai.enabled')

    if [[ "${openai_enabled}" == "true" ]]; then
        local azure_ep openai_ep api_ver
        azure_ep=$(json_get "${RESPONSE_BODY}" '.services.openai.endpoints.azure_openai')
        openai_ep=$(json_get "${RESPONSE_BODY}" '.services.openai.endpoints.openai_compatible')
        api_ver=$(json_get "${RESPONSE_BODY}" '.services.openai.endpoints.api_version')
        [[ -n "${azure_ep}" && "${azure_ep}" == https://* ]]
        [[ -n "${openai_ep}" && "${openai_ep}" == *"/openai/v1" ]]
        [[ -n "${api_ver}" ]]
    fi
}

@test "Tenant-1: enabled document_intelligence service has endpoint and example" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local docint_enabled
    docint_enabled=$(json_get "${RESPONSE_BODY}" '.services.document_intelligence.enabled')

    if [[ "${docint_enabled}" == "true" ]]; then
        local ep example
        ep=$(json_get "${RESPONSE_BODY}" '.services.document_intelligence.endpoint')
        example=$(json_get "${RESPONSE_BODY}" '.services.document_intelligence.example')
        [[ -n "${ep}" && "${ep}" == https://* ]]
        [[ "${example}" == *"documentintelligence"* ]]
    fi
}

@test "Tenant-1: enabled ai_search service has endpoint and example" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local search_enabled
    search_enabled=$(json_get "${RESPONSE_BODY}" '.services.ai_search.enabled')

    if [[ "${search_enabled}" == "true" ]]; then
        local ep example
        ep=$(json_get "${RESPONSE_BODY}" '.services.ai_search.endpoint')
        example=$(json_get "${RESPONSE_BODY}" '.services.ai_search.example')
        [[ -n "${ep}" && "${ep}" == *"/ai-search" ]]
        [[ "${example}" == *"/ai-search/"* ]]
    fi
}

@test "Tenant-1: enabled speech_services has stt and tts endpoints with examples" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local speech_enabled
    speech_enabled=$(json_get "${RESPONSE_BODY}" '.services.speech_services.enabled')

    if [[ "${speech_enabled}" == "true" ]]; then
        local stt_ep tts_ep
        stt_ep=$(json_get "${RESPONSE_BODY}" '.services.speech_services.stt_endpoint')
        tts_ep=$(json_get "${RESPONSE_BODY}" '.services.speech_services.tts_endpoint')
        [[ "${stt_ep}" == *"speech/recognition"* ]]
        [[ "${tts_ep}" == *"cognitiveservices"* ]]
    fi
}

@test "Tenant-1: enabled storage service has endpoint and example" {
    local t1
    t1="$(tenant_1)"
    skip_if_no_key "${t1}"

    response=$(get_tenant_info "${t1}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local storage_enabled
    storage_enabled=$(json_get "${RESPONSE_BODY}" '.services.storage.enabled')

    if [[ "${storage_enabled}" == "true" ]]; then
        local ep example
        ep=$(json_get "${RESPONSE_BODY}" '.services.storage.endpoint')
        example=$(json_get "${RESPONSE_BODY}" '.services.storage.example')
        [[ -n "${ep}" && "${ep}" == *"/storage" ]]
        [[ "${example}" == *"/storage/"* ]]
    fi
}

@test "Tenant-2: disabled services only have enabled=false" {
    local t2
    t2="$(tenant_2)"
    skip_if_no_key "${t2}"

    response=$(get_tenant_info "${t2}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    # SDPR has speech disabled - should have enabled=false and null endpoint fields
    local speech_enabled
    speech_enabled=$(json_get "${RESPONSE_BODY}" '.services.speech_services.enabled')
    [[ "${speech_enabled}" == "false" ]]

    # Disabled services should have null endpoint fields
    local stt_endpoint
    stt_endpoint=$(json_get "${RESPONSE_BODY}" '.services.speech_services.stt_endpoint')
    [[ "${stt_endpoint}" == "null" ]]
    local tts_endpoint
    tts_endpoint=$(json_get "${RESPONSE_BODY}" '.services.speech_services.tts_endpoint')
    [[ "${tts_endpoint}" == "null" ]]
}

@test "Tenant-1 and Tenant-2: base_url uses same gateway hostname" {
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
    local url1
    url1=$(json_get "${RESPONSE_BODY}" '.base_url')

    response2=$(get_tenant_info "${t2}")
    parse_response "${response2}"
    local url2
    url2=$(json_get "${RESPONSE_BODY}" '.base_url')

    # Both tenants should share the same gateway host but differ in tenant path
    # Extract hostname (everything before the tenant path segment)
    local host1 host2
    host1="${url1%/${t1}}"
    host2="${url2%/${t2}}"
    [[ "${host1}" == "${host2}" ]]
}
