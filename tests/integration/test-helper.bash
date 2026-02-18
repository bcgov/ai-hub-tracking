#!/usr/bin/env bash
# Test helper functions for bats integration tests

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.bash"

# Refresh tenant key from centralized hub Key Vault via Azure CLI.
# Strategy:
# 1) Try rotation metadata safe_slot first
# 2) Fallback to primary then secondary secrets
get_tenant_key_from_vault() {
    local tenant="${1}"
    local preferred_slot="${2:-}"

    if [[ "${ENABLE_VAULT_KEY_FALLBACK:-true}" != "true" ]]; then
        return 1
    fi

    if ! command -v az >/dev/null 2>&1; then
        echo "[key-fallback] az CLI not found; cannot refresh key for ${tenant}" >&2
        return 1
    fi

    if ! az account show >/dev/null 2>&1; then
        echo "[key-fallback] az CLI not authenticated; cannot refresh key for ${tenant}" >&2
        return 1
    fi

    local vault_name="${HUB_KEYVAULT_NAME:-}"
    if [[ -z "${vault_name}" ]]; then
        echo "[key-fallback] HUB_KEYVAULT_NAME not set; cannot refresh key for ${tenant}" >&2
        return 1
    fi

    local safe_slot="${preferred_slot}"
    local metadata_json=""
    if [[ -z "${safe_slot}" ]]; then
        metadata_json=$(az keyvault secret show \
            --vault-name "${vault_name}" \
            --name "${tenant}-apim-rotation-metadata" \
            --query value -o tsv 2>/dev/null || true)

        if [[ -n "${metadata_json}" ]]; then
            safe_slot=$(echo "${metadata_json}" | jq -r '.safe_slot // empty' 2>/dev/null || true)
        fi
    fi

    local candidates=()
    if [[ "${safe_slot}" == "primary" ]]; then
        candidates+=("${tenant}-apim-primary-key" "${tenant}-apim-secondary-key")
    elif [[ "${safe_slot}" == "secondary" ]]; then
        candidates+=("${tenant}-apim-secondary-key" "${tenant}-apim-primary-key")
    else
        candidates+=("${tenant}-apim-primary-key" "${tenant}-apim-secondary-key")
    fi

    local refreshed_key=""
    local secret_name
    for secret_name in "${candidates[@]}"; do
        refreshed_key=$(az keyvault secret show \
            --vault-name "${vault_name}" \
            --name "${secret_name}" \
            --query value -o tsv 2>/dev/null || true)
        if [[ -n "${refreshed_key}" ]]; then
            printf '%s' "${refreshed_key}"
            return 0
        fi
    done

    echo "[key-fallback] Failed to refresh key for ${tenant} from vault ${vault_name}" >&2
    return 1
}

refresh_tenant_key_from_vault() {
    local tenant="${1}"
    local preferred_slot="${2:-}"
    local refreshed_key=""
    if ! refreshed_key=$(get_tenant_key_from_vault "${tenant}" "${preferred_slot}"); then
        return 1
    fi

    set_subscription_key "${tenant}" "${refreshed_key}"
    echo "[key-fallback] Refreshed ${tenant} key from vault" >&2
    return 0
}

