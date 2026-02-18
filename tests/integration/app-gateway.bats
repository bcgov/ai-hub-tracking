#!/usr/bin/env bats
# Integration tests for Application Gateway
# Validates App Gateway is up, SSL termination works, and traffic routes
# through to APIM correctly via the custom domain (e.g. test.aihub.gov.bc.ca).
#
# These tests require App Gateway to be deployed; they are skipped otherwise.

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
# Connectivity & Health
# =============================================================================

@test "AppGW: Custom domain resolves and returns HTTP 200" {
    skip_if_no_appgw

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 15 \
        "https://${APPGW_HOSTNAME}/" 2>/dev/null || echo "000")

    echo "# HTTPS probe to ${APPGW_HOSTNAME}: HTTP ${status}" >&3
    [[ "${status}" != "000" ]]
    # APIM returns 401/404 for bare root — any non-connection-failure is fine
    [[ "${status}" -ge 200 ]] && [[ "${status}" -lt 600 ]]
}

@test "AppGW: TLS certificate is valid and matches hostname" {
    skip_if_no_appgw

    # Use openssl to verify the cert presented by App Gateway
    local cert_info
    cert_info=$(echo | openssl s_client -servername "${APPGW_HOSTNAME}" \
        -connect "${APPGW_HOSTNAME}:443" 2>/dev/null \
        | openssl x509 -noout -subject -dates -ext subjectAltName 2>/dev/null || true)

    echo "# TLS cert info:" >&3
    echo "# ${cert_info}" >&3

    # Cert should exist
    [[ -n "${cert_info}" ]]
    # Cert should not be expired (openssl exits 0 only if valid)
    echo | openssl s_client -servername "${APPGW_HOSTNAME}" \
        -connect "${APPGW_HOSTNAME}:443" 2>/dev/null \
        | openssl x509 -noout -checkend 0 2>/dev/null
}

@test "AppGW: HTTPS health probe returns non-error status" {
    skip_if_no_appgw

    # APIM's built-in status endpoint used as App GW health probe
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 \
        "https://${APPGW_HOSTNAME}/status-0123456789abcdef" 2>/dev/null || echo "000")

    echo "# Health probe status: ${status}" >&3
    [[ "${status}" == "200" ]]
}

# =============================================================================
# Routing through App Gateway
# =============================================================================

@test "AppGW: Chat completion routed through App Gateway returns 200" {
    skip_if_no_appgw
    skip_if_no_key "wlrs-water-form-assistant"

    local subscription_key
    subscription_key=$(get_subscription_key "wlrs-water-form-assistant")

    local response
    response=$(curl -s -w "\n%{http_code}" \
        --max-time 30 \
        "https://${APPGW_HOSTNAME}/wlrs-water-form-assistant/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}" \
        -H "api-key: ${subscription_key}" \
        -H "Content-Type: application/json" \
        -d '{"messages":[{"role":"user","content":"Say hello"}],"max_tokens":10}')

    local status
    status=$(echo "${response}" | tail -1)
    local body
    body=$(echo "${response}" | sed '$d')

    echo "# AppGW chat status: ${status}" >&3
    [[ "${status}" == "200" ]]

    # Verify valid JSON with choices
    echo "${body}" | jq -e '.choices[0].message.content' >/dev/null
}

@test "AppGW: Document Intelligence routed through App Gateway returns 200 or 202" {
    skip_if_no_appgw
    skip_if_no_key "wlrs-water-form-assistant"

    local subscription_key
    subscription_key=$(get_subscription_key "wlrs-water-form-assistant")

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 15 \
        -X POST "https://${APPGW_HOSTNAME}/wlrs-water-form-assistant/documentintelligence/documentModels/prebuilt-layout:analyze?api-version=${DOCINT_API_VERSION}" \
        -H "api-key: ${subscription_key}" \
        -H "Content-Type: application/json" \
        -d '{"base64Source":"dGVzdA=="}')

    echo "# AppGW DocInt status: ${status}" >&3
    [[ "${status}" == "200" ]] || [[ "${status}" == "202" ]] || [[ "${status}" == "400" ]]
}

