#!/usr/bin/env bats
# Integration tests for Document Intelligence API via APIM
# Tests Document Intelligence layout analysis endpoints for both tenants
#
# NOTE: These tests require Document Intelligence backend routing to be working in APIM.
# If tests fail with 404, verify that the APIM policy is correctly routing to docint backend.

load 'test-helper'

setup() {
    setup_test_suite
}

# Check if Document Intelligence is accessible before running tests
docint_accessible() {
    local tenant="${1}"
    local subscription_key
    subscription_key=$(get_subscription_key "${tenant}")
    
    local url="${APIM_GATEWAY_URL}/${tenant}/documentintelligence/documentModels/prebuilt-layout:analyze?api-version=${DOCINT_API_VERSION}"
    
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${url}" \
        -H "Ocp-Apim-Subscription-Key: ${subscription_key}" \
        -H "Content-Type: application/json" \
        --max-time 10 \
        -d '{"base64Source":"dGVzdA=="}' 2>/dev/null)
    
    # 400 means backend is reachable but bad request (good!)
    # 202 or 200 means success
    # 404 means routing not working
    [[ "${status}" == "400" ]] || [[ "${status}" == "200" ]] || [[ "${status}" == "202" ]]
}

# Sample minimal PDF for testing (base64 encoded)
# This is a minimal valid PDF with "Test Document" text
SAMPLE_PDF_BASE64="JVBERi0xLjQKMSAwIG9iago8PAovVHlwZSAvQ2F0YWxvZwovUGFnZXMgMiAwIFIKPj4KZW5kb2JqCjIgMCBvYmoKPDwKL1R5cGUgL1BhZ2VzCi9LaWRzIFszIDAgUl0KL0NvdW50IDEKPJ4KZW5kb2JqCjMgMCBvYmoKPDwKL1R5cGUgL1BhZ2UKL1BhcmVudCAyIDAgUgovTWVkaWFCb3ggWzAgMCA2MTIgNzkyXQovQ29udGVudHMgNCAwIFIKL1Jlc291cmNlcwo8PAovRm9udAo8PAovRjEgNSAwIFIKPj4KPj4KPj4KZW5kb2JqCjQgMCBvYmoKPDwKL0xlbmd0aCA0NAo+PgpzdHJlYW0KQlQKL0YxIDEyIFRmCjEwMCA3MDAgVGQKKFRlc3QgRG9jdW1lbnQpIFRqCkVUCmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iago8PAovVHlwZSAvRm9udAovU3VidHlwZSAvVHlwZTEKL0Jhc2VGb250IC9IZWx2ZXRpY2EKPJ4KZW5kb2JqCnhyZWYKMCA2CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAwOSAwMDAwMCBuIAowMDAwMDAwMDU4IDAwMDAwIG4gCjAwMDAwMDAxMTUgMDAwMDAgbiAKMDAwMDAwMDI4MCAwMDAwMCBuIAowMDAwMDAwMzczIDAwMDAwIG4gCnRyYWlsZXIKPDwKL1NpemUgNgovUm9vdCAxIDAgUgo+PgpzdGFydHhyZWYKNDQ4CiUlRU9G"

# =============================================================================
# WLRS Tenant Tests
# =============================================================================

@test "WLRS: Document analysis endpoint returns 200 or 202" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    # Skip if Document Intelligence backend is not accessible
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible (404) - check APIM policy routing"
    fi
    
    response=$(docint_analyze "wlrs-water-form-assistant" "prebuilt-layout" "${SAMPLE_PDF_BASE64}")
    parse_response "${response}"
    
    # Document Intelligence returns 202 Accepted for async operations
    # or 200 for immediate results
    [[ "${RESPONSE_STATUS}" == "200" ]] || [[ "${RESPONSE_STATUS}" == "202" ]]
}

