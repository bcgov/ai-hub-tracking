#!/usr/bin/env bash
# Configuration loader for integration tests
# Loads APIM gateway URL and subscription keys from terraform outputs

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../../infra-ai-hub"

# Function to load config from terraform output
load_terraform_config() {
    local env="${1:-test}"
    
    echo "Loading terraform configuration for environment: ${env}" >&2
    
    # Check if we're in the right directory
    if [[ ! -d "${INFRA_DIR}" ]]; then
        echo "Error: Cannot find infra-ai-hub directory at ${INFRA_DIR}" >&2
        return 1
    fi
    
    # Get terraform output
    local tf_output
    if ! tf_output=$(cd "${INFRA_DIR}" && terraform output -json 2>/dev/null); then
        echo "Error: Failed to get terraform output. Run 'terraform apply' first." >&2
        return 1
    fi
    
    # Extract APIM gateway URL
    APIM_GATEWAY_URL=$(echo "${tf_output}" | jq -r '.apim_gateway_url.value // empty')
    if [[ -z "${APIM_GATEWAY_URL}" ]]; then
        echo "Error: apim_gateway_url not found in terraform output" >&2
        return 1
    fi
    export APIM_GATEWAY_URL
    
    # Extract APIM name
    APIM_NAME=$(echo "${tf_output}" | jq -r '.apim_name.value // empty')
    export APIM_NAME
    
    # Extract subscription keys (sensitive values)
    local subscriptions
    subscriptions=$(echo "${tf_output}" | jq -r '.apim_tenant_subscriptions.value // empty')
    
    if [[ -n "${subscriptions}" ]]; then
        WLRS_SUBSCRIPTION_KEY=$(echo "${subscriptions}" | jq -r '.["wlrs-water-form-assistant"].primary_key // empty')
        SDPR_SUBSCRIPTION_KEY=$(echo "${subscriptions}" | jq -r '.["sdpr-invoice-automation"].primary_key // empty')
        export WLRS_SUBSCRIPTION_KEY SDPR_SUBSCRIPTION_KEY
    fi
    
    echo "Configuration loaded successfully:" >&2
    echo "  APIM Gateway URL: ${APIM_GATEWAY_URL}" >&2
    echo "  APIM Name: ${APIM_NAME}" >&2
    echo "  WLRS Key: ${WLRS_SUBSCRIPTION_KEY:+********}" >&2
    echo "  SDPR Key: ${SDPR_SUBSCRIPTION_KEY:+********}" >&2
}

# Function to get subscription key for a tenant
get_subscription_key() {
    local tenant="${1}"
    
    case "${tenant}" in
        wlrs-water-form-assistant)
            echo "${WLRS_SUBSCRIPTION_KEY:-}"
            ;;
        sdpr-invoice-automation)
            echo "${SDPR_SUBSCRIPTION_KEY:-}"
            ;;
        *)
            echo "Unknown tenant: ${tenant}" >&2
            return 1
            ;;
    esac
}

# Function to check if config is loaded
config_loaded() {
    [[ -n "${APIM_GATEWAY_URL:-}" ]] && [[ -n "${WLRS_SUBSCRIPTION_KEY:-}" ]] && [[ -n "${SDPR_SUBSCRIPTION_KEY:-}" ]]
}

# Function to validate prerequisites
check_prerequisites() {
    local missing=()
    
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: Missing required tools: ${missing[*]}" >&2
        return 1
    fi
    
    return 0
}

# Export functions
export -f get_subscription_key config_loaded check_prerequisites

# Default values if terraform output is not available (for testing)
: "${APIM_GATEWAY_URL:=https://ai-services-hub-test-apim.azure-api.net}"
export APIM_GATEWAY_URL

# API versions
export OPENAI_API_VERSION="2024-10-21"
export DOCINT_API_VERSION="2024-11-30"

# Tenants
export TENANTS=("wlrs-water-form-assistant" "sdpr-invoice-automation")

# Models available
export DEFAULT_MODEL="gpt-4.1-mini"