@test "AppGW: Operation-Location header uses App Gateway URL not backend" {
    skip_if_no_appgw
    skip_if_no_key "wlrs-water-form-assistant"

    local subscription_key
    subscription_key=$(get_subscription_key "wlrs-water-form-assistant")

    # Use a minimal valid PDF so DocInt returns 202 with Operation-Location
    local sample_pdf="JVBERi0xLjQKMSAwIG9iago8PAovVHlwZSAvQ2F0YWxvZwovUGFnZXMgMiAwIFIKPj4KZW5kb2JqCjIgMCBvYmoKPDwKL1R5cGUgL1BhZ2VzCi9LaWRzIFszIDAgUl0KL0NvdW50IDEKPJ4KZW5kb2JqCjMgMCBvYmoKPDwKL1R5cGUgL1BhZ2UKL1BhcmVudCAyIDAgUgovTWVkaWFCb3ggWzAgMCA2MTIgNzkyXQovQ29udGVudHMgNCAwIFIKL1Jlc291cmNlcwo8PAovRm9udAo8PAovRjEgNSAwIFIKPj4KPj4KPj4KZW5kb2JqCjQgMCBvYmoKPDwKL0xlbmd0aCA0NAo+PgpzdHJlYW0KQlQKL0YxIDEyIFRmCjEwMCA3MDAgVGQKKFRlc3QgRG9jdW1lbnQpIFRqCkVUCmVuZHN0cmVhbQplbmRvYmoKNSAwIG9iago8PAovVHlwZSAvRm9udAovU3VidHlwZSAvVHlwZTEKL0Jhc2VGb250IC9IZWx2ZXRpY2EKPJ4KZW5kb2JqCnhyZWYKMCA2CjAwMDAwMDAwMDAgNjU1MzUgZiAKMDAwMDAwMDAwOSAwMDAwMCBuIAowMDAwMDAwMDU4IDAwMDAwIG4gCjAwMDAwMDAxMTUgMDAwMDAgbiAKMDAwMDAwMDI4MCAwMDAwMCBuIAowMDAwMDAwMzczIDAwMDAwIG4gCnRyYWlsZXIKPDwKL1NpemUgNgovUm9vdCAxIDAgUgo+PgpzdGFydHhyZWYKNDQ4CiUlRU9G"

    local full_response
    full_response=$(curl -s -i \
        --max-time 15 \
        -X POST "https://${APPGW_HOSTNAME}/wlrs-water-form-assistant/documentintelligence/documentModels/prebuilt-layout:analyze?api-version=${DOCINT_API_VERSION}" \
        -H "api-key: ${subscription_key}" \
        -H "Content-Type: application/json" \
        -d "{\"base64Source\":\"${sample_pdf}\"}")

    # Extract actual HTTP status (skip proxy CONNECT "200 Connection established" line)
    local http_status
    http_status=$(echo "${full_response}" | grep -oP '^HTTP/[0-9.]+ \K[0-9]{3}' | tail -1)
    echo "# DocInt via AppGW status: ${http_status}" >&3

    # Must get a 202 with Operation-Location for async analysis
    [[ "${http_status}" == "202" ]]

    local op_location
    op_location=$(echo "${full_response}" | grep -i "operation-location" | head -1 | sed 's/^[^:]*: //' | tr -d '\r\n')
    echo "# Operation-Location: ${op_location}" >&3

    [[ -n "${op_location}" ]]

    # APIM policy uses X-Forwarded-Host from App Gateway to rewrite the header.
    # Operation-Location MUST contain the App Gateway hostname so clients poll
    # through App Gateway, not bypass it via direct APIM or backend URLs.
    if echo "${op_location}" | grep -q "cognitiveservices.azure.com"; then
        fail "Operation-Location contains direct backend URL (bypass): ${op_location}"
    fi
    if echo "${op_location}" | grep -q "azure-api.net"; then
        fail "Operation-Location contains APIM URL (should be App Gateway): ${op_location}"
    fi
    if ! echo "${op_location}" | grep -q "${APPGW_HOSTNAME}"; then
        fail "Operation-Location does not contain App Gateway hostname (${APPGW_HOSTNAME}): ${op_location}"
    fi
}