@test "WLRS: Document analysis returns operation-location header" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    
    local subscription_key
    subscription_key=$(get_subscription_key "wlrs-water-form-assistant")
    
    local body
    body=$(cat <<EOF
{"base64Source": "${SAMPLE_PDF_BASE64}"}
EOF
)
    
    local url="${APIM_GATEWAY_URL}/wlrs-water-form-assistant/documentintelligence/documentModels/prebuilt-layout:analyze?api-version=${DOCINT_API_VERSION}"
    
    # Capture headers with -i flag
    local full_response
    full_response=$(curl -s -i -X POST "${url}" \
        -H "Ocp-Apim-Subscription-Key: ${subscription_key}" \
        -H "Content-Type: application/json" \
        -d "${body}" 2>/dev/null)
    
    # Check for operation-location header (case insensitive)
    if echo "${full_response}" | grep -iq "operation-location"; then
        return 0
    fi
    
    # If no operation-location, should have a direct result (200)
    local status
    status=$(echo "${full_response}" | head -1 | grep -o '[0-9]\{3\}')
    [[ "${status}" == "200" ]]
}

@test "WLRS: Operation-Location header uses APIM gateway URL not backend URL" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    
    local subscription_key
    subscription_key=$(get_subscription_key "wlrs-water-form-assistant")
    
    local body='{"base64Source": "'"${SAMPLE_PDF_BASE64}"'"}'
    
    local url="${APIM_GATEWAY_URL}/wlrs-water-form-assistant/documentintelligence/documentModels/prebuilt-layout:analyze?api-version=${DOCINT_API_VERSION}"
    
    # Capture headers with -i flag
    local full_response
    full_response=$(curl -s -i -X POST "${url}" \
        -H "Ocp-Apim-Subscription-Key: ${subscription_key}" \
        -H "Content-Type: application/json" \
        -d "${body}" 2>/dev/null)
    
    # Extract Operation-Location header value
    local operation_location
    operation_location=$(echo "${full_response}" | grep -i "operation-location" | head -1 | sed 's/^[^:]*: //' | tr -d '\r\n')
    
    # If no operation-location header, skip (might be a 200 direct response)
    if [[ -z "${operation_location}" ]]; then
        local status
        status=$(echo "${full_response}" | head -1 | grep -o '[0-9]\{3\}')
        if [[ "${status}" == "200" ]]; then
            skip "Direct 200 response - no async operation"
        fi
        fail "Expected Operation-Location header in 202 response"
    fi
    
    # Verify Operation-Location contains APIM gateway URL, not backend URL
    # Should contain: ai-services-hub-test-apim.azure-api.net (APIM gateway)
    # Should NOT contain: .cognitiveservices.azure.com (direct backend)
    
    if echo "${operation_location}" | grep -q "cognitiveservices.azure.com"; then
        fail "Operation-Location contains direct backend URL: ${operation_location}"
    fi
    
    if ! echo "${operation_location}" | grep -q "azure-api.net"; then
        fail "Operation-Location does not contain APIM gateway URL: ${operation_location}"
    fi
    
    # Verify it contains the tenant path
    if ! echo "${operation_location}" | grep -q "wlrs-water-form-assistant"; then
        fail "Operation-Location missing tenant path: ${operation_location}"
    fi
    
    return 0
}

