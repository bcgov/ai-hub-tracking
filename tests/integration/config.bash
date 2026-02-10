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
    
    # Extract App Gateway URL (custom domain — preferred for end-to-end testing)
    APPGW_URL=$(echo "${tf_output}" | jq -r '.appgw_url.value // empty')
    export APPGW_URL

    # Extract APIM gateway URL (direct APIM — fallback)
    APIM_GATEWAY_URL=$(echo "${tf_output}" | jq -r '.apim_gateway_url.value // empty')
    if [[ -z "${APIM_GATEWAY_URL}" ]] && [[ -z "${APPGW_URL}" ]]; then
        echo "Error: Neither appgw_url nor apim_gateway_url found in terraform output" >&2
        return 1
    fi
    export APIM_GATEWAY_URL

    # Prefer App GW URL for API calls (routes through WAF + custom domain)
    if [[ -n "${APPGW_URL}" ]]; then
        APIM_GATEWAY_URL="${APPGW_URL}"
        export APIM_GATEWAY_URL
    fi
    
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
    echo "  API Base URL: ${APIM_GATEWAY_URL}" >&2
    echo "  App GW URL: ${APPGW_URL:-not set}" >&2
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
# Prefer App GW custom domain (end-to-end through WAF) over direct APIM
: "${APIM_GATEWAY_URL:=https://test.aihub.gov.bc.ca}"
export APIM_GATEWAY_URL

# App Gateway hostname (for Operation-Location header validation)
# This is the external-facing hostname that clients use
: "${APPGW_HOSTNAME:=test.aihub.gov.bc.ca}"
export APPGW_HOSTNAME

# API versions
export OPENAI_API_VERSION="2024-10-21"
export DOCINT_API_VERSION="2024-11-30"

# Tenants
export TENANTS=("wlrs-water-form-assistant" "sdpr-invoice-automation")

# Models available (default fallback)
export DEFAULT_MODEL="gpt-4.1-mini"

# =============================================================================
# Dynamic Model Loading from tenant.tfvars
# =============================================================================
# Loads model deployment names from the tenant configuration files
# This ensures tests stay in sync with actual deployments

# Function to extract model names from a tenant.tfvars file
# Usage: get_tenant_models <tenant>
# Returns: space-separated list of model deployment names
get_tenant_models() {
    local tenant="${1}"
    local tfvars_file="${SCRIPT_DIR}/../../infra-ai-hub/params/test/tenants/${tenant}/tenant.tfvars"
    
    if [[ ! -f "${tfvars_file}" ]]; then
        echo "Warning: tenant.tfvars not found for ${tenant}, using DEFAULT_MODEL" >&2
        echo "${DEFAULT_MODEL}"
        return 0
    fi
    
    # Extract model names from model_deployments array in tfvars
    # Pattern: name = "model-name"
    local models
    models=$(grep -oP '^\s*name\s*=\s*"\K[^"]+' "${tfvars_file}" 2>/dev/null | tr '\n' ' ')
    
    if [[ -z "${models}" ]]; then
        echo "Warning: No models found in ${tfvars_file}, using DEFAULT_MODEL" >&2
        echo "${DEFAULT_MODEL}"
        return 0
    fi
    
    echo "${models}"
}

# Function to get chat completion models only (exclude embeddings and codex)
# Usage: get_tenant_chat_models <tenant>
# Returns: space-separated list of chat model names (excludes embedding and codex models)
get_tenant_chat_models() {
    local tenant="${1}"
    local all_models
    all_models=$(get_tenant_models "${tenant}")
    
    # Filter out models that don't support chat completions:
    # - embedding models (they use embeddings API)
    # - codex models (they use completions API, not chat/completions)
    local chat_models=""
    for model in ${all_models}; do
        if [[ "${model}" != *"embedding"* ]] && [[ "${model}" != *"codex"* ]]; then
            chat_models="${chat_models} ${model}"
        fi
    done
    
    echo "${chat_models}" | xargs  # Trim whitespace
}

# Export functions for use in bats tests
export -f get_tenant_models get_tenant_chat_models