# HTTP request wrapper with standard headers
# Usage: apim_request <method> <tenant> <path> [body]
apim_request() {
    local method="${1}"
    local tenant="${2}"
    local path="${3}"
    local body="${4:-}"
    
    local subscription_key
    subscription_key=$(get_subscription_key "${tenant}")
    
    if [[ -z "${subscription_key}" ]]; then
        echo "Error: No subscription key for tenant ${tenant}" >&2
        return 1
    fi
    
    local url="${APIM_GATEWAY_URL}/${tenant}${path}"
    
    local curl_opts=(
        -s                                          # Silent
        -w "\n%{http_code}"                         # Append HTTP status code
        -H "api-key: ${subscription_key}"           # APIM subscription key (SDK compatible)
        -H "Content-Type: application/json"
        -H "Accept: application/json"
        --max-time 60                               # 60 second timeout
    )
    
    if [[ -n "${body}" ]]; then
        curl_opts+=(-d "${body}")
    fi
    
    local response
    response=$(curl -X "${method}" "${curl_opts[@]}" "${url}")

    local status
    status=$(echo "${response}" | tail -n1)

    # 401 fallback: key may be stale after rotation; refresh from KV and retry once
    if [[ "${status}" == "401" ]] && refresh_tenant_key_from_vault "${tenant}"; then
        subscription_key=$(get_subscription_key "${tenant}")
        curl_opts=(
            -s
            -w "\n%{http_code}"
            -H "api-key: ${subscription_key}"
            -H "Content-Type: application/json"
            -H "Accept: application/json"
            --max-time 60
        )
        if [[ -n "${body}" ]]; then
            curl_opts+=(-d "${body}")
        fi
        response=$(curl -X "${method}" "${curl_opts[@]}" "${url}")
    fi

    echo "${response}"
}

# HTTP request wrapper using the Ocp-Apim-Subscription-Key header
# Usage: apim_request_ocp <method> <tenant> <path> [body]
apim_request_ocp() {
    local method="${1}"
    local tenant="${2}"
    local path="${3}"
    local body="${4:-}"

    local subscription_key
    subscription_key=$(get_subscription_key "${tenant}")

    if [[ -z "${subscription_key}" ]]; then
        echo "Error: No subscription key for tenant ${tenant}" >&2
        return 1
    fi

    local url="${APIM_GATEWAY_URL}/${tenant}${path}"

    local curl_opts=(
        -s                                          # Silent
        -w "\n%{http_code}"                         # Append HTTP status code
        -H "Ocp-Apim-Subscription-Key: ${subscription_key}"
        -H "Content-Type: application/json"
        -H "Accept: application/json"
        --max-time 60                               # 60 second timeout
    )

    if [[ -n "${body}" ]]; then
        curl_opts+=(-d "${body}")
    fi

    local response
    response=$(curl -X "${method}" "${curl_opts[@]}" "${url}")

    local status
    status=$(echo "${response}" | tail -n1)

    # 401 fallback: key may be stale after rotation; refresh from KV and retry once
    if [[ "${status}" == "401" ]] && refresh_tenant_key_from_vault "${tenant}"; then
        subscription_key=$(get_subscription_key "${tenant}")
        curl_opts=(
            -s
            -w "\n%{http_code}"
            -H "Ocp-Apim-Subscription-Key: ${subscription_key}"
            -H "Content-Type: application/json"
            -H "Accept: application/json"
            --max-time 60
        )
        if [[ -n "${body}" ]]; then
            curl_opts+=(-d "${body}")
        fi
        response=$(curl -X "${method}" "${curl_opts[@]}" "${url}")
    fi

    echo "${response}"
}

# Parse response to separate body from status code
# Returns: body in RESPONSE_BODY, status in RESPONSE_STATUS
parse_response() {
    local response="${1}"
    
    # Last line is the status code
    RESPONSE_STATUS=$(echo "${response}" | tail -n1)
    # Everything else is the body
    RESPONSE_BODY=$(echo "${response}" | sed '$d')
    
    export RESPONSE_STATUS RESPONSE_BODY
}

# Retry configuration for rate limiting
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"

# Make a request with retry logic for transient failures and 429 rate limiting
# Usage: apim_request_with_retry <method> <tenant> <path> [body]
apim_request_with_retry() {
    local method="${1}"
    local tenant="${2}"
    local path="${3}"
    local body="${4:-}"
    local retries=0
    local response
    
    while [[ ${retries} -lt ${MAX_RETRIES} ]]; do
        response=$(apim_request "${method}" "${tenant}" "${path}" "${body}")
        parse_response "${response}"
        
        if [[ "${RESPONSE_STATUS}" == "000" ]]; then
            retries=$((retries + 1))
            echo "Transport failure (000), retry ${retries}/${MAX_RETRIES} after ${RETRY_DELAY}s..." >&2
            sleep "${RETRY_DELAY}"
        elif [[ "${RESPONSE_STATUS}" == "429" ]]; then
            retries=$((retries + 1))
            # Extract retry-after from response if available, default to RETRY_DELAY
            local retry_after
            retry_after=$(echo "${RESPONSE_BODY}" | grep -oP 'retry after \K[0-9]+' || echo "${RETRY_DELAY}")
            echo "Rate limited (429), retry ${retries}/${MAX_RETRIES} after ${retry_after}s..." >&2
            sleep "${retry_after}"
        else
            echo "${response}"
            return 0
        fi
    done
    
    # Return the last response after all retries exhausted
    echo "${response}"
}