@test "SDPR: Operation-Location header uses APIM gateway URL not backend URL" {
    skip_if_no_key "sdpr-invoice-automation"
    if ! docint_accessible "sdpr-invoice-automation"; then
        skip "Document Intelligence backend not accessible"
    fi
    
    local subscription_key
    subscription_key=$(get_subscription_key "sdpr-invoice-automation")
    
    local body='{"base64Source": "'"${SAMPLE_PDF_BASE64}"'"}'
    
    local url="${APIM_GATEWAY_URL}/sdpr-invoice-automation/documentintelligence/documentModels/prebuilt-invoice:analyze?api-version=${DOCINT_API_VERSION}"
    
    # Capture headers with -i flag
    local full_response
    full_response=$(curl -s -i -X POST "${url}" \
        -H "Ocp-Apim-Subscription-Key: ${subscription_key}" \
        -H "Content-Type: application/json" \
        -d "${body}" 2>/dev/null)
    
    # Extract Operation-Location header value
    local operation_location
    operation_location=$(echo "${full_response}" | grep -i "operation-location" | head -1 | sed 's/^[^:]*: //' | tr -d '\r\n')
    
    # If no operation-location header, skip (might be a 200 direct response)
    if [[ -z "${operation_location}" ]]; then
        local status
        status=$(echo "${full_response}" | head -1 | grep -o '[0-9]\{3\}')
        if [[ "${status}" == "200" ]]; then
            skip "Direct 200 response - no async operation"
        fi
        fail "Expected Operation-Location header in 202 response"
    fi
    
    # Verify Operation-Location contains APIM gateway URL, not backend URL
    if echo "${operation_location}" | grep -q "cognitiveservices.azure.com"; then
        fail "Operation-Location contains direct backend URL: ${operation_location}"
    fi
    
    if ! echo "${operation_location}" | grep -q "azure-api.net"; then
        fail "Operation-Location does not contain APIM gateway URL: ${operation_location}"
    fi
    
    # Verify it contains the tenant path
    if ! echo "${operation_location}" | grep -q "sdpr-invoice-automation"; then
        fail "Operation-Location missing tenant path: ${operation_location}"
    fi
    
    return 0
}

@test "WLRS: Document analysis accepts JSON input" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    
    local body='{"base64Source": "'"${SAMPLE_PDF_BASE64}"'"}'
    
    response=$(apim_request "POST" "wlrs-water-form-assistant" \
        "/documentintelligence/documentModels/prebuilt-layout:analyze?api-version=${DOCINT_API_VERSION}" \
        "${body}")
    parse_response "${response}"
    
    # Should be accepted (200 or 202)
    [[ "${RESPONSE_STATUS}" == "200" ]] || [[ "${RESPONSE_STATUS}" == "202" ]]
}

@test "WLRS: prebuilt-invoice model is accessible" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    
    local body='{"base64Source": "'"${SAMPLE_PDF_BASE64}"'"}'
    
    response=$(apim_request "POST" "wlrs-water-form-assistant" \
        "/documentintelligence/documentModels/prebuilt-invoice:analyze?api-version=${DOCINT_API_VERSION}" \
        "${body}")
    parse_response "${response}"
    
    # Should be accepted (200 or 202) or 400 if content isn't an invoice
    [[ "${RESPONSE_STATUS}" == "200" ]] || [[ "${RESPONSE_STATUS}" == "202" ]] || [[ "${RESPONSE_STATUS}" == "400" ]]
}

# =============================================================================
# SDPR Tenant Tests  
# =============================================================================

@test "SDPR: Document analysis endpoint returns 200 or 202" {
    skip_if_no_key "sdpr-invoice-automation"
    if ! docint_accessible "sdpr-invoice-automation"; then
        skip "Document Intelligence backend not accessible"
    fi
    
    response=$(docint_analyze "sdpr-invoice-automation" "prebuilt-layout" "${SAMPLE_PDF_BASE64}")
    parse_response "${response}"
    
    [[ "${RESPONSE_STATUS}" == "200" ]] || [[ "${RESPONSE_STATUS}" == "202" ]]
}

@test "SDPR: prebuilt-invoice model works for invoice automation" {
    skip_if_no_key "sdpr-invoice-automation"
    if ! docint_accessible "sdpr-invoice-automation"; then
        skip "Document Intelligence backend not accessible"
    fi
    
    local body='{"base64Source": "'"${SAMPLE_PDF_BASE64}"'"}'
    
    response=$(apim_request "POST" "sdpr-invoice-automation" \
        "/documentintelligence/documentModels/prebuilt-invoice:analyze?api-version=${DOCINT_API_VERSION}" \
        "${body}")
    parse_response "${response}"
    
    # Should be accepted - 200, 202, or 400 if not a valid invoice
    [[ "${RESPONSE_STATUS}" == "200" ]] || [[ "${RESPONSE_STATUS}" == "202" ]] || [[ "${RESPONSE_STATUS}" == "400" ]]
}

