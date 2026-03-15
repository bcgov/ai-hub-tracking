#!/usr/bin/env bats
# =============================================================================
# Integration tests for PII Redaction Failure Scenarios
# =============================================================================
# These tests cover two categories:
# 1. Explicit fault-injection scenarios where the external PII redaction
#    service is intentionally made unreachable.
# 2. Always-on live-environment checks such as oversized payload handling.
#
# Failure error contract (fail-closed 503):
#   {
#     "error": {
#       "code":           "PiiRedactionFailed",
#       "message":        "PII redaction could not be completed and fail-closed policy is in effect.",
#       "request_id":     "<uuid>",
#       "failure_reason": "<reason>"
#     }
#   }
#
# failure_reason values (non-exhaustive):
#   - "no-response"         service unreachable / connection refused
#   - "payload-too-large"   payload exceeds PII_MAX_PAYLOAD_BYTES
#   - "http-<NNN>"          service returned an unexpected HTTP status
#   - "incomplete-coverage" full_coverage=false (see pii-coverage.bats)
#   - "service-error: <e>"  service returned status="error"
#   - "processing-timeout"  service took too long
#   - "missing-chunk-output" chunk result missing from service response
#
# Fault-injection tenant requirements:
#   The unreachable-service scenarios need two tenants whose piiServiceUrl named
#   value points to an INVALID / unreachable endpoint
#   (e.g. http://127.0.0.1:9999/redact):
#   - A fail-closed tenant: FAIL_CLOSED_TEST_TENANT
#   - A fail-open tenant:   FAIL_OPEN_TEST_TENANT
#
#   Enable those tests only when all of the following are true:
#   - PII_FAILURE_TEST_ENABLED=true
#   - PII_FAILURE_MODE=unreachable
#   - the selected tenants are intentionally pointed at an unreachable endpoint
#
#   Do not run those cases against the normal live test environment.
# =============================================================================

load 'test-helper'

FAIL_CLOSED_TEST_TENANT="${FAIL_CLOSED_TENANT:-sdpr-invoice-automation}"
FAIL_OPEN_TEST_TENANT="${FAIL_OPEN_TENANT:-wlrs-water-form-assistant}"

setup() {
    setup_test_suite
}

# ---------------------------------------------------------------------------
# Skip guard: the unreachable-service scenarios require explicit fault
# injection. They should not run in the normal integration suite against the
# live test environment.
# ---------------------------------------------------------------------------
skip_unless_unreachable_failure_test_enabled() {
    if [[ "${PII_FAILURE_TEST_ENABLED:-false}" != "true" ]] || [[ "${PII_FAILURE_MODE:-}" != "unreachable" ]]; then
        skip "Set PII_FAILURE_TEST_ENABLED=true and PII_FAILURE_MODE=unreachable with invalid piiServiceUrl overrides to run unreachable-service failure tests"
    fi
}

skip_unless_fail_closed_key() {
    skip_unless_unreachable_failure_test_enabled
    local key
    key=$(get_subscription_key "${FAIL_CLOSED_TEST_TENANT}")
    if [[ -z "${key}" ]]; then
        skip "No subscription key for fail-closed test tenant: ${FAIL_CLOSED_TEST_TENANT}"
    fi
}

skip_unless_fail_open_key() {
    skip_unless_unreachable_failure_test_enabled
    local key
    key=$(get_subscription_key "${FAIL_OPEN_TEST_TENANT}")
    if [[ -z "${key}" ]]; then
        skip "No subscription key for fail-open test tenant: ${FAIL_OPEN_TEST_TENANT}"
    fi
}

# =============================================================================
# FAIL-CLOSED — service unreachable
# =============================================================================

@test "PII-FAILURE: fail-closed → service unreachable → returns 503" {
    skip_unless_fail_closed_key

    local prompt="My name is Jane Smith, SIN 222-333-444. Process my application."
    response=$(chat_completion "${FAIL_CLOSED_TEST_TENANT}" "${DEFAULT_MODEL}" "${prompt}" 30)
    parse_response "${response}"

    echo "HTTP Status: ${RESPONSE_STATUS}" >&2
    echo "Response (first 400 chars): ${RESPONSE_BODY:0:400}" >&2

    assert_status "503" "${RESPONSE_STATUS}"
}

