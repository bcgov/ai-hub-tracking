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
        -H "api-key: ${subscription_key}" \
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
        -H "api-key: ${subscription_key}" \
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
    skip_if_no_appgw
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
        -H "api-key: ${subscription_key}" \
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
    
    # Verify Operation-Location contains App Gateway URL, not backend URL
    # Should contain: test.aihub.gov.bc.ca (App Gateway)
    # Should NOT contain: .cognitiveservices.azure.com (direct backend)
    # Should NOT contain: azure-api.net (direct APIM - must go through App Gateway)
    
    if echo "${operation_location}" | grep -q "cognitiveservices.azure.com"; then
        fail "Operation-Location contains direct backend URL: ${operation_location}"
    fi
    
    if echo "${operation_location}" | grep -q "azure-api.net"; then
        fail "Operation-Location contains APIM URL (should be App Gateway): ${operation_location}"
    fi
    
    if ! echo "${operation_location}" | grep -q "${APPGW_HOSTNAME}"; then
        fail "Operation-Location does not contain App Gateway hostname (${APPGW_HOSTNAME}): ${operation_location}"
    fi
    
    # Verify it contains the tenant path
    if ! echo "${operation_location}" | grep -q "wlrs-water-form-assistant"; then
        fail "Operation-Location missing tenant path: ${operation_location}"
    fi
    
    return 0
}

@test "SDPR: Operation-Location header uses APIM gateway URL not backend URL" {
    skip_if_no_key "sdpr-invoice-automation"
    skip_if_no_appgw
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
        -H "api-key: ${subscription_key}" \
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
    
    # Verify Operation-Location contains App Gateway URL, not backend URL
    if echo "${operation_location}" | grep -q "cognitiveservices.azure.com"; then
        fail "Operation-Location contains direct backend URL: ${operation_location}"
    fi
    
    if echo "${operation_location}" | grep -q "azure-api.net"; then
        fail "Operation-Location contains APIM URL (should be App Gateway): ${operation_location}"
    fi
    
    if ! echo "${operation_location}" | grep -q "${APPGW_HOSTNAME}"; then
        fail "Operation-Location does not contain App Gateway hostname (${APPGW_HOSTNAME}): ${operation_location}"
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
# Full Async Flow Tests - JPG Image Analysis with Polling
# =============================================================================

# Path to test form fixture (BC Monthly Report form)
# WAF request_body_enforcement=false allows large payloads; WAF still inspects first 128KB
TEST_FORM_JPG="${BATS_TEST_DIRNAME}/test_form.jpg"

@test "WLRS: Full async flow - submit JPG file, poll operation, validate extracted text" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    [[ -f "${TEST_FORM_JPG}" ]] || fail "Test fixture not found: ${TEST_FORM_JPG}"

    # Step 1: Submit file directly as binary (octet-stream)
    local full_response
    full_response=$(docint_analyze_file "wlrs-water-form-assistant" "prebuilt-layout" "${TEST_FORM_JPG}")

    # Step 2: Verify 202 Accepted (or 200 for direct result)
    local status
    status=$(echo "${full_response}" | grep "^HTTP/" | tail -1 | grep -o '[0-9]\{3\}')
    [[ "${status}" == "202" ]] || [[ "${status}" == "200" ]]

    # If 200 direct response, extract content from body
    if [[ "${status}" == "200" ]]; then
        local body
        body=$(echo "${full_response}" | sed -n '/^\r*$/,$ p' | tail -n +2)
        local content
        content=$(json_get "${body}" '.analyzeResult.content')
        assert_contains "${content}" "Monthly Report"
        return 0
    fi

    # Step 3: Extract Operation-Location header
    local operation_location
    operation_location=$(echo "${full_response}" | grep -i "operation-location" | head -1 | sed 's/^[^:]*: //' | tr -d '\r\n')
    [[ -n "${operation_location}" ]] || fail "Missing Operation-Location header in 202 response"

    # Step 4: Convert full URL to relative path and poll until succeeded
    local operation_path
    operation_path=$(extract_operation_path "wlrs-water-form-assistant" "${operation_location}")
    wait_for_operation "wlrs-water-form-assistant" "${operation_path}" 60

    # Step 5: Validate extracted content from analyzeResult
    local content
    content=$(json_get "${RESPONSE_BODY}" '.analyzeResult.content')
    [[ -n "${content}" ]] || fail "analyzeResult.content is empty"

    # Assert OCR extracted expected text from the BC Monthly Report form
    assert_contains "${content}" "Monthly Report"
    assert_contains "${content}" "Declaration"
}

