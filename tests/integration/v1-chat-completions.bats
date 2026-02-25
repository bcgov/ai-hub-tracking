#!/usr/bin/env bats
# Integration tests for OpenAI-compatible /v1/ endpoint format
# Tests the /v1/chat/completions path where model is specified in the request body
# instead of the URL path (/deployments/{model}/...).
#
# These tests validate:
# - /v1/ format routing and deployment name resolution
# - Request body model field tenant-prefixing
# - Input validation (missing model, invalid JSON)
# - Authorization: Bearer header support
# - Regression: /deployments/ format still works
#
# See: https://github.com/bcgov/ai-hub-tracking/issues/115

load 'test-helper'

setup() {
    setup_test_suite
}

skip_if_no_key() {
    local tenant="${1}"
    local key
    key=$(get_subscription_key "${tenant}")

    if [[ -z "${key}" ]]; then
        skip "No subscription key for ${tenant}"
    fi
}

# =============================================================================
# /v1/ Format — Core Functionality
# =============================================================================

@test "V1: Chat completion via /v1/ format returns 200" {
    skip_if_no_key "wlrs-water-form-assistant"

    response=$(chat_completion_v1 "wlrs-water-form-assistant" "gpt-4.1-mini" "Say hello in one word" 10)
    parse_response "${response}"

    echo "# V1 chat status: ${RESPONSE_STATUS}" >&3
    assert_status "200" "${RESPONSE_STATUS}"
}

@test "V1: Response contains valid choices array" {
    skip_if_no_key "wlrs-water-form-assistant"

    response=$(chat_completion_v1 "wlrs-water-form-assistant" "gpt-4.1-mini" "What is 2+2?" 10)
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    # Validate response structure matches OpenAI format
    local choices
    choices=$(echo "${RESPONSE_BODY}" | jq -e '.choices' 2>/dev/null)
    [[ -n "${choices}" ]]

    local content
    content=$(echo "${RESPONSE_BODY}" | jq -r '.choices[0].message.content' 2>/dev/null)
    [[ -n "${content}" ]]
}

@test "V1: Model name is not double-prefixed in response" {
    skip_if_no_key "wlrs-water-form-assistant"

    response=$(chat_completion_v1 "wlrs-water-form-assistant" "gpt-4.1-mini" "Say hello" 10)
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    # The response model field should contain the deployment name (tenant-prefixed once)
    local response_model
    response_model=$(echo "${RESPONSE_BODY}" | jq -r '.model // empty' 2>/dev/null)
    echo "# Response model field: ${response_model}" >&3

    # Should NOT have double tenant prefix
    if echo "${response_model}" | grep -q "wlrs-water-form-assistant-wlrs-water-form-assistant-"; then
        fail "Model name is double-prefixed: ${response_model}"
    fi
}

@test "V1: All deployed chat models work via /v1/ format" {
    skip_if_no_key "wlrs-water-form-assistant"

    local models
    models=$(get_tenant_chat_models "wlrs-water-form-assistant")

    if [[ -z "${models}" ]]; then
        skip "No models found for WLRS tenant"
    fi

    local failed_models=""
    local passed_count=0
    local total_count=0
    local skipped_count=0

    for model in ${models}; do
        total_count=$((total_count + 1))
        echo "Testing /v1/ with model: ${model}" >&3

        response=$(chat_completion_v1 "wlrs-water-form-assistant" "${model}" "Say hello" 10)
        parse_response "${response}"

        if [[ "${RESPONSE_STATUS}" == "200" ]]; then
            passed_count=$((passed_count + 1))
            echo "  ✓ ${model}: OK" >&3
        elif [[ "${RESPONSE_STATUS}" == "429" ]]; then
            skipped_count=$((skipped_count + 1))
            echo "  ⚠ ${model}: Rate limited (429), skipping" >&3
        elif [[ "${RESPONSE_STATUS}" == "400" ]]; then
            skipped_count=$((skipped_count + 1))
            echo "  ⚠ ${model}: API format issue (400), may need different API version" >&3
        else
            failed_models="${failed_models} ${model}(${RESPONSE_STATUS})"
            echo "  ✗ ${model}: Failed with status ${RESPONSE_STATUS}" >&3
        fi
    done

    echo "Results: ${passed_count}/${total_count} passed, ${skipped_count} skipped" >&3

    if [[ -n "${failed_models}" ]]; then
        echo "Unexpected failures:${failed_models}" >&2
        return 1
    fi

    [[ ${passed_count} -gt 0 ]]
}