# Make a request with retry logic for transient failures and 429 rate limiting (Ocp-Apim-Subscription-Key header)
# Usage: apim_request_with_retry_ocp <method> <tenant> <path> [body]
apim_request_with_retry_ocp() {
    local method="${1}"
    local tenant="${2}"
    local path="${3}"
    local body="${4:-}"
    local retries=0
    local response

    while [[ ${retries} -lt ${MAX_RETRIES} ]]; do
        response=$(apim_request_ocp "${method}" "${tenant}" "${path}" "${body}")
        parse_response "${response}"

        if [[ "${RESPONSE_STATUS}" == "000" ]]; then
            retries=$((retries + 1))
            echo "Transport failure (000), retry ${retries}/${MAX_RETRIES} after ${RETRY_DELAY}s..." >&2
            sleep "${RETRY_DELAY}"
        elif [[ "${RESPONSE_STATUS}" == "429" ]]; then
            retries=$((retries + 1))
            local retry_after
            retry_after=$(echo "${RESPONSE_BODY}" | grep -oP 'retry after \K[0-9]+' || echo "${RETRY_DELAY}")
            echo "Rate limited (429), retry ${retries}/${MAX_RETRIES} after ${retry_after}s..." >&2
            sleep "${retry_after}"
        else
            echo "${response}"
            return 0
        fi
    done

    echo "${response}"
}

# Make a chat completion request (with retry for rate limiting)
# Usage: chat_completion <tenant> <model> <message>
# Note: GPT-5.x models require 'max_completion_tokens' instead of 'max_tokens'
#       and do not support custom temperature values
chat_completion() {
    local tenant="${1}"
    local model="${2}"
    local message="${3}"
    local max_tokens="${4:-100}"
    
    local path="/openai/deployments/${model}/chat/completions?api-version=${OPENAI_API_VERSION}"
    local body
    
    # GPT-5 and newer models have different API requirements:
    # - Use 'max_completion_tokens' instead of 'max_tokens'
    # - Do not support custom temperature (only default value 1 is allowed)
    # Pattern: gpt-5*, gpt-5.1*, etc.
    if [[ "${model}" == gpt-5* ]]; then
        body=$(cat <<EOF
{
    "messages": [
        {
            "role": "user",
            "content": "${message}"
        }
    ],
    "max_completion_tokens": ${max_tokens}
}
EOF
)
    else
        body=$(cat <<EOF
{
    "messages": [
        {
            "role": "user",
            "content": "${message}"
        }
    ],
    "max_tokens": ${max_tokens},
    "temperature": 0.7
}
EOF
)
    fi
    
    apim_request_with_retry "POST" "${tenant}" "${path}" "${body}"
}

# Make a chat completion request using Ocp-Apim-Subscription-Key header
# Usage: chat_completion_ocp <tenant> <model> <message>
chat_completion_ocp() {
    local tenant="${1}"
    local model="${2}"
    local message="${3}"
    local max_tokens="${4:-100}"

    local path="/openai/deployments/${model}/chat/completions?api-version=${OPENAI_API_VERSION}"
    local body

    if [[ "${model}" == gpt-5* ]]; then
        body=$(cat <<EOF
{
    "messages": [
        {
            "role": "user",
            "content": "${message}"
        }
    ],
    "max_completion_tokens": ${max_tokens}
}
EOF
)
    else
        body=$(cat <<EOF
{
    "messages": [
        {
            "role": "user",
            "content": "${message}"
        }
    ],
    "max_tokens": ${max_tokens},
    "temperature": 0.7
}
EOF
)
    fi

    apim_request_with_retry_ocp "POST" "${tenant}" "${path}" "${body}"
}