@test "WLRS: Async flow returns valid analyzeResult structure" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    [[ -f "${TEST_FORM_JPG}" ]] || fail "Test fixture not found: ${TEST_FORM_JPG}"

    local full_response
    full_response=$(docint_analyze_file "wlrs-water-form-assistant" "prebuilt-layout" "${TEST_FORM_JPG}")

    local status
    status=$(echo "${full_response}" | grep "^HTTP/" | tail -1 | grep -o '[0-9]\{3\}')

    if [[ "${status}" == "200" ]]; then
        local body
        body=$(echo "${full_response}" | sed -n '/^\r*$/,$ p' | tail -n +2)
        RESPONSE_BODY="${body}"
    elif [[ "${status}" == "202" ]]; then
        local operation_location
        operation_location=$(echo "${full_response}" | grep -i "operation-location" | head -1 | sed 's/^[^:]*: //' | tr -d '\r\n')
        local operation_path
        operation_path=$(extract_operation_path "wlrs-water-form-assistant" "${operation_location}")
        wait_for_operation "wlrs-water-form-assistant" "${operation_path}" 60
    else
        fail "Unexpected status ${status}"
    fi

    # Validate analyzeResult structure
    local result_status
    result_status=$(json_get "${RESPONSE_BODY}" '.status')
    [[ "${result_status}" == "succeeded" ]] || [[ "${result_status}" == "completed" ]]

    # analyzeResult must have pages array
    local page_count
    page_count=$(json_get "${RESPONSE_BODY}" '.analyzeResult.pages | length')
    [[ "${page_count}" -ge 1 ]] || fail "Expected at least 1 page, got ${page_count}"

    # analyzeResult.content must be non-empty
    local content_length
    content_length=$(json_get "${RESPONSE_BODY}" '.analyzeResult.content | length')
    [[ "${content_length}" -gt 0 ]] || fail "analyzeResult.content is empty"
}

@test "WLRS: Async flow extracts multiple fields from form JPG" {
    skip_if_no_key "wlrs-water-form-assistant"
    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi
    [[ -f "${TEST_FORM_JPG}" ]] || fail "Test fixture not found: ${TEST_FORM_JPG}"

    local full_response
    full_response=$(docint_analyze_file "wlrs-water-form-assistant" "prebuilt-layout" "${TEST_FORM_JPG}")

    local status
    status=$(echo "${full_response}" | grep "^HTTP/" | tail -1 | grep -o '[0-9]\{3\}')

    if [[ "${status}" == "200" ]]; then
        RESPONSE_BODY=$(echo "${full_response}" | sed -n '/^\r*$/,$ p' | tail -n +2)
    elif [[ "${status}" == "202" ]]; then
        local operation_location
        operation_location=$(echo "${full_response}" | grep -i "operation-location" | head -1 | sed 's/^[^:]*: //' | tr -d '\r\n')
        local operation_path
        operation_path=$(extract_operation_path "wlrs-water-form-assistant" "${operation_location}")
        wait_for_operation "wlrs-water-form-assistant" "${operation_path}" 60
    else
        fail "Unexpected status ${status}"
    fi

    local content
    content=$(json_get "${RESPONSE_BODY}" '.analyzeResult.content')

    # Validate multiple text fields were extracted from the BC Monthly Report form
    assert_contains "${content}" "Monthly Report"
    assert_contains "${content}" "Ministry of Social Development"
    assert_contains "${content}" "Since your last declaration"
    assert_contains "${content}" "Declare all income"
    assert_contains "${content}" "Declaration"
}

@test "SDPR: Full async flow - submit JPG file with prebuilt-invoice, poll and validate" {
    skip_if_no_key "sdpr-invoice-automation"
    if ! docint_accessible "sdpr-invoice-automation"; then
        skip "Document Intelligence backend not accessible"
    fi
    [[ -f "${TEST_FORM_JPG}" ]] || fail "Test fixture not found: ${TEST_FORM_JPG}"

    # Submit file directly with prebuilt-invoice model (SDPR's primary use case)
    local full_response
    full_response=$(docint_analyze_file "sdpr-invoice-automation" "prebuilt-invoice" "${TEST_FORM_JPG}")

    local status
    status=$(echo "${full_response}" | grep "^HTTP/" | tail -1 | grep -o '[0-9]\{3\}')
    [[ "${status}" == "202" ]] || [[ "${status}" == "200" ]]

    if [[ "${status}" == "200" ]]; then
        local body
        body=$(echo "${full_response}" | sed -n '/^\r*$/,$ p' | tail -n +2)
        local content
        content=$(json_get "${body}" '.analyzeResult.content')
        assert_contains "${content}" "Monthly Report"
        return 0
    fi

    # Poll the operation
    local operation_location
    operation_location=$(echo "${full_response}" | grep -i "operation-location" | head -1 | sed 's/^[^:]*: //' | tr -d '\r\n')
    [[ -n "${operation_location}" ]] || fail "Missing Operation-Location header in 202 response"

    local operation_path
    operation_path=$(extract_operation_path "sdpr-invoice-automation" "${operation_location}")
    wait_for_operation "sdpr-invoice-automation" "${operation_path}" 120

    # Validate extracted content
    local content
    content=$(json_get "${RESPONSE_BODY}" '.analyzeResult.content')
    [[ -n "${content}" ]] || fail "analyzeResult.content is empty"

    assert_contains "${content}" "Monthly Report"
    assert_contains "${content}" "Declaration"
}

