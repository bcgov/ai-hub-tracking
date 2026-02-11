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
NC='\033[0m' # No Color

# Variables tracking configuration
ENVIRONMENT=""
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
Usage: $0 <command> <environment> [options]

Commands:
    init        Initialize Terraform (download providers, configure backend)
    plan        Create execution plan
    apply       Apply changes (all modules in parallel)
    apply-phased Apply in two phases: 1) all except foundry_project, 2) foundry_project with parallelism=1
    destroy     Destroy infrastructure (all modules in parallel)
    destroy-phased Destroy in two phases: 1) foundry_project with parallelism=1, 2) all remaining
    validate    Validate configuration
    fmt         Format Terraform files
    output      Show Terraform outputs
    refresh     Refresh state
    state       Run state commands (e.g., state list, state show)

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
    
    TFVARS_ARGS=("-var-file=$shared_tfvars")
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
            
            TFVARS_ARGS+=("-var-file=$combined_tenants_file")
            log_info "Generated combined tenants file: $combined_tenants_file"
        else
            log_warning "No tenant configurations found in: $tenants_dir"
            # Create empty tenants map
            echo "tenants = {}" > "$combined_tenants_file"
            TFVARS_ARGS+=("-var-file=$combined_tenants_file")
        fi
    else
        log_warning "Tenants directory not found: $tenants_dir"
        # Create empty tenants map
        echo "tenants = {}" > "$combined_tenants_file"
        TFVARS_ARGS+=("-var-file=$combined_tenants_file")
    fi
    
    log_success "Variable files configured"
}

# =============================================================================
# Terraform Commands
# =============================================================================
tf_init() {
    log_info "Initializing Terraform..."
    
    # Validate backend config
    if [[ -z "${BACKEND_RESOURCE_GROUP}" ]]; then
        log_error "BACKEND_RESOURCE_GROUP not set (use TF_VAR_vnet_resource_group_name or set directly)"
        exit 1
    fi
    if [[ -z "${BACKEND_STORAGE_ACCOUNT}" ]]; then
        log_error "BACKEND_STORAGE_ACCOUNT not set"
        exit 1
    fi
    
    local state_key="ai-services-hub/${ENVIRONMENT}/terraform.tfstate"
    log_info "Backend: ${BACKEND_STORAGE_ACCOUNT}/${BACKEND_CONTAINER_NAME}/${state_key}"
    
    cd "$INFRA_DIR"

    local init_args=("-upgrade")
    if [[ "${CI:-false}" == "true" ]]; then
        init_args+=("-input=false" "-reconfigure")
    fi

    terraform init "${init_args[@]}" \
        -backend-config="resource_group_name=${BACKEND_RESOURCE_GROUP}" \
        -backend-config="storage_account_name=${BACKEND_STORAGE_ACCOUNT}" \
        -backend-config="container_name=${BACKEND_CONTAINER_NAME}" \
        -backend-config="key=${state_key}" \
        -backend-config="subscription_id=${ARM_SUBSCRIPTION_ID:-}" \
        -backend-config="tenant_id=${ARM_TENANT_ID:-}" \
        -backend-config="client_id=${TF_VAR_client_id:-}" \
        -backend-config="use_oidc=${ARM_USE_OIDC:-false}" \
        "$@"
    
    log_success "Terraform initialized"
}

ensure_initialized() {
    cd "$INFRA_DIR"
    
    if [[ ! -d ".terraform" ]] || [[ ! -f ".terraform.lock.hcl" ]]; then
        log_warning "Terraform not initialized. Running init..."
        tf_init
        return
    fi

    if [[ ! -d ".terraform/modules" ]] || [[ -z "$(ls -A .terraform/modules 2>/dev/null)" ]]; then
        log_warning "Terraform modules not installed. Running init..."
        tf_init
        return
    fi
    
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
    plan_args+=("-input=false")
    plan_args+=("$@")
    
    terraform plan "${plan_args[@]}"
    
    log_success "Plan created"
}

extract_import_target_from_tf_output() {
    local tf_output_file="$1"
    local script_path="${INFRA_DIR}/scripts/extract-import-target.sh"

    if [[ -x "$script_path" ]]; then
        "$script_path" "$tf_output_file"
    else
        # shellcheck source=extract-import-target.sh
        source "$script_path"
        extract_import_target "$tf_output_file"
    fi
}

