#!/usr/bin/env bats
# Integration tests for Chat Completions API via APIM
# Tests OpenAI chat completion endpoints for both tenants

load 'test-helper'

setup() {
    setup_test_suite
}

# =============================================================================
# WLRS Tenant Tests
# =============================================================================

@test "WLRS: Chat completion returns 200 OK" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    response=$(chat_completion "wlrs-water-form-assistant" "${DEFAULT_MODEL}" "Say hello in one word")
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
}

@test "WLRS: Chat completion returns valid JSON with choices" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    response=$(chat_completion "wlrs-water-form-assistant" "${DEFAULT_MODEL}" "What is 2+2?")
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
    
    # Validate response structure
    local choices
    choices=$(json_get "${RESPONSE_BODY}" '.choices | length')
    [[ "${choices}" -gt 0 ]]
}

@test "WLRS: Chat completion includes usage metrics" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    response=$(chat_completion "wlrs-water-form-assistant" "${DEFAULT_MODEL}" "Hello")
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
    
    # Check usage tokens are present
    local prompt_tokens
    prompt_tokens=$(json_get "${RESPONSE_BODY}" '.usage.prompt_tokens')
    [[ "${prompt_tokens}" -gt 0 ]]
    
    local completion_tokens
    completion_tokens=$(json_get "${RESPONSE_BODY}" '.usage.completion_tokens')
    [[ "${completion_tokens}" -gt 0 ]]
}

@test "WLRS: Chat completion handles system prompt" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    local body
    body=$(cat <<EOF
{
    "messages": [
        {"role": "system", "content": "You are a helpful water form assistant."},
        {"role": "user", "content": "Hello"}
    ],
    "max_tokens": 50
}
EOF
)
    
    response=$(apim_request "POST" "wlrs-water-form-assistant" \
        "/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}" \
        "${body}")
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
}

@test "WLRS: Chat completion returns correlation ID in headers" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    # This test needs to capture headers, so we use -i to include headers
    local subscription_key
    subscription_key=$(get_subscription_key "wlrs-water-form-assistant")
    
    local body='{"messages":[{"role":"user","content":"Hi"}],"max_tokens":10}'
    local url="${APIM_GATEWAY_URL}/wlrs-water-form-assistant/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}"
    
    local response
    response=$(curl -s -i -X POST "${url}" \
        -H "Ocp-Apim-Subscription-Key: ${subscription_key}" \
        -H "Content-Type: application/json" \
        --proxy "${HTTPS_PROXY:-}" \
        --max-time 60 \
        -d "${body}" 2>/dev/null)
    
    # Check for x-correlation-id or x-ms-request-id header (case insensitive)
    echo "${response}" | grep -iqE "(x-correlation-id|x-ms-request-id)"
}

# =============================================================================
# SDPR Tenant Tests
# =============================================================================

@test "SDPR: Chat completion returns 200 OK" {
    skip_if_no_key "sdpr-invoice-automation"
    
    response=$(chat_completion "sdpr-invoice-automation" "${DEFAULT_MODEL}" "Say hello in one word")
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
}

@test "SDPR: Chat completion returns valid JSON with choices" {
    skip_if_no_key "sdpr-invoice-automation"
    
    response=$(chat_completion "sdpr-invoice-automation" "${DEFAULT_MODEL}" "What is 3+3?")
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
    
    # Validate response structure
    local choices
    choices=$(json_get "${RESPONSE_BODY}" '.choices | length')
    [[ "${choices}" -gt 0 ]]
}

@test "SDPR: Chat completion includes usage metrics" {
    skip_if_no_key "sdpr-invoice-automation"
    
    response=$(chat_completion "sdpr-invoice-automation" "${DEFAULT_MODEL}" "Hello")
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
    
    # Check usage tokens are present
    local prompt_tokens
    prompt_tokens=$(json_get "${RESPONSE_BODY}" '.usage.prompt_tokens')
    [[ "${prompt_tokens}" -gt 0 ]]
}

@test "SDPR: Chat completion handles invoice-related prompts" {
    skip_if_no_key "sdpr-invoice-automation"
    
    response=$(chat_completion "sdpr-invoice-automation" "${DEFAULT_MODEL}" \
        "Extract the total from this invoice: Total Due: \$150.00")
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
    
    # Response should mention the amount
    assert_contains "${RESPONSE_BODY}" "150"
}

# =============================================================================
# Error Handling Tests
# =============================================================================

@test "Invalid subscription key returns 401" {
    local body='{"messages":[{"role":"user","content":"Hi"}],"max_tokens":10}'
    local url="${APIM_GATEWAY_URL}/wlrs-water-form-assistant/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}"
    
    response=$(curl -s -w "\n%{http_code}" -X POST "${url}" \
        -H "Ocp-Apim-Subscription-Key: invalid-key-12345" \
        -H "Content-Type: application/json" \
        --proxy "${HTTPS_PROXY:-}" \
        -d "${body}")
    parse_response "${response}"
    
    assert_status "401" "${RESPONSE_STATUS}"
}

@test "Missing subscription key returns 401" {
    local body='{"messages":[{"role":"user","content":"Hi"}],"max_tokens":10}'
    local url="${APIM_GATEWAY_URL}/wlrs-water-form-assistant/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}"
    
    response=$(curl -s -w "\n%{http_code}" -X POST "${url}" \
        -H "Content-Type: application/json" \
        --proxy "${HTTPS_PROXY:-}" \
        -d "${body}")
    parse_response "${response}"
    
    assert_status "401" "${RESPONSE_STATUS}"
}

@test "Invalid tenant returns 404" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    local subscription_key
    subscription_key=$(get_subscription_key "wlrs-water-form-assistant")
    
    local body='{"messages":[{"role":"user","content":"Hi"}],"max_tokens":10}'
    local url="${APIM_GATEWAY_URL}/invalid-tenant/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}"
    
    response=$(curl -s -w "\n%{http_code}" -X POST "${url}" \
        -H "Ocp-Apim-Subscription-Key: ${subscription_key}" \
        -H "Content-Type: application/json" \
        --proxy "${HTTPS_PROXY:-}" \
        -d "${body}")
    parse_response "${response}"
    
    # Should return 404 or 401 (no access to other tenants)
    [[ "${RESPONSE_STATUS}" == "404" ]] || [[ "${RESPONSE_STATUS}" == "401" ]]
}

@test "Invalid model returns 404" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    response=$(chat_completion "wlrs-water-form-assistant" "nonexistent-model" "Hello")
    parse_response "${response}"
    
    # Should return 404 for non-existent model
    assert_status "404" "${RESPONSE_STATUS}"
}

@test "Empty messages array returns 400" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    local body='{"messages":[],"max_tokens":10}'
    
    response=$(apim_request "POST" "wlrs-water-form-assistant" \
        "/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}" \
        "${body}")
    parse_response "${response}"
    
    assert_status "400" "${RESPONSE_STATUS}"
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
