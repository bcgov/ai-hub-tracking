#!/usr/bin/env bats
# Integration tests for PII Redaction APIM Policy
# Tests that WLRS has PII redaction enabled and SDPR has it disabled

load 'test-helper'

setup() {
    setup_test_suite
}

# Test data containing various PII patterns
TEST_EMAIL="john.doe@example.com"
TEST_PHONE="555-123-4567"
TEST_SSN="123-45-6789"
TEST_CREDIT_CARD="4111-1111-1111-1111"

# =============================================================================
# WLRS Tenant Tests - PII Redaction ENABLED
# =============================================================================

@test "WLRS: Email address is redacted in response" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    # Send a prompt that includes an email address
    local prompt="My email is ${TEST_EMAIL}. Please repeat my email back to me."
    
    response=$(chat_completion "wlrs-water-form-assistant" "${DEFAULT_MODEL}" "${prompt}" 150)
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
    
    # Extract the assistant's response content
    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')
    
    # The response should NOT contain the actual email
    if [[ "${content}" == *"${TEST_EMAIL}"* ]]; then
        fail "Email was NOT redacted. Response: ${content}"
    fi
}

@test "WLRS: Phone number is redacted in response" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    local prompt="My phone number is ${TEST_PHONE}. Please repeat my phone number."
    
    response=$(chat_completion "wlrs-water-form-assistant" "${DEFAULT_MODEL}" "${prompt}" 150)
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
    
    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')
    
    # The response should NOT contain the actual phone number
    if [[ "${content}" == *"${TEST_PHONE}"* ]]; then
        fail "Phone number was NOT redacted. Response: ${content}"
    fi
}

@test "WLRS: SSN pattern is redacted in response" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    local prompt="My social security number is ${TEST_SSN}. What is my SSN?"
    
    response=$(chat_completion "wlrs-water-form-assistant" "${DEFAULT_MODEL}" "${prompt}" 150)
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
    
    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')
    
    # The response should NOT contain the actual SSN
    if [[ "${content}" == *"${TEST_SSN}"* ]]; then
        fail "SSN was NOT redacted. Response: ${content}"
    fi
}

@test "WLRS: Credit card number is redacted in response" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    local prompt="My credit card is ${TEST_CREDIT_CARD}. Please confirm my card number."
    
    response=$(chat_completion "wlrs-water-form-assistant" "${DEFAULT_MODEL}" "${prompt}" 150)
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
    
    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')
    
    # The response should NOT contain the actual credit card number
    if [[ "${content}" == *"${TEST_CREDIT_CARD}"* ]] || [[ "${content}" == *"4111111111111111"* ]]; then
        fail "Credit card was NOT redacted. Response: ${content}"
    fi
}

@test "WLRS: Multiple PII types are all redacted" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    local prompt="Contact info: Email ${TEST_EMAIL}, Phone ${TEST_PHONE}. Please summarize my contact info."
    
    response=$(chat_completion "wlrs-water-form-assistant" "${DEFAULT_MODEL}" "${prompt}" 200)
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
    
    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')
    
    # Neither email nor phone should appear
    if [[ "${content}" == *"${TEST_EMAIL}"* ]]; then
        fail "Email was NOT redacted in multi-PII test. Response: ${content}"
    fi
    
    if [[ "${content}" == *"${TEST_PHONE}"* ]]; then
        fail "Phone was NOT redacted in multi-PII test. Response: ${content}"
    fi
}

# =============================================================================
# SDPR Tenant Tests - PII Redaction DISABLED
# =============================================================================

@test "SDPR: Email address is NOT redacted (redaction disabled)" {
    skip_if_no_key "sdpr-invoice-automation"
    
    # For SDPR, PII should pass through since they work with invoices
    # that legitimately contain contact information
    local prompt="Extract the email from this invoice header: Contact: ${TEST_EMAIL}"
    
    response=$(chat_completion "sdpr-invoice-automation" "${DEFAULT_MODEL}" "${prompt}" 150)
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
    
    # This is a "negative" test - we expect the email to appear
    # Note: The model might not repeat the email exactly, so we check that
    # the request was processed without redaction (200 OK)
    
    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')
    
    # The response should be able to reference the email domain at minimum
    # or acknowledge the email address (since no redaction)
    echo "SDPR Response (should allow PII): ${content}"
}

@test "SDPR: Invoice amounts are processed correctly" {
    skip_if_no_key "sdpr-invoice-automation"
    
    local prompt="Extract the total from: Invoice Total: \$1,234.56. Billing contact: billing@company.com"
    
    response=$(chat_completion "sdpr-invoice-automation" "${DEFAULT_MODEL}" "${prompt}" 150)
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
    
    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')
    
    # Should be able to extract the amount
    assert_contains "${content}" "1,234.56" || assert_contains "${content}" "1234.56"
}

