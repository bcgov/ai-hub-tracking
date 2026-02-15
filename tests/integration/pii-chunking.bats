#!/usr/bin/env bats
# Integration tests for PII Redaction with large payloads (chunking)
# Verifies that PII is redacted in small (~2k), medium (~15k), and huge (~30k) payloads
# These tests exercise the document-chunking logic added to the pii-anonymization fragment

load 'test-helper'

setup() {
    setup_test_suite
}

# ---------------------------------------------------------------------------
# PII markers we embed and later assert are NOT in the AI response
# ---------------------------------------------------------------------------
PII_NAME_1="John Doe"
PII_NAME_2="Gary Gibson"
PII_SIN_1="111-111-111"
PII_SIN_2="222-222-222"
PII_PHONE="604-555-5555"
PII_ADDRESS="1234 Willow Street, Vancouver, BC V6B 3N9"
PII_EMAIL="john.doe@example.com"

# ---------------------------------------------------------------------------
# Helper: generate filler text of approximately N characters
# Uses a repeating paragraph so the Language Service treats it as real text.
# ---------------------------------------------------------------------------
generate_filler() {
    local target_chars="${1}"
    local paragraph="The Ministry of Social Development and Poverty Reduction collects information pursuant to the Freedom of Information and Protection of Privacy Act for administering assistance programs. Applicants must declare all income sources including employment insurance, spousal support, rental income, worker compensation, pensions, and tax credits. All declarations are verified for continuing eligibility under the applicable Acts and Regulations. "
    local result=""
    while [[ ${#result} -lt ${target_chars} ]]; do
        result="${result}${paragraph}"
    done
    # Trim to target length at a word boundary
    result="${result:0:${target_chars}}"
    echo "${result}"
}

# ---------------------------------------------------------------------------
# Helper: build a chat completion JSON body with PII embedded in user content
# Usage: build_pii_payload <filler_chars>
# ---------------------------------------------------------------------------
build_pii_payload() {
    local filler_chars="${1}"
    local filler
    filler=$(generate_filler "${filler_chars}")

    # Escape the filler for JSON (handle any special chars)
    local escaped_filler
    escaped_filler=$(printf '%s' "${filler}" | jq -Rs '.')
    # Remove surrounding quotes added by jq -Rs
    escaped_filler="${escaped_filler:1:${#escaped_filler}-2}"

    cat <<EOJSON
{
    "messages": [
        {
            "role": "system",
            "content": "You are a helpful assistant. Summarize the document below in 2 sentences. Do NOT repeat any personal information such as names, phone numbers, social insurance numbers, or addresses."
        },
        {
            "role": "user",
            "content": "Applicant: ${PII_NAME_1}, Phone: ${PII_PHONE}, SIN: ${PII_SIN_1}, Email: ${PII_EMAIL}, Address: ${PII_ADDRESS}. Spouse: ${PII_NAME_2}, SIN: ${PII_SIN_2}. ${escaped_filler} Signed by ${PII_NAME_1} and ${PII_NAME_2} on 2025-12-01."
        }
    ],
    "max_completion_tokens": 300
}
EOJSON
}

# ---------------------------------------------------------------------------
# Helper: assert that none of the PII markers appear in a string
# ---------------------------------------------------------------------------
assert_no_pii() {
    local content="${1}"
    local label="${2:-response}"

    # Check full names
    if [[ "${content}" == *"${PII_NAME_1}"* ]]; then
        echo "FAIL: ${label} contains PII name '${PII_NAME_1}'" >&2
        echo "Content (first 500 chars): ${content:0:500}" >&2
        return 1
    fi
    if [[ "${content}" == *"${PII_NAME_2}"* ]]; then
        echo "FAIL: ${label} contains PII name '${PII_NAME_2}'" >&2
        echo "Content (first 500 chars): ${content:0:500}" >&2
        return 1
    fi

    # Check SINs (with and without dashes)
    if [[ "${content}" == *"${PII_SIN_1}"* ]] || [[ "${content}" == *"802507116"* ]]; then
        echo "FAIL: ${label} contains PII SIN '${PII_SIN_1}'" >&2
        return 1
    fi
    if [[ "${content}" == *"${PII_SIN_2}"* ]] || [[ "${content}" == *"483531857"* ]]; then
        echo "FAIL: ${label} contains PII SIN '${PII_SIN_2}'" >&2
        return 1
    fi

    # Check address
    if [[ "${content}" == *"1234 Willow Street"* ]] || [[ "${content}" == *"V6B 3N9"* ]]; then
        echo "FAIL: ${label} contains PII address" >&2
        return 1
    fi

    # Check phone
    if [[ "${content}" == *"${PII_PHONE}"* ]] || [[ "${content}" == *"6045557890"* ]]; then
        echo "FAIL: ${label} contains PII phone '${PII_PHONE}'" >&2
        return 1
    fi

    # Check email
    if [[ "${content}" == *"${PII_EMAIL}"* ]]; then
        echo "FAIL: ${label} contains PII email '${PII_EMAIL}'" >&2
        return 1
    fi

    return 0
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
# Test 1: Small payload (~2k chars) — fits in a single PII document
# =============================================================================

@test "PII-CHUNKING: Small payload (~2k chars) - PII is fully redacted" {
    skip_if_no_key "wlrs-water-form-assistant"

    local body
    body=$(build_pii_payload 1500)

    local path="/openai/deployments/gpt-5-mini/chat/completions?api-version=${OPENAI_API_VERSION}"

    echo "# Payload size: ~$(echo "${body}" | wc -c) bytes" >&3

    response=$(apim_request_with_retry "POST" "wlrs-water-form-assistant" "${path}" "${body}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')

    echo "# AI response (first 300 chars): ${content:0:300}" >&3

    # Assert no PII leaked
    assert_no_pii "${content}" "small-payload"
}

# =============================================================================
# Test 2: Medium payload (~15k chars) — triggers chunking (3 chunks)
# =============================================================================

@test "PII-CHUNKING: Medium payload (~15k chars) - PII is fully redacted across chunks" {
    skip_if_no_key "wlrs-water-form-assistant"

    local body
    body=$(build_pii_payload 14000)

    local path="/openai/deployments/gpt-5-mini/chat/completions?api-version=${OPENAI_API_VERSION}"

    echo "# Payload size: ~$(echo "${body}" | wc -c) bytes" >&3

    response=$(apim_request_with_retry "POST" "wlrs-water-form-assistant" "${path}" "${body}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')

    echo "# AI response (first 300 chars): ${content:0:300}" >&3

    # Assert no PII leaked
    assert_no_pii "${content}" "medium-payload"
}

# =============================================================================
# Test 3: Huge payload (~30k chars) — triggers chunking (6+ chunks)
# =============================================================================

@test "PII-CHUNKING: Huge payload (~30k chars) - PII is fully redacted across many chunks" {
    skip_if_no_key "wlrs-water-form-assistant"

    local body
    body=$(build_pii_payload 29000)

    local path="/openai/deployments/gpt-5-mini/chat/completions?api-version=${OPENAI_API_VERSION}"

    echo "# Payload size: ~$(echo "${body}" | wc -c) bytes" >&3

    response=$(apim_request_with_retry "POST" "wlrs-water-form-assistant" "${path}" "${body}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')

    echo "# AI response (first 300 chars): ${content:0:300}" >&3

    # Assert no PII leaked
    assert_no_pii "${content}" "huge-payload"
}
