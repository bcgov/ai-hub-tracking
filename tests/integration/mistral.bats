#!/usr/bin/env bats
# Integration tests for Mistral routing via APIM.
#
# Scope:
# - ai-hub-admin tenant only
# - Skip cleanly unless the relevant Mistral deployments are exposed by /internal/tenant-info
# - Validate the supported OpenAI-compatible chat route, the blocked legacy chat route,
#   and the OCR document route against the first deployed Mistral document model.

load 'test-helper'

setup() {
    setup_test_suite
}

ai_hub_admin_tenant() {
    echo "${AI_HUB_ADMIN_TENANT:-ai-hub-admin}"
}

skip_if_no_key() {
    local tenant="${1}"
    local key
    key=$(get_subscription_key "${tenant}" 2>/dev/null || echo "")
    if [[ -z "${key}" ]]; then
        skip "No subscription key for tenant: ${tenant}"
    fi
}

get_tenant_info_json() {
    local tenant="${1}"
    local response
    response=$(apim_request "GET" "${tenant}" "/internal/tenant-info")
    parse_response "${response}"
    if [[ "${RESPONSE_STATUS}" != "200" ]]; then
        echo "Failed to read /internal/tenant-info for ${tenant}: HTTP ${RESPONSE_STATUS}" >&2
        return 1
    fi
    printf '%s' "${RESPONSE_BODY}"
}

get_mistral_chat_model() {
    local tenant_info_json="${1}"
    echo "${tenant_info_json}" | jq -r '.models[] | select(.name == "Mistral-Large-3") | .name' | head -1
}

get_mistral_document_model() {
    local tenant_info_json="${1}"
    echo "${tenant_info_json}" | jq -r '.models[] | select(.name | startswith("mistral-document-ai-")) | .name' | head -1
}

# Minimal valid PDF fixture. OCR output content is not asserted; this suite only
# validates APIM routing and successful document processing for deployed models.
MISTRAL_OCR_SAMPLE_PDF_BASE64="JVBERi0xLjQKMSAwIG9iago8PAovVHlwZSAvQ2F0YWxvZwovUGFnZXMgMiAwIFIKPj4KZW5kb2JqCjIgMCBvYmoKPDwKL1R5cGUgL1BhZ2VzCi9LaWRzIFszIDAgUl0KL0NvdW50IDEKPj4KZW5kb2JqCjMgMCBvYmoKPDwKL1R5cGUgL1BhZ2UKL1BhcmVudCAyIDAgUgovTWVkaWFCb3ggWzAgMCA2MTIgNzkyXQovQ29udGVudHMgNCAwIFIKL1Jlc291cmNlcwo8PAovRm9udAo8PAovRjEgNSAwIFIKPj4KPj4KPj4KZW5kb2JqCjQgMCBvYmoKPDwKL0xlbmd0aCA0NAo+PgpzdHJlYW0KQlQKL0YxIDEyIFRmCjEwMCA3MDAgVGQKKFRlc3QgRG9jdW1lbnQpIFRqCkVUCmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iago8PAovVHlwZSAvRm9udAovU3VidHlwZSAvVHlwZTEKL0Jhc2VGb250IC9IZWx2ZXRpY2EKPj4KZW5kb2JqCnhyZWYKMCA2CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAwOSAwMDAwMCBuIAowMDAwMDAwMDU4IDAwMDAwIG4gCjAwMDAwMDAxMTUgMDAwMDAgbiAKMDAwMDAwMDI4MCAwMDAwMCBuIAowMDAwMDAwMzczIDAwMDAwIG4gCnRyYWlsZXIKPDwKL1NpemUgNgovUm9vdCAxIDAgUgo+PgpzdGFydHhyZWYKNDQ4CiUlRU9G"

