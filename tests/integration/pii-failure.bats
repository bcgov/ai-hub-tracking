#!/usr/bin/env bats
# Integration tests for PII Redaction fail-closed/fail-open behavior
# These tests simulate PII service failure by temporarily modifying the APIM piiServiceUrl

load 'test-helper'

# File-level setup: Break PII service to test fail-closed/fail-open behavior
setup_file() {
    # Check prerequisites
    if ! command -v az >/dev/null 2>&1; then
        echo "Error: Azure CLI (az) is required for PII failure tests" >&2
        exit 1
    fi

    # Load configuration
    local env="${TEST_ENV:-test}"

    # Get terraform outputs for resource group and APIM name
    local infra_dir="${BATS_TEST_DIRNAME}/../../infra-ai-hub"

    if [[ ! -d "${infra_dir}" ]]; then
        echo "Error: Cannot find infra-ai-hub directory at ${infra_dir}" >&2
        exit 1
    fi

    # Get terraform output
    local tf_output
    if ! tf_output=$(cd "${infra_dir}" && terraform output -json 2>/dev/null); then
        echo "Error: Failed to get terraform output" >&2
        echo "Make sure terraform has been applied in ${infra_dir}" >&2
        exit 1
    fi

    # Extract resource group and APIM name
    export PII_TEST_RESOURCE_GROUP=$(echo "${tf_output}" | jq -r '.resource_group_name.value // empty')
    export PII_TEST_APIM_NAME=$(echo "${tf_output}" | jq -r '.apim_name.value // empty')

    if [[ -z "${PII_TEST_RESOURCE_GROUP}" ]] || [[ -z "${PII_TEST_APIM_NAME}" ]]; then
        echo "Error: Could not determine resource group or APIM name from terraform" >&2
        echo "Resource Group: ${PII_TEST_RESOURCE_GROUP:-<empty>}" >&2
        echo "APIM Name: ${PII_TEST_APIM_NAME:-<empty>}" >&2
        exit 1
    fi

    echo "Setting up PII failure test environment..." >&2
    echo "  Resource Group: ${PII_TEST_RESOURCE_GROUP}" >&2
    echo "  APIM Name: ${PII_TEST_APIM_NAME}" >&2

    # Create a temporary file to store the original URL
    export PII_ORIGINAL_URL_FILE="${BATS_FILE_TMPDIR}/original_pii_url"

    # Get current piiServiceUrl
    echo "Retrieving current piiServiceUrl..." >&2
    local original_url
    if ! original_url=$(az apim nv show \
        --resource-group "${PII_TEST_RESOURCE_GROUP}" \
        --service-name "${PII_TEST_APIM_NAME}" \
        --named-value-id piiServiceUrl \
        --query value \
        --output tsv 2>&1); then
        echo "Error: Failed to retrieve piiServiceUrl" >&2
        echo "${original_url}" >&2
        exit 1
    fi

    if [[ -z "${original_url}" ]]; then
        echo "Error: piiServiceUrl is empty or does not exist" >&2
        exit 1
    fi

    echo "  Original URL: ${original_url}" >&2
    echo "${original_url}" > "${PII_ORIGINAL_URL_FILE}"

    # Set invalid URL to simulate service failure
    local invalid_url="https://invalid.cognitiveservices.azure.com"
    echo "Setting invalid piiServiceUrl to simulate failure..." >&2
    echo "  Invalid URL: ${invalid_url}" >&2

    if ! az apim nv update \
        --resource-group "${PII_TEST_RESOURCE_GROUP}" \
        --service-name "${PII_TEST_APIM_NAME}" \
        --named-value-id piiServiceUrl \
        --value "${invalid_url}" \
        --output none 2>&1; then
        echo "Error: Failed to update piiServiceUrl" >&2
        exit 1
    fi

    # Wait for APIM to propagate the change
    echo "Waiting 15 seconds for APIM to propagate the change..." >&2
    sleep 15

    echo "PII service disabled for testing" >&2
}