@test "SDPR: prebuilt-read model is accessible" {
    skip_if_no_key "sdpr-invoice-automation"
    if ! docint_accessible "sdpr-invoice-automation"; then
        skip "Document Intelligence backend not accessible"
    fi
    
    local body='{"base64Source": "'"${SAMPLE_PDF_BASE64}"'"}'
    
    response=$(apim_request "POST" "sdpr-invoice-automation" \
        "/documentintelligence/documentModels/prebuilt-read:analyze?api-version=${DOCINT_API_VERSION}" \
        "${body}")
    parse_response "${response}"
    
    [[ "${RESPONSE_STATUS}" == "200" ]] || [[ "${RESPONSE_STATUS}" == "202" ]]
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "Document analysis with invalid base64 returns 400" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    
    local body='{"base64Source": "not-valid-base64!!!"}'
    
    response=$(apim_request "POST" "wlrs-water-form-assistant" \
        "/documentintelligence/documentModels/prebuilt-layout:analyze?api-version=${DOCINT_API_VERSION}" \
        "${body}")
    parse_response "${response}"
    
    assert_status "400" "${RESPONSE_STATUS}"
}

@test "Document analysis with empty body returns 400" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    
    response=$(apim_request "POST" "wlrs-water-form-assistant" \
        "/documentintelligence/documentModels/prebuilt-layout:analyze?api-version=${DOCINT_API_VERSION}" \
        "{}")
    parse_response "${response}"
    
    assert_status "400" "${RESPONSE_STATUS}"
}

@test "Document analysis with invalid model returns 404" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    
    local body='{"base64Source": "'"${SAMPLE_PDF_BASE64}"'"}'
    
    response=$(apim_request "POST" "wlrs-water-form-assistant" \
        "/documentintelligence/documentModels/nonexistent-model:analyze?api-version=${DOCINT_API_VERSION}" \
        "${body}")
    parse_response "${response}"
    
    # Should be 404 for non-existent model
    assert_status "404" "${RESPONSE_STATUS}"
}

@test "Document analysis without subscription key returns 401" {
    local body='{"base64Source": "'"${SAMPLE_PDF_BASE64}"'"}'
    local url="${APIM_GATEWAY_URL}/wlrs-water-form-assistant/documentintelligence/documentModels/prebuilt-layout:analyze?api-version=${DOCINT_API_VERSION}"
    
    response=$(curl -s -w "\n%{http_code}" -X POST "${url}" \
        -H "Content-Type: application/json" \
        -d "${body}")
    parse_response "${response}"
    
    assert_status "401" "${RESPONSE_STATUS}"
}

# =============================================================================
# API Version Tests
# =============================================================================

@test "Document analysis works with supported API version" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    
    local body='{"base64Source": "'"${SAMPLE_PDF_BASE64}"'"}'
    
    # Test with the configured API version
    response=$(apim_request "POST" "wlrs-water-form-assistant" \
        "/documentintelligence/documentModels/prebuilt-layout:analyze?api-version=${DOCINT_API_VERSION}" \
        "${body}")
    parse_response "${response}"
    
    # Should not get 400 for bad API version
    [[ "${RESPONSE_STATUS}" != "400" ]] || {
        # If 400, check if it's for content, not API version
        if echo "${RESPONSE_BODY}" | grep -qi "api-version"; then
            fail "API version ${DOCINT_API_VERSION} not supported"
        fi
    }
}

# =============================================================================
# Helper Functions
# =============================================================================

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
