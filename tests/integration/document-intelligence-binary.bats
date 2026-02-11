#!/usr/bin/env bats
# Integration tests for Document Intelligence binary file uploads via WAF
# Validates that the WAF custom rule (AllowDocIntelFileUploads) correctly allows
# binary file uploads (application/octet-stream, application/pdf, multipart/form-data)
# through to Document Intelligence without OWASP managed rule inspection.
#
# These tests complement document-intelligence.bats which tests JSON (base64Source)
# payloads. JSON payloads are handled by the existing RequestArgNames WAF exclusion.
#
# WAF Custom Rule Logic (evaluated BEFORE managed rules):
#   IF RequestUri CONTAINS "documentintelligence" OR "formrecognizer"
#   AND Content-Type CONTAINS octet-stream/image/pdf/multipart
#   THEN Allow (bypass managed rules)

load 'test-helper'

setup() {
    setup_test_suite
}

# Path to test form fixture (BC Monthly Report form)
TEST_FORM_JPG="${BATS_TEST_DIRNAME}/test_form.jpg"

# Check if Document Intelligence is accessible before running tests
docint_accessible() {
    local tenant="${1}"
    local subscription_key
    subscription_key=$(get_subscription_key "${tenant}")

    local url="${APIM_GATEWAY_URL}/${tenant}/documentintelligence/documentModels/prebuilt-layout:analyze?api-version=${DOCINT_API_VERSION}"

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${url}" \
        -H "api-key: ${subscription_key}" \
        -H "Content-Type: application/json" \
        --max-time 10 \
        -d '{"base64Source":"dGVzdA=="}' 2>/dev/null)

    [[ "${status}" == "400" ]] || [[ "${status}" == "200" ]] || [[ "${status}" == "202" ]]
}

skip_if_no_key() {
    local tenant="${1}"
    local key
    key=$(get_subscription_key "${tenant}")
    if [[ -z "${key}" ]]; then
        skip "No subscription key for ${tenant}"
    fi
}

fail() {
    echo "$1" >&2
    return 1
}

# =============================================================================
# WLRS Tenant — Binary Upload (application/octet-stream)
# =============================================================================

@test "WLRS: Binary upload (octet-stream) to prebuilt-layout returns 200 or 202" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    [[ -f "${TEST_FORM_JPG}" ]] || skip "Test fixture not found: ${TEST_FORM_JPG}"

    local full_response
    full_response=$(docint_analyze_binary "wlrs-water-form-assistant" "prebuilt-layout" "${TEST_FORM_JPG}")

    local status
    status=$(extract_http_status "${full_response}")

    # WAF should allow this through; backend should accept binary
    if [[ "${status}" == "403" ]]; then
        fail "WAF blocked binary upload (403 Forbidden) — AllowDocIntelFileUploads rule may not be active"
    fi

    [[ "${status}" == "200" ]] || [[ "${status}" == "202" ]]
    echo "  ✓ Binary upload returned HTTP ${status}" >&3
}

@test "WLRS: Binary upload (octet-stream) full async flow — submit, poll, validate text" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    [[ -f "${TEST_FORM_JPG}" ]] || skip "Test fixture not found: ${TEST_FORM_JPG}"

    local full_response
    full_response=$(docint_analyze_binary "wlrs-water-form-assistant" "prebuilt-layout" "${TEST_FORM_JPG}")

    local status
    status=$(extract_http_status "${full_response}")
    [[ "${status}" == "200" ]] || [[ "${status}" == "202" ]]

    if [[ "${status}" == "200" ]]; then
        local body
        body=$(extract_response_body "${full_response}")
        local content
        content=$(json_get "${body}" '.analyzeResult.content')
        assert_contains "${content}" "Monthly Report"
        return 0
    fi

    # 202 Accepted — poll the operation
    local operation_location
    operation_location=$(echo "${full_response}" | grep -i "operation-location" | head -1 | sed 's/^[^:]*: //' | tr -d '\r\n')
    [[ -n "${operation_location}" ]] || fail "Missing Operation-Location header in 202 response"

    local operation_path
    operation_path=$(extract_operation_path "wlrs-water-form-assistant" "${operation_location}")
    wait_for_operation "wlrs-water-form-assistant" "${operation_path}" 60

    local content
    content=$(json_get "${RESPONSE_BODY}" '.analyzeResult.content')
    [[ -n "${content}" ]] || fail "analyzeResult.content is empty"
    assert_contains "${content}" "Monthly Report"

    echo "  ✓ Binary upload OCR extracted expected text" >&3
}

# =============================================================================
# WLRS Tenant — PDF Content-Type Upload
# =============================================================================