# File-level teardown: Restore PII service
teardown_file() {
    echo "Restoring PII service..." >&2

    # Check if we have the necessary variables
    if [[ -z "${PII_TEST_RESOURCE_GROUP}" ]] || [[ -z "${PII_TEST_APIM_NAME}" ]]; then
        echo "Warning: Missing resource group or APIM name, cannot restore" >&2
        return 0
    fi

    if [[ ! -f "${PII_ORIGINAL_URL_FILE}" ]]; then
        echo "Warning: Original URL file not found, cannot restore" >&2
        return 0
    fi

    local original_url
    original_url=$(cat "${PII_ORIGINAL_URL_FILE}")

    if [[ -z "${original_url}" ]]; then
        echo "Warning: Original URL is empty, cannot restore" >&2
        return 0
    fi

    echo "  Restoring URL: ${original_url}" >&2

    if ! az apim nv update \
        --resource-group "${PII_TEST_RESOURCE_GROUP}" \
        --service-name "${PII_TEST_APIM_NAME}" \
        --named-value-id piiServiceUrl \
        --value "${original_url}" \
        --output none 2>&1; then
        echo "Error: Failed to restore piiServiceUrl" >&2
        echo "MANUAL ACTION REQUIRED: Restore piiServiceUrl to: ${original_url}" >&2
        return 1
    fi

    echo "PII service restored successfully" >&2

    # Wait for APIM to propagate the restoration
    echo "Waiting 10 seconds for APIM to propagate the restoration..." >&2
    sleep 10
}

# Per-test setup
setup() {
    setup_test_suite
}

# =============================================================================
# Fail-Closed Behavior Tests
# =============================================================================
# These tests verify behavior when the PII service is unavailable.
# setup_file() has already set piiServiceUrl to an invalid endpoint.
#
# Tenants:
# - sdpr-invoice-automation: fail_closed=true (blocks when PII service fails)
# - wlrs-water-form-assistant: fail_closed=false (allows passthrough when PII service fails)
# =============================================================================

@test "FAIL-CLOSED: sdpr-invoice-automation blocks request when PII service fails" {
    skip_if_no_key "sdpr-invoice-automation"

    # sdpr-invoice-automation has fail_closed=true
    # When PII service fails, request should be blocked with 503
    local prompt="My email is test@example.com. Please process this."

    response=$(chat_completion "sdpr-invoice-automation" "${DEFAULT_MODEL}" "${prompt}" 50)
    parse_response "${response}"

    # When fail_closed=true and PII service fails, expect 503
    assert_status "503" "${RESPONSE_STATUS}"

    # Verify error response format
    local error_code
    error_code=$(json_get "${RESPONSE_BODY}" '.error.code')
    [[ "${error_code}" == "PiiRedactionUnavailable" ]]

    local error_message
    error_message=$(json_get "${RESPONSE_BODY}" '.error.message')
    assert_contains "${error_message}" "PII redaction service is unavailable"

    # Verify request_id is present for correlation
    local request_id
    request_id=$(json_get "${RESPONSE_BODY}" '.error.request_id')
    [[ -n "${request_id}" ]]
}

@test "FAIL-OPEN: wlrs-water-form-assistant succeeds when PII service is unavailable" {
    skip_if_no_key "wlrs-water-form-assistant"

    # wlrs-water-form-assistant has fail_closed=false (fail-open)
    # Even when PII service is unavailable, request should succeed
    local prompt="My email is test@example.com. Please repeat it."

    response=$(chat_completion "wlrs-water-form-assistant" "${DEFAULT_MODEL}" "${prompt}" 100)
    parse_response "${response}"

    # Fail-open: request should succeed with original content passed through
    assert_status "200" "${RESPONSE_STATUS}"

    # Note: The response may contain the unredacted email since PII service failed
    # and fail_closed=false allows passthrough
    local content
    content=$(json_get "${RESPONSE_BODY}" '.choices[0].message.content')

    # Verify we got a response (content passed through unredacted)
    [[ -n "${content}" ]]
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