# Make a document intelligence analyze request
# Usage: docint_analyze <tenant> <model> <base64_content>
docint_analyze() {
    local tenant="${1}"
    local model="${2:-prebuilt-layout}"
    local base64_content="${3}"
    
    local path="/documentintelligence/documentModels/${model}:analyze?api-version=${DOCINT_API_VERSION}"
    local body
    body=$(cat <<EOF
{
    "base64Source": "${base64_content}"
}
EOF
)
    
    apim_request "POST" "${tenant}" "${path}" "${body}"
}

# Make a document intelligence analyze request using Ocp-Apim-Subscription-Key header
# Usage: docint_analyze_ocp <tenant> <model> <base64_content>
docint_analyze_ocp() {
    local tenant="${1}"
    local model="${2:-prebuilt-layout}"
    local base64_content="${3}"

    local path="/documentintelligence/documentModels/${model}:analyze?api-version=${DOCINT_API_VERSION}"
    local body
    body=$(cat <<EOF
{
    "base64Source": "${base64_content}"
}
EOF
)

    apim_request_ocp "POST" "${tenant}" "${path}" "${body}"
}

# Assert HTTP status code
# Usage: assert_status <expected> <actual>
# If SKIP_ON_RATE_LIMIT=true and status is 429, the test will be skipped instead of failing
assert_status() {
    local expected="${1}"
    local actual="${2}"
    
    # Handle rate limiting gracefully
    if [[ "${actual}" == "429" ]] && [[ "${SKIP_ON_RATE_LIMIT:-false}" == "true" ]]; then
        skip "Rate limited (429) - skipping test"
    fi
    
    if [[ "${actual}" != "${expected}" ]]; then
        echo "Expected status ${expected}, got ${actual}" >&2
        echo "Response body: ${RESPONSE_BODY:-<empty>}" >&2
        return 1
    fi
}

# Assert response contains substring
# Usage: assert_contains <response> <substring>
assert_contains() {
    local response="${1}"
    local substring="${2}"
    
    if [[ "${response}" != *"${substring}"* ]]; then
        echo "Expected response to contain '${substring}'" >&2
        echo "Response: ${response}" >&2
        return 1
    fi
}

# Assert response does NOT contain substring
# Usage: assert_not_contains <response> <substring>
assert_not_contains() {
    local response="${1}"
    local substring="${2}"
    
    if [[ "${response}" == *"${substring}"* ]]; then
        echo "Expected response to NOT contain '${substring}'" >&2
        echo "Response: ${response}" >&2
        return 1
    fi
}

# Extract JSON field value
# Usage: json_get <json> <jq_path>
# Note: Handles [REDACTED_PHONE] placeholders inserted by DLP proxies
json_get() {
    local json="${1}"
    local path="${2}"
    
    # Replace [REDACTED_PHONE] with a valid placeholder number to fix JSON parsing
    # This is a workaround for DLP proxies that redact Unix timestamps
    local sanitized_json
    sanitized_json=$(echo "${json}" | sed 's/\[REDACTED_PHONE\]/0/g')
    
    echo "${sanitized_json}" | jq -r "${path}"
}

# Check if value looks like PII (for redaction tests)
# Returns 0 if PII pattern detected (email, phone, SSN pattern)
looks_like_pii() {
    local value="${1}"
    
    # Email pattern
    if [[ "${value}" =~ [A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,} ]]; then
        return 0
    fi
    
    # Phone pattern (various formats)
    if [[ "${value}" =~ [0-9]{3}[-.\)][0-9]{3}[-.]?[0-9]{4} ]]; then
        return 0
    fi
    
    # SSN pattern
    if [[ "${value}" =~ [0-9]{3}-[0-9]{2}-[0-9]{4} ]]; then
        return 0
    fi
    
    return 1
}