@test "WLRS: PDF content-type upload to prebuilt-layout returns 200 or 202" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    [[ -f "${TEST_FORM_JPG}" ]] || skip "Test fixture not found: ${TEST_FORM_JPG}"

    # Send JPG with application/pdf header — Doc Intel rejects format mismatch
    # but WAF should still allow it through (not block with 403)
    local full_response
    full_response=$(docint_analyze_pdf "wlrs-water-form-assistant" "prebuilt-layout" "${TEST_FORM_JPG}")

    local status
    status=$(extract_http_status "${full_response}")

    # WAF must not block with 403
    if [[ "${status}" == "403" ]]; then
        fail "WAF blocked PDF content-type upload (403 Forbidden) — AllowDocIntelFileUploads rule may not cover application/pdf"
    fi

    # Backend may return 200/202 (accepted) or 400 (format mismatch for JPG-as-PDF)
    [[ "${status}" == "200" ]] || [[ "${status}" == "202" ]] || [[ "${status}" == "400" ]]
    echo "  ✓ PDF content-type upload returned HTTP ${status} (not blocked by WAF)" >&3
}

# =============================================================================
# WLRS Tenant — Multipart Form Upload
# =============================================================================

@test "WLRS: Multipart form upload to prebuilt-layout is not blocked by WAF" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    [[ -f "${TEST_FORM_JPG}" ]] || skip "Test fixture not found: ${TEST_FORM_JPG}"

    local full_response
    full_response=$(docint_analyze_multipart "wlrs-water-form-assistant" "prebuilt-layout" "${TEST_FORM_JPG}")

    local status
    status=$(extract_http_status "${full_response}")

    # WAF must not block with 403
    if [[ "${status}" == "403" ]]; then
        fail "WAF blocked multipart upload (403 Forbidden) — AllowDocIntelFileUploads rule may not cover multipart/form-data"
    fi

    # Backend may return 200/202 (accepted) or 400/415 (unsupported media type)
    # The key assertion is that WAF does NOT return 403
    [[ "${status}" == "200" ]] || [[ "${status}" == "202" ]] || [[ "${status}" == "400" ]] || [[ "${status}" == "415" ]]
    echo "  ✓ Multipart upload returned HTTP ${status} (not blocked by WAF)" >&3
}

# =============================================================================
# SDPR Tenant — Binary Upload (application/octet-stream)
# =============================================================================

@test "SDPR: Binary upload (octet-stream) to prebuilt-invoice returns 200 or 202" {
    skip_if_no_key "sdpr-invoice-automation"
    if ! docint_accessible "sdpr-invoice-automation"; then
        skip "Document Intelligence backend not accessible"
    fi
    [[ -f "${TEST_FORM_JPG}" ]] || skip "Test fixture not found: ${TEST_FORM_JPG}"

    local full_response
    full_response=$(docint_analyze_binary "sdpr-invoice-automation" "prebuilt-invoice" "${TEST_FORM_JPG}")

    local status
    status=$(extract_http_status "${full_response}")

    if [[ "${status}" == "403" ]]; then
        fail "WAF blocked binary upload (403 Forbidden) — AllowDocIntelFileUploads rule may not be active"
    fi

    [[ "${status}" == "200" ]] || [[ "${status}" == "202" ]]
    echo "  ✓ SDPR binary upload returned HTTP ${status}" >&3
}

@test "SDPR: Binary upload (octet-stream) full async flow — submit, poll, validate" {
    skip_if_no_key "sdpr-invoice-automation"
    if ! docint_accessible "sdpr-invoice-automation"; then
        skip "Document Intelligence backend not accessible"
    fi
    [[ -f "${TEST_FORM_JPG}" ]] || skip "Test fixture not found: ${TEST_FORM_JPG}"

    local full_response
    full_response=$(docint_analyze_binary "sdpr-invoice-automation" "prebuilt-invoice" "${TEST_FORM_JPG}")

    local status
    status=$(extract_http_status "${full_response}")
    [[ "${status}" == "200" ]] || [[ "${status}" == "202" ]]

    if [[ "${status}" == "200" ]]; then
        local body
        body=$(extract_response_body "${full_response}")
        local content
        content=$(json_get "${body}" '.analyzeResult.content')
        assert_contains "${content}" "Monthly Report"
        return 0
    fi

    local operation_location
    operation_location=$(echo "${full_response}" | grep -i "operation-location" | head -1 | sed 's/^[^:]*: //' | tr -d '\r\n')
    [[ -n "${operation_location}" ]] || fail "Missing Operation-Location header in 202 response"

    local operation_path
    operation_path=$(extract_operation_path "sdpr-invoice-automation" "${operation_location}")
    wait_for_operation "sdpr-invoice-automation" "${operation_path}" 60

    local content
    content=$(json_get "${RESPONSE_BODY}" '.analyzeResult.content')
    [[ -n "${content}" ]] || fail "analyzeResult.content is empty"
    assert_contains "${content}" "Monthly Report"

    echo "  ✓ SDPR binary upload OCR extracted expected text" >&3
}