# =============================================================================
# /v1/ Format — Streaming
# =============================================================================

@test "V1: Streaming request with stream:true returns 200" {
    skip_if_no_key "wlrs-water-form-assistant"

    local path="/openai/v1/chat/completions"
    local body='{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"Say hello"}],"max_tokens":10,"stream":true}'

    response=$(apim_request_with_retry "POST" "wlrs-water-form-assistant" "${path}" "${body}")
    parse_response "${response}"

    echo "# V1 streaming status: ${RESPONSE_STATUS}" >&3
    assert_status "200" "${RESPONSE_STATUS}"
}

@test "V1: Streaming response contains SSE data chunks" {
    skip_if_no_key "wlrs-water-form-assistant"

    local path="/openai/v1/chat/completions"
    local body='{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"Say hello"}],"max_tokens":10,"stream":true}'

    response=$(apim_request_with_retry "POST" "wlrs-water-form-assistant" "${path}" "${body}")
    parse_response "${response}"

    # Verify SSE format: must contain data: lines
    local data_lines
    data_lines=$(echo "${RESPONSE_BODY}" | grep -c '^data: ' || true)
    echo "# SSE data lines: ${data_lines}" >&3
    [[ ${data_lines} -ge 2 ]]
}

@test "V1: Streaming response ends with data: [DONE]" {
    skip_if_no_key "wlrs-water-form-assistant"

    local path="/openai/v1/chat/completions"
    local body='{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"Say hello"}],"max_tokens":10,"stream":true}'

    response=$(apim_request_with_retry "POST" "wlrs-water-form-assistant" "${path}" "${body}")
    parse_response "${response}"

    # SSE stream must terminate with [DONE]
    local has_done
    has_done=$(echo "${RESPONSE_BODY}" | grep -c '^\s*data: \[DONE\]' || true)
    echo "# Has [DONE]: ${has_done}" >&3
    [[ ${has_done} -ge 1 ]]
}

@test "V1: Streaming chunks contain valid chat.completion.chunk objects" {
    skip_if_no_key "wlrs-water-form-assistant"

    local path="/openai/v1/chat/completions"
    local body='{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"Say hello"}],"max_tokens":10,"stream":true}'

    response=$(apim_request_with_retry "POST" "wlrs-water-form-assistant" "${path}" "${body}")
    parse_response "${response}"

    # Extract a chat.completion.chunk (skip Azure prompt_filter_results and [DONE])
    # tr -d '\r': SSE uses \r\n line endings; Linux preserves \r which breaks jq parsing
    # Split pipeline: collect all chunks first, then head -1, to avoid SIGPIPE under pipefail
    local all_chunks chunk
    all_chunks=$(echo "${RESPONSE_BODY}" | tr -d '\r' | grep '^data: {' | sed 's/^data: //' | jq -c 'select(.object == "chat.completion.chunk")' 2>/dev/null) || true
    chunk=$(echo "${all_chunks}" | head -1)
    echo "# Chunk: ${chunk:0:120}..." >&3

    # Validate it's valid JSON with expected object type
    local object_type
    object_type=$(echo "${chunk}" | jq -r '.object // empty' 2>/dev/null || echo "")
    echo "# Object type: ${object_type}" >&3
    [[ "${object_type}" == "chat.completion.chunk" ]]
}

@test "V1: Streaming response includes model name in chunks" {
    skip_if_no_key "wlrs-water-form-assistant"

    local path="/openai/v1/chat/completions"
    local body='{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"Say hello"}],"max_tokens":10,"stream":true}'

    response=$(apim_request_with_retry "POST" "wlrs-water-form-assistant" "${path}" "${body}")
    parse_response "${response}"

    # Extract model from a content chunk (skip Azure prompt_filter_results)
    # tr -d '\r': SSE uses \r\n line endings; Linux preserves \r which breaks jq parsing
    local all_models model
    all_models=$(echo "${RESPONSE_BODY}" | tr -d '\r' | grep '^data: {' | sed 's/^data: //' | jq -r 'select(.object == "chat.completion.chunk") | .model // empty' 2>/dev/null) || true
    model=$(echo "${all_models}" | head -1)
    echo "# Streaming model: ${model}" >&3
    [[ -n "${model}" ]]
    # Model should not be double-prefixed
    [[ "${model}" != *"wlrs-water-form-assistant-wlrs-water-form-assistant"* ]]
}

# =============================================================================
# /v1/ Format — Input Validation
# =============================================================================

