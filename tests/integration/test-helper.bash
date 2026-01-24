#!/usr/bin/env bash
# Test helper functions for bats integration tests

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.bash"

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
        -H "Ocp-Apim-Subscription-Key: ${subscription_key}"
        -H "Content-Type: application/json"
        -H "Accept: application/json"
        --max-time 60                               # 60 second timeout
    )
    
    if [[ -n "${body}" ]]; then
        curl_opts+=(-d "${body}")
    fi
    
    curl -X "${method}" "${curl_opts[@]}" "${url}"
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

# Make a chat completion request
# Usage: chat_completion <tenant> <model> <message>
chat_completion() {
    local tenant="${1}"
    local model="${2}"
    local message="${3}"
    local max_tokens="${4:-100}"
    
    local path="/openai/deployments/${model}/chat/completions?api-version=${OPENAI_API_VERSION}"
    local body
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
    
    apim_request "POST" "${tenant}" "${path}" "${body}"
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

# Assert HTTP status code
# Usage: assert_status <expected> <actual>
assert_status() {
    local expected="${1}"
    local actual="${2}"
    
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
    # Check prerequisites
    check_prerequisites
    
    # Try to load config from terraform if not already set
    if ! config_loaded; then
        echo "Subscription keys not set, attempting to load from terraform..." >&2
        load_terraform_config "test" || true
    fi
    
    # Validate required config
    if [[ -z "${APIM_GATEWAY_URL:-}" ]]; then
        echo "Error: APIM_GATEWAY_URL not set" >&2
        return 1
    fi
}

# Export functions
export -f apim_request parse_response chat_completion docint_analyze
export -f assert_status assert_contains assert_not_contains json_get
export -f looks_like_pii is_redacted wait_for_operation setup_test_suite