# Check if value is redacted (contains asterisks or [REDACTED])
is_redacted() {
    local value="${1}"
    
    if [[ "${value}" == *"*"* ]] || [[ "${value}" == *"[REDACTED]"* ]] || [[ "${value}" == *"XXXXX"* ]]; then
        return 0
    fi
    
    return 1
}

# Make a document intelligence analyze request by reading a file, base64-encoding it,
# and sending as JSON. Returns full response with headers (uses -i flag).
# Note: Binary upload (application/octet-stream) is blocked by the App Gateway WAF.
# Usage: docint_analyze_file <tenant> <model> <file_path>
docint_analyze_file() {
    local tenant="${1}"
    local model="${2:-prebuilt-layout}"
    local file_path="${3}"

    if [[ ! -f "${file_path}" ]]; then
        echo "Error: File not found: ${file_path}" >&2
        return 1
    fi

    local subscription_key
    subscription_key=$(get_subscription_key "${tenant}")

    local url="${APIM_GATEWAY_URL}/${tenant}/documentintelligence/documentModels/${model}:analyze?api-version=${DOCINT_API_VERSION}"

    # Base64-encode the file and wrap in JSON (WAF blocks raw binary uploads)
    local b64_content
    b64_content=$(base64 -w0 "${file_path}")

    local tmpfile
    tmpfile=$(mktemp)
    echo "{\"base64Source\": \"${b64_content}\"}" > "${tmpfile}"

    curl -s -i -X POST "${url}" \
        -H "api-key: ${subscription_key}" \
        -H "Content-Type: application/json" \
        --max-time 120 \
        -d "@${tmpfile}" 2>/dev/null

    local rc=$?
    rm -f "${tmpfile}"
    return ${rc}
}

# Extract relative operation path from a full Operation-Location URL
# Strips the APIM gateway URL and tenant prefix to produce a path usable with apim_request
# Usage: extract_operation_path <tenant> <full_operation_location_url>
extract_operation_path() {
    local tenant="${1}"
    local operation_url="${2}"

    # Strip the base URL prefix (e.g. https://test.aihub.gov.bc.ca/wlrs-water-form-assistant)
    local prefix="${APIM_GATEWAY_URL}/${tenant}"
    echo "${operation_url}" | sed "s|${prefix}||"
}

# Wait for async operation (for Document Intelligence)
# Usage: wait_for_operation <tenant> <operation_location> <max_wait_seconds>
wait_for_operation() {
    local tenant="${1}"
    local operation_location="${2}"
    local max_wait="${3:-30}"
    
    local start_time=$(date +%s)
    local end_time=$((start_time + max_wait))
    
    while [[ $(date +%s) -lt ${end_time} ]]; do
        local response
        response=$(apim_request "GET" "${tenant}" "${operation_location}")
        parse_response "${response}"
        
        local status
        status=$(json_get "${RESPONSE_BODY}" '.status')
        
        case "${status}" in
            succeeded|completed)
                return 0
                ;;
            failed)
                echo "Operation failed: ${RESPONSE_BODY}" >&2
                return 1
                ;;
            *)
                sleep 2
                ;;
        esac
    done
    
    echo "Operation timed out after ${max_wait} seconds" >&2
    return 1
}

# Setup function for bats tests
setup_test_suite() {
    local test_env="${TEST_ENV:-test}"

    # Check prerequisites
    check_prerequisites
    
    # Try to load config from terraform if not already set
    if ! config_loaded; then
        echo "Subscription keys not set, attempting to load from terraform..." >&2
        load_terraform_config "${test_env}" || true
    fi
    
    # Validate required config
    if [[ -z "${APIM_GATEWAY_URL:-}" ]]; then
        echo "Error: APIM_GATEWAY_URL not set" >&2
        return 1
    fi
}

# Skip current bats test unless App Gateway is deployed for TEST_ENV
skip_if_no_appgw() {
    if ! is_appgw_deployed; then
        skip "App Gateway is not deployed for TEST_ENV=${TEST_ENV:-test}; skipping AppGW-specific test"
    fi
}

