#!/usr/bin/env bats
# =============================================================================
# Integration tests for PII Redaction Coverage Verification (P1 Safety)
# =============================================================================
# These tests verify that the PII fragment correctly detects and handles
# incomplete redaction coverage caused by the Azure Language Service's
# 5-document-per-synchronous-request limit.
#
# Scenario:
#   A payload with more content messages than the 5-doc limit causes excess
#   messages to be silently dropped from PII scanning. The coverage check
#   detects this:
#   - Fail-closed tenants (SDPR): receive 503 + coverage diagnostics
#   - Fail-open tenants (WLRS): request passes through, coverage logged
#
# Note on 5-doc limit:
#   Azure Language Service PiiEntityRecognition limits synchronous requests
#   to 5 documents. The fragment sends each message's content as a separate
#   document (with chunking for oversized messages). When a request has >5
#   content-bearing messages, only the first N that fit are sent to the API.
#   The remainder are unscanned. The coverage check detects this gap.
#
# Tenants:
#   - sdpr-invoice-automation: fail_closed=true  → blocks on incomplete coverage
#   - wlrs-water-form-assistant: fail_closed=false → passes through
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
# Helper: Build a chat-completion JSON payload with N user messages + 1 system.
# Each user message contains unique PII content → becomes 1 document each.
# With the 5-doc API limit, total docs = N+1. If N+1 > 5 (i.e. N > 4),
# excess messages beyond the cap are unscanned.
#
# Usage: build_many_messages_payload <num_user_messages>
# ---------------------------------------------------------------------------
build_many_messages_payload() {
    local num_user_msgs="${1:-7}"

    # Start JSON with system message (takes 1 doc slot)
    local json='{"messages":['
    json+='{"role":"system","content":"Reply with the single word OK. Do not repeat any personal information."}'

    # Add user messages, each with unique PII markers (~90 chars, no chunking)
    for i in $(seq 1 "${num_user_msgs}"); do
        json+=",{\"role\":\"user\",\"content\":\"Case ${i}: Applicant ${PII_NAME}-${i}, Phone: ${PII_PHONE}, SIN: ${PII_SIN}. Review this application.\"}"
    done

    json+='],"max_tokens":50,"temperature":0.7}'
    echo "${json}"
}

# =============================================================================
# Helper for skip logic
# =============================================================================
skip_if_no_key() {
    local tenant="${1}"
    local key
    key=$(get_subscription_key "${tenant}")
    if [[ -z "${key}" ]]; then
        skip "No subscription key for ${tenant}"
    fi
}

# =============================================================================
# Test 1: FAIL-CLOSED (SDPR) — 7 user messages + 1 system = 8 docs > 5 → 503
# =============================================================================
# sdpr-invoice-automation has fail_closed=true.
# With 8 messages (1 system + 7 user), the code cap of 5 documents means
# only messages 0-4 get PII documents. Messages 5-7 are unscanned.
# The PII API returns 200 (5 ≤ 5 limit), but coverage check detects
# 3 unscanned messages → fullCoverage=false → 503 block.
# =============================================================================

