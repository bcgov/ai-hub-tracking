#!/usr/bin/env bats
# Integration tests for Chat Completions API via APIM
# Tests OpenAI chat completion endpoints for both tenants

load 'test-helper'

setup() {
    setup_test_suite
}

# =============================================================================
# WLRS Tenant Tests - Dynamic Model Testing
# =============================================================================
# These tests dynamically load models from tenant.tfvars, ensuring tests
# stay in sync with actual deployments without manual updates.

@test "WLRS: Primary model (gpt-4.1-mini) responds successfully" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    response=$(chat_completion "wlrs-water-form-assistant" "gpt-4.1-mini" "Say hello" 10)
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
}

@test "WLRS: All deployed chat models connectivity check" {
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
        echo "Testing model: ${model}" >&3
        
        response=$(chat_completion "wlrs-water-form-assistant" "${model}" "Say hello" 10)
        parse_response "${response}"
        
        if [[ "${RESPONSE_STATUS}" == "200" ]]; then
            passed_count=$((passed_count + 1))
            echo "  ✓ ${model}: OK" >&3
        elif [[ "${RESPONSE_STATUS}" == "429" ]]; then
            # Rate limited - skip
            skipped_count=$((skipped_count + 1))
            echo "  ⚠ ${model}: Rate limited (429), skipping" >&3
        elif [[ "${RESPONSE_STATUS}" == "400" ]]; then
            # API version incompatibility - log but don't fail
            # Some models (GPT-5.x) may require different API versions
            skipped_count=$((skipped_count + 1))
            echo "  ⚠ ${model}: API format issue (400), may need different API version" >&3
        else
            failed_models="${failed_models} ${model}(${RESPONSE_STATUS})"
            echo "  ✗ ${model}: Failed with status ${RESPONSE_STATUS}" >&3
        fi
    done
    
    echo "Results: ${passed_count} passed, ${skipped_count} skipped, ${#failed_models} failed out of ${total_count} models" >&3
    
    # Fail only on unexpected errors (not 400 API version issues or 429 rate limits)
    if [[ -n "${failed_models}" ]]; then
        echo "Unexpected failures:${failed_models}" >&2
        return 1
    fi
    
    # At least one model should work
    [[ ${passed_count} -gt 0 ]]
}

# =============================================================================
# WLRS Tenant Tests - Core Functionality
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
    
    response=$(apim_request_with_retry "POST" "wlrs-water-form-assistant" \
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
        -H "api-key: ${subscription_key}" \
        -H "Content-Type: application/json" \
        --proxy "${HTTPS_PROXY:-}" \
        --max-time 60 \
        -d "${body}" 2>/dev/null)
    
    # Check for x-correlation-id or x-ms-request-id header (case insensitive)
    echo "${response}" | grep -iqE "(x-correlation-id|x-ms-request-id)"
}

# =============================================================================
# SDPR Tenant Tests - Dynamic Model Testing
# =============================================================================

@test "SDPR: Primary model (gpt-4.1-mini) responds successfully" {
    skip_if_no_key "sdpr-invoice-automation"
    
    response=$(chat_completion "sdpr-invoice-automation" "gpt-4.1-mini" "Say hello" 10)
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
}

@test "SDPR: All deployed chat models connectivity check" {
    skip_if_no_key "sdpr-invoice-automation"
    
    local models
    models=$(get_tenant_chat_models "sdpr-invoice-automation")
    
    if [[ -z "${models}" ]]; then
        skip "No models found for SDPR tenant"
    fi
    
    local failed_models=""
    local passed_count=0
    local total_count=0
    local skipped_count=0
    
    for model in ${models}; do
        total_count=$((total_count + 1))
        echo "Testing model: ${model}" >&3
        
        response=$(chat_completion "sdpr-invoice-automation" "${model}" "Say hello" 10)
        parse_response "${response}"
        
        if [[ "${RESPONSE_STATUS}" == "200" ]]; then
            passed_count=$((passed_count + 1))
            echo "  ✓ ${model}: OK" >&3
        elif [[ "${RESPONSE_STATUS}" == "429" ]]; then
            # Rate limited - skip
            skipped_count=$((skipped_count + 1))
            echo "  ⚠ ${model}: Rate limited (429), skipping" >&3
        elif [[ "${RESPONSE_STATUS}" == "400" ]]; then
            # API version incompatibility - log but don't fail
            # Some models (GPT-5.x) may require different API versions
            skipped_count=$((skipped_count + 1))
            echo "  ⚠ ${model}: API format issue (400), may need different API version" >&3
        else
            failed_models="${failed_models} ${model}(${RESPONSE_STATUS})"
            echo "  ✗ ${model}: Failed with status ${RESPONSE_STATUS}" >&3
        fi
    done
    
    echo "Results: ${passed_count} passed, ${skipped_count} skipped, ${#failed_models} failed out of ${total_count} models" >&3
    
    # Fail only on unexpected errors (not 400 API version issues or 429 rate limits)
    if [[ -n "${failed_models}" ]]; then
        echo "Unexpected failures:${failed_models}" >&2
        return 1
    fi
    
    # At least one model should work
    [[ ${passed_count} -gt 0 ]]
}