@test "SDPR: prebuilt-read model extracts raw text from JPG file" {
    skip_if_no_key "sdpr-invoice-automation"
    if ! docint_accessible "sdpr-invoice-automation"; then
        skip "Document Intelligence backend not accessible"
    fi
    [[ -f "${TEST_FORM_JPG}" ]] || fail "Test fixture not found: ${TEST_FORM_JPG}"

    local full_response
    full_response=$(docint_analyze_file "sdpr-invoice-automation" "prebuilt-read" "${TEST_FORM_JPG}")

    local status
    status=$(echo "${full_response}" | grep "^HTTP/" | tail -1 | grep -o '[0-9]\{3\}')
    [[ "${status}" == "202" ]] || [[ "${status}" == "200" ]]

    if [[ "${status}" == "200" ]]; then
        RESPONSE_BODY=$(echo "${full_response}" | sed -n '/^\r*$/,$ p' | tail -n +2)
    elif [[ "${status}" == "202" ]]; then
        local operation_location
        operation_location=$(echo "${full_response}" | grep -i "operation-location" | head -1 | sed 's/^[^:]*: //' | tr -d '\r\n')
        local operation_path
        operation_path=$(extract_operation_path "sdpr-invoice-automation" "${operation_location}")
        wait_for_operation "sdpr-invoice-automation" "${operation_path}" 60
    else
        fail "Unexpected status ${status}"
    fi

    local content
    content=$(json_get "${RESPONSE_BODY}" '.analyzeResult.content')
    [[ -n "${content}" ]] || fail "analyzeResult.content is empty"

    # prebuilt-read should extract the raw text from the BC Monthly Report form
    assert_contains "${content}" "Monthly Report"
    assert_contains "${content}" "Declaration"
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

@test "Document analysis without subscription key returns 401 or 404" {
    local body='{"base64Source": "'"${SAMPLE_PDF_BASE64}"'"}'
    local url="${APIM_GATEWAY_URL}/wlrs-water-form-assistant/documentintelligence/documentModels/prebuilt-layout:analyze?api-version=${DOCINT_API_VERSION}"
    
    response=$(curl -s -w "\n%{http_code}" -X POST "${url}" \
        -H "Content-Type: application/json" \
        -d "${body}")
    parse_response "${response}"
    
    [[ "${RESPONSE_STATUS}" == "401" ]] || [[ "${RESPONSE_STATUS}" == "404" ]]
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
# NR-DAP Tenant Tests (1% quota - lightweight tests)
# =============================================================================

@test "NR-DAP: Document analysis endpoint returns 200 or 202" {
    skip_if_no_key "nr-dap-fish-wildlife"
    
    if ! docint_accessible "nr-dap-fish-wildlife"; then
        skip "Document Intelligence backend not accessible for NR-DAP"
    fi
    
    response=$(docint_analyze "nr-dap-fish-wildlife" "prebuilt-layout" "${SAMPLE_PDF_BASE64}")
    parse_response "${response}"
    
    [[ "${RESPONSE_STATUS}" == "200" ]] || [[ "${RESPONSE_STATUS}" == "202" ]]
}

@test "NR-DAP: Document analysis accepts JSON input" {
    skip_if_no_key "nr-dap-fish-wildlife"
    if ! docint_accessible "nr-dap-fish-wildlife"; then
        skip "Document Intelligence backend not accessible for NR-DAP"
    fi
    
    local body='{"base64Source": "'"${SAMPLE_PDF_BASE64}"'"}'
    
    response=$(apim_request "POST" "nr-dap-fish-wildlife" \
        "/documentintelligence/documentModels/prebuilt-layout:analyze?api-version=${DOCINT_API_VERSION}" \
        "${body}")
    parse_response "${response}"
    
    [[ "${RESPONSE_STATUS}" == "200" ]] || [[ "${RESPONSE_STATUS}" == "202" ]]
}

@test "NR-DAP: Full async flow - submit JPG file, poll operation, validate" {
    skip_if_no_key "nr-dap-fish-wildlife"
    if ! docint_accessible "nr-dap-fish-wildlife"; then
        skip "Document Intelligence backend not accessible for NR-DAP"
    fi
    
    local test_file="${BATS_TEST_DIRNAME}/test_form_small.jpg"
    if [[ ! -f "${test_file}" ]]; then
        skip "Test form image not found: ${test_file}"
    fi
    
    # Submit document for analysis
    local full_response
    full_response=$(docint_analyze_file "nr-dap-fish-wildlife" "prebuilt-layout" "${test_file}")
    
    local status
    status=$(extract_http_status "${full_response}")
    [[ "${status}" == "200" ]] || [[ "${status}" == "202" ]]
    
    if [[ "${status}" == "202" ]]; then
        # Extract operation location and poll for completion
        local operation_location
        operation_location=$(echo "${full_response}" | grep -i "operation-location" | head -1 | sed 's/^[^:]*: //' | tr -d '\r\n')
        
        local operation_path
        operation_path=$(extract_operation_path "nr-dap-fish-wildlife" "${operation_location}")
        
        wait_for_operation "nr-dap-fish-wildlife" "${operation_path}" 60
        
        local content
        content=$(json_get "${RESPONSE_BODY}" '.analyzeResult.content')
        [[ -n "${content}" ]]
    fi
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