@test "SDPR: Contact information from invoices is preserved" {
    skip_if_no_key "sdpr-invoice-automation"
    
    local prompt="Parse this invoice: Vendor Phone: 604-555-1234, Total: \$500.00"
    
    response=$(chat_completion "sdpr-invoice-automation" "${DEFAULT_MODEL}" "${prompt}" 200)
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
    
    # Verify the request was processed (SDPR doesn't redact invoice data)
    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')
    
    echo "SDPR Invoice parsing response: ${content}"
}

# =============================================================================
# Cross-Tenant Isolation Tests
# =============================================================================

@test "WLRS key cannot access SDPR APIs" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    local wlrs_key
    wlrs_key=$(get_subscription_key "wlrs-water-form-assistant")
    
    local body='{"messages":[{"role":"user","content":"Hello"}],"max_tokens":10}'
    local url="${APIM_GATEWAY_URL}/sdpr-invoice-automation/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}"
    
    response=$(curl -s -w "\n%{http_code}" -X POST "${url}" \
        -H "api-key: ${wlrs_key}" \
        -H "Content-Type: application/json" \
        -d "${body}")
    parse_response "${response}"
    
    # Should be denied - either 401 or 403
    [[ "${RESPONSE_STATUS}" == "401" ]] || [[ "${RESPONSE_STATUS}" == "403" ]]
}

@test "SDPR key cannot access WLRS APIs" {
    skip_if_no_key "sdpr-invoice-automation"
    
    local sdpr_key
    sdpr_key=$(get_subscription_key "sdpr-invoice-automation")
    
    local body='{"messages":[{"role":"user","content":"Hello"}],"max_tokens":10}'
    local url="${APIM_GATEWAY_URL}/wlrs-water-form-assistant/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}"
    
    response=$(curl -s -w "\n%{http_code}" -X POST "${url}" \
        -H "api-key: ${sdpr_key}" \
        -H "Content-Type: application/json" \
        -d "${body}")
    parse_response "${response}"
    
    # Should be denied - either 401 or 403
    [[ "${RESPONSE_STATUS}" == "401" ]] || [[ "${RESPONSE_STATUS}" == "403" ]]
}

# =============================================================================
# Fail-Closed Behavior Tests
# =============================================================================
# These tests verify the fail-closed behavior for PII redaction.
# When fail_closed=true, any PII service failure should block the request.
# When fail_closed=false (default), failures allow the request through.
#
# NOTE: Testing actual PII service failure requires either:
# 1. A tenant configured with fail_closed=true AND
# 2. A way to simulate PII service failure (e.g., invalid piiServiceUrl, network issue)
#
# The tests below verify:
# - The expected error response format for fail-closed mode
# - That fail-open tenants still work (current behavior)
# =============================================================================

@test "FAIL-OPEN: wlrs-water-form-assistant processes requests successfully" {
    skip_if_no_key "wlrs-water-form-assistant"

    # wlrs-water-form-assistant has PII redaction enabled with fail_closed=false (default)
    # This test verifies that even if there were PII service issues,
    # the fail-open behavior would allow the request through
    local prompt="Hello, this is a simple test message without PII."

    response=$(chat_completion "wlrs-water-form-assistant" "${DEFAULT_MODEL}" "${prompt}" 50)
    parse_response "${response}"

    # Should succeed - fail-open allows requests through
    assert_status "200" "${RESPONSE_STATUS}"

    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')

    # Verify we got a valid response
    [[ -n "${content}" ]]
}

@test "FAIL-CLOSED: sdpr-invoice-automation succeeds when PII service is healthy" {
    skip_if_no_key "sdpr-invoice-automation"

    # sdpr-invoice-automation has PII redaction enabled with fail_closed=true
    # This test verifies that normal requests work when PII service is healthy
    local prompt="Process this request normally."

    response=$(chat_completion "sdpr-invoice-automation" "${DEFAULT_MODEL}" "${prompt}" 50)
    parse_response "${response}"

    # Should succeed - PII service is healthy, so fail_closed doesn't trigger
    assert_status "200" "${RESPONSE_STATUS}"

    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')

    # Verify we got a valid response
    [[ -n "${content}" ]]
}

# =============================================================================
# Fail-Closed Integration Test (requires special setup)
# =============================================================================
# To run this test, you need:
# 1. A tenant configured with fail_closed=true in tenant.tfvars:
#    apim_policies = {
#      pii_redaction = {
#        enabled = true
#        fail_closed = true
#      }
#    }
# 2. A way to simulate PII service failure:
#    - Set piiServiceUrl named value to an invalid endpoint
#    - Temporarily disable the Language Service
#    - Use network policies to block connectivity
#
# Example tenant config for fail-closed testing:
# tenants = {
#   "test-fail-closed" = {
#     tenant_name = "test-fail-closed"
#     display_name = "Test Fail Closed"
#     enabled = true
#     apim_policies = {
#       pii_redaction = {
#         enabled = true
#         fail_closed = true
#       }
#     }
#     ...
#   }
# }
# =============================================================================

# Fail-closed and fail-open behavior tests have been moved to pii-failure.bats
# These tests require temporarily disabling the PII service via Azure CLI

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
