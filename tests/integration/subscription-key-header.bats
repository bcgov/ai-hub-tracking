#!/usr/bin/env bats
# Integration tests for Ocp-Apim-Subscription-Key header support
# Verifies APIM accepts the legacy subscription header used by some SDKs
#
# NOTE: These tests only pass when APIM APIs use the default subscription key
# header name (Ocp-Apim-Subscription-Key). When APIs are configured with custom
# subscription_key_parameter_names (e.g., header='api-key' for Azure OpenAI SDK
# compatibility), the legacy header is not accepted and tests are skipped.

load 'test-helper'

setup() {
    setup_test_suite
    # Skip all tests: APIM APIs use custom subscription_key_parameter_names
    # (header='api-key') for Azure OpenAI SDK compatibility, so the legacy
    # Ocp-Apim-Subscription-Key header is not accepted.
    skip "APIM APIs use custom subscription key header (api-key); Ocp-Apim-Subscription-Key not supported"
}

# Check if Document Intelligence is accessible before running tests
docint_accessible() {
    local tenant="${1}"
    local subscription_key
    subscription_key=$(get_subscription_key "${tenant}")

    local url="${APIM_GATEWAY_URL}/${tenant}/documentintelligence/documentModels/prebuilt-layout:analyze?api-version=${DOCINT_API_VERSION}"

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${url}" \
        -H "api-key: ${subscription_key}" \
        -H "Content-Type: application/json" \
        --max-time 10 \
        -d '{"base64Source":"dGVzdA=="}' 2>/dev/null)

    [[ "${status}" == "400" ]] || [[ "${status}" == "200" ]] || [[ "${status}" == "202" ]]
}

# Minimal sample PDF for testing (base64 encoded)
SAMPLE_PDF_BASE64="JVBERi0xLjQKMSAwIG9iago8PAovVHlwZSAvQ2F0YWxvZwovUGFnZXMgMiAwIFIKPj4KZW5kb2JqCjIgMCBvYmoKPDwKL1R5cGUgL1BhZ2VzCi9LaWRzIFszIDAgUl0KL0NvdW50IDEKPJ4KZW5kb2JqCjMgMCBvYmoKPDwKL1R5cGUgL1BhZ2UKL1BhcmVudCAyIDAgUgovTWVkaWFCb3ggWzAgMCA2MTIgNzkyXQovQ29udGVudHMgNCAwIFIKL1Jlc291cmNlcwo8PAovRm9udAo8PAovRjEgNSAwIFIKPj4KPj4KPj4KZW5kb2JqCjQgMCBvYmoKPDwKL0xlbmd0aCA0NAo+PgpzdHJlYW0KQlQKL0YxIDEyIFRmCjEwMCA3MDAgVGQKKFRlc3QgRG9jdW1lbnQpIFRqCkVUCmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iago8PAovVHlwZSAvRm9udAovU3VidHlwZSAvVHlwZTEKL0Jhc2VGb250IC9IZWx2ZXRpY2EKPJ4KZW5kb2JqCnhyZWYKMCA2CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAwOSAwMDAwMCBuIAowMDAwMDAwMDU4IDAwMDAwIG4gCjAwMDAwMDAxMTUgMDAwMDAgbiAKMDAwMDAwMDI4MCAwMDAwMCBuIAowMDAwMDAwMzczIDAwMDAwIG4gCnRyYWlsZXIKPDwKL1NpemUgNgovUm9vdCAxIDAgUgo+PgpzdGFydHhyZWYKNDQ4CiUlRU9G"

skip_if_no_key() {
    local tenant="${1}"
    local key
    key=$(get_subscription_key "${tenant}")

    if [[ -z "${key}" ]]; then
        skip "No subscription key for ${tenant}"
    fi
}

@test "WLRS: Chat completion works with Ocp-Apim-Subscription-Key" {
    skip_if_no_key "wlrs-water-form-assistant"

    response=$(chat_completion_ocp "wlrs-water-form-assistant" "${DEFAULT_MODEL}" "Say hello" 10)
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"
}

@test "SDPR: Chat completion works with Ocp-Apim-Subscription-Key" {
    skip_if_no_key "sdpr-invoice-automation"

    response=$(chat_completion_ocp "sdpr-invoice-automation" "${DEFAULT_MODEL}" "Say hello" 10)
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"
}

@test "WLRS: Document Intelligence works with Ocp-Apim-Subscription-Key" {
    skip_if_no_key "wlrs-water-form-assistant"

    if ! docint_accessible "wlrs-water-form-assistant"; then
        skip "Document Intelligence backend not accessible"
    fi

    response=$(docint_analyze_ocp "wlrs-water-form-assistant" "prebuilt-layout" "${SAMPLE_PDF_BASE64}")
    parse_response "${response}"

    [[ "${RESPONSE_STATUS}" == "200" ]] || [[ "${RESPONSE_STATUS}" == "202" ]]
}
