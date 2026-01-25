#!/bin/bash
# =============================================================================
# Terraform Deployment Script - Run from initial-setup/infra/ or repo root
# =============================================================================
# Reusable script for Terraform operations (init, plan, apply, destroy, etc.)
#
# Usage (from repo root):
#   ./initial-setup/infra/deploy-terraform.sh <command> [options]
#
# Usage (from initial-setup/infra folder):
#   ./deploy-terraform.sh <command> [options]
#
# Commands:
#   init      - Initialize Terraform
#   plan      - Create execution plan
#   apply     - Apply changes (with auto-approve in CI mode)
#   destroy   - Destroy infrastructure (with auto-approve in CI mode)
#   validate  - Validate configuration
#   fmt       - Format Terraform files
#   output    - Show outputs
#   refresh   - Refresh state
#
# Options:
#   -target=<resource>  - Target specific resource
#   -var-file=<file>    - Use specific var file
#   --auto-approve      - Skip confirmation (default in CI mode)
#
# Environment Variables:
#   CI=true                    - Enable CI mode (auto-approve, no interactive prompts)
#   TF_VAR_subscription_id     - Azure Subscription ID
#   TF_VAR_tenant_id           - Azure Tenant ID
#   TF_VAR_client_id           - Azure Client ID (for OIDC)
#   ARM_USE_OIDC=true          - Use OIDC authentication
#
# Examples:
#   ./initial-setup/infra/deploy-terraform.sh init
#   ./initial-setup/infra/deploy-terraform.sh plan
#   ./initial-setup/infra/deploy-terraform.sh apply
#   ./initial-setup/infra/deploy-terraform.sh apply -target=module.jumpbox
#   export CI=true && ./initial-setup/infra/deploy-terraform.sh apply
#   ./initial-setup/infra/deploy-terraform.sh destroy
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Script is now inside infra/, so INFRA_DIR is the same as SCRIPT_DIR
INFRA_DIR="${SCRIPT_DIR}"
TFVARS_FILE="${INFRA_DIR}/terraform.tfvars"

# Backend configuration (must be set via environment variables)
BACKEND_RESOURCE_GROUP="${BACKEND_RESOURCE_GROUP:-}"
BACKEND_STORAGE_ACCOUNT="${BACKEND_STORAGE_ACCOUNT:-}"
BACKEND_CONTAINER_NAME="${BACKEND_CONTAINER_NAME:-tfstate}"
BACKEND_STATE_KEY="${BACKEND_STATE_KEY:-ai-hub-deploy-utils/tools/terraform.tfstate}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables tracking configuration source
USE_TFVARS=false
TFVARS_ARGS=()

# =============================================================================
# Logging Functions
# =============================================================================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# Helper Functions
# =============================================================================
usage() {
    cat << EOF
Usage: $0 <command> [options]

Commands:
    init        Initialize Terraform (download providers, configure backend)
    plan        Create execution plan
    apply       Apply changes
    destroy     Destroy infrastructure
    validate    Validate configuration
    fmt         Format Terraform files
    output      Show Terraform outputs
    refresh     Refresh state
    state       Run state commands (e.g., state list, state show)

Options:
    -target=<resource>    Target specific resource
    -var-file=<file>      Use specific var file
    --auto-approve        Skip confirmation prompts

Environment:
    CI=true               Enable CI mode (auto-approve, less verbose)
    
Examples:
    $0 init
    $0 plan
    $0 apply
    $0 apply -target=module.jumpbox
    $0 destroy -target=module.bastion
    CI=true $0 apply

EOF
    exit 1
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Terraform
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed!"
        log_error "Install from: https://developer.hashicorp.com/terraform/downloads"
        exit 1
    fi
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed!"
        log_error "Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_warning "Not logged into Azure CLI"
        if [[ "${CI:-false}" == "true" ]]; then
            log_info "CI mode detected - assuming OIDC/service principal authentication"
        else
            log_info "Please login to Azure..."
            az login
        fi
    fi
    
    log_success "Prerequisites check passed"
}