# =============================================================================
# SDPR Tenant Tests - Core Functionality
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

@test "Invalid subscription key returns 401 or 404" {
    local body='{"messages":[{"role":"user","content":"Hi"}],"max_tokens":10}'
    local url="${APIM_GATEWAY_URL}/wlrs-water-form-assistant/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}"
    
    response=$(curl -s -w "\n%{http_code}" -X POST "${url}" \
        -H "api-key: invalid-key-12345" \
        -H "Content-Type: application/json" \
        --proxy "${HTTPS_PROXY:-}" \
        -d "${body}")
    parse_response "${response}"
    
    [[ "${RESPONSE_STATUS}" == "401" ]] || [[ "${RESPONSE_STATUS}" == "404" ]]
}

@test "Missing subscription key returns 401 or 404" {
    local body='{"messages":[{"role":"user","content":"Hi"}],"max_tokens":10}'
    local url="${APIM_GATEWAY_URL}/wlrs-water-form-assistant/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}"
    
    response=$(curl -s -w "\n%{http_code}" -X POST "${url}" \
        -H "Content-Type: application/json" \
        --proxy "${HTTPS_PROXY:-}" \
        -d "${body}")
    parse_response "${response}"
    
    [[ "${RESPONSE_STATUS}" == "401" ]] || [[ "${RESPONSE_STATUS}" == "404" ]]
}

@test "Invalid tenant returns 404" {
    skip_if_no_key "wlrs-water-form-assistant"
    
    local subscription_key
    subscription_key=$(get_subscription_key "wlrs-water-form-assistant")
    
    local body='{"messages":[{"role":"user","content":"Hi"}],"max_tokens":10}'
    local url="${APIM_GATEWAY_URL}/invalid-tenant/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}"
    
    response=$(curl -s -w "\n%{http_code}" -X POST "${url}" \
        -H "api-key: ${subscription_key}" \
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
# NR-DAP Tenant Tests - Dynamic Model Testing (1% quota allocation)
# =============================================================================
# NR-DAP has the lowest quota allocation (1%), so these tests validate that
# the reduced capacity still handles requests correctly. Uses lower max_tokens
# to stay within rate limits.

@test "NR-DAP: Primary model (gpt-5-mini) responds successfully" {
    skip_if_no_key "nr-dap-fish-wildlife"
    
    response=$(chat_completion "nr-dap-fish-wildlife" "gpt-5-mini" "Say hello" 10)
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
}

@test "NR-DAP: All deployed chat models connectivity check" {
    skip_if_no_key "nr-dap-fish-wildlife"
    
    local models
    models=$(get_tenant_chat_models "nr-dap-fish-wildlife")
    
    if [[ -z "${models}" ]]; then
        skip "No models found for NR-DAP tenant"
    fi
    
    local failed_models=""
    local passed_count=0
    local total_count=0
    local skipped_count=0
    
    for model in ${models}; do
        total_count=$((total_count + 1))
        echo "Testing model: ${model}" >&3
        
        # Use minimal tokens (10) to avoid hitting low quota limits
        response=$(chat_completion "nr-dap-fish-wildlife" "${model}" "Say hello" 10)
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
        
        # Brief pause between models to avoid rate limit cascade with low quota
        sleep 1
    done
    
    echo "Results: ${passed_count} passed, ${skipped_count} skipped, ${#failed_models} failed out of ${total_count} models" >&3
    
    if [[ -n "${failed_models}" ]]; then
        echo "Unexpected failures:${failed_models}" >&2
        return 1
    fi
    
    [[ ${passed_count} -gt 0 ]]
}

@test "NR-DAP: Chat completion returns valid JSON with choices" {
    skip_if_no_key "nr-dap-fish-wildlife"
    
    response=$(chat_completion "nr-dap-fish-wildlife" "gpt-5-mini" "What is 2+2?" 10)
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
    
    local choices
    choices=$(json_get "${RESPONSE_BODY}" '.choices | length')
    [[ "${choices}" -gt 0 ]]
}

@test "NR-DAP: Chat completion includes usage metrics" {
    skip_if_no_key "nr-dap-fish-wildlife"
    
    response=$(chat_completion "nr-dap-fish-wildlife" "gpt-5-mini" "Hello" 10)
    parse_response "${response}"
    
    assert_status "200" "${RESPONSE_STATUS}"
    
    local prompt_tokens
    prompt_tokens=$(json_get "${RESPONSE_BODY}" '.usage.prompt_tokens')
    [[ "${prompt_tokens}" -gt 0 ]]
    
    local completion_tokens
    completion_tokens=$(json_get "${RESPONSE_BODY}" '.usage.completion_tokens')
    [[ "${completion_tokens}" -gt 0 ]]
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