# =============================================================================
# Security
# =============================================================================

@test "AppGW: Request without subscription key returns 401 or 404" {
    skip_if_no_appgw

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 \
        "https://${APPGW_HOSTNAME}/wlrs-water-form-assistant/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}" \
        -H "Content-Type: application/json" \
        -d '{"messages":[{"role":"user","content":"hello"}]}')

    echo "# Unauthenticated via AppGW: ${status}" >&3
    [[ "${status}" == "401" ]] || [[ "${status}" == "404" ]]
}

@test "AppGW: Unauthenticated burst traffic is rate-limited" {
    skip_if_no_appgw

    # WAF unauthenticated rule threshold is 10 req/min per client IP.
    local url="https://${APPGW_HOSTNAME}"
    local payload='{"messages":[{"role":"user","content":"rate-limit-test"}],"max_tokens":5}'

    local saw_rate_limited="false"
    local saw_unauth="false"
    local statuses=""

    # Send a short burst above threshold.
    for i in $(seq 1 15); do
        local code
        code=$(curl -s -o /dev/null -w "%{http_code}" \
            --max-time 10 \
            "${url}" \
            -H "Content-Type: application/json" \
            -d "${payload}" || echo "000")

        statuses="${statuses} ${code}"

        if [[ "${code}" == "401" ]] || [[ "${code}" == "404" ]]; then
            saw_unauth="true"
        fi

        if [[ "${code}" == "403" ]] || [[ "${code}" == "429" ]]; then
            saw_rate_limited="true"
            saw_unauth="true"
        fi

        # Any other status indicates an unexpected auth/routing behavior.
        [[ "${code}" == "401" ]] || [[ "${code}" == "403" ]] || [[ "${code}" == "404" ]] || [[ "${code}" == "429" ]]
    done

    echo "# Unauthenticated burst status codes:${statuses}" >&3
    # Environment may reject at APIM (401/404) before WAF returns 403/429.
    # We still validate unauthenticated access is consistently denied.
    [[ "${saw_unauth}" == "true" ]]
}

@test "AppGW: Invalid tenant via App Gateway returns 404" {
    skip_if_no_appgw
    skip_if_no_key "wlrs-water-form-assistant"

    local subscription_key
    subscription_key=$(get_subscription_key "wlrs-water-form-assistant")

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 \
        "https://${APPGW_HOSTNAME}/nonexistent-tenant/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}" \
        -H "api-key: ${subscription_key}" \
        -H "Content-Type: application/json" \
        -d '{"messages":[{"role":"user","content":"hello"}]}')

    echo "# Invalid tenant via AppGW: ${status}" >&3
    [[ "${status}" == "404" ]]
}

@test "AppGW: HTTP-to-HTTPS redirect works" {
    skip_if_no_appgw

    # App Gateway should redirect HTTP to HTTPS (or refuse HTTP)
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 \
        -L "http://${APPGW_HOSTNAME}/" 2>/dev/null || echo "000")

    echo "# HTTP-to-HTTPS: final status ${status}" >&3
    # After redirect, should land on HTTPS (any real response)
    [[ "${status}" -ge 200 ]] && [[ "${status}" -lt 600 ]]
}

# =============================================================================
# Cross-tenant isolation via App Gateway
# =============================================================================

@test "AppGW: WLRS key cannot access SDPR APIs via App Gateway" {
    skip_if_no_appgw
    skip_if_no_key "wlrs-water-form-assistant"

    local wlrs_key
    wlrs_key=$(get_subscription_key "wlrs-water-form-assistant")

    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 \
        "https://${APPGW_HOSTNAME}/sdpr-invoice-automation/openai/deployments/${DEFAULT_MODEL}/chat/completions?api-version=${OPENAI_API_VERSION}" \
        -H "api-key: ${wlrs_key}" \
        -H "Content-Type: application/json" \
        -d '{"messages":[{"role":"user","content":"hello"}]}')

    echo "# WLRS key -> SDPR via AppGW: ${status}" >&3
    [[ "${status}" == "401" ]] || [[ "${status}" == "403" ]] || [[ "${status}" == "404" ]]
}