setup_azure_auth() {
    log_info "Setting up Azure authentication..."
    
    # Get subscription from tfvars or environment
    if [[ -n "${TF_VAR_subscription_id:-}" ]]; then
        SUBSCRIPTION_ID="${TF_VAR_subscription_id}"
    elif [[ -f "$TFVARS_FILE" ]]; then
        SUBSCRIPTION_ID=$(grep -E "^subscription_id\s*=" "$TFVARS_FILE" | sed 's/.*=\s*"\(.*\)".*/\1/' | tr -d ' ')
    fi
    
    if [[ -n "${SUBSCRIPTION_ID:-}" ]]; then
        log_info "Setting Azure subscription: ${SUBSCRIPTION_ID}"
        az account set --subscription "$SUBSCRIPTION_ID"
    fi
    
    # Display current context
    local current_sub=$(az account show --query "name" --output tsv 2>/dev/null || echo "Unknown")
    local current_user=$(az account show --query "user.name" --output tsv 2>/dev/null || echo "Unknown")
    log_info "Azure account: $current_user"
    log_info "Subscription: $current_sub"
    
    # Set ARM environment variables for Terraform
    export ARM_SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
    export ARM_TENANT_ID="${TF_VAR_tenant_id:-$(az account show --query tenantId -o tsv)}"
    
    # Check for OIDC vs CLI auth
    if [[ "${ARM_USE_OIDC:-false}" == "true" ]] || [[ "${TF_VAR_use_oidc:-false}" == "true" ]]; then
        log_info "Using OIDC authentication"
        export ARM_USE_OIDC=true
        export ARM_CLIENT_ID="${TF_VAR_client_id:-$ARM_CLIENT_ID}"
    else
        log_info "Using Azure CLI authentication"
        export ARM_USE_CLI=true
    fi
    
    log_success "Azure authentication configured"
}

# Check if tfvars file exists, otherwise validate required environment variables
setup_variables_source() {
    log_info "Checking variables configuration..."
    
    if [[ -f "$TFVARS_FILE" ]]; then
        USE_TFVARS=true
        TFVARS_ARGS=("-var-file=$TFVARS_FILE")
        log_success "Using terraform.tfvars file"
    else
        log_info "terraform.tfvars not found, validating environment variables..."
        
        # Required variables for all deployments
        local required_vars=(
            "TF_VAR_app_name"
            "TF_VAR_subscription_id"
            "TF_VAR_tenant_id"
            "TF_VAR_location"
            "TF_VAR_resource_group_name"
            "TF_VAR_vnet_name"
            "TF_VAR_vnet_resource_group_name"
            "TF_VAR_vnet_address_space"
        )
        
        local missing_vars=()
        for var in "${required_vars[@]}"; do
            if [[ -z "${!var:-}" ]]; then
                missing_vars+=("$var")
            fi
        done
        
        if [[ ${#missing_vars[@]} -gt 0 ]]; then
            log_error "Missing required environment variables:"
            for var in "${missing_vars[@]}"; do
                log_error "  - $var"
            done
            exit 1
        fi
        
        log_success "All required environment variables are set"
    fi
}

# =============================================================================
# Terraform Commands
# =============================================================================
tf_init() {
    log_info "Initializing Terraform..."
    log_info "Backend: ${BACKEND_STORAGE_ACCOUNT}/${BACKEND_CONTAINER_NAME}/${BACKEND_STATE_KEY}"
    cd "$INFRA_DIR"

    local init_args=()
    # In CI we never want interactive prompts
    if [[ "${CI:-false}" == "true" ]]; then
        init_args+=("-input=false")
    fi

    terraform init -upgrade "${init_args[@]}" \
        -backend-config="resource_group_name=${BACKEND_RESOURCE_GROUP}" \
        -backend-config="storage_account_name=${BACKEND_STORAGE_ACCOUNT}" \
        -backend-config="container_name=${BACKEND_CONTAINER_NAME}" \
        -backend-config="key=${BACKEND_STATE_KEY}" \
        -backend-config="use_oidc=${ARM_USE_OIDC:-false}" \
        "$@"
    
    log_success "Terraform initialized"
}

# Check if Terraform is initialized, if not run init
ensure_initialized() {
    cd "$INFRA_DIR"
    
    # Check if .terraform directory exists and lock file is valid
    if [[ ! -d ".terraform" ]] || [[ ! -f ".terraform.lock.hcl" ]]; then
        log_warning "Terraform not initialized. Running init..."
        tf_init
        return
    fi

    # Modules are installed under .terraform/modules; config changes can add new modules
    if [[ ! -d ".terraform/modules" ]] || [[ -z "$(ls -A .terraform/modules 2>/dev/null)" ]]; then
        log_warning "Terraform modules not installed. Running init..."
        tf_init
        return
    fi
    
    # Check if providers are properly installed by verifying lock file has content
    if ! grep -q "provider" ".terraform.lock.hcl" 2>/dev/null; then
        log_warning "Lock file incomplete. Re-initializing..."
        tf_init
    fi
}

tf_validate() {
    log_info "Validating Terraform configuration..."
    cd "$INFRA_DIR"
    
    terraform validate
    
    log_success "Configuration is valid"
}

tf_fmt() {
    log_info "Formatting Terraform files..."
    cd "$INFRA_DIR"
    
    terraform fmt -recursive
    
    log_success "Formatting complete"
}

tf_plan() {
    log_info "Creating Terraform plan..."
    ensure_initialized
    cd "$INFRA_DIR"
    
    local plan_args=("${TFVARS_ARGS[@]}")
    
    # Add any additional arguments passed
    plan_args+=("$@")
    
    terraform plan "${plan_args[@]}"
    
    log_success "Plan created"
}
extract_import_target_from_tf_output() {
    # Wrapper around the external script for extracting import targets.
    # See scripts/extract-import-target.sh for implementation and
    # scripts/extract-import-target.test.sh for test cases.
    local tf_output_file="$1"
    local script_path="${INFRA_DIR}/scripts/extract-import-target.sh"

    if [[ -x "$script_path" ]]; then
        "$script_path" "$tf_output_file"
    else
        # Fallback: source the script and call the function directly
        # shellcheck source=scripts/extract-import-target.sh
        source "$script_path"
        extract_import_target "$tf_output_file"
    fi
}
tf_import_existing_resource_if_needed() {
    # If the last Terraform command failed due to an "already exists" error,
    # automatically import the resource into state.
    # Returns:
    #   0 if an import was performed
    #   1 if no importable error was found
    #   2 if an importable error was found but import failed
    local tf_output_file="$1"

    local import_line
    if ! import_line="$(extract_import_target_from_tf_output "$tf_output_file")"; then
        return 1
    fi

    local import_addr
    local import_id
    import_addr="${import_line%%$'\t'*}"
    import_id="${import_line#*$'\t'}"

    if [[ -z "$import_addr" || -z "$import_id" || "$import_addr" == "$import_id" ]]; then
        return 1
    fi

    log_warning "Detected existing Azure resource; importing into Terraform state"
    log_info "Import address: $import_addr"
    log_info "Import ID: $import_id"

    # Import requires the same variables context as apply/plan.
    if terraform import "${TFVARS_ARGS[@]}" "$import_addr" "$import_id"; then
        log_success "Import succeeded: $import_addr"
        return 0
    fi

    log_error "Import failed for: $import_addr"
    return 2
}
tf_apply() {
    log_info "Applying Terraform changes..."
    # Apply should always ensure init has run because modules/providers may change.
    # In CI we run init every time (idempotent) to avoid "Module not installed" errors.
    if [[ "${CI:-false}" == "true" ]]; then
        tf_init
    else
        ensure_initialized
    fi
    cd "$INFRA_DIR"
    
    local apply_args=("${TFVARS_ARGS[@]}")
    
    # Auto-approve in CI mode
    if [[ "${CI:-false}" == "true" ]]; then
        apply_args+=("-auto-approve")
    fi
    
    # Add any additional arguments passed
    apply_args+=("$@")
    
    local max_retries=3
    local attempt=1

    while true; do
        local tf_output_file
        tf_output_file="$(mktemp -t terraform-apply.XXXXXX.log)"

        log_info "Running terraform apply (attempt ${attempt}/${max_retries})"

        set +e
        terraform apply "${apply_args[@]}" 2>&1 | tee "$tf_output_file"
        local tf_exit=${PIPESTATUS[0]}
        set -e

        if [[ $tf_exit -eq 0 ]]; then
            rm -f "$tf_output_file"
            break
        fi

        # Try to auto-import existing resources, then retry.
        if tf_import_existing_resource_if_needed "$tf_output_file"; then
            rm -f "$tf_output_file"
            attempt=$((attempt + 1))
            if [[ $attempt -gt $max_retries ]]; then
                log_error "Exceeded maximum retries (${max_retries}) for auto-import/retry"
                exit $tf_exit
            fi
            continue
        fi

        rm -f "$tf_output_file"
        log_error "Terraform apply failed (non-importable error)."
        exit $tf_exit
    done
    
    log_success "Apply complete"
    
    # Automatically show outputs after successful apply
    log_info ""
    log_info "=== Deployment Outputs ==="
    tf_output
}

tf_destroy() {
    log_info "Destroying Terraform resources..."
    ensure_initialized
    cd "$INFRA_DIR"
    
    local destroy_args=("${TFVARS_ARGS[@]}")
    
    # Auto-approve in CI mode
    if [[ "${CI:-false}" == "true" ]]; then
        destroy_args+=("-auto-approve")
    fi
    
    # Add any additional arguments passed
    destroy_args+=("$@")
    
    if [[ "${CI:-false}" != "true" ]]; then
        log_warning "This will DESTROY infrastructure!"
        read -p "Are you sure? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Destroy cancelled"
            exit 0
        fi
    fi
    
    terraform destroy "${destroy_args[@]}"
    
    log_success "Destroy complete"
}

tf_output() {
    log_info "Showing Terraform outputs..."
    cd "$INFRA_DIR"
    
    terraform output "$@"
}

tf_refresh() {
    log_info "Refreshing Terraform state..."
    cd "$INFRA_DIR"
    
    terraform refresh "${TFVARS_ARGS[@]}" "$@"
    
    log_success "State refreshed"
}

tf_state() {
    cd "$INFRA_DIR"
    terraform state "$@"
}

# =============================================================================
# Main
# =============================================================================
main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi
    
    local command="$1"
    shift
    
    # Show CI mode status
    if [[ "${CI:-false}" == "true" ]]; then
        log_info "Running in CI mode (auto-approve enabled)"
    fi
    
    # Run prerequisites and auth setup for most commands
    case "$command" in
        fmt|validate)
            # These don't need Azure auth
            ;;
        *)
            check_prerequisites
            setup_azure_auth
            setup_variables_source  # Check for tfvars or environment variables
            ;;
    esac
    
    # Execute command
    case "$command" in
        init)
            tf_init "$@"
            ;;
        plan)
            tf_plan "$@"
            ;;
        apply)
            tf_apply "$@"
            ;;
        destroy)
            tf_destroy "$@"
            ;;
        validate)
            tf_validate "$@"
            ;;
        fmt)
            tf_fmt "$@"
            ;;
        output)
            tf_output "$@"
            ;;
        refresh)
            tf_refresh "$@"
            ;;
        state)
            tf_state "$@"
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            ;;
    esac
}

main "$@"