# Make a Document Intelligence analyze request by sending a file as raw binary
# (application/octet-stream). This tests the WAF custom rule that allows binary
# file uploads to Doc Intel paths without managed rule inspection.
# Returns full response with headers (uses -i flag).
# Usage: docint_analyze_binary <tenant> <model> <file_path>
docint_analyze_binary() {
    local tenant="${1}"
    local model="${2:-prebuilt-layout}"
    local file_path="${3}"

    if [[ ! -f "${file_path}" ]]; then
        echo "Error: File not found: ${file_path}" >&2
        return 1
    fi

    local subscription_key
    subscription_key=$(get_subscription_key "${tenant}")

    local url="${APIM_GATEWAY_URL}/${tenant}/documentintelligence/documentModels/${model}:analyze?api-version=${DOCINT_API_VERSION}"

    curl -s -i -X POST "${url}" \
        -H "api-key: ${subscription_key}" \
        -H "Content-Type: application/octet-stream" \
        --data-binary "@${file_path}" \
        --max-time 120 2>/dev/null
}

# Make a Document Intelligence analyze request by sending a file as application/pdf.
# Tests the WAF custom rule specifically for PDF content type.
# Returns full response with headers (uses -i flag).
# Usage: docint_analyze_pdf <tenant> <model> <file_path>
docint_analyze_pdf() {
    local tenant="${1}"
    local model="${2:-prebuilt-layout}"
    local file_path="${3}"

    if [[ ! -f "${file_path}" ]]; then
        echo "Error: File not found: ${file_path}" >&2
        return 1
    fi

    local subscription_key
    subscription_key=$(get_subscription_key "${tenant}")

    local url="${APIM_GATEWAY_URL}/${tenant}/documentintelligence/documentModels/${model}:analyze?api-version=${DOCINT_API_VERSION}"

    curl -s -i -X POST "${url}" \
        -H "api-key: ${subscription_key}" \
        -H "Content-Type: application/pdf" \
        --data-binary "@${file_path}" \
        --max-time 120 2>/dev/null
}

# Make a Document Intelligence analyze request via multipart/form-data.
# Tests WAF custom rule for multipart file uploads.
# Returns full response with headers (uses -i flag).
# Usage: docint_analyze_multipart <tenant> <model> <file_path>
docint_analyze_multipart() {
    local tenant="${1}"
    local model="${2:-prebuilt-layout}"
    local file_path="${3}"

    if [[ ! -f "${file_path}" ]]; then
        echo "Error: File not found: ${file_path}" >&2
        return 1
    fi

    local subscription_key
    subscription_key=$(get_subscription_key "${tenant}")

    local url="${APIM_GATEWAY_URL}/${tenant}/documentintelligence/documentModels/${model}:analyze?api-version=${DOCINT_API_VERSION}"

    curl -s -i -X POST "${url}" \
        -H "api-key: ${subscription_key}" \
        -F "file=@${file_path}" \
        --max-time 120 2>/dev/null
}

# Extract HTTP status from a full response (headers + body captured with -i)
# Usage: extract_http_status <full_response>
extract_http_status() {
    local full_response="${1}"
    echo "${full_response}" | grep "^HTTP/" | tail -1 | grep -o '[0-9]\{3\}'
}

# Extract body from a full response (headers + body captured with -i)
# Usage: extract_response_body <full_response>
extract_response_body() {
    local full_response="${1}"
    echo "${full_response}" | sed -n '/^\r*$/,$ p' | tail -n +2
}

# Export functions
export -f apim_request apim_request_with_retry parse_response chat_completion docint_analyze
export -f docint_analyze_file docint_analyze_binary docint_analyze_pdf docint_analyze_multipart
export -f extract_operation_path extract_http_status extract_response_body
export -f assert_status assert_contains assert_not_contains json_get
export -f looks_like_pii is_redacted wait_for_operation setup_test_suite skip_if_no_appgw