@test "V1: Missing model field returns 400" {
    skip_if_no_key "wlrs-water-form-assistant"

    local path="/openai/v1/chat/completions"
    local body='{"messages":[{"role":"user","content":"hello"}],"max_tokens":10}'

    response=$(apim_request "POST" "wlrs-water-form-assistant" "${path}" "${body}")
    parse_response "${response}"

    echo "# Missing model status: ${RESPONSE_STATUS}" >&3
    assert_status "400" "${RESPONSE_STATUS}"

    # Verify error code
    local error_code
    error_code=$(echo "${RESPONSE_BODY}" | jq -r '.error.code' 2>/dev/null)
    [[ "${error_code}" == "MissingModel" ]]
}

@test "V1: Invalid JSON body returns 400" {
    skip_if_no_key "wlrs-water-form-assistant"

    local path="/openai/v1/chat/completions"
    local body='this is not valid json'

    response=$(apim_request "POST" "wlrs-water-form-assistant" "${path}" "${body}")
    parse_response "${response}"

    echo "# Invalid JSON status: ${RESPONSE_STATUS}" >&3
    assert_status "400" "${RESPONSE_STATUS}"

    local error_code
    error_code=$(echo "${RESPONSE_BODY}" | jq -r '.error.code' 2>/dev/null)
    [[ "${error_code}" == "InvalidRequestBody" ]]
}

# =============================================================================
# Authorization: Bearer Token Support
# =============================================================================

@test "V1: Bearer token auth returns 200 via /v1/ format" {
    skip_if_no_key "wlrs-water-form-assistant"

    response=$(chat_completion_v1_bearer "wlrs-water-form-assistant" "gpt-4.1-mini" "Say hello" 10)
    parse_response "${response}"

    echo "# Bearer + /v1/ status: ${RESPONSE_STATUS}" >&3
    assert_status "200" "${RESPONSE_STATUS}"
}

@test "V1: Bearer token auth works with /deployments/ format too" {
    skip_if_no_key "wlrs-water-form-assistant"

    local path="/openai/deployments/gpt-4.1-mini/chat/completions?api-version=${OPENAI_API_VERSION}"
    local body='{"messages":[{"role":"user","content":"Say hello"}],"max_tokens":10}'

    response=$(apim_request_bearer "POST" "wlrs-water-form-assistant" "${path}" "${body}")
    parse_response "${response}"

    echo "# Bearer + /deployments/ status: ${RESPONSE_STATUS}" >&3
    assert_status "200" "${RESPONSE_STATUS}"
}

# =============================================================================
# Regression — /deployments/ Format Still Works
# =============================================================================

@test "V1-Regression: /deployments/ format still returns 200" {
    skip_if_no_key "wlrs-water-form-assistant"

    response=$(chat_completion "wlrs-water-form-assistant" "gpt-4.1-mini" "Say hello" 10)
    parse_response "${response}"

    echo "# /deployments/ regression status: ${RESPONSE_STATUS}" >&3
    assert_status "200" "${RESPONSE_STATUS}"
}

@test "V1-Regression: /deployments/ response has valid choices" {
    skip_if_no_key "wlrs-water-form-assistant"

    response=$(chat_completion "wlrs-water-form-assistant" "gpt-4.1-mini" "What is 2+2?" 10)
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local content
    content=$(echo "${RESPONSE_BODY}" | jq -r '.choices[0].message.content' 2>/dev/null)
    [[ -n "${content}" ]]
}

# =============================================================================
# Cross-tenant Isolation
# =============================================================================

@test "V1: WLRS key cannot access SDPR via /v1/ format" {
    skip_if_no_key "wlrs-water-form-assistant"

    local wlrs_key
    wlrs_key=$(get_subscription_key "wlrs-water-form-assistant")

    local url="${APIM_GATEWAY_URL}/sdpr-invoice-automation/openai/v1/chat/completions"
    local body='{"model":"gpt-4.1-mini","messages":[{"role":"user","content":"hello"}],"max_tokens":10}'

    local response
    response=$(curl -s -w "\n%{http_code}" \
        --max-time 30 \
        -X POST "${url}" \
        -H "api-key: ${wlrs_key}" \
        -H "Content-Type: application/json" \
        -d "${body}")

    local status
    status=$(echo "${response}" | tail -1)

    echo "# Cross-tenant V1 status: ${status}" >&3
    [[ "${status}" == "401" ]] || [[ "${status}" == "403" ]] || [[ "${status}" == "404" ]]
}
