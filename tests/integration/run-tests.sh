#!/bin/bash
# Run all integration tests for AI Services Hub APIM
# Loads configuration from terraform outputs and executes bats tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../../infra-ai-hub"

# Test environment (dev/test/prod)
: "${TEST_ENV:=test}"
export TEST_ENV

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Print colored message with timestamp
_ts() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }
log_info() { echo -e "${GRAY}$(_ts)${NC} ${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GRAY}$(_ts)${NC} ${GREEN}[SUCCESS]${NC} $*"; }
log_warn() { echo -e "${GRAY}$(_ts)${NC} ${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${GRAY}$(_ts)${NC} ${RED}[ERROR]${NC} $*"; }

# Tests excluded from this run (populated via --exclude flag)
EXCLUDED_TESTS=()

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
    log_info "Test environment: ${TEST_ENV}"
    
    # Check if config is already provided via environment
    if [[ -n "${APIM_GATEWAY_URL:-}" ]] && ( [[ -n "${WLRS_SUBSCRIPTION_KEY:-}" ]] || [[ -n "${SDPR_SUBSCRIPTION_KEY:-}" ]] ); then
        log_success "Configuration loaded from environment variables"
        log_success "APIM Gateway URL: ${APIM_GATEWAY_URL}"
        log_success "WLRS subscription key loaded"
        [[ -n "${SDPR_SUBSCRIPTION_KEY:-}" ]] && log_success "SDPR subscription key loaded"
        [[ -n "${APIM_KEYS_TENANT_1:-}" ]] && log_success "APIM Keys Tenant-1: ${APIM_KEYS_TENANT_1}"
        [[ -n "${APIM_KEYS_TENANT_2:-}" ]] && log_success "APIM Keys Tenant-2: ${APIM_KEYS_TENANT_2}"
        return 0
    fi
    
    log_info "Attempting to load from terraform outputs..."
    
    # Check if terraform state exists
    if [[ ! -f "${INFRA_DIR}/.terraform/terraform.tfstate" ]] && [[ ! -f "${INFRA_DIR}/terraform.tfstate" ]]; then
        log_warn "Terraform state not found. Checking for remote state..."
    fi
    
    # Get stack-aggregated output
    local tf_output_raw
    local _err_log
    _err_log="$(mktemp)"
    if ! tf_output_raw=$(cd "${INFRA_DIR}" && ./scripts/deploy-terraform.sh output "${TEST_ENV}" 2>"${_err_log}"); then
        log_error "Failed to get stack output"
        # deploy-terraform.sh logs errors to stdout (captured in tf_output_raw);
        # show the captured stdout so CI logs reveal the root cause.
        if [[ -n "${tf_output_raw:-}" ]]; then
            log_error "--- deploy-terraform.sh stdout ---"
            echo "${tf_output_raw}" >&2
            log_error "--- end stdout ---"
        fi
        if [[ -s "${_err_log}" ]]; then
            log_error "--- deploy-terraform.sh stderr ---"
            cat "${_err_log}" >&2
            log_error "--- end stderr ---"
        fi
        rm -f "${_err_log}"
        echo "You can provide configuration via environment variables instead:"
        echo "  export APIM_GATEWAY_URL=https://your-apim.azure-api.net"
        echo "  export WLRS_SUBSCRIPTION_KEY=your-key"
        echo "  export SDPR_SUBSCRIPTION_KEY=your-key"
        exit 1
    fi
    rm -f "${_err_log}"

    local tf_output
    tf_output=$(echo "${tf_output_raw}" | sed -n '/^{/,$p')
    if [[ -z "${tf_output}" ]]; then
        log_error "Failed to parse JSON output from stack output"
        exit 1
    fi
    
    # Extract values
    # Prefer App GW URL (custom domain, end-to-end through WAF)
    local appgw_url
    appgw_url=$(echo "${tf_output}" | jq -r '.appgw_url.value // empty')
    export APIM_GATEWAY_URL=$(echo "${tf_output}" | jq -r '.apim_gateway_url.value // empty')
    export APIM_NAME=$(echo "${tf_output}" | jq -r '.apim_name.value // empty')
    export HUB_KEYVAULT_NAME=$(echo "${tf_output}" | jq -r '.apim_key_rotation_summary.value.hub_keyvault_name // empty')
    
    if [[ -n "${appgw_url}" ]]; then
        export APIM_GATEWAY_URL="${appgw_url}"
        export APPGW_URL="${appgw_url}"
        export APPGW_DEPLOYED="true"
        log_success "Using App GW URL: ${appgw_url}"
    elif [[ -n "${APIM_GATEWAY_URL}" ]]; then
        export APPGW_DEPLOYED="false"
        log_warn "App GW URL not available, using direct APIM: ${APIM_GATEWAY_URL}"
    else
        log_error "Neither appgw_url nor apim_gateway_url found in terraform output"
        log_info "Available outputs:"
        echo "${tf_output}" | jq -r 'keys[]'
        exit 1
    fi

    # Hub Key Vault is only set when key rotation is globally enabled
    local key_rotation_enabled
    key_rotation_enabled=$(echo "${tf_output}" | jq -r '.apim_key_rotation_summary.value.globally_enabled // false')
    if [[ "${key_rotation_enabled}" == "true" ]]; then
        if [[ -n "${HUB_KEYVAULT_NAME}" ]]; then
            log_success "Hub Key Vault name loaded: ${HUB_KEYVAULT_NAME}"
        else
            log_warn "Key rotation enabled but Hub Key Vault name not found in terraform output"
        fi
    else
        log_info "Key rotation disabled — Hub Key Vault not required"
    fi
    
    # Extract subscription keys (sensitive)
    local subscriptions
    subscriptions=$(echo "${tf_output}" | jq -r '.apim_tenant_subscriptions.value // empty')
    
    if [[ -n "${subscriptions}" ]]; then
        export WLRS_SUBSCRIPTION_KEY=$(echo "${subscriptions}" | jq -r '.["wlrs-water-form-assistant"].primary_key // empty')
        export SDPR_SUBSCRIPTION_KEY=$(echo "${subscriptions}" | jq -r '.["sdpr-invoice-automation"].primary_key // empty')
        export NRDAP_SUBSCRIPTION_KEY=$(echo "${subscriptions}" | jq -r '.["nr-dap-fish-wildlife"].primary_key // empty')

        export APIM_KEYS_TENANT_1="${APIM_KEYS_TENANT_1:-wlrs-water-form-assistant}"
        export APIM_KEYS_TENANT_2="${APIM_KEYS_TENANT_2:-sdpr-invoice-automation}"
        
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

        if [[ -n "${NRDAP_SUBSCRIPTION_KEY}" ]]; then
            log_success "NR-DAP subscription key loaded"
        else
            log_warn "NR-DAP subscription key not found"
        fi

        log_success "APIM Keys Tenant-1: ${APIM_KEYS_TENANT_1}"
        log_success "APIM Keys Tenant-2: ${APIM_KEYS_TENANT_2}"
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

    # Filter out excluded test files
    if [[ ${#EXCLUDED_TESTS[@]} -gt 0 ]]; then
        local filtered=()
        for test_file in "${test_files[@]}"; do
            local filename
            filename=$(basename "${test_file}")
            local exclude=false
            for excl in "${EXCLUDED_TESTS[@]}"; do
                if [[ "${filename}" == "${excl}" ]]; then
                    exclude=true
                    break
                fi
            done
            [[ "${exclude}" == "false" ]] && filtered+=("${test_file}")
        done
        log_info "Excluding tests: ${EXCLUDED_TESTS[*]}"
        test_files=("${filtered[@]}")
    fi
    
    log_info "Running tests..."
    echo ""
    
    # Guard: fail if no test files were found
    local has_tests=false
    for test_file in "${test_files[@]}"; do
        [[ -f "${test_file}" ]] && has_tests=true && break
    done
    if [[ "$has_tests" == "false" ]]; then
        log_error "No test files found to run"
        return 1
    fi

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
    local start_time=$SECONDS
    echo ""
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║       AI Services Hub APIM Integration Tests                ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo ""
    log_info "Test run started at $(_ts)"
    
    # Parse arguments
    local test_files=()
    local verbose=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -e|--env)
                TEST_ENV="$2"
                export TEST_ENV
                shift 2
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -x|--exclude)
                IFS=',' read -ra EXCLUDED_TESTS <<< "$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [options] [environment] [test-file.bats ...]"
                echo ""
                echo "Options:"
                echo "  -e, --env        Environment to test (dev|test|prod). Default: TEST_ENV or test"
                echo "  -v, --verbose    Show detailed test output"
                echo "  -x, --exclude    Comma-separated list of test filenames to skip"
                echo "  -h, --help       Show this help message"
                echo ""
                echo "The first bare argument matching dev|test|prod is treated as the environment."
                echo ""
                echo "Examples:"
                echo "  $0 test                                           # Run all tests against test env"
                echo "  $0                                                # Run all tests (default: test)"
                echo "  $0 chat-completions.bats                          # Run specific test file"
                echo "  $0 -v pii-redaction.bats                          # Run with verbose output"
                echo "  $0 --exclude apim-key-rotation.bats               # Skip KV-dependent tests"
                echo "  $0 --exclude apim-key-rotation.bats,app-gateway.bats  # Skip multiple"
                exit 0
                ;;
            *)
                # First bare arg that looks like an environment name → treat as env
                if [[ -z "${env_set:-}" && "$1" =~ ^(dev|test|prod)$ ]]; then
                    TEST_ENV="$1"
                    export TEST_ENV
                    env_set=true
                else
                    test_files+=("$1")
                fi
                shift
                ;;
        esac
    done

    check_prerequisites
    load_config
    test_connectivity

    echo ""
    echo "Starting test execution..."
    echo ""
    
    if run_tests "${test_files[@]}"; then
        echo ""
        local elapsed=$(( SECONDS - start_time ))
        local mins=$(( elapsed / 60 ))
        local secs=$(( elapsed % 60 ))
        log_success "All tests passed! — total time: ${mins}m ${secs}s"
        exit 0
    else
        echo ""
        local elapsed=$(( SECONDS - start_time ))
        local mins=$(( elapsed / 60 ))
        local secs=$(( elapsed % 60 ))
        log_error "Some tests failed — total time: ${mins}m ${secs}s"
        exit 1
    fi
}

main "$@"