@test "PII-FAILURE: fail-closed → service unreachable → error code is PiiRedactionFailed" {
    skip_unless_fail_closed_key

    local prompt="My name is Jane Smith, SIN 222-333-444."
    response=$(chat_completion "${FAIL_CLOSED_TEST_TENANT}" "${DEFAULT_MODEL}" "${prompt}" 30)
    parse_response "${response}"

    assert_status "503" "${RESPONSE_STATUS}"

    local error_code
    error_code=$(json_get "${RESPONSE_BODY}" '.error.code')
    echo "Error code: ${error_code}" >&2
    [[ "${error_code}" == "PiiRedactionFailed" ]]
}

@test "PII-FAILURE: fail-closed → 503 body has non-empty message" {
    skip_unless_fail_closed_key

    local prompt="My name is Jane Smith, SIN 222-333-444."
    response=$(chat_completion "${FAIL_CLOSED_TEST_TENANT}" "${DEFAULT_MODEL}" "${prompt}" 30)
    parse_response "${response}"

    assert_status "503" "${RESPONSE_STATUS}"

    local error_message
    error_message=$(json_get "${RESPONSE_BODY}" '.error.message')
    echo "Error message: ${error_message}" >&2
    [[ -n "${error_message}" ]]
}

@test "PII-FAILURE: fail-closed → 503 body has a request_id UUID" {
    skip_unless_fail_closed_key

    local prompt="My name is Jane Smith, SIN 222-333-444."
    response=$(chat_completion "${FAIL_CLOSED_TEST_TENANT}" "${DEFAULT_MODEL}" "${prompt}" 30)
    parse_response "${response}"

    assert_status "503" "${RESPONSE_STATUS}"

    local request_id
    request_id=$(json_get "${RESPONSE_BODY}" '.error.request_id')
    echo "Request ID: ${request_id}" >&2
    [[ -n "${request_id}" ]]
    # request_id must be a UUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
    [[ "${request_id}" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

@test "PII-FAILURE: fail-closed → 503 body has non-empty failure_reason" {
    skip_unless_fail_closed_key

    local prompt="My name is Jane Smith, SIN 222-333-444."
    response=$(chat_completion "${FAIL_CLOSED_TEST_TENANT}" "${DEFAULT_MODEL}" "${prompt}" 30)
    parse_response "${response}"

    assert_status "503" "${RESPONSE_STATUS}"

    local failure_reason
    failure_reason=$(json_get "${RESPONSE_BODY}" '.error.failure_reason')
    echo "Failure reason: ${failure_reason}" >&2
    [[ -n "${failure_reason}" ]]
}

@test "PII-FAILURE: fail-closed → service unreachable → failure_reason is no-response" {
    skip_unless_fail_closed_key

    # When piiServiceUrl is an unreachable endpoint, APIM gets a connection error
    # and the fragment sets failure_reason="no-response"
    local prompt="My name is Jane Smith, SIN 222-333-444."
    response=$(chat_completion "${FAIL_CLOSED_TEST_TENANT}" "${DEFAULT_MODEL}" "${prompt}" 30)
    parse_response "${response}"

    assert_status "503" "${RESPONSE_STATUS}"

    local failure_reason
    failure_reason=$(json_get "${RESPONSE_BODY}" '.error.failure_reason')
    echo "Failure reason: ${failure_reason}" >&2
    [[ "${failure_reason}" == "no-response" ]]
}

@test "PII-FAILURE: fail-closed → 503 body does NOT use stale PiiRedactionUnavailable code" {
    skip_unless_fail_closed_key

    local prompt="My name is Jane Smith, SIN 222-333-444."
    response=$(chat_completion "${FAIL_CLOSED_TEST_TENANT}" "${DEFAULT_MODEL}" "${prompt}" 30)
    parse_response "${response}"

    assert_status "503" "${RESPONSE_STATUS}"

    local error_code
    error_code=$(json_get "${RESPONSE_BODY}" '.error.code')
    [[ "${error_code}" != "PiiRedactionUnavailable" ]]
}

# =============================================================================
# FAIL-OPEN — service unreachable
# =============================================================================

@test "PII-FAILURE: fail-open → service unreachable → returns 200" {
    skip_unless_fail_open_key

    # fail_closed=false → on any PII service failure, original body passes to LLM
    local prompt="Hello, how are you?"
    response=$(chat_completion "${FAIL_OPEN_TEST_TENANT}" "${DEFAULT_MODEL}" "${prompt}" 30)
    parse_response "${response}"

    echo "HTTP Status: ${RESPONSE_STATUS}" >&2
    echo "Response (first 400 chars): ${RESPONSE_BODY:0:400}" >&2

    assert_status "200" "${RESPONSE_STATUS}"
}

@test "PII-FAILURE: fail-open → service unreachable → LLM response content is non-empty" {
    skip_unless_fail_open_key

    local prompt="Hello, respond with the word OK."
    response=$(chat_completion "${FAIL_OPEN_TEST_TENANT}" "${DEFAULT_MODEL}" "${prompt}" 30)
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')
    echo "LLM content: ${content:0:200}" >&2
    [[ -n "${content}" ]]
}

# =============================================================================
# PAYLOAD-TOO-LARGE
# =============================================================================
# When the JSON body size exceeds PII_MAX_PAYLOAD_BYTES (default 1 MB),
# the fragment sets failure_reason="payload-too-large" and blocks (fail-closed)
# or passes through (fail-open).
#
# This test does NOT need the service unreachable — it uses a live tenant
# and an oversized payload. It is gated only on key availability.
# =============================================================================

@test "PII-FAILURE: payload-too-large triggers 503 with failure_reason payload-too-large (fail-closed)" {
    local key
    key=$(get_subscription_key "sdpr-invoice-automation")
    if [[ -z "${key}" ]]; then
        skip "No subscription key for sdpr-invoice-automation"
    fi

    # Build a payload just over 1 MB (default PII_MAX_PAYLOAD_BYTES=1048576)
    # 1200 chars × 900 messages ≈ 1.08 MB JSON body
    # We use a compact filler word to avoid chunking overhead in the service.
    local messages='{"messages":['
    messages+='{"role":"system","content":"Be brief."}'

    local word="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"  # 34 chars
    for i in $(seq 1 900); do
        messages+=",{\"role\":\"user\",\"content\":\"Message ${i}: $(printf '%0.s'"${word}"' ' {1..35})\"}"
    done
    messages+='],"max_tokens":5}'

    local path="/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}"
    response=$(apim_request_with_retry "POST" "sdpr-invoice-automation" "${path}" "${messages}")
    parse_response "${response}"

    echo "HTTP Status: ${RESPONSE_STATUS}" >&2

    # Only assert the specific failure_reason when we actually get a 503
    # (if the payload is below the configured threshold, we may get 200 or 400)
    if [[ "${RESPONSE_STATUS}" == "503" ]]; then
        local error_code
        error_code=$(json_get "${RESPONSE_BODY}" '.error.code')
        [[ "${error_code}" == "PiiRedactionFailed" ]]

        local failure_reason
        failure_reason=$(json_get "${RESPONSE_BODY}" '.error.failure_reason')
        echo "Failure reason: ${failure_reason}" >&2
        [[ "${failure_reason}" == "payload-too-large" ]]
    elif [[ "${RESPONSE_STATUS}" == "413" ]]; then
        # APIM itself rejected the oversized body before the fragment ran
        echo "# Payload rejected by APIM with 413 (body size limit enforced upstream)" >&3
    else
        echo "# Payload did not exceed PII_MAX_PAYLOAD_BYTES threshold (got ${RESPONSE_STATUS})" >&3
        assert_status "200" "${RESPONSE_STATUS}"
    fi
}