@test "AI Hub Admin: tenant-info exposes deployed Mistral models when configured" {
    local tenant
    tenant="$(ai_hub_admin_tenant)"
    skip_if_no_key "${tenant}"

    local response
    response=$(apim_request "GET" "${tenant}" "/internal/tenant-info")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local mistral_count
    mistral_count=$(echo "${RESPONSE_BODY}" | jq '[.models[] | select(.name == "Mistral-Large-3" or (.name | startswith("mistral-document-ai-")))] | length')

    if [[ "${mistral_count}" -eq 0 ]]; then
        skip "No Mistral models deployed for ${tenant}"
    fi

    local openai_enabled
    openai_enabled=$(json_get "${RESPONSE_BODY}" '.services.openai.enabled')
    [[ "${openai_enabled}" == "true" ]]
}

@test "AI Hub Admin: deployed Mistral chat model works via /openai/v1/chat/completions" {
    local tenant
    tenant="$(ai_hub_admin_tenant)"
    skip_if_no_key "${tenant}"

    local tenant_info_json
    tenant_info_json=$(get_tenant_info_json "${tenant}")

    local chat_model
    chat_model=$(get_mistral_chat_model "${tenant_info_json}")
    if [[ -z "${chat_model}" ]]; then
        skip "No Mistral chat model deployed for ${tenant}"
    fi

    local response
    response=$(chat_completion_v1 "${tenant}" "${chat_model}" "Say hello in one short sentence." 20)
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local content
    content=$(echo "${RESPONSE_BODY}" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    [[ -n "${content}" ]]
}

@test "AI Hub Admin: Mistral chat model is rejected on the legacy non-OpenAI route" {
    local tenant
    tenant="$(ai_hub_admin_tenant)"
    skip_if_no_key "${tenant}"

    local tenant_info_json
    tenant_info_json=$(get_tenant_info_json "${tenant}")

    local chat_model
    chat_model=$(get_mistral_chat_model "${tenant_info_json}")
    if [[ -z "${chat_model}" ]]; then
        skip "No Mistral chat model deployed for ${tenant}"
    fi

    local body
    body=$(cat <<EOF
{
    "model": "${chat_model}",
    "messages": [
        {
            "role": "user",
            "content": "Hello"
        }
    ],
    "max_tokens": 10
}
EOF
)

    local response
    response=$(apim_request "POST" "${tenant}" "/providers/mistral/models/${chat_model}/chat/completions" "${body}")
    parse_response "${response}"

    assert_status "400" "${RESPONSE_STATUS}"

    local error_code
    error_code=$(echo "${RESPONSE_BODY}" | jq -r '.error.code // empty' 2>/dev/null)
    [[ "${error_code}" == "InvalidMistralRoute" ]]
}

@test "AI Hub Admin: deployed Mistral document model accepts OCR requests" {
    local tenant
    tenant="$(ai_hub_admin_tenant)"
    skip_if_no_key "${tenant}"

    local tenant_info_json
    tenant_info_json=$(get_tenant_info_json "${tenant}")

    local document_model
    document_model=$(get_mistral_document_model "${tenant_info_json}")
    if [[ -z "${document_model}" ]]; then
        skip "No Mistral document model deployed for ${tenant}"
    fi

    local body
    body=$(cat <<EOF
{
    "model": "${document_model}",
    "document": {
        "type": "document_url",
        "document_url": "data:application/pdf;base64,${MISTRAL_OCR_SAMPLE_PDF_BASE64}"
    },
    "include_image_base64": false
}
EOF
)

    local response
    response=$(apim_request_with_retry "POST" "${tenant}" "/providers/mistral/azure/ocr" "${body}")
    parse_response "${response}"

    assert_status "200" "${RESPONSE_STATUS}"

    local response_model
    response_model=$(json_get "${RESPONSE_BODY}" '.model')
    [[ "${response_model}" == "${document_model}" ]]

    local page_count
    page_count=$(json_get "${RESPONSE_BODY}" '.pages | length')
    [[ "${page_count}" -gt 0 ]]

    local processed_pages
    processed_pages=$(json_get "${RESPONSE_BODY}" '.usage_info.pages_processed')
    [[ "${processed_pages}" -gt 0 ]]
}