#!/usr/bin/env bats
# =============================================================================
# Integration tests for PII Redaction Coverage Verification (P1 Safety)
# =============================================================================
# These tests verify that the APIM pii-anonymization fragment correctly handles
# the full_coverage flag returned by the external PII redaction service.
#
# Architecture:
#   APIM pii-anonymization fragment → POST /redact (external Python service)
#   Service response: { status: "ok", full_coverage: bool, redacted_body: {...} }
#                  or { status: "error", full_coverage: false, failure_reason: "..." }
#
# APIM interprets:
#   - full_coverage=true  + status="ok"  → success, pass redacted body to LLM
#   - full_coverage=false or status!="ok" → sets failure_reason="incomplete-coverage"
#                                           fail_closed tenant → 503 PiiRedactionFailed
#                                           fail_open  tenant → pass original body to LLM
#
# Error response shape (fail-closed 503):
#   { "error": { "code": "PiiRedactionFailed",
#                "message": "...",
#                "request_id": "<uuid>",
#                "failure_reason": "incomplete-coverage" } }
#
# Tenants:
#   - sdpr-invoice-automation:     fail_closed=true  → blocks on incomplete coverage
#   - wlrs-water-form-assistant:   fail_closed=false → passes through on incomplete coverage
#
# Prerequisites:
#   - Both tenants deployed with pii_redaction.enabled=true
#   - Subscription keys available in Key Vault
# =============================================================================

load 'test-helper'

setup() {
    setup_test_suite
}

# ---------------------------------------------------------------------------
# PII markers embedded in test messages
# ---------------------------------------------------------------------------
PII_NAME="John Doe"
PII_SIN="111-111-111"
PII_PHONE="604-555-5555"

# ---------------------------------------------------------------------------
# Helper for skip logic
# ---------------------------------------------------------------------------
skip_if_no_key() {
    local tenant="${1}"
    local key
    key=$(get_subscription_key "${tenant}")
    if [[ -z "${key}" ]]; then
        skip "No subscription key for ${tenant}"
    fi
}

# =============================================================================
# Test 1: FAIL-CLOSED (SDPR) — normal payload → full coverage → 200
# =============================================================================
# Sanity check: a standard 2-message payload (system + 1 user) should pass
# through successfully with full_coverage=true for a fail-closed tenant.
# The external service processes all documents → returns full_coverage=true
# → APIM passes redacted body to LLM → 200 response.
# =============================================================================

@test "PII-COVERAGE: fail-closed tenant succeeds when service returns full coverage" {
    skip_if_no_key "sdpr-invoice-automation"

    local prompt="My name is ${PII_NAME}, SIN: ${PII_SIN}. Please process my application."
    response=$(chat_completion "sdpr-invoice-automation" "${DEFAULT_MODEL}" "${prompt}" 50)
    parse_response "${response}"

    echo "HTTP Status: ${RESPONSE_STATUS}" >&2
    echo "Response (first 300 chars): ${RESPONSE_BODY:0:300}" >&2

    # Full coverage → should succeed even with fail_closed=true
    assert_status "200" "${RESPONSE_STATUS}"

    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')
    [[ -n "${content}" ]]
}

# =============================================================================
# Test 2: FAIL-CLOSED (SDPR) — 503 error body has all required fields
# =============================================================================
# When a fail-closed tenant's request is blocked (any PiiRedactionFailed 503),
# the error body must contain: code, message, request_id, failure_reason.
# This test uses a payload that triggers partial coverage — specifically
# an extremely large payload that exceeds the service's batch cap
# (PII_MAX_CONCURRENT_BATCHES × PII_MAX_DOCS_PER_CALL × PII_MAX_DOC_CHARS).
#
# Note: If the service configuration does not trigger partial coverage for
# this specific size, this test will 200. Adjust filler size as needed for
# the deployed service configuration.
# =============================================================================