tf_import_existing_resource_if_needed() {
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

    if terraform import "${TFVARS_ARGS[@]}" "$import_addr" "$import_id"; then
        log_success "Import succeeded: $import_addr"
        return 0
    fi

    log_error "Import failed for: $import_addr"
    return 2
}

run_terraform_with_retries() {
    local command="$1"
    shift

    local max_retries=3
    local attempt=1

    while true; do
        local tf_output_file
        tf_output_file="$(mktemp -t terraform-${command}.XXXXXX.log)"

        log_info "Running terraform ${command} (attempt ${attempt}/${max_retries})"

        set +e
        terraform "$command" "$@" 2>&1 | tee "$tf_output_file"
        local tf_exit=${PIPESTATUS[0]}
        set -e

        if [[ $tf_exit -eq 0 ]]; then
            rm -f "$tf_output_file"
            break
        fi

        # Try to handle recoverable errors before failing
        local handled=false

        # Check for deposed object errors (404 on delete)
        if tf_remove_deposed_object_if_needed "$tf_output_file"; then
            handled=true
        # Check for existing resource that needs import (apply only)
        elif [[ "$command" == "apply" ]] && tf_import_existing_resource_if_needed "$tf_output_file"; then
            handled=true
        fi

        if [[ "$handled" == "true" ]]; then
            rm -f "$tf_output_file"
            attempt=$((attempt + 1))
            if [[ $attempt -gt $max_retries ]]; then
                log_error "Exceeded maximum retries (${max_retries}) for auto-recovery"
                exit $tf_exit
            fi
            continue
        fi

        rm -f "$tf_output_file"
        log_error "Terraform ${command} failed (non-recoverable error)."
        exit $tf_exit
    done
}

# Detect and remove deposed objects from state
# Deposed objects occur when a resource replace fails mid-operation, leaving
# Terraform trying to delete a resource that no longer exists (404 errors)
tf_remove_deposed_object_if_needed() {
    local tf_output_file="$1"

    # Look for deposed object deletion errors
    # Pattern: "Error: deleting deposed object for <resource_address>"
    # Followed by: "StatusCode=404" or "not found" or similar
    local deposed_resource
    deposed_resource=$(grep -oP '(?<=Error: deleting deposed object for )[^\s,]+' "$tf_output_file" 2>/dev/null | head -1)

    if [[ -z "$deposed_resource" ]]; then
        # Alternative pattern: "deposed object" with resource address
        deposed_resource=$(grep -oP 'deposed object.*?(\S+\.\S+\[\d+\]|\S+\.\S+\.\S+\[\d+\]|\S+\.\S+\.\S+\.\S+\[\d+\])' "$tf_output_file" 2>/dev/null | grep -oP '\S+\[\d+\]$' | head -1)
    fi

    if [[ -z "$deposed_resource" ]]; then
        return 1
    fi

    # Verify this is a 404/not-found situation (safe to remove from state)
    if ! grep -qiE '(StatusCode=404|not found|does not exist|NoSuchResource)' "$tf_output_file" 2>/dev/null; then
        log_warning "Deposed object detected but error is not 404/not-found. Manual intervention required."
        return 1
    fi

    log_warning "Detected deposed object with 404 error (resource already deleted)"
    log_info "Deposed resource: $deposed_resource"
    log_info "Removing deposed object from state..."

    if terraform state rm "$deposed_resource" 2>/dev/null; then
        log_success "Removed deposed object from state: $deposed_resource"
        return 0
    fi

    log_error "Failed to remove deposed object from state: $deposed_resource"
    return 2
}