@test "PII-COVERAGE: fail-closed tenant blocks when messages exceed 5-doc limit" {
    skip_if_no_key "sdpr-invoice-automation"

    echo "Building payload with 7 user messages (8 total = 8 docs needed, 5 sent)..." >&2
    local body
    body=$(build_many_messages_payload 7)

    echo "Sending to sdpr-invoice-automation (fail_closed=true)..." >&2
    local path="/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}"
    response=$(apim_request_with_retry "POST" "sdpr-invoice-automation" "${path}" "${body}")
    parse_response "${response}"

    echo "HTTP Status: ${RESPONSE_STATUS}" >&2
    echo "Response (first 500 chars): ${RESPONSE_BODY:0:500}" >&2

    # Fail-closed + incomplete coverage → must block with 503
    assert_status "503" "${RESPONSE_STATUS}"

    # Verify error response structure
    local error_code
    error_code=$(json_get "${RESPONSE_BODY}" '.error.code')
    echo "Error code: ${error_code}" >&2
    [[ "${error_code}" == "PiiRedactionUnavailable" ]]

    # Verify failure_reason indicates partial redaction (not a PII API error)
    local failure_reason
    failure_reason=$(json_get "${RESPONSE_BODY}" '.error.failure_reason')
    echo "Failure reason: ${failure_reason}" >&2
    assert_contains "${failure_reason}" "partial-redaction"
    assert_contains "${failure_reason}" "unscanned"

    # Verify coverage object is present and accurate
    local msgs_unscanned
    msgs_unscanned=$(json_get "${RESPONSE_BODY}" '.error.coverage.msgsUnscanned')
    echo "Messages unscanned: ${msgs_unscanned}" >&2
    [[ "${msgs_unscanned}" -gt 0 ]]

    local full_coverage
    full_coverage=$(json_get "${RESPONSE_BODY}" '.error.coverage.fullCoverage')
    echo "Full coverage: ${full_coverage}" >&2
    [[ "${full_coverage}" == "false" || "${full_coverage}" == "False" ]]

    # Verify message explains the partial-redaction situation
    local error_message
    error_message=$(json_get "${RESPONSE_BODY}" '.error.message')
    echo "Error message: ${error_message}" >&2
    assert_contains "${error_message}" "incomplete"
}

# =============================================================================
# Test 2: FAIL-OPEN (WLRS) — 7 user messages + 1 system = 8 docs > 5 → 200
# =============================================================================
# wlrs-water-form-assistant has fail_closed=false.
# Same payload: 8 messages, 5 docs processed by PII API.
# Because fail-open, the request passes through to the LLM with:
#   - First 5 messages PII-redacted (within limit)
#   - Remaining 3 messages left with original content
# Expect: HTTP 200 with an LLM response.
# =============================================================================

@test "PII-COVERAGE: fail-open tenant passes through when messages exceed 5-doc limit" {
    skip_if_no_key "wlrs-water-form-assistant"

    echo "Building payload with 7 user messages (8 total = 8 docs needed, 5 sent)..." >&2
    local body
    body=$(build_many_messages_payload 7)

    echo "Sending to wlrs-water-form-assistant (fail_closed=false)..." >&2
    local path="/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}"
    response=$(apim_request_with_retry "POST" "wlrs-water-form-assistant" "${path}" "${body}")
    parse_response "${response}"

    echo "HTTP Status: ${RESPONSE_STATUS}" >&2
    echo "Response (first 500 chars): ${RESPONSE_BODY:0:500}" >&2

    # Fail-open → request should succeed despite incomplete coverage
    assert_status "200" "${RESPONSE_STATUS}"

    # Verify we got an actual LLM response
    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')
    echo "LLM response content: ${content:0:200}" >&2
    [[ -n "${content}" ]]
}

# =============================================================================
# Test 3: Normal payload (≤ 5 docs) works with full coverage for fail-closed
# =============================================================================
# Sanity check: a normal 2-message payload (system + user) should still pass
# through successfully with full coverage for a fail-closed tenant.
# =============================================================================

@test "PII-COVERAGE: fail-closed tenant succeeds with normal payload (full coverage)" {
    skip_if_no_key "sdpr-invoice-automation"

    echo "Sending normal 2-message payload to sdpr-invoice-automation..." >&2
    local prompt="My name is ${PII_NAME}, SIN: ${PII_SIN}. Process my application."
    response=$(chat_completion "sdpr-invoice-automation" "${DEFAULT_MODEL}" "${prompt}" 50)
    parse_response "${response}"

    echo "HTTP Status: ${RESPONSE_STATUS}" >&2
    echo "Response (first 500 chars): ${RESPONSE_BODY:0:500}" >&2

    # Normal payload with full coverage → should succeed even with fail_closed=true
    assert_status "200" "${RESPONSE_STATUS}"

    # Verify we got an LLM response (not a 503 error)
    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')
    [[ -n "${content}" ]]
}