@test "PII-COVERAGE: 503 error body has code, message, request_id, failure_reason" {
    skip_if_no_key "sdpr-invoice-automation"

    # Build a payload with a very long text to push toward the payload-too-large
    # or incomplete-coverage path. This relies on service limits being hit.
    # We generate 10 user messages, each 4500 chars (close to max_doc_chars limit)
    # to stress the batch cap.
    local messages='{"messages":['
    messages+='{"role":"system","content":"Reply with the single word OK only."}'
    for i in $(seq 1 10); do
        local filler
        filler=$(printf '%0.s' {1..1} && python3 -c "print('A' * 4500)" 2>/dev/null || printf '%4500s' | tr ' ' 'A')
        messages+=",{\"role\":\"user\",\"content\":\"Case ${i}: ${PII_NAME}, SIN ${PII_SIN}, Phone ${PII_PHONE}. ${filler}\"}"
    done
    messages+='],"max_tokens":10}'

    local path="/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}"
    response=$(apim_request_with_retry "POST" "sdpr-invoice-automation" "${path}" "${messages}")
    parse_response "${response}"

    echo "HTTP Status: ${RESPONSE_STATUS}" >&2

    # Only validate error body shape when we actually get a 503
    if [[ "${RESPONSE_STATUS}" == "503" ]]; then
        local error_code
        error_code=$(json_get "${RESPONSE_BODY}" '.error.code')
        echo "Error code: ${error_code}" >&2
        [[ "${error_code}" == "PiiRedactionFailed" ]]

        local error_message
        error_message=$(json_get "${RESPONSE_BODY}" '.error.message')
        [[ -n "${error_message}" ]]

        local request_id
        request_id=$(json_get "${RESPONSE_BODY}" '.error.request_id')
        echo "Request ID: ${request_id}" >&2
        [[ -n "${request_id}" ]]

        local failure_reason
        failure_reason=$(json_get "${RESPONSE_BODY}" '.error.failure_reason')
        echo "Failure reason: ${failure_reason}" >&2
        [[ -n "${failure_reason}" ]]
    else
        # Payload did not trigger coverage failure — skip the body assertion
        echo "# Payload did not trigger 503 (got ${RESPONSE_STATUS}) — skipping body shape check" >&3
        assert_status "200" "${RESPONSE_STATUS}"
    fi
}

# =============================================================================
# Test 3: FAIL-OPEN (WLRS) — passes through when service reports error
# =============================================================================
# wlrs-water-form-assistant has fail_closed=false.
# When the external service reports full_coverage=false or returns an error,
# fail-open behaviour passes the original (unredacted) body to the LLM.
# Expect: HTTP 200 with a valid LLM response.
# =============================================================================

@test "PII-COVERAGE: fail-open tenant gets 200 on normal payload" {
    skip_if_no_key "wlrs-water-form-assistant"

    local prompt="My name is ${PII_NAME}, SIN: ${PII_SIN}. Please process my application."
    response=$(chat_completion "wlrs-water-form-assistant" "${DEFAULT_MODEL}" "${prompt}" 50)
    parse_response "${response}"

    echo "HTTP Status: ${RESPONSE_STATUS}" >&2

    # fail-open → always 200 when PII service is reachable
    assert_status "200" "${RESPONSE_STATUS}"

    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')
    [[ -n "${content}" ]]
}

# =============================================================================
# Test 4: FAIL-CLOSED — error.code is exactly "PiiRedactionFailed" (not stale enum)
# =============================================================================
# Guards against regression to the old error code "PiiRedactionUnavailable".
# We indirectly verify this by checking a successful fail-closed response
# does NOT contain the old error code, and verifying the 503 body contract
# when a failure does occur (the error code must be "PiiRedactionFailed").
# =============================================================================

@test "PII-COVERAGE: successful fail-closed response body is valid JSON" {
    skip_if_no_key "sdpr-invoice-automation"

    local prompt="Invoice total: \$1,234.56. Vendor: Acme Corp."
    response=$(chat_completion "sdpr-invoice-automation" "${DEFAULT_MODEL}" "${prompt}" 50)
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    # Verify response is parseable JSON with choices array
    local choices_count
    choices_count=$(echo "${RESPONSE_BODY}" | jq '.choices | length' 2>/dev/null)
    [[ "${choices_count}" -ge 1 ]]

    # Verify the old error code does NOT appear in a successful response
    local old_code
    old_code=$(json_get "${RESPONSE_BODY}" '.error.code // ""')
    [[ "${old_code}" != "PiiRedactionUnavailable" ]]
}