tf_apply() {
    log_info "Applying Terraform changes..."
    if [[ "${CI:-false}" == "true" ]]; then
        tf_init
    else
        ensure_initialized
    fi
    cd "$INFRA_DIR"
    
    local apply_args=("${TFVARS_ARGS[@]}")
    apply_args+=("-input=false")
    
    if [[ "${CI:-false}" == "true" ]]; then
        apply_args+=("-auto-approve")
    fi
    
    apply_args+=("$@")

    # Check if this is a targeted apply
    local is_targeted=false
    local is_foundry_target=false
    for arg in "$@"; do
        if [[ "$arg" == "-target="* ]]; then
            is_targeted=true
            if [[ "$arg" == *"foundry_project"* ]]; then
                is_foundry_target=true
            fi
        fi
    done
    
    # If targeting foundry_project specifically, use parallelism=1
    if [[ "$is_foundry_target" == "true" ]]; then
        log_info "Detected foundry_project target - using parallelism=1 to avoid ETag conflicts"
        apply_args+=("-parallelism=1")
    fi
    
    run_terraform_with_retries apply "${apply_args[@]}"
    
    log_success "Apply complete"
    
}

# =============================================================================
# Multi-Phase Apply
# Phase 1: Core infrastructure + tenant resources (parallel)
# Phase 2: AI Foundry projects + model deployments (parallelism=1)
# Phase 3: APIM Backend and Policy Orchestration
# Phase 4: Final apply (all remaining changes)
# =============================================================================
tf_apply_phased() {
    log_info "Starting phased apply..."
    log_info "Phase 1: Core infrastructure + tenants (parallel)"
    log_info "Phase 2: AI Foundry projects + models (parallelism=1)"
    log_info "Phase 3: APIM orchestration"
    log_info "Phase 4: Final apply"

    if [[ "${CI:-false}" == "true" ]]; then
        tf_init
    else
        ensure_initialized
    fi
    cd "$INFRA_DIR"

    # =========================================================================
    # PHASE 1: Core infrastructure + tenant resources (parallel)
    # Includes: network, hub, APIM, app gateway, defender, tenant resources
    # NOTE: module.tenant no longer has model deployments (moved to foundry_project)
    # =========================================================================
    log_info "=== PHASE 1: Applying core infrastructure + tenants (parallel) ==="
    
    local phase1_args=("${TFVARS_ARGS[@]}")
    phase1_args+=("-input=false")
    
    if [[ "${CI:-false}" == "true" ]]; then
        phase1_args+=("-auto-approve")
    fi

    # Target core infrastructure and tenant resources (no model deployments here)
    local targets=(
        "-target=azurerm_resource_group.main"
        "-target=module.network"
        "-target=module.ai_foundry_hub"
        "-target=module.apim"
        "-target=module.app_gateway"
        "-target=module.defender"
        "-target=module.tenant"
        "-target=module.tenant_user_management"
    )

    log_info "Phase 1 targets: ${targets[*]}"

    run_terraform_with_retries apply "${phase1_args[@]}" "${targets[@]}" "$@"
    log_success "Phase 1 complete"

    # =========================================================================
    # PHASE 2: AI Foundry Projects + Model Deployments (serialized)
    # Run with parallelism=1 to avoid ETag conflicts on shared AI Foundry Hub
    # Model deployments are now in foundry_project module, not tenant module
    # =========================================================================
    log_info "=== PHASE 2: Applying AI Foundry projects + models (parallelism=1) ==="
    
    local phase2_args=("${TFVARS_ARGS[@]}")
    phase2_args+=("-input=false")
    phase2_args+=("-parallelism=1")
    
    if [[ "${CI:-false}" == "true" ]]; then
        phase2_args+=("-auto-approve")
    fi
    
    # Only foundry_project module - contains projects AND model deployments
    phase2_args+=("-target=module.foundry_project")

    run_terraform_with_retries apply "${phase2_args[@]}" "$@"
    log_success "Phase 2 complete"

    # Phase 3: APIM Backend and Policy Orchestration
    # ==========================================================================
    # APIM has strict ordering constraints:
    # - CREATION: Backends MUST exist before policies reference them
    # - DELETION: Policies MUST be updated before backends are deleted
    #
    # Strategy:
    # 1. Analyze plan to detect backend creations and deletions
    # 2. If deletions exist: update policies FIRST (Phase 4a), then everything else in Phase 5
    # 3. If only creations (no deletions): create backends FIRST (Phase 4a), then policies in Phase 5
    # 4. If no backend changes: skip Phase 4 entirely
    # ==========================================================================

    log_info "=== PHASE 3: APIM Policy and Backend Orchestration ==="
    
    # Generate a plan to detect what's changing
    local plan_file="${INFRA_DIR}/.phase3-plan"
    local plan_json="${INFRA_DIR}/.phase3-plan.json"
    
    log_info "Analyzing Terraform plan for APIM changes..."
    terraform plan "${TFVARS_ARGS[@]}" -input=false -out="$plan_file" > /dev/null 2>&1 || true
    terraform show -json "$plan_file" > "$plan_json" 2>/dev/null || true
    
    # Check for backend creations and deletions
    local backends_to_create=""
    local backends_to_destroy=""
    
    if [[ -f "$plan_json" ]]; then
        backends_to_create=$(jq -r '
            .resource_changes[]? 
            | select(.type == "azurerm_api_management_backend") 
            | select(.change.actions | contains(["create"]))
            | .address
        ' "$plan_json" 2>/dev/null | grep -v '^$' || true)
        
        backends_to_destroy=$(jq -r '
            .resource_changes[]? 
            | select(.type == "azurerm_api_management_backend") 
            | select(.change.actions | contains(["delete"]))
            | .address
        ' "$plan_json" 2>/dev/null | grep -v '^$' || true)
    fi
    
    # Priority: Handle deletions first (policy update must happen before backend deletion)
    if [[ -n "$backends_to_destroy" ]]; then
        log_info "Detected backends scheduled for destruction:"
        echo "$backends_to_destroy" | while read -r addr; do
            [[ -n "$addr" ]] && log_info "  - $addr"
        done
        
        # Phase 3a: Update policies FIRST to remove stale backend references
        log_info "Updating APIM policies before backend deletion..."
        
        local phase3a_args=("${TFVARS_ARGS[@]}")
        phase3a_args+=("-input=false")
        
        if [[ "${CI:-false}" == "true" ]]; then
            phase3a_args+=("-auto-approve")
        fi
        
        # Target only policy resources - no depends_on to backends means this won't trigger backend deletion
        phase3a_args+=("-target=azurerm_api_management_api_policy.tenant")
        
        if ! run_terraform_with_retries apply "${phase3a_args[@]}"; then
            log_warning "Policy update had issues, continuing with full apply..."
        fi
        log_success "Phase 3a (policy update for backend deletion) complete"
        
    elif [[ -n "$backends_to_create" ]]; then
        # Only creations, no deletions - create backends first
        log_info "Detected backends scheduled for creation (no deletions):"
        echo "$backends_to_create" | while read -r addr; do
            [[ -n "$addr" ]] && log_info "  - $addr"
        done
        
        log_info "Creating new APIM backends before policy application..."
        
        local phase3a_args=("${TFVARS_ARGS[@]}")
        phase3a_args+=("-input=false")
        
        if [[ "${CI:-false}" == "true" ]]; then
            phase3a_args+=("-auto-approve")
        fi
        
        # Target backend resources for creation
        phase3a_args+=(
            "-target=azurerm_api_management_backend.openai"
            "-target=azurerm_api_management_backend.docint"
            "-target=azurerm_api_management_backend.storage"
            "-target=azurerm_api_management_backend.ai_search"
            "-target=azurerm_api_management_backend.speech_services"
        )
        
        if ! run_terraform_with_retries apply "${phase3a_args[@]}"; then
            log_warning "Backend creation had issues, continuing..."
        fi
        log_success "Phase 3a (backend creation) complete"
    else
        log_info "No APIM backend changes detected, skipping Phase 3a"
    fi
    
    rm -f "$plan_file" "$plan_json"
    log_success "Phase 3 complete"

    # Phase 4: Final apply for all remaining resources
    # Now that policies no longer reference stale backends, backend destruction is safe
    log_info "=== PHASE 4: Final apply (all remaining changes) ==="
    
    local phase4_args=("${TFVARS_ARGS[@]}")
    phase4_args+=("-input=false")
    
    if [[ "${CI:-false}" == "true" ]]; then
        phase4_args+=("-auto-approve")
    fi

    run_terraform_with_retries apply "${phase4_args[@]}" "$@"
    log_success "Phase 4 complete"
    
    log_success "Phased apply complete"
}

tf_destroy() {
    log_info "Destroying Terraform resources..."
    ensure_initialized
    cd "$INFRA_DIR"
    
    local destroy_args=("${TFVARS_ARGS[@]}")
    destroy_args+=("-input=false")
    
    if [[ "${CI:-false}" == "true" ]]; then
        destroy_args+=("-auto-approve")
    fi
    
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

# =============================================================================
# Two-Phase Destroy
# Phase 1: Destroy AI Foundry projects + model deployments (parallelism=1)
# Phase 2: Destroy all remaining modules (parallel)
# Reverse order of apply to respect dependencies
# =============================================================================
tf_destroy_phased() {
    log_info "Starting phased destroy..."
    log_info "Phase 1: AI Foundry projects + models (parallelism=1)"
    log_info "Phase 2: APIM policy/backend teardown (ordered)"
    log_info "Phase 3: All remaining modules (parallel)"

    ensure_initialized
    cd "$INFRA_DIR"

    if [[ "${CI:-false}" != "true" ]]; then
        log_warning "This will DESTROY infrastructure!"
        read -p "Are you sure? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            log_info "Destroy cancelled"
            exit 0
        fi
    fi

    # Phase 1: Destroy foundry_project with parallelism=1
    # This includes AI Foundry projects AND model deployments
    log_info "=== PHASE 1: Destroying AI Foundry projects + models (parallelism=1) ==="
    
    local phase1_args=("${TFVARS_ARGS[@]}")
    phase1_args+=("-input=false")
    phase1_args+=("-parallelism=1")
    phase1_args+=("-target=module.foundry_project")
    
    if [[ "${CI:-false}" == "true" ]]; then
        phase1_args+=("-auto-approve")
    fi

    run_terraform_with_retries destroy "${phase1_args[@]}" "$@"
    log_success "Phase 1 destroy complete"

    # Phase 2: APIM policy/backend teardown (reverse of apply orchestration)
    # Ensure policies are removed before backends to avoid APIM 400 errors
    log_info "=== PHASE 2: APIM policy/backend teardown (ordered) ==="

    local phase2a_args=("${TFVARS_ARGS[@]}")
    phase2a_args+=("-input=false")

    if [[ "${CI:-false}" == "true" ]]; then
        phase2a_args+=("-auto-approve")
    fi

    # Destroy APIM API policies first
    phase2a_args+=("-target=azurerm_api_management_api_policy.tenant")
    run_terraform_with_retries destroy "${phase2a_args[@]}" "$@"
    log_success "Phase 2a destroy (APIM API policies) complete"

    # Then destroy APIM backends
    local phase2b_args=("${TFVARS_ARGS[@]}")
    phase2b_args+=("-input=false")

    if [[ "${CI:-false}" == "true" ]]; then
        phase2b_args+=("-auto-approve")
    fi

    phase2b_args+=(
        "-target=azurerm_api_management_backend.ai_foundry"
        "-target=azurerm_api_management_backend.openai"
        "-target=azurerm_api_management_backend.docint"
        "-target=azurerm_api_management_backend.storage"
        "-target=azurerm_api_management_backend.ai_search"
        "-target=azurerm_api_management_backend.speech_services"
    )

    run_terraform_with_retries destroy "${phase2b_args[@]}" "$@"
    log_success "Phase 2b destroy (APIM backends) complete"

    # Phase 3: Destroy all remaining resources (parallel)
    log_info "=== PHASE 3: Destroying all remaining modules (parallel) ==="
    
    local phase2_args=("${TFVARS_ARGS[@]}")
    phase2_args+=("-input=false")
    
    if [[ "${CI:-false}" == "true" ]]; then
        phase2_args+=("-auto-approve")
    fi

    run_terraform_with_retries destroy "${phase2_args[@]}" "$@"
    log_success "Phase 3 destroy complete"
    
    log_success "Phased destroy complete"
}

tf_output() {
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
    
    # Commands that don't need environment
    case "$command" in
        fmt|validate)
            cd "$INFRA_DIR"
            case "$command" in
                fmt) tf_fmt "$@" ;;
                validate) tf_validate "$@" ;;
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
        init)
            tf_init "$@"
            ;;
        plan)
            tf_plan "$@"
            ;;
        apply)
            tf_apply "$@"
            ;;
        apply-phased)
            tf_apply_phased "$@"
            ;;
        destroy)
            tf_destroy "$@"
            ;;
        destroy-phased)
            tf_destroy_phased "$@"
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