# =============================================================================
# SDPR Tenant — PDF Content-Type Upload
# =============================================================================

@test "SDPR: PDF content-type upload to prebuilt-invoice is not blocked by WAF" {
    skip_if_no_key "sdpr-invoice-automation"
    if ! docint_accessible "sdpr-invoice-automation"; then
        skip "Document Intelligence backend not accessible"
    fi
    [[ -f "${TEST_FORM_JPG}" ]] || skip "Test fixture not found: ${TEST_FORM_JPG}"

    local full_response
    full_response=$(docint_analyze_pdf "sdpr-invoice-automation" "prebuilt-invoice" "${TEST_FORM_JPG}")

    local status
    status=$(extract_http_status "${full_response}")

    if [[ "${status}" == "403" ]]; then
        fail "WAF blocked PDF content-type upload (403 Forbidden)"
    fi

    [[ "${status}" == "200" ]] || [[ "${status}" == "202" ]] || [[ "${status}" == "400" ]]
    echo "  ✓ SDPR PDF content-type upload returned HTTP ${status} (not blocked by WAF)" >&3
}

# =============================================================================
# Negative Tests — WAF should still block non-Doc-Intel binary paths
# =============================================================================

@test "Binary upload to non-Doc-Intel path is blocked by WAF managed rules" {
    skip_if_no_key "wlrs-water-form-assistant"
    [[ -f "${TEST_FORM_JPG}" ]] || skip "Test fixture not found: ${TEST_FORM_JPG}"

    local subscription_key
    subscription_key=$(get_subscription_key "wlrs-water-form-assistant")

    # Send binary to a non-Doc-Intel path (OpenAI chat completions)
    # WAF custom rule should NOT match (wrong path), so managed rules apply
    local url="${APIM_GATEWAY_URL}/wlrs-water-form-assistant/openai/deployments/gpt-4.1-mini/chat/completions?api-version=${OPENAI_API_VERSION}"

    local full_response
    full_response=$(curl -s -i -X POST "${url}" \
        -H "api-key: ${subscription_key}" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${TEST_FORM_JPG}" \
        --max-time 30 2>/dev/null)

    local status
    status=$(extract_http_status "${full_response}")

    # WAF managed rules should inspect and potentially block this (403)
    # or the backend should reject it (400/415) since OpenAI doesn't accept binary
    # The key assertion: this should NOT return 200/202 with a valid response
    [[ "${status}" != "200" ]] && [[ "${status}" != "202" ]]
    echo "  ✓ Binary upload to non-Doc-Intel path returned HTTP ${status} (not allowed through)" >&3
}

# =============================================================================
# Operation-Location Header Validation for Binary Uploads
# =============================================================================

@test "WLRS: Binary upload Operation-Location uses App Gateway URL" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    [[ -f "${TEST_FORM_JPG}" ]] || skip "Test fixture not found: ${TEST_FORM_JPG}"

    local full_response
    full_response=$(docint_analyze_binary "wlrs-water-form-assistant" "prebuilt-layout" "${TEST_FORM_JPG}")

    local status
    status=$(extract_http_status "${full_response}")

    if [[ "${status}" != "202" ]]; then
        skip "Non-202 response (${status}) — no Operation-Location to validate"
    fi

    local operation_location
    operation_location=$(echo "${full_response}" | grep -i "operation-location" | head -1 | sed 's/^[^:]*: //' | tr -d '\r\n')
    [[ -n "${operation_location}" ]] || fail "Missing Operation-Location header"

    # Must use App Gateway URL, not backend or direct APIM
    if echo "${operation_location}" | grep -q "cognitiveservices.azure.com"; then
        fail "Operation-Location contains direct backend URL: ${operation_location}"
    fi

    if echo "${operation_location}" | grep -q "azure-api.net"; then
        fail "Operation-Location contains APIM URL (should be App Gateway): ${operation_location}"
    fi

    if ! echo "${operation_location}" | grep -q "${APPGW_HOSTNAME}"; then
        fail "Operation-Location missing App Gateway hostname (${APPGW_HOSTNAME}): ${operation_location}"
    fi

    echo "  ✓ Binary upload Operation-Location correctly uses ${APPGW_HOSTNAME}" >&3
}
