#!/bin/bash
# Run all integration tests for AI Services Hub APIM
# Loads configuration from terraform outputs and executes bats tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../../infra-ai-hub"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored message
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Bats binary - check common locations
find_bats() {
    if command -v bats >/dev/null 2>&1; then
        echo "bats"
    elif [[ -x "$HOME/bats-core/bin/bats" ]]; then
        echo "$HOME/bats-core/bin/bats"
    else
        echo ""
    fi
}
BATS_BIN="$(find_bats)"

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    local missing=()
    
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    [[ -n "${BATS_BIN}" ]] || missing+=("bats")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        echo ""
        echo "Install missing tools:"
        echo "  - curl: Usually pre-installed on most systems"
        echo "  - jq: https://stedolan.github.io/jq/download/"
        echo "  - bats: git clone https://github.com/bats-core/bats-core.git ~/bats-core"
        exit 1
    fi
    
    log_success "All prerequisites met (bats: ${BATS_BIN})"
}

# Load configuration from environment variables or terraform
load_config() {
    log_info "Loading configuration..."
    
    # Check if config is already provided via environment
    if [[ -n "${APIM_GATEWAY_URL:-}" ]] && [[ -n "${WLRS_SUBSCRIPTION_KEY:-}" ]] && [[ -n "${SDPR_SUBSCRIPTION_KEY:-}" ]]; then
        log_success "Configuration loaded from environment variables"
        log_success "APIM Gateway URL: ${APIM_GATEWAY_URL}"
        log_success "WLRS subscription key loaded"
        log_success "SDPR subscription key loaded"
        return 0
    fi
    
    log_info "Attempting to load from terraform outputs..."
    
    # Check if terraform state exists
    if [[ ! -f "${INFRA_DIR}/.terraform/terraform.tfstate" ]] && [[ ! -f "${INFRA_DIR}/terraform.tfstate" ]]; then
        log_warn "Terraform state not found. Checking for remote state..."
    fi
    
    # Get terraform output
    local tf_output
    if ! tf_output=$(cd "${INFRA_DIR}" && terraform output -json 2>/dev/null); then
        log_error "Failed to get terraform output"
        echo "You can provide configuration via environment variables instead:"
        echo "  export APIM_GATEWAY_URL=https://your-apim.azure-api.net"
        echo "  export WLRS_SUBSCRIPTION_KEY=your-key"
        echo "  export SDPR_SUBSCRIPTION_KEY=your-key"
        exit 1
    fi
    
    # Extract values
    export APIM_GATEWAY_URL=$(echo "${tf_output}" | jq -r '.apim_gateway_url.value // empty')
    export APIM_NAME=$(echo "${tf_output}" | jq -r '.apim_name.value // empty')
    
    if [[ -z "${APIM_GATEWAY_URL}" ]]; then
        log_error "apim_gateway_url not found in terraform output"
        log_info "Available outputs:"
        echo "${tf_output}" | jq -r 'keys[]'
        exit 1
    fi
    
    log_success "APIM Gateway URL: ${APIM_GATEWAY_URL}"
    
    # Extract subscription keys (sensitive)
    local subscriptions
    subscriptions=$(echo "${tf_output}" | jq -r '.apim_tenant_subscriptions.value // empty')
    
    if [[ -n "${subscriptions}" ]]; then
        export WLRS_SUBSCRIPTION_KEY=$(echo "${subscriptions}" | jq -r '.["wlrs-water-form-assistant"].primary_key // empty')
        export SDPR_SUBSCRIPTION_KEY=$(echo "${subscriptions}" | jq -r '.["sdpr-invoice-automation"].primary_key // empty')
        
        if [[ -n "${WLRS_SUBSCRIPTION_KEY}" ]]; then
            log_success "WLRS subscription key loaded"
        else
            log_warn "WLRS subscription key not found"
        fi
        
        if [[ -n "${SDPR_SUBSCRIPTION_KEY}" ]]; then
            log_success "SDPR subscription key loaded"
        else
            log_warn "SDPR subscription key not found"
        fi
    else
        log_warn "Subscription keys not found in terraform output"
        log_info "Tests requiring subscription keys will be skipped"
    fi
}

# Test connectivity
test_connectivity() {
    log_info "Testing connectivity to APIM gateway..."
    
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 10 \
        "${APIM_GATEWAY_URL}" 2>/dev/null || echo "000")
    
    if [[ "${status}" == "000" ]]; then
        log_error "Cannot connect to APIM gateway"
        exit 1
    fi
    
    log_success "APIM gateway is reachable (HTTP ${status})"
}

# Run tests
run_tests() {
    local test_files=("$@")
    
    if [[ ${#test_files[@]} -eq 0 ]]; then
        # Run all test files
        test_files=("${SCRIPT_DIR}"/*.bats)
    fi
    
    log_info "Running tests..."
    echo ""
    
    local failed=0
    for test_file in "${test_files[@]}"; do
        if [[ -f "${test_file}" ]]; then
            local filename=$(basename "${test_file}")
            echo "=========================================="
            echo "Running: ${filename}"
            echo "=========================================="
            
            if "${BATS_BIN}" --tap "${test_file}"; then
                log_success "${filename} passed"
            else
                log_error "${filename} failed"
                ((failed++))
            fi
            echo ""
        fi
    done
    
    return ${failed}
}

# Main
main() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║       AI Services Hub APIM Integration Tests                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_prerequisites
    load_config
    test_connectivity
    
    echo ""
    echo "Starting test execution..."
    echo ""
    
    # Parse arguments
    local test_files=()
    local verbose=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)
                verbose=true
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [options] [test-file.bats ...]"
                echo ""
                echo "Options:"
                echo "  -v, --verbose    Show detailed test output"
                echo "  -h, --help       Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                          # Run all tests"
                echo "  $0 chat-completions.bats    # Run specific test file"
                echo "  $0 -v pii-redaction.bats    # Run with verbose output"
                exit 0
                ;;
            *)
                test_files+=("$1")
                shift
                ;;
        esac
    done
    
    if run_tests "${test_files[@]}"; then
        echo ""
        log_success "All tests passed!"
        exit 0
    else
        echo ""
        log_error "Some tests failed"
        exit 1
    fi
}

main "$@"
