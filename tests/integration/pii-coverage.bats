#!/usr/bin/env bats
# =============================================================================
# Integration tests for PII Redaction Coverage Verification (P1 Safety)
# =============================================================================
# These tests verify that the PII fragment correctly detects and handles
# incomplete redaction coverage.
#
# Batching: The fragment sends the Language Service API multiple requests of
# up to 5 documents each (max 100 documents total). So payloads with ≤100
# documents get full coverage; only when >100 documents are needed do we get
# unscanned messages.
#
# Scenario 1 (≤50 docs): Payload with 8 messages → 8 docs → 2 API requests →
#   full coverage. Fail-closed and fail-open both get 200.
#
# Scenario 2 (>100 docs): Payload with 102+ documents causes excess to be
#   unscanned. Fail-closed blocks with 503; fail-open passes through.
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
# Test 1: FAIL-CLOSED (SDPR) — 8 messages now get full coverage via batching → 200
# =============================================================================
# With request batching (up to 50 docs in batches of 5), 8 messages = 8 docs
# are sent in 2 API calls and merged. Full coverage → 200 even for fail-closed.
# =============================================================================

@test "PII-COVERAGE: fail-closed tenant succeeds when 8 messages (full coverage via batching)" {
    skip_if_no_key "sdpr-invoice-automation"

    echo "Building payload with 7 user messages (8 total = 8 docs, 2 batches)..." >&2
    local body
    body=$(build_many_messages_payload 7)

    echo "Sending to sdpr-invoice-automation (fail_closed=true)..." >&2
    local path="/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}"
    response=$(apim_request_with_retry "POST" "sdpr-invoice-automation" "${path}" "${body}")
    parse_response "${response}"

    echo "HTTP Status: ${RESPONSE_STATUS}" >&2
    echo "Response (first 500 chars): ${RESPONSE_BODY:0:500}" >&2

    # Full coverage via batching → must succeed with 200
    assert_status "200" "${RESPONSE_STATUS}"

    # Verify we got an LLM response (not a 503 error)
    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')
    [[ -n "${content}" ]]
}

# =============================================================================
# Test 2: FAIL-OPEN (WLRS) — 8 messages get full coverage via batching → 200
# =============================================================================
# Same as Test 1: 8 messages, 2 batches, full coverage. Expect 200.
# =============================================================================

@test "PII-COVERAGE: fail-open tenant succeeds when 8 messages (full coverage via batching)" {
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

# =============================================================================
# Test 4: >100 documents — fail-closed blocks (excess unscanned)
# =============================================================================
# Payload with 102 docs (1 system + 101 user messages) exceeds the 100-doc cap.
# Only first 100 docs are sent; 2 messages unscanned → fullCoverage=false → 503.
# =============================================================================

@test "PII-COVERAGE: fail-closed tenant blocks when payload exceeds 100-doc cap" {
    skip_if_no_key "sdpr-invoice-automation"

    echo "Building payload with 101 user messages (102 total docs > 100 cap)..." >&2
    local body
    body=$(build_many_messages_payload 101)

    echo "Sending to sdpr-invoice-automation (fail_closed=true)..." >&2
    local path="/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}"
    response=$(apim_request_with_retry "POST" "sdpr-invoice-automation" "${path}" "${body}")
    parse_response "${response}"

    echo "HTTP Status: ${RESPONSE_STATUS}" >&2

    # Fail-closed + incomplete coverage (>50 docs) → must block with 503
    assert_status "503" "${RESPONSE_STATUS}"

    local error_code
    error_code=$(json_get "${RESPONSE_BODY}" '.error.code')
    [[ "${error_code}" == "PiiRedactionUnavailable" ]]

    local failure_reason
    failure_reason=$(json_get "${RESPONSE_BODY}" '.error.failure_reason')
    assert_contains "${failure_reason}" "partial-redaction"
    assert_contains "${failure_reason}" "unscanned"

    local msgs_unscanned
    msgs_unscanned=$(json_get "${RESPONSE_BODY}" '.error.coverage.msgsUnscanned')
    [[ "${msgs_unscanned}" -gt 0 ]]
}
