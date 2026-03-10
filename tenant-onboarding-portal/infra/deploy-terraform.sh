#!/bin/bash
# =============================================================================
# Terraform Deployment Script for Tenant Onboarding Portal
# =============================================================================
# Reusable script for Terraform operations and portal application deployment
# tasks for the tenant-onboarding-portal workspace.
#
# Usage:
#   ./deploy-terraform.sh <command> <environment> [options]
#
# Commands:
#   init         - Initialize Terraform
#   plan         - Create execution plan
#   apply        - Apply changes
#   destroy      - Destroy infrastructure
#   validate     - Validate configuration
#   fmt          - Format Terraform files
#   output       - Show outputs as JSON
#   package-app  - Install portal deps, build, and create deployment zip
#   deploy-app   - Deploy the portal zip to Azure App Service
#   swap-slot    - Swap an App Service deployment slot
#   health-check - Verify the deployed portal health endpoint
#
# Environments:
#   dev, test, prod, tools
#
# Options:
#   -target=<resource>         Target specific Terraform resource
#   --auto-approve             Skip confirmation prompts
#   --state-key=<key>          Override Terraform backend state key
#   --no-var-file              Do not load terraform.tfvars automatically
#   --app-name=<name>          App Service name for app deployment commands
#   --resource-group=<name>    Resource group for app deployment commands
#   --slot=<name>              App Service slot name for deploy/swap commands
#   --target-slot=<name>       Slot swap target (default: production)
#   --src-path=<path>          Deployment zip path (default: portal-deploy.zip)
#   --hostname=<host-or-url>   Hostname or URL for health checks
#   --health-path=<path>       Health endpoint path (default: /healthz)
#   --health-retries=<count>   Number of health check attempts (default: 12)
#   --health-interval=<secs>   Delay between health checks (default: 10)
#   --timeout=<secs>           Azure deploy timeout in seconds (default: 300)
#   --infra-only               Skip app package/deploy after terraform apply
#
# Environment Variables:
#   CI=true                  Enable CI mode
#   TF_VAR_subscription_id   Azure Subscription ID
#   TF_VAR_tenant_id         Azure Tenant ID
#   TF_VAR_client_id         Azure Client ID (for OIDC)
#   ARM_USE_OIDC=true        Use OIDC authentication
#   BACKEND_RESOURCE_GROUP    Resource group holding the Terraform state account
#   BACKEND_STORAGE_ACCOUNT   Storage account holding Terraform state
#   BACKEND_CONTAINER_NAME    Storage container for Terraform state (default tfstate)
#   PORTAL_STATE_KEY          Backend state key override (default portal/<env>/terraform.tfstate)
#   PORTAL_RESOURCE_GROUP     Default App Service resource group
#   PORTAL_APP_SERVICE_NAME   Default App Service name
#   PORTAL_APP_HOSTNAME       Default hostname used by health-check
#   PORTAL_DEPLOY_ZIP         Default deployment zip path
#   GITHUB_OUTPUT             GitHub Actions output file path for apply outputs
#
# Examples:
#   ./deploy-terraform.sh plan dev
#   ./deploy-terraform.sh apply tools --auto-approve
#   ./deploy-terraform.sh destroy test -target=module.portal_storage
#   CI=true ./deploy-terraform.sh plan tools --state-key=portal/pr123/terraform.tfstate
#   ./deploy-terraform.sh package-app tools
#   ./deploy-terraform.sh deploy-app tools --app-name=ai-hub-onboarding --resource-group=rg-tools --slot=staging
#   ./deploy-terraform.sh health-check tools --hostname=ai-hub-onboarding.azurewebsites.net
#   ./deploy-terraform.sh apply tools --auto-approve --infra-only
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}"
PORTAL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_DIR="${PORTAL_ROOT}/backend"
FRONTEND_DIR="${PORTAL_ROOT}/frontend"
DEFAULT_DEPLOY_ZIP="${PORTAL_ROOT}/portal-deploy.zip"
NODE_VERSION_FILE="${PORTAL_NODE_VERSION_FILE:-${PORTAL_ROOT}/.node-version}"
# Resolve relative path to absolute (relative to workspace root = PORTAL_ROOT's parent)
# Required because the GHA env var is set as a repo-root-relative path but the script may
# run from a sub-directory (e.g., tenant-onboarding-portal/infra).
if [[ ! "$NODE_VERSION_FILE" = /* ]]; then
    NODE_VERSION_FILE="$(cd "${PORTAL_ROOT}/.." && pwd)/${NODE_VERSION_FILE}"
fi

VALID_ENVIRONMENTS=("dev" "test" "prod" "tools")

BACKEND_RESOURCE_GROUP="${BACKEND_RESOURCE_GROUP:-}"
BACKEND_STORAGE_ACCOUNT="${BACKEND_STORAGE_ACCOUNT:-}"
BACKEND_CONTAINER_NAME="${BACKEND_CONTAINER_NAME:-tfstate}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m'

COMMAND=""
ENVIRONMENT=""
AUTO_APPROVE=false
USE_VAR_FILE=true
STATE_KEY_OVERRIDE=""
TF_ARGS=()
APP_NAME="${PORTAL_APP_SERVICE_NAME:-}"
RESOURCE_GROUP="${PORTAL_RESOURCE_GROUP:-${TF_VAR_resource_group_name:-}}"
SLOT=""
TARGET_SLOT="production"
ZIP_PATH="${PORTAL_DEPLOY_ZIP:-${DEFAULT_DEPLOY_ZIP}}"
HOSTNAME="${PORTAL_APP_HOSTNAME:-}"
HEALTH_PATH="/healthz"
HEALTH_RETRIES=12
HEALTH_INTERVAL=10
DEPLOY_TIMEOUT=300
SKIP_APP_DEPLOY=false
APPLY_RESOURCE_GROUP=""
APPLY_APP_NAME=""
APPLY_APP_HOSTNAME=""
APPLY_STAGING_HOSTNAME=""
NODE_CMD=""
NPM_CMD=""

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

usage() {
    local exit_code="${1:-1}"
    cat << EOF
Usage: $0 <command> <environment> [options]

Commands:
    init         Initialize Terraform
    plan         Create execution plan
    apply        Apply changes
    destroy      Destroy infrastructure
    validate     Validate configuration
    fmt          Format Terraform files
    output       Show outputs as JSON
    package-app  Install portal dependencies, build, and create deployment zip
    deploy-app   Deploy the portal zip to Azure App Service
    swap-slot    Swap an App Service slot into production
    health-check Verify the deployed portal health endpoint

Environments:
    dev, test, prod, tools

Options:
    -target=<resource>         Target specific Terraform resource
    --auto-approve             Skip confirmation prompts
    --state-key=<key>          Override backend state key
    --no-var-file              Do not automatically load terraform.tfvars
    --app-name=<name>          App Service name for app deployment commands
    --resource-group=<name>    Resource group for app deployment commands
    --slot=<name>              App Service slot name for deploy/swap commands
    --target-slot=<name>       Slot swap target (default: production)
    --src-path=<path>          Deployment zip path (default: portal-deploy.zip)
    --hostname=<host-or-url>   Hostname or URL for health checks
    --health-path=<path>       Health endpoint path (default: /healthz)
    --health-retries=<count>   Number of health check attempts (default: 12)
    --health-interval=<secs>   Delay between health checks (default: 10)
    --timeout=<secs>           Azure deploy timeout in seconds (default: 300)
    --infra-only               Skip app package/deploy after terraform apply

Examples:
    $0 plan dev
    $0 apply tools --auto-approve
    $0 destroy test -target=module.portal_storage
    CI=true $0 plan tools --state-key=portal/pr123/terraform.tfstate
    $0 package-app tools
    $0 deploy-app tools --app-name=ai-hub-onboarding --resource-group=rg-tools --slot=staging
    $0 health-check tools --hostname=ai-hub-onboarding.azurewebsites.net
    $0 apply tools --auto-approve --infra-only

EOF
    exit "$exit_code"
}

validate_environment() {
    local env="$1"
    local valid_env

    for valid_env in "${VALID_ENVIRONMENTS[@]}"; do
        if [[ "$env" == "$valid_env" ]]; then
            return 0
        fi
    done

    log_error "Invalid environment: $env"
    log_error "Valid environments: ${VALID_ENVIRONMENTS[*]}"
    exit 1
}

require_command() {
    local command_name="$1"
    local description="$2"

    if ! command -v "$command_name" &> /dev/null; then
        log_error "${description} is not installed"
        exit 1
    fi
}

has_command() {
    command -v "$1" &> /dev/null
}

is_windows_environment() {
    # True in WSL (wslpath available) or Git Bash (pwd -W works).
    # pwsh alone is NOT sufficient — it is also present on GHA Linux runners.
    has_command wslpath && return 0
    (cd "$PORTAL_ROOT" && pwd -W >/dev/null 2>&1) && return 0
    return 1
}

package_temp_parent() {
    local temp_root

    temp_root="${PORTAL_ROOT}/.tmp"
    mkdir -p "$temp_root"
    printf '%s\n' "$temp_root"
}

to_windows_path() {
    local target_path="$1"

    if has_command wslpath; then
        wslpath -w "$target_path"
        return 0
    fi

    if (cd "$PORTAL_ROOT" && pwd -W >/dev/null 2>&1); then
        if [[ -d "$target_path" ]]; then
            (cd "$target_path" && pwd -W)
        else
            (
                cd "$(dirname "$target_path")"
                printf '%s\\%s' "$(pwd -W)" "$(basename "$target_path")"
            )
        fi
        return 0
    fi

    log_error "to_windows_path called outside a Windows/WSL environment; call is_windows_environment() before invoking this function"
    exit 1
}

resolve_node_commands() {
    if [[ -n "$NODE_CMD" && -n "$NPM_CMD" ]]; then
        return 0
    fi

    if has_command node; then
        NODE_CMD="node"
    elif has_command node.exe; then
        NODE_CMD="node.exe"
    else
        log_error "Node.js is not installed"
        exit 1
    fi

    if has_command npm; then
        NPM_CMD="npm"
    elif has_command npm.cmd; then
        NPM_CMD="npm.cmd"
    else
        log_error "npm is not installed"
        exit 1
    fi
}

require_zip_archiver() {
    if has_command zip || has_command powershell.exe || has_command pwsh; then
        return 0
    fi

    log_error "No supported zip archiver is installed (expected one of: zip, powershell.exe, pwsh)"
    exit 1
}

required_node_major() {
    if [[ ! -f "$NODE_VERSION_FILE" ]]; then
        log_error "Missing Node version file: ${NODE_VERSION_FILE}"
        exit 1
    fi

    tr -d '[:space:]' < "$NODE_VERSION_FILE"
}

ensure_node_version() {
    local required_major
    local current_major

    resolve_node_commands
    required_major="$(required_node_major)"
    current_major="$("$NODE_CMD" -p "process.versions.node.split('.')[0]")"

    if [[ "$current_major" != "$required_major" ]]; then
        log_error "Node.js major version ${required_major} is required (found ${current_major})"
        exit 1
    fi
}

ensure_azure_login() {
    if ! az account show &> /dev/null; then
        if [[ "${CI:-false}" == "true" || "${ARM_USE_OIDC:-false}" == "true" ]]; then
            log_info "Azure CLI login not detected; continuing because CI/OIDC mode is enabled"
        else
            log_info "Please login to Azure..."
            az login >/dev/null
        fi
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites for ${COMMAND}..."

    case "$COMMAND" in
        init|plan|destroy|validate|fmt|output)
            require_command terraform "Terraform"
            require_command az "Azure CLI"
            ensure_azure_login
            ;;
        apply)
            require_command terraform "Terraform"
            require_command az "Azure CLI"
            ensure_azure_login
            if [[ "$SKIP_APP_DEPLOY" != "true" ]]; then
                ensure_node_version
                require_zip_archiver
                require_command curl "curl"
            fi
            ;;
        package-app)
            ensure_node_version
            require_zip_archiver
            ;;
        deploy-app|swap-slot)
            require_command az "Azure CLI"
            ensure_azure_login
            ;;
        health-check)
            require_command curl "curl"
            ;;
        *)
            log_error "Unknown command: ${COMMAND}"
            usage
            ;;
    esac

    log_success "Prerequisites check passed"
}

setup_azure_auth() {
    log_info "Setting up Azure authentication..."

    if [[ -n "${TF_VAR_subscription_id:-}" ]]; then
        az account set --subscription "${TF_VAR_subscription_id}"
    fi

    export ARM_SUBSCRIPTION_ID="${TF_VAR_subscription_id:-$(az account show --query id -o tsv)}"
    export ARM_TENANT_ID="${TF_VAR_tenant_id:-$(az account show --query tenantId -o tsv)}"

    if [[ "${ARM_USE_OIDC:-false}" == "true" ]]; then
        export ARM_USE_OIDC=true
        if [[ -n "${TF_VAR_client_id:-}" ]]; then
            export ARM_CLIENT_ID="${TF_VAR_client_id}"
        fi
        log_info "Using OIDC authentication"
    else
        export ARM_USE_CLI=true
        log_info "Using Azure CLI authentication"
    fi

    log_success "Azure authentication configured"
}

setup_azure_cli_context() {
    log_info "Setting up Azure CLI context..."

    if [[ -n "${ARM_SUBSCRIPTION_ID:-}" ]]; then
        az account set --subscription "${ARM_SUBSCRIPTION_ID}"
    elif [[ -n "${TF_VAR_subscription_id:-}" ]]; then
        az account set --subscription "${TF_VAR_subscription_id}"
    fi

    log_success "Azure CLI context configured"
}

backend_state_key() {
    if [[ -n "$STATE_KEY_OVERRIDE" ]]; then
        echo "$STATE_KEY_OVERRIDE"
    elif [[ -n "${PORTAL_STATE_KEY:-}" ]]; then
        echo "${PORTAL_STATE_KEY}"
    else
        echo "portal/${ENVIRONMENT}/terraform.tfstate"
    fi
}

run_terraform_init() {
    log_info "Initializing Terraform..."
    local -a init_args=("-input=false")

    if [[ -n "$BACKEND_RESOURCE_GROUP" && -n "$BACKEND_STORAGE_ACCOUNT" ]]; then
        local state_key
        state_key="$(backend_state_key)"
        log_info "Using remote backend key: ${state_key}"
        init_args+=(
            "-backend-config=resource_group_name=${BACKEND_RESOURCE_GROUP}"
            "-backend-config=storage_account_name=${BACKEND_STORAGE_ACCOUNT}"
            "-backend-config=container_name=${BACKEND_CONTAINER_NAME}"
            "-backend-config=key=${state_key}"
        )

        if [[ "${ARM_USE_OIDC:-false}" == "true" ]]; then
            init_args+=("-backend-config=use_oidc=true")
        fi
    else
        log_warning "Backend environment variables not set; using backend.tf defaults"
    fi

    (cd "$INFRA_DIR" && terraform init "${init_args[@]}")
    log_success "Terraform initialization complete"
}

terraform_common_args() {
    local -a args=("-var=app_env=${ENVIRONMENT}")

    if [[ "$USE_VAR_FILE" == "true" && -f "${INFRA_DIR}/terraform.tfvars" ]]; then
        args+=("-var-file=terraform.tfvars")
    fi

    args+=("${TF_ARGS[@]}")
    printf '%s\n' "${args[@]}"
}

terraform_output_raw() {
    local output_name="$1"
    (cd "$INFRA_DIR" && terraform output -raw "$output_name" 2>/dev/null || true)
}

run_terraform_command() {
    local command="$1"
    shift
    local -a command_args=("$@")
    (cd "$INFRA_DIR" && terraform "$command" "${command_args[@]}")
}

require_value() {
    local value="$1"
    local label="$2"

    if [[ -z "$value" ]]; then
        log_error "${label} is required for ${COMMAND}"
        exit 1
    fi
}

package_portal_app() {
    local package_root
    local package_backend_dir
    local package_frontend_dir
    local package_temp_root

    package_temp_root="$(package_temp_parent)"
    package_root="$(mktemp -d "${package_temp_root}/portal-package.XXXXXX")"
    package_backend_dir="${package_root}/backend"
    package_frontend_dir="${package_root}/frontend"

    trap "rm -rf \"$package_root\"" RETURN

    log_info "Creating isolated package workspace: ${package_root}"
    create_package_workspace "$package_root"

    log_info "Installing frontend dependencies..."
    (cd "$package_frontend_dir" && "$NPM_CMD" ci)

    log_info "Installing backend dependencies..."
    (cd "$package_backend_dir" && "$NPM_CMD" ci)

    log_info "Building frontend bundle..."
    (cd "$package_frontend_dir" && "$NPM_CMD" run build)

    log_info "Syncing frontend assets into backend package..."
    (cd "$package_backend_dir" && "$NODE_CMD" scripts/sync-frontend-dist.cjs)

    log_info "Building backend bundle..."
    (cd "$package_backend_dir" && "$NPM_CMD" run build)

    log_info "Pruning backend dev dependencies from deployment artifact..."
    (cd "$package_backend_dir" && "$NPM_CMD" prune --omit=dev)

    rm -f "$ZIP_PATH"

    log_info "Creating deployment zip: ${ZIP_PATH}"
    create_deployment_zip "$package_backend_dir"

    log_success "Deployment zip created ($(du -sh "$ZIP_PATH" | cut -f1))"
}

create_package_workspace() {
    local destination_root="$1"

    if has_command tar; then
        mkdir -p "$destination_root"
        (
            cd "$PORTAL_ROOT"
            tar -cf - \
                --exclude=backend/node_modules \
                --exclude=frontend/node_modules \
                --exclude=backend/dist \
                --exclude=backend/frontend-dist \
                --exclude=frontend/dist \
                --exclude=.tmp \
                --exclude=portal-deploy.zip \
                --exclude=.git \
                .
        ) | (
            cd "$destination_root"
            tar -xf -
        )
        return 0
    fi

    create_package_workspace_with_powershell "$destination_root"
}

create_package_workspace_with_powershell() {
    local destination_root="$1"
    local shell_bin=""
    local windows_portal_root=""
    local windows_destination_root=""
    local ps_script=""

    if has_command powershell.exe; then
        shell_bin="powershell.exe"
    elif has_command pwsh; then
        shell_bin="pwsh"
    else
        log_error "No supported workspace copy tool is available (expected tar, powershell.exe, or pwsh)"
        exit 1
    fi

    windows_portal_root="$(to_windows_path "$PORTAL_ROOT")"
    mkdir -p "$destination_root"
    windows_destination_root="$(to_windows_path "$destination_root")"
    ps_script="\
      \$sourceRoot = [System.IO.Path]::GetFullPath('${windows_portal_root//\/\\}'); \
      \$destinationRoot = [System.IO.Path]::GetFullPath('${windows_destination_root//\/\\}'); \
      if (Test-Path \$destinationRoot) { Remove-Item \$destinationRoot -Recurse -Force; } ; \
      New-Item -ItemType Directory -Path \$destinationRoot | Out-Null; \
    robocopy \$sourceRoot \$destinationRoot /MIR /XD .git .tmp backend\\node_modules frontend\\node_modules backend\\dist backend\\frontend-dist frontend\\dist /XF portal-deploy.zip | Out-Null"

    "$shell_bin" -NoLogo -NoProfile -Command "$ps_script"
}

create_deployment_zip() {
    local source_backend_dir="${1:-$BACKEND_DIR}"
    local -a exclude_args=(
        "--exclude=frontend-dist/.vite/*"
        "--exclude=*/__pycache__/*"
        "--exclude=*.pyc"
        "--exclude=*/tests/*"
        "--exclude=playwright-report/*"
        "--exclude=test-results/*"
        "--exclude=infra/*"
        "--exclude=docs/*"
        "--exclude=.venv/*"
        "--exclude=.env*"
        "--exclude=.git*"
    )

    if has_command zip; then
        (
            cd "$source_backend_dir"
            zip -r "$ZIP_PATH" . \
                --exclude "frontend-dist/.vite/*" \
                --exclude "*/__pycache__/*" \
                --exclude "*.pyc" \
                --exclude "*/tests/*" \
                --exclude "playwright-report/*" \
                --exclude "test-results/*" \
                --exclude "infra/*" \
                --exclude "docs/*" \
                --exclude ".venv/*" \
                --exclude ".env*" \
                --exclude ".git*"
        )
        validate_deployment_zip
        return 0
    fi

    create_deployment_zip_with_powershell "$source_backend_dir"
    validate_deployment_zip
}

create_deployment_zip_with_powershell() {
    local source_backend_dir="${1:-$BACKEND_DIR}"
    local shell_bin=""
    local windows_backend_dir=""
    local windows_zip_path=""
    local ps_script=""

    if has_command powershell.exe; then
        shell_bin="powershell.exe"
    elif has_command pwsh; then
        shell_bin="pwsh"
    else
        log_error "PowerShell is not available for zip packaging"
        exit 1
    fi

    windows_backend_dir="$(to_windows_path "$source_backend_dir")"
    windows_zip_path="$(to_windows_path "$ZIP_PATH")"
    ps_script="\
      \$backendDir = [System.IO.Path]::GetFullPath('${windows_backend_dir//\/\\}'); \
      \$zipPath = [System.IO.Path]::GetFullPath('${windows_zip_path//\/\\}'); \
      \$stagingDir = Join-Path ([System.IO.Path]::GetDirectoryName(\$zipPath)) 'portal-deploy-staging'; \
      if (Test-Path \$stagingDir) { Remove-Item \$stagingDir -Recurse -Force; } ; \
      New-Item -ItemType Directory -Path \$stagingDir | Out-Null; \
            robocopy \$backendDir \$stagingDir /MIR /XD frontend-dist\\.vite infra docs .venv tests __pycache__ /XF *.pyc .env .env.* .git .gitignore .gitattributes | Out-Null; \
      if (Test-Path \$zipPath) { Remove-Item \$zipPath -Force; } ; \
            Add-Type -AssemblyName System.IO.Compression; \
            Add-Type -AssemblyName System.IO.Compression.FileSystem; \
            \$archive = [System.IO.Compression.ZipFile]::Open(\$zipPath, [System.IO.Compression.ZipArchiveMode]::Create); \
            try { \
                \$files = Get-ChildItem -Path \$stagingDir -Recurse -File; \
                foreach (\$file in \$files) { \
                    \$relativePath = \$file.FullName.Substring(\$stagingDir.Length + 1).Replace('\\', '/'); \
                    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(\$archive, \$file.FullName, \$relativePath, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null; \
                } \
            } finally { \
                \$archive.Dispose(); \
            } ; \
      Remove-Item \$stagingDir -Recurse -Force"

    "$shell_bin" -NoLogo -NoProfile -Command "$ps_script"
}

validate_deployment_zip() {
    local shell_bin=""
    local windows_zip_path=""
    local validation_script=""

    # Windows-style path validation is only meaningful in WSL/Git Bash environments.
    # On native Linux (GHA runners, CI), zip always produces POSIX paths — no validation needed.
    if ! is_windows_environment; then
        return 0
    fi

    if has_command powershell.exe; then
        shell_bin="powershell.exe"
    elif has_command pwsh; then
        shell_bin="pwsh"
    else
        return 0
    fi

    windows_zip_path="$(to_windows_path "$ZIP_PATH")"
        validation_script="\
            Add-Type -AssemblyName System.IO.Compression.FileSystem; \
            \$zipPath = [System.IO.Path]::GetFullPath('${windows_zip_path//\/\\}'); \
            \$zip = [System.IO.Compression.ZipFile]::OpenRead(\$zipPath); \
            try { \
                \$invalidEntries = \$zip.Entries | Where-Object { \$_.FullName -like '*\\*' } | Select-Object -ExpandProperty FullName; \
                if (\$invalidEntries) { \
                    Write-Error ('Deployment zip contains Windows-style entry paths: ' + ((\$invalidEntries | Select-Object -First 10) -join ', ')); \
                    exit 1; \
                } \
            } finally { \
                \$zip.Dispose(); \
            }"

        "$shell_bin" -NoLogo -NoProfile -Command "$validation_script" >/dev/null
}

load_apply_outputs() {
    APPLY_RESOURCE_GROUP="$(terraform_output_raw resource_group_name)"
    APPLY_APP_NAME="$(terraform_output_raw app_service_name)"
    APPLY_APP_HOSTNAME="$(terraform_output_raw app_service_default_hostname)"
    APPLY_STAGING_HOSTNAME="$(terraform_output_raw staging_slot_hostname)"

    if [[ -z "$RESOURCE_GROUP" ]]; then
        RESOURCE_GROUP="$APPLY_RESOURCE_GROUP"
    fi

    if [[ -z "$APP_NAME" ]]; then
        APP_NAME="$APPLY_APP_NAME"
    fi

    if [[ -z "$HOSTNAME" ]]; then
        HOSTNAME="$APPLY_APP_HOSTNAME"
    fi
}

emit_apply_outputs() {
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        {
            echo "resource_group_name=${APPLY_RESOURCE_GROUP}"
            echo "app_service_name=${APPLY_APP_NAME}"
            echo "app_hostname=${APPLY_APP_HOSTNAME}"
            echo "staging_hostname=${APPLY_STAGING_HOSTNAME}"
        } >> "$GITHUB_OUTPUT"
    fi

    log_info "Resource group: ${APPLY_RESOURCE_GROUP}"
    log_info "App Service: ${APPLY_APP_NAME}"
    log_info "App hostname: ${APPLY_APP_HOSTNAME}"
    if [[ -n "$APPLY_STAGING_HOSTNAME" ]]; then
        log_info "Staging hostname: ${APPLY_STAGING_HOSTNAME}"
    fi
}

deploy_after_apply() {
    if [[ "$SKIP_APP_DEPLOY" == "true" ]]; then
        log_info "Skipping app packaging and deployment because --infra-only was supplied"
        return 0
    fi

    require_value "$RESOURCE_GROUP" "Resource group"
    require_value "$APP_NAME" "App Service name"

    package_portal_app

    if [[ -n "$APPLY_STAGING_HOSTNAME" ]]; then
        SLOT="staging"
        HOSTNAME="$APPLY_STAGING_HOSTNAME"
        deploy_portal_app
        verify_portal_health
        swap_portal_slot
        SLOT=""
        HOSTNAME="$APPLY_APP_HOSTNAME"
        verify_portal_health
    else
        SLOT=""
        HOSTNAME="$APPLY_APP_HOSTNAME"
        deploy_portal_app
        verify_portal_health
    fi
}

deploy_portal_app() {
    local deploy_zip_path=""

    require_value "$RESOURCE_GROUP" "Resource group"
    require_value "$APP_NAME" "App Service name"

    if [[ ! -f "$ZIP_PATH" ]]; then
        log_error "Deployment zip not found: ${ZIP_PATH}"
        exit 1
    fi

    if is_windows_environment; then
        deploy_zip_path="$(to_windows_path "$ZIP_PATH")"
    else
        deploy_zip_path="$ZIP_PATH"
    fi

    log_info "Disabling SCM build during deployment for self-contained package..."
    local -a delete_appsettings_args=(
        webapp config appsettings delete
        --resource-group "$RESOURCE_GROUP"
        --name "$APP_NAME"
        --setting-names WEBSITE_RUN_FROM_PACKAGE PORT WEBSITES_PORT
    )

    if [[ -n "$SLOT" ]]; then
        delete_appsettings_args+=(--slot "$SLOT")
    fi

    az "${delete_appsettings_args[@]}" >/dev/null 2>&1 || true

    local -a appsettings_args=(
        webapp config appsettings set
        --resource-group "$RESOURCE_GROUP"
        --name "$APP_NAME"
        --settings SCM_DO_BUILD_DURING_DEPLOYMENT=false
        WEBSITES_ENABLE_APP_SERVICE_STORAGE=true
    )

    if [[ -n "$SLOT" ]]; then
        appsettings_args+=(--slot "$SLOT")
    fi

    az "${appsettings_args[@]}" >/dev/null

    local -a deploy_args=(
        webapp deployment source config-zip
        --resource-group "$RESOURCE_GROUP"
        --name "$APP_NAME"
        --src "$deploy_zip_path"
        --track-status true
        --timeout "$DEPLOY_TIMEOUT"
    )

    if [[ -n "$SLOT" ]]; then
        deploy_args+=(--slot "$SLOT")
    fi

    log_info "Deploying ${deploy_zip_path} to ${APP_NAME}${SLOT:+ slot ${SLOT}}..."
    az "${deploy_args[@]}"
    log_success "App deployment complete"
}

swap_portal_slot() {
    require_value "$RESOURCE_GROUP" "Resource group"
    require_value "$APP_NAME" "App Service name"
    require_value "$SLOT" "Slot"
    require_value "$TARGET_SLOT" "Target slot"

    log_info "Swapping slot ${SLOT} into ${TARGET_SLOT} for ${APP_NAME}..."
    az webapp deployment slot swap \
        --resource-group "$RESOURCE_GROUP" \
        --name "$APP_NAME" \
        --slot "$SLOT" \
        --target-slot "$TARGET_SLOT"
    log_success "Slot swap complete"
}

normalize_health_url() {
    local host_or_url="$1"

    if [[ "$host_or_url" =~ ^https?:// ]]; then
        echo "${host_or_url%/}${HEALTH_PATH}"
    else
        echo "https://${host_or_url}${HEALTH_PATH}"
    fi
}

verify_portal_health() {
    require_value "$HOSTNAME" "Hostname"

    local url
    local status
    local attempt

    url="$(normalize_health_url "$HOSTNAME")"
    log_info "Checking ${url} ..."

    for attempt in $(seq 1 "$HEALTH_RETRIES"); do
        status=$(curl -s -o /dev/null -w "%{http_code}" "$url")
        if [[ "$status" == "200" ]]; then
            log_success "Portal is healthy (HTTP ${status})"
            return 0
        fi

        log_warning "Attempt ${attempt}/${HEALTH_RETRIES}: HTTP ${status}; retrying in ${HEALTH_INTERVAL}s"
        sleep "$HEALTH_INTERVAL"
    done

    log_error "Health check failed for ${url} after ${HEALTH_RETRIES} attempts"
    exit 1
}

confirm_action() {
    local action="$1"

    if [[ "$AUTO_APPROVE" == "true" || "${CI:-false}" == "true" ]]; then
        return 0
    fi

    read -r -p "Proceed with '${action}' for ${ENVIRONMENT}? [y/N] " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        log_warning "Operation cancelled"
        exit 0
    fi
}

parse_args() {
    if [[ $# -eq 1 && ( "$1" == "--help" || "$1" == "-h" ) ]]; then
        usage 0
    fi

    if [[ $# -lt 2 ]]; then
        usage
    fi

    COMMAND="$1"
    ENVIRONMENT="$2"
    shift 2

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --auto-approve)
                AUTO_APPROVE=true
                ;;
            --state-key=*)
                STATE_KEY_OVERRIDE="${1#*=}"
                ;;
            --no-var-file)
                USE_VAR_FILE=false
                ;;
            --app-name=*)
                APP_NAME="${1#*=}"
                ;;
            --resource-group=*)
                RESOURCE_GROUP="${1#*=}"
                ;;
            --slot=*)
                SLOT="${1#*=}"
                ;;
            --target-slot=*)
                TARGET_SLOT="${1#*=}"
                ;;
            --src-path=*|--zip-path=*)
                ZIP_PATH="${1#*=}"
                ;;
            --hostname=*)
                HOSTNAME="${1#*=}"
                ;;
            --health-path=*)
                HEALTH_PATH="${1#*=}"
                ;;
            --health-retries=*)
                HEALTH_RETRIES="${1#*=}"
                ;;
            --health-interval=*)
                HEALTH_INTERVAL="${1#*=}"
                ;;
            --timeout=*)
                DEPLOY_TIMEOUT="${1#*=}"
                ;;
            --infra-only)
                SKIP_APP_DEPLOY=true
                ;;
            --help|-h)
                usage 0
                ;;
            -target=*|-replace=*|-var=*|-var-file=*|-lock=*|-lock-timeout=*|-parallelism=*|-refresh=*|-compact-warnings|-json|-no-color)
                TF_ARGS+=("$1")
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
        shift
    done
}

main() {
    parse_args "$@"
    validate_environment "$ENVIRONMENT"
    check_prerequisites

    case "$COMMAND" in
        init)
            setup_azure_auth
            run_terraform_init
            ;;
        fmt)
            setup_azure_auth
            log_info "Formatting Terraform files..."
            run_terraform_command fmt -recursive
            log_success "Terraform formatting complete"
            ;;
        validate)
            setup_azure_auth
            run_terraform_init
            log_info "Validating Terraform configuration..."
            run_terraform_command validate
            log_success "Terraform validation complete"
            ;;
        plan)
            setup_azure_auth
            mapfile -t common_args < <(terraform_common_args)
            run_terraform_init
            log_info "Creating Terraform plan for ${ENVIRONMENT}..."
            run_terraform_command plan -input=false "${common_args[@]}"
            ;;
        apply)
            setup_azure_auth
            setup_azure_cli_context
            mapfile -t common_args < <(terraform_common_args)
            run_terraform_init
            confirm_action "apply"
            log_info "Applying Terraform changes for ${ENVIRONMENT}..."
            if [[ "$AUTO_APPROVE" == "true" || "${CI:-false}" == "true" ]]; then
                run_terraform_command apply -input=false -auto-approve "${common_args[@]}"
            else
                run_terraform_command apply -input=false "${common_args[@]}"
            fi
            load_apply_outputs
            emit_apply_outputs
            deploy_after_apply
            log_success "Terraform apply complete"
            ;;
        destroy)
            setup_azure_auth
            mapfile -t common_args < <(terraform_common_args)
            run_terraform_init
            confirm_action "destroy"
            log_warning "Destroying Terraform resources for ${ENVIRONMENT}..."
            if [[ "$AUTO_APPROVE" == "true" || "${CI:-false}" == "true" ]]; then
                run_terraform_command destroy -input=false -auto-approve "${common_args[@]}"
            else
                run_terraform_command destroy -input=false "${common_args[@]}"
            fi
            log_success "Terraform destroy complete"
            ;;
        output)
            setup_azure_auth
            run_terraform_init
            run_terraform_command output -json
            ;;
        package-app)
            package_portal_app
            ;;
        deploy-app)
            setup_azure_cli_context
            deploy_portal_app
            ;;
        swap-slot)
            setup_azure_cli_context
            swap_portal_slot
            ;;
        health-check)
            verify_portal_health
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            usage
            ;;
    esac
}

main "$@"