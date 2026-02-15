#!/bin/bash
# =============================================================================
# Terraform Deployment Script for AI Foundry Hub
# =============================================================================
# Reusable script for Terraform operations (init, plan, apply, destroy, etc.)
#
# Usage:
#   ./scripts/deploy-terraform.sh <command> <environment> [options]
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
# Environments:
#   dev, test, prod
#
# Options:
#   -target=<resource>  - Target specific resource
#   --auto-approve      - Skip confirmation (default in CI mode)
#
# Environment Variables:
#   CI=true                    - Enable CI mode (auto-approve, no interactive prompts)
#   TF_VAR_subscription_id     - Azure Subscription ID
#   TF_VAR_tenant_id           - Azure Tenant ID
#   TF_VAR_client_id           - Azure Client ID (for OIDC)
#   ARM_USE_OIDC=true          - Use OIDC authentication
#
# Auto-Recovery Features:
#   - Deposed objects: Automatically removes deposed objects from state when
#     Terraform fails with 404 errors trying to delete already-deleted resources
#   - Existing resources: Automatically imports resources that exist in Azure
#     but not in Terraform state
#
# Examples:
#   ./scripts/deploy-terraform.sh plan dev
#   ./scripts/deploy-terraform.sh apply test
#   ./scripts/deploy-terraform.sh destroy prod -target=module.tenants
#   CI=true ./scripts/deploy-terraform.sh apply dev
# =============================================================================

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Valid environments
VALID_ENVIRONMENTS=("dev" "test" "prod")

# Backend configuration (can be overridden by environment variables)
BACKEND_RESOURCE_GROUP="${BACKEND_RESOURCE_GROUP:-}"
BACKEND_STORAGE_ACCOUNT="${BACKEND_STORAGE_ACCOUNT:-}"
BACKEND_CONTAINER_NAME="${BACKEND_CONTAINER_NAME:-tfstate}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Variables tracking configuration
ENVIRONMENT=""

# =============================================================================
# Logging Functions
# =============================================================================
_ts() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }

log_info() {
    echo -e "${GRAY}$(_ts)${NC} ${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GRAY}$(_ts)${NC} ${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${GRAY}$(_ts)${NC} ${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${GRAY}$(_ts)${NC} ${RED}[ERROR]${NC} $*"
}

# =============================================================================
# Helper Functions
# =============================================================================
usage() {
    cat << EOF
Usage: $0 <command> <environment> [options]

Commands:
    plan        Create execution plans for all stacks
    apply       Apply changes across all stacks (shared -> tenant -> foundry -> apim -> tenant-user-mgmt)
    destroy     Destroy infrastructure in reverse dependency order
    validate    Validate all stack roots
    fmt         Format Terraform files
    output      Show aggregated stack outputs as JSON

Environments:
    dev, test, prod

Options:
    -target=<resource>    Target specific resource
    --auto-approve        Skip confirmation prompts

Environment:
    CI=true               Enable CI mode (auto-approve, less verbose)
    
Examples:
    $0 plan dev
    $0 apply test
    $0 apply prod -target=module.ai_foundry_hub
    $0 destroy dev -target=module.tenants
    CI=true $0 apply dev

EOF
    exit 1
}

validate_environment() {
    local env="$1"
    for valid_env in "${VALID_ENVIRONMENTS[@]}"; do
        if [[ "$env" == "$valid_env" ]]; then
            return 0
        fi
    done
    log_error "Invalid environment: $env"
    log_error "Valid environments: ${VALID_ENVIRONMENTS[*]}"
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

# =============================================================================
# Graph API Permission Check
# =============================================================================
# Tenant user management requires Microsoft Graph User.Read.All permission.
# This function probes the Graph API to check if the current identity has it.
# Returns 0 if permission is available, 1 if not.
# =============================================================================
check_graph_permissions() {
    log_info "Checking Microsoft Graph API permissions..."

    # 1. Get a Graph token via the current Azure CLI identity
    local token
    token=$(az account get-access-token \
        --resource https://graph.microsoft.com \
        --query accessToken -o tsv 2>/dev/null) || {
        log_warning "Could not acquire Graph API token"
        return 1
    }

    if [[ -z "${token:-}" ]]; then
        log_warning "Graph API token is empty"
        return 1
    fi

    # 2. Probe with a minimal call — 200 means User.Read.All is granted
    local http_status
    http_status=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${token}" \
        "https://graph.microsoft.com/v1.0/users?\$top=1&\$select=id" 2>/dev/null) || {
        log_warning "Graph API probe failed (curl error)"
        return 1
    }

    if [[ "${http_status}" == "200" ]]; then
        log_success "Graph API User.Read.All permission confirmed"
        return 0
    else
        log_warning "Graph API returned HTTP ${http_status} — User.Read.All permission not available"
        return 1
    fi
}

setup_azure_auth() {
    log_info "Setting up Azure authentication..."
    
    # Get subscription from environment
    if [[ -n "${TF_VAR_subscription_id:-}" ]]; then
        SUBSCRIPTION_ID="${TF_VAR_subscription_id}"
        log_info "Setting Azure subscription: ${SUBSCRIPTION_ID}"
        az account set --subscription "$SUBSCRIPTION_ID"
    fi
    
    # Display current context
    local current_sub=$(az account show --query "name" --output tsv 2>/dev/null || echo "Unknown")
    local current_user=$(az account show --query "user.name" --output tsv 2>/dev/null || echo "Unknown")
    log_info "Azure account: $current_user"
    log_info "Subscription: $current_sub"
    
    # Set ARM environment variables for Terraform
    export ARM_SUBSCRIPTION_ID="${TF_VAR_subscription_id:-$(az account show --query id -o tsv)}"
    export ARM_TENANT_ID="${TF_VAR_tenant_id:-$(az account show --query tenantId -o tsv)}"
    
    # Check for OIDC vs CLI auth
    if [[ "${ARM_USE_OIDC:-false}" == "true" ]]; then
        log_info "Using OIDC authentication"
        export ARM_USE_OIDC=true
        export ARM_CLIENT_ID="${TF_VAR_client_id:-$ARM_CLIENT_ID}"
    else
        log_info "Using Azure CLI authentication"
        export ARM_USE_CLI=true
    fi
    
    log_success "Azure authentication configured"
}

setup_variables() {
    log_info "Setting up variable files for environment: $ENVIRONMENT"
    
    local shared_tfvars="${INFRA_DIR}/params/${ENVIRONMENT}/shared.tfvars"
    local tenants_dir="${INFRA_DIR}/params/${ENVIRONMENT}/tenants"
    local combined_tenants_file="${INFRA_DIR}/.tenants-${ENVIRONMENT}.auto.tfvars"
    
    # Check shared.tfvars exists
    if [[ ! -f "$shared_tfvars" ]]; then
        log_error "Shared config not found: $shared_tfvars"
        exit 1
    fi
    
    log_info "Using shared config: $shared_tfvars"
    
    # Merge individual tenant tfvars files into a combined tenants map
    if [[ -d "$tenants_dir" ]]; then
        # Collect tenant files into an array (handles spaces in paths)
        local -a tenant_files_arr=()
        local tenant_count=0
        
        while IFS= read -r -d '' file; do
            tenant_files_arr+=("$file")
            ((tenant_count++)) || true
        done < <(find "$tenants_dir" -name "tenant.tfvars" -type f -print0 2>/dev/null | sort -z)
        
        if [[ $tenant_count -gt 0 ]]; then
            log_info "Merging $tenant_count tenant configuration(s)..."
            
            # Start the combined tenants map
            {
                echo "# Auto-generated - DO NOT EDIT"
                echo "# Combined tenant configurations from params/${ENVIRONMENT}/tenants/*/"
                echo "# Generated at: $(date -Iseconds 2>/dev/null || date)"
                echo ""
                echo "tenants = {"
            } > "$combined_tenants_file"
            
            # Process each tenant file
            for tenant_file in "${tenant_files_arr[@]}"; do
                local tenant_name
                tenant_name=$(basename "$(dirname "$tenant_file")")
                log_info "  - $tenant_name"
                
                # Add tenant to combined file
                {
                    echo ""
                    echo "  # From: tenants/${tenant_name}/tenant.tfvars"
                    # Extract just the block content (without "tenant = ") and add key prefix on same line
                    local block_content
                    block_content=$(awk '/^tenant[[:space:]]*=[[:space:]]*\{/,/^\}$/' "$tenant_file" | \
                        sed 's/^tenant[[:space:]]*=[[:space:]]*//')
                    echo "  \"${tenant_name}\" = ${block_content}"
                } >> "$combined_tenants_file"
            done
            
            # Close the tenants map
            echo "}" >> "$combined_tenants_file"
            
            log_info "Generated combined tenants file: $combined_tenants_file"
        else
            log_warning "No tenant configurations found in: $tenants_dir"
            # Create empty tenants map
            echo "tenants = {}" > "$combined_tenants_file"
        fi
    else
        log_warning "Tenants directory not found: $tenants_dir"
        # Create empty tenants map
        echo "tenants = {}" > "$combined_tenants_file"
    fi
    
    log_success "Variable files configured"
}

# =============================================================================
# Terraform Commands
# =============================================================================
tf_fmt() {
    log_info "Formatting Terraform files..."
    cd "$INFRA_DIR"
    
    terraform fmt -recursive
    
    log_success "Formatting complete"
}

# =============================================================================
# Scaled Stack Operations
# All apply/plan/destroy/validate operations delegate to deploy-scaled.sh
# which manages isolated stack roots (shared, tenant, foundry, apim, tenant-user-mgmt).
# =============================================================================

tf_destroy() {
    log_info "Destroying infrastructure in reverse dependency order..."

    if [[ "${CI:-false}" != "true" ]]; then
        log_warning "This will DESTROY infrastructure using isolated stack states!"
        read -p "Are you sure? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Destroy cancelled"
            exit 0
        fi
    fi

    SCALED_CALLER="deploy-terraform" bash "${SCRIPT_DIR}/deploy-scaled.sh" "destroy" "$ENVIRONMENT" "$@"
}

stack_state_key() {
    local stack="$1"
    case "$stack" in
        shared) echo "ai-services-hub/${ENVIRONMENT}/shared.tfstate" ;;
        tenant) echo "" ;;
        foundry) echo "ai-services-hub/${ENVIRONMENT}/foundry.tfstate" ;;
        apim) echo "ai-services-hub/${ENVIRONMENT}/apim.tfstate" ;;
        tenant-user-mgmt) echo "ai-services-hub/${ENVIRONMENT}/tenant-user-management.tfstate" ;;
        *) echo "" ;;
    esac
}

tf_stack_output_json() {
    local stack="$1"
    local dir="${INFRA_DIR}/stacks/${stack}"
    local key
    key="$(stack_state_key "$stack")"

    (
        cd "$dir"
        terraform init -input=false -reconfigure \
            -backend-config="resource_group_name=${BACKEND_RESOURCE_GROUP}" \
            -backend-config="storage_account_name=${BACKEND_STORAGE_ACCOUNT}" \
            -backend-config="container_name=${BACKEND_CONTAINER_NAME}" \
            -backend-config="key=${key}" \
            -backend-config="subscription_id=${ARM_SUBSCRIPTION_ID:-}" \
            -backend-config="tenant_id=${ARM_TENANT_ID:-}" \
            -backend-config="client_id=${TF_VAR_client_id:-}" \
            -backend-config="use_oidc=${ARM_USE_OIDC:-false}" >/dev/null

        terraform output -json 2>/dev/null || echo '{}'
    )
}

tf_output() {
    local apim_outputs
    local shared_outputs
    apim_outputs="$(tf_stack_output_json apim)"
    shared_outputs="$(tf_stack_output_json shared)"

    jq -n \
        --argjson shared "$shared_outputs" \
        --argjson apim "$apim_outputs" \
        '{
            appgw_url: { value: ($shared.appgw_url.value // null) },
            resource_group_name: { value: ($shared.resource_group_name.value // null) },
            apim_gateway_url: { value: ($apim.apim_gateway_url.value // null) },
            apim_name: { value: ($apim.apim_name.value // null) },
            apim_key_rotation_summary: { value: ($apim.apim_key_rotation_summary.value // {}) },
            apim_tenant_subscriptions: {
                sensitive: true,
                value: ($apim.apim_tenant_subscriptions.value // {})
            }
        }'
}

# =============================================================================
# Main
# =============================================================================
main() {
    local start_time=$SECONDS

    if [[ $# -lt 1 ]]; then
        usage
    fi
    
    local command="$1"
    shift
    
    # Commands that don't need environment
    case "$command" in
        fmt)
            cd "$INFRA_DIR"
            case "$command" in
                fmt) tf_fmt "$@" ;;
            esac
            exit 0
            ;;
    esac
    
    # All other commands need environment
    if [[ $# -lt 1 ]]; then
        log_error "Environment required for command: $command"
        usage
    fi
    
    ENVIRONMENT="$1"
    shift
    validate_environment "$ENVIRONMENT"
    
    # Use vnet resource group as backend resource group if not set
    BACKEND_RESOURCE_GROUP="${BACKEND_RESOURCE_GROUP:-${TF_VAR_vnet_resource_group_name:-}}"

    # Log workflow start for infrastructure operations (not quick lookups like output)
    if [[ "$command" != "output" ]]; then
        log_info "Workflow started at $(_ts)"
    fi
    
    # Show mode status
    if [[ "${CI:-false}" == "true" ]]; then
        log_info "Running in CI mode (auto-approve enabled)"
    fi
    log_info "Environment: $ENVIRONMENT"
    
    # Run prerequisites and auth setup
    check_prerequisites
    setup_azure_auth
    setup_variables
    
    # Execute command
    case "$command" in
        plan)
            SCALED_CALLER="deploy-terraform" bash "${SCRIPT_DIR}/deploy-scaled.sh" "plan" "$ENVIRONMENT" "$@"
            ;;
        apply)
            SCALED_CALLER="deploy-terraform" bash "${SCRIPT_DIR}/deploy-scaled.sh" "apply" "$ENVIRONMENT" "$@"
            ;;
        destroy)
            tf_destroy "$@"
            ;;
        validate)
            SCALED_CALLER="deploy-terraform" bash "${SCRIPT_DIR}/deploy-scaled.sh" "validate" "$ENVIRONMENT" "$@"
            ;;
        output)
            tf_output "$@"
            ;;
        *)
            log_error "Unknown command: $command"
            usage
            ;;
    esac

    # Log timing for infrastructure operations (not output/fmt which are quick lookups)
    if [[ "$command" != "output" && "$command" != "fmt" ]]; then
        local elapsed=$(( SECONDS - start_time ))
        local mins=$(( elapsed / 60 ))
        local secs=$(( elapsed % 60 ))
        log_success "Workflow finished at $(_ts) — total time: ${mins}m ${secs}s"
    fi
}

main "$@"
