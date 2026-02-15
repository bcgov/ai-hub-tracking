#!/bin/bash
# =============================================================================
# Terraform Stack Engine (Internal)
# =============================================================================
# Executes Terraform across isolated stack roots in dependency order:
#   Phase 1: shared
#   Phase 2: tenant (per-tenant, parallel)
#   Phase 3: foundry + apim + tenant-user-mgmt (all in parallel)
# For destroy, execution is reversed.
#
# This is an internal engine. The public entrypoint is `deploy-terraform.sh`.
#
# Auto-recovery:
#   - Removes deposed objects when delete returns 404
#   - Auto-imports existing Azure resources on apply when import hint exists
#   - Retries on transient Azure conflicts and connection errors
#
# Usage (delegated by deploy-terraform.sh):
#   ./scripts/deploy-scaled.sh <validate|plan|apply|destroy> <env> [...terraform args]
#
# Required environment variables:
#   BACKEND_RESOURCE_GROUP, BACKEND_STORAGE_ACCOUNT
#
# Optional environment variables:
#   BACKEND_CONTAINER_NAME=tfstate
#   TF_MAX_RECOVERY_RETRIES=5
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

COMMAND="${1:-}"
ENVIRONMENT="${2:-}"
shift 2 || true
EXTRA_ARGS=("$@")

BACKEND_RESOURCE_GROUP="${BACKEND_RESOURCE_GROUP:-}"
BACKEND_STORAGE_ACCOUNT="${BACKEND_STORAGE_ACCOUNT:-}"
BACKEND_CONTAINER_NAME="${BACKEND_CONTAINER_NAME:-tfstate}"

TF_MAX_RECOVERY_RETRIES="${TF_MAX_RECOVERY_RETRIES:-5}"

CURRENT_IMPORT_ARGS=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GRAY='\033[0;90m'
NC='\033[0m'

_ts() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }

log_info() {
  echo -e "${GRAY}$(_ts)${NC} ${BLUE}[INFO]${NC} $*"
}

log_success() {
  echo -e "${GRAY}$(_ts)${NC} ${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
  echo -e "${GRAY}$(_ts)${NC} ${YELLOW}[WARNING]${NC} $*" >&2
}

log_error() {
  echo -e "${GRAY}$(_ts)${NC} ${RED}[ERROR]${NC} $*" >&2
}

usage() {
  cat << EOF
Usage: $0 <validate|plan|apply|destroy> <environment> [terraform-options]
EOF
  exit 1
}

if [[ -z "${COMMAND}" || -z "${ENVIRONMENT}" ]]; then
  usage
fi

if [[ "${SCALED_CALLER:-}" != "deploy-terraform" ]]; then
  log_warning "Direct invocation detected. Prefer ./scripts/deploy-terraform.sh for full auth/variable/recovery parity."
fi

if [[ -z "${BACKEND_RESOURCE_GROUP}" || -z "${BACKEND_STORAGE_ACCOUNT}" ]]; then
  log_error "BACKEND_RESOURCE_GROUP and BACKEND_STORAGE_ACCOUNT must be set"
  exit 1
fi

run_capturing_output() {
  local description="$1"
  local log_file="$2"
  shift 2

  log_info "Starting ${description}"
  set +e
  "$@" 2>&1 | tee "${log_file}"
  local exit_code=${PIPESTATUS[0]}
  set -e

  if [[ $exit_code -eq 0 ]]; then
    log_success "${description} completed successfully"
    return 0
  fi

  log_error "${description} failed with exit code ${exit_code}"
  return "$exit_code"
}

extract_import_target_from_tf_output() {
  local tf_output_file="$1"
  local script_path="${INFRA_DIR}/scripts/extract-import-target.sh"

  if [[ -x "$script_path" ]]; then
    "$script_path" "$tf_output_file"
  else
    source "$script_path"
    extract_import_target "$tf_output_file"
  fi
}

tf_import_existing_resource_if_needed() {
  local tf_output_file="$1"

  local import_tf_args=()
  local arg
  for arg in "${CURRENT_IMPORT_ARGS[@]}"; do
    if [[ "$arg" =~ ^-var-file=/([a-zA-Z])/(.*)$ ]]; then
      local drive_letter
      local rest_path
      drive_letter="${BASH_REMATCH[1]}"
      rest_path="${BASH_REMATCH[2]}"
      import_tf_args+=("-var-file=${drive_letter^^}:/${rest_path}")
    else
      import_tf_args+=("$arg")
    fi
  done

  local import_lines
  import_lines="$({
    awk '
      function trim(s) {
        sub(/^[[:space:]]+/, "", s)
        sub(/[[:space:]]+$/, "", s)
        return s
      }

      function extract_addr(line, s) {
        if (match(line, /with[[:space:]]+[^,]+,/)) {
          s = substr(line, RSTART, RLENGTH)
          sub(/^with[[:space:]]+/, "", s)
          sub(/,$/, "", s)
          s = trim(s)

          if (s ~ /^error:/) {
            return ""
          }

          if (s ~ /[[:space:]]/) {
            return ""
          }

          if (s ~ /^module\./ || s ~ /^[[:alnum:]_]+\./) {
            return s
          }
        }
        return ""
      }

      function extract_id(line, s) {
        if (match(line, /ID[[:space:]]+\"[^\"]+\"/)) {
          s = substr(line, RSTART, RLENGTH)
          sub(/^ID[[:space:]]+\"/, "", s)
          sub(/\"$/, "", s)
          return trim(s)
        }

        if (match(line, /\\\"[^\\\"]+\\\"/)) {
          s = substr(line, RSTART, RLENGTH)
          sub(/^\\\"/, "", s)
          sub(/\\\"$/, "", s)
          return trim(s)
        }

        return ""
      }

      BEGIN {
        pending_id = ""
      }

      {
        gsub(/\r/, "", $0)
        line = $0

        if (line ~ /already exists/) {
          pending_id = ""
        }

        id = extract_id(line)
        if (id != "") {
          pending_id = id
        }

        addr = extract_addr(line)
        if (addr != "" && pending_id != "") {
          print addr "\t" pending_id
          pending_id = ""
        }
      }
    ' "$tf_output_file"
  } | awk '!seen[$0]++')"

  if [[ -z "$import_lines" ]]; then
    local import_line
    if ! import_line="$(extract_import_target_from_tf_output "$tf_output_file")"; then
      return 1
    fi
    import_lines="$import_line"
  fi

  local imported_any=false
  local failed_any=false

  while IFS=$'\t' read -r import_addr import_id; do
    [[ -z "$import_addr" || -z "$import_id" || "$import_addr" == "$import_id" ]] && continue

    log_warning "Detected existing Azure resource; importing into Terraform state"
    log_info "Import address: $import_addr"
    log_info "Import ID: $import_id"

    if MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' terraform import "${import_tf_args[@]}" "$import_addr" "$import_id"; then
      log_info "Import succeeded: $import_addr"
      imported_any=true
    else
      log_error "Import failed for: $import_addr"
      failed_any=true
    fi
  done <<< "$import_lines"

  if [[ "$failed_any" == "true" ]]; then
    return 2
  fi

  if [[ "$imported_any" == "true" ]]; then
    return 0
  fi

  return 1
}

tf_remove_deposed_object_if_needed() {
  local tf_output_file="$1"

  local deposed_resource
  deposed_resource=$(grep -oP '(?<=Error: deleting deposed object for )[^\s,]+' "$tf_output_file" 2>/dev/null | head -1)

  if [[ -z "$deposed_resource" ]]; then
    deposed_resource=$(grep -oP 'deposed object.*?(\S+\.\S+\[\d+\]|\S+\.\S+\.\S+\[\d+\]|\S+\.\S+\.\S+\.\S+\[\d+\])' "$tf_output_file" 2>/dev/null | grep -oP '\S+\[\d+\]$' | head -1)
  fi

  if [[ -z "$deposed_resource" ]]; then
    return 1
  fi

  if ! grep -qiE '(StatusCode=404|not found|does not exist|NoSuchResource)' "$tf_output_file" 2>/dev/null; then
    log_warning "Deposed object detected but error is not 404/not-found. Manual intervention required."
    return 1
  fi

  log_warning "Detected deposed object with 404 error (resource already deleted)"
  log_info "Deposed resource: $deposed_resource"

  if terraform state rm "$deposed_resource" 2>/dev/null; then
    log_info "Removed deposed object from state: $deposed_resource"
    return 0
  fi

  log_error "Failed to remove deposed object from state: $deposed_resource"
  return 2
}

# ── Plan guard: detect whether shared stack has usable outputs ───────────
# After a full destroy the remote state exists but contains no outputs.
# Downstream stacks (tenant/foundry/apim) reference those outputs via
# data.terraform_remote_state.shared and will error with "object with no
# attributes".  This helper lets plan stop early with a clear message
# instead of failing.
check_shared_outputs_available() {
  local shared_dir
  shared_dir="$(stack_dir shared)"
  local output_json
  if output_json="$(cd "$shared_dir" && terraform output -json 2>/dev/null)"; then
    # terraform output -json returns {} when there are no outputs
    if [[ "$output_json" == "{}" || -z "$output_json" ]]; then
      return 1
    fi
    return 0
  fi
  # terraform output itself failed (e.g. no state at all)
  return 1
}

tf_destroy_missing_shared_outputs_if_needed() {
  local tf_output_file="$1"

  if grep -qiE 'data\.terraform_remote_state\.shared\.outputs.*object with no attributes|object with no attributes.*data\.terraform_remote_state\.shared\.outputs' "$tf_output_file" 2>/dev/null; then
    local state_tmp
    state_tmp="$(mktemp "${INFRA_DIR}/.terraform-state-list-${ENVIRONMENT}-XXXXXX.log")"

    if terraform state list >"$state_tmp" 2>&1; then
      if [[ -s "$state_tmp" ]]; then
        log_error "Destroy cannot auto-skip missing shared outputs because current stack state is not empty"
        head -n 5 "$state_tmp" || true
        rm -f "$state_tmp"
        return 1
      fi

      log_warning "Destroy failed due missing shared outputs but current stack state is empty; treating stack as already dismantled"
      rm -f "$state_tmp"
      return 0
    fi

    log_warning "Unable to verify stack state after missing shared outputs error; will not auto-skip"
    rm -f "$state_tmp"
    return 1
  fi

  return 1
}

tf_destroy_subnet_in_use_retry_if_needed() {
  local tf_output_file="$1"

  if grep -qiE 'InUseSubnetCannotBeDeleted|serviceAssociationLinks/AppServiceLink' "$tf_output_file" 2>/dev/null; then
    log_warning "Detected transient subnet in-use association during destroy; waiting before retry"
    sleep 30
    return 0
  fi

  return 1
}

tf_request_conflict_retry_if_needed() {
  local tf_output_file="$1"

  if grep -qiE 'RequestConflict|AnotherOperationInProgress|Another operation is being performed on the parent resource|Another operation on this or dependent resource is in progress' "$tf_output_file" 2>/dev/null; then
    log_warning "Detected transient Azure resource conflict; waiting before retry"
    sleep 45
    return 0
  fi

  return 1
}

tf_transient_connection_retry_if_needed() {
  local tf_output_file="$1"

  if grep -qiE 'connection may have been reset|connection reset by peer|TLS handshake timeout|EOF|context deadline exceeded' "$tf_output_file" 2>/dev/null; then
    log_warning "Detected transient connection error; waiting before retry"
    sleep 15
    return 0
  fi

  return 1
}

tf_destroy_apim_backend_policy_if_needed() {
  local tf_output_file="$1"

  if ! grep -qiE "Backend.*is used by the following entities" "$tf_output_file" 2>/dev/null; then
    return 1
  fi

  log_warning "APIM backends cannot be deleted while referenced by policies"
  log_info "Destroying APIM API policies first..."

  local policy_targets=()
  while IFS= read -r addr; do
    [[ -n "$addr" ]] && policy_targets+=("-target=${addr}")
  done < <(terraform state list 2>/dev/null | grep 'azurerm_api_management_api_policy' || true)

  if [[ ${#policy_targets[@]} -eq 0 ]]; then
    log_warning "No API policy resources found in state to target"
    return 1
  fi

  local destroy_args=(-input=false -auto-approve)
  local arg
  for arg in "${CURRENT_IMPORT_ARGS[@]}"; do
    destroy_args+=("$arg")
  done

  if terraform destroy "${destroy_args[@]}" "${policy_targets[@]}"; then
    log_info "APIM API policies removed; retrying full destroy"
    return 0
  fi

  log_error "Failed to remove APIM API policies"
  return 1
}

run_terraform_with_retries() {
  local description="$1"
  local command="$2"
  shift 2
  local tf_args=("$@")

  local attempt=1
  while true; do
    local tf_output_file
    tf_output_file="$(mktemp "${INFRA_DIR}/.terraform-${command}-${ENVIRONMENT}-XXXXXX.log")"

    local tf_exit=0
    if run_capturing_output "${description} (attempt ${attempt}/${TF_MAX_RECOVERY_RETRIES})" "$tf_output_file" terraform "$command" "${tf_args[@]}"; then
      rm -f "$tf_output_file"
      return 0
    else
      tf_exit=$?
    fi
    local handled=false

    # Check for "already dismantled" condition first — skip immediately, no retry
    if [[ "$command" == "destroy" ]] && tf_destroy_missing_shared_outputs_if_needed "$tf_output_file"; then
      log_info "Stack already dismantled; skipping destroy"
      rm -f "$tf_output_file"
      return 0
    fi

    if tf_remove_deposed_object_if_needed "$tf_output_file"; then
      handled=true
    elif [[ "$command" == "apply" ]] && tf_import_existing_resource_if_needed "$tf_output_file"; then
      handled=true
    elif tf_request_conflict_retry_if_needed "$tf_output_file"; then
      handled=true
    elif tf_transient_connection_retry_if_needed "$tf_output_file"; then
      handled=true
    elif [[ "$command" == "destroy" ]] && tf_destroy_apim_backend_policy_if_needed "$tf_output_file"; then
      handled=true
    elif [[ "$command" == "destroy" ]] && tf_destroy_subnet_in_use_retry_if_needed "$tf_output_file"; then
      handled=true
    fi

    if [[ "$handled" == "true" ]]; then
      rm -f "$tf_output_file"
      attempt=$((attempt + 1))
      if [[ $attempt -gt $TF_MAX_RECOVERY_RETRIES ]]; then
        log_error "Exceeded maximum retries (${TF_MAX_RECOVERY_RETRIES}) for auto-recovery"
        return $tf_exit
      fi
      continue
    fi

    rm -f "$tf_output_file"
    return $tf_exit
  done
}

merge_all_tenants() {
  local shared_tfvars="${INFRA_DIR}/params/${ENVIRONMENT}/shared.tfvars"
  local tenants_dir="${INFRA_DIR}/params/${ENVIRONMENT}/tenants"
  local combined_file="${INFRA_DIR}/.tenants-${ENVIRONMENT}.auto.tfvars"

  [[ -f "$shared_tfvars" ]] || { echo "[ERROR] Missing $shared_tfvars" >&2; exit 1; }

  {
    echo "# Auto-generated"
    echo "tenants = {"
  } > "$combined_file"

  if [[ -d "$tenants_dir" ]]; then
    while IFS= read -r -d '' file; do
      local tenant_name
      tenant_name="$(basename "$(dirname "$file")")"
      local block_content
      block_content=$(awk '/^tenant[[:space:]]*=[[:space:]]*\{/,/^\}$/' "$file" | sed 's/^tenant[[:space:]]*=[[:space:]]*//')
      echo "  \"${tenant_name}\" = ${block_content}" >> "$combined_file"
    done < <(find "$tenants_dir" -name "tenant.tfvars" -type f -print0 | sort -z)
  fi

  echo "}" >> "$combined_file"
}

list_tenants() {
  find "${INFRA_DIR}/params/${ENVIRONMENT}/tenants" -name "tenant.tfvars" -type f 2>/dev/null | sort || true
}

build_single_tenant_tfvars() {
  local tenant_file="$1"
  local tenant_key
  tenant_key="$(basename "$(dirname "$tenant_file")")"
  local out_file="${INFRA_DIR}/.tenant-${ENVIRONMENT}-${tenant_key}.auto.tfvars"
  local block_content
  block_content=$(awk '/^tenant[[:space:]]*=[[:space:]]*\{/,/^\}$/' "$tenant_file" | sed 's/^tenant[[:space:]]*=[[:space:]]*//')

  {
    echo "# Auto-generated"
    echo "tenants = {"
    echo "  \"${tenant_key}\" = ${block_content}"
    echo "}"
  } > "$out_file"

  echo "$out_file"
}

stack_dir() {
  local stack="$1"
  echo "${INFRA_DIR}/stacks/${stack}"
}

stack_state_key() {
  local stack="$1"
  local tenant_key="${2:-}"
  case "$stack" in
    shared) echo "ai-services-hub/${ENVIRONMENT}/shared.tfstate" ;;
    tenant) echo "ai-services-hub/${ENVIRONMENT}/tenant-${tenant_key}.tfstate" ;;
    foundry) echo "ai-services-hub/${ENVIRONMENT}/foundry.tfstate" ;;
    apim) echo "ai-services-hub/${ENVIRONMENT}/apim.tfstate" ;;
    tenant-user-mgmt) echo "ai-services-hub/${ENVIRONMENT}/tenant-user-management.tfstate" ;;
    *) echo "" ;;
  esac
}

check_graph_permissions() {
  local token
  token=$(az account get-access-token \
    --resource https://graph.microsoft.com \
    --query accessToken -o tsv 2>/dev/null) || return 1

  [[ -n "${token:-}" ]] || return 1

  local http_status
  http_status=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${token}" \
    "https://graph.microsoft.com/v1.0/users?\$top=1&\$select=id" 2>/dev/null) || return 1

  [[ "$http_status" == "200" ]]
}

tf_init_stack() {
  local stack="$1"
  local tenant_key="${2:-}"
  local dir
  dir="$(stack_dir "$stack")"
  local key
  key="$(stack_state_key "$stack" "$tenant_key")"

  (
    cd "$dir"
    local init_log
    init_log="$(mktemp "${INFRA_DIR}/.terraform-init-${ENVIRONMENT}-XXXXXX.log")"
    local init_flags=(-input=false -upgrade -reconfigure)
    run_capturing_output "terraform init (${stack}${tenant_key:+:${tenant_key}})" \
      "$init_log" \
      terraform init "${init_flags[@]}" \
        -backend-config="resource_group_name=${BACKEND_RESOURCE_GROUP}" \
        -backend-config="storage_account_name=${BACKEND_STORAGE_ACCOUNT}" \
        -backend-config="container_name=${BACKEND_CONTAINER_NAME}" \
        -backend-config="key=${key}" \
        -backend-config="subscription_id=${ARM_SUBSCRIPTION_ID:-}" \
        -backend-config="tenant_id=${ARM_TENANT_ID:-}" \
        -backend-config="client_id=${TF_VAR_client_id:-}" \
        -backend-config="use_oidc=${ARM_USE_OIDC:-false}"
    rm -f "$init_log"
  )
}

tf_run_stack() {
  local stack="$1"
  local action="$2"
  local tfvars_file="$3"
  local tenant_key="${4:-}"
  local dir
  dir="$(stack_dir "$stack")"

  local base_tfvars=()

  # terraform.tfvars is gitignored — only present for local dev.
  # In GHA, these values come from TF_VAR_* environment variables.
  if [[ -f "${INFRA_DIR}/terraform.tfvars" ]]; then
    base_tfvars+=("-var-file=${INFRA_DIR}/terraform.tfvars")
  fi

  base_tfvars+=(
    "-var-file=${INFRA_DIR}/params/${ENVIRONMENT}/shared.tfvars"
  )

  if [[ -n "$tfvars_file" ]]; then
    base_tfvars+=("-var-file=${tfvars_file}")
  fi

  local backend_vars=(
    "-var=backend_resource_group=${BACKEND_RESOURCE_GROUP}"
    "-var=backend_storage_account=${BACKEND_STORAGE_ACCOUNT}"
    "-var=backend_container_name=${BACKEND_CONTAINER_NAME}"
  )

  local common_vars=(
    "-var=app_env=${ENVIRONMENT}"
  )

  (
    cd "$dir"
    case "$action" in
      validate)
        local validate_log
        validate_log="$(mktemp "${INFRA_DIR}/.terraform-validate-${ENVIRONMENT}-XXXXXX.log")"
        run_capturing_output "terraform validate (${stack}${tenant_key:+:${tenant_key}})" "$validate_log" terraform validate
        rm -f "$validate_log"
        ;;
      plan)
        CURRENT_IMPORT_ARGS=("${base_tfvars[@]}" "${backend_vars[@]}" "${common_vars[@]}")
        run_terraform_with_retries "terraform plan (${stack}${tenant_key:+:${tenant_key}})" plan \
          -input=false "${base_tfvars[@]}" "${backend_vars[@]}" "${common_vars[@]}" "${EXTRA_ARGS[@]}"
        ;;
      apply)
        local apply_args=(-input=false)
        if [[ "${CI:-false}" == "true" ]]; then
          apply_args+=(-auto-approve)
        fi
        CURRENT_IMPORT_ARGS=("${base_tfvars[@]}" "${backend_vars[@]}" "${common_vars[@]}")
        run_terraform_with_retries "terraform apply (${stack}${tenant_key:+:${tenant_key}})" apply \
          "${apply_args[@]}" "${base_tfvars[@]}" "${backend_vars[@]}" "${common_vars[@]}" "${EXTRA_ARGS[@]}"
        ;;
      destroy)
        local destroy_args=(-input=false)
        if [[ "${CI:-false}" == "true" ]]; then
          destroy_args+=(-auto-approve)
        fi
        CURRENT_IMPORT_ARGS=("${base_tfvars[@]}" "${backend_vars[@]}" "${common_vars[@]}")
        run_terraform_with_retries "terraform destroy (${stack}${tenant_key:+:${tenant_key}})" destroy \
          "${destroy_args[@]}" "${base_tfvars[@]}" "${backend_vars[@]}" "${common_vars[@]}" "${EXTRA_ARGS[@]}"
        ;;
      *)
        echo "Unknown action: $action" >&2
        exit 1
        ;;
    esac
  )
}

run_shared() {
  tf_init_stack shared
  tf_run_stack shared "$1" ""
}

run_single_tenant() {
  local action="$1"
  local tenant_file="$2"
  local parallel="${3:-false}"
  local tenant_key
  tenant_key="$(basename "$(dirname "$tenant_file")")"
  local tenant_tfvars
  tenant_tfvars="$(build_single_tenant_tfvars "$tenant_file")"

  if [[ "$parallel" == "true" ]]; then
    # Isolate .terraform/ dir per tenant so parallel inits don't collide
    export TF_DATA_DIR="${INFRA_DIR}/.terraform-tenant-${ENVIRONMENT}-${tenant_key}"
  fi

  tf_init_stack tenant "$tenant_key"
  tf_run_stack tenant "$action" "$tenant_tfvars" "$tenant_key"

  if [[ "$parallel" == "true" ]]; then
    rm -rf "${TF_DATA_DIR}"
    unset TF_DATA_DIR
  fi
}

run_tenant_per_tenant() {
  local action="$1"
  local tenant_files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    tenant_files+=("$f")
  done < <(list_tenants)

  if [[ ${#tenant_files[@]} -le 1 ]]; then
    # Single tenant — run inline (no overhead)
    for tf in "${tenant_files[@]}"; do
      run_single_tenant "$action" "$tf"
    done
    return
  fi

  # Multiple tenants — run in parallel
  log_info "Running ${#tenant_files[@]} tenants in parallel"
  local pids=()
  local keys=()
  local logs=()

  for tf in "${tenant_files[@]}"; do
    local tk
    tk="$(basename "$(dirname "$tf")")"
    local log_file="${INFRA_DIR}/.tenant-parallel-${ENVIRONMENT}-${tk}.log"
    keys+=("$tk")
    logs+=("$log_file")

    run_single_tenant "$action" "$tf" true > "$log_file" 2>&1 &
    pids+=($!)
  done

  # Wait for all, collect results
  local any_failed=false
  for i in "${!pids[@]}"; do
    local tenant_exit=0
    wait "${pids[$i]}" || tenant_exit=$?
    # Stream the captured log first (preserves chronological order)
    cat "${logs[$i]}"
    rm -f "${logs[$i]}"
    if [[ $tenant_exit -eq 0 ]]; then
      log_success "tenant:${keys[$i]} completed successfully"
    else
      log_error "tenant:${keys[$i]} failed (exit code $tenant_exit)"
      any_failed=true
    fi
  done

  if [[ "$any_failed" == "true" ]]; then
    log_error "One or more tenant deployments failed"
    return 1
  fi
}

run_foundry() {
  tf_init_stack foundry
  # Serialize operations to avoid RequestConflict on AI model deployments
  # (Azure allows only one deployment operation at a time per Cognitive Services account)
  local saved_extra=("${EXTRA_ARGS[@]}")
  EXTRA_ARGS+=("-parallelism=1")
  tf_run_stack foundry "$1" "${INFRA_DIR}/.tenants-${ENVIRONMENT}.auto.tfvars"
  EXTRA_ARGS=("${saved_extra[@]}")
}

run_apim() {
  tf_init_stack apim
  tf_run_stack apim "$1" "${INFRA_DIR}/.tenants-${ENVIRONMENT}.auto.tfvars"
}

run_tenant_user_mgmt() {
  local action="$1"

  if ! check_graph_permissions; then
    echo "[WARNING] Skipping tenant-user-mgmt in scaled flow — Graph User.Read.All not available"
    return 0
  fi

  tf_init_stack tenant-user-mgmt
  tf_run_stack tenant-user-mgmt "$action" "${INFRA_DIR}/.tenants-${ENVIRONMENT}.auto.tfvars"
}

# ---------------------------------------------------------------------------
# Phase 3 parallel runner — foundry + apim + tenant-user-mgmt are independent
# of each other and can run concurrently once shared+tenant are done.
# ---------------------------------------------------------------------------
run_phase3_parallel() {
  local action="$1"
  local names=("foundry" "apim" "tenant-user-mgmt")
  local runners=("run_foundry" "run_apim" "run_tenant_user_mgmt")
  local pids=()
  local logs=()

  log_info "Running phase-3 stacks in parallel: ${names[*]}"

  for i in "${!runners[@]}"; do
    local log_file="${INFRA_DIR}/.phase3-${ENVIRONMENT}-${names[$i]}.log"
    logs+=("$log_file")
    ${runners[$i]} "$action" > "$log_file" 2>&1 &
    pids+=($!)
  done

  local any_failed=false
  for i in "${!pids[@]}"; do
    local exit_code=0
    wait "${pids[$i]}" || exit_code=$?
    cat "${logs[$i]}"
    rm -f "${logs[$i]}"
    if [[ $exit_code -eq 0 ]]; then
      log_success "${names[$i]} completed successfully"
    else
      log_error "${names[$i]} failed (exit code $exit_code)"
      any_failed=true
    fi
  done

  if [[ "$any_failed" == "true" ]]; then
    log_error "One or more phase-3 stacks failed"
    return 1
  fi
}

run_tenant_per_tenant_destroy() {
  local tenant_files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    tenant_files+=("$f")
  done < <(list_tenants | sort -r)

  if [[ ${#tenant_files[@]} -le 1 ]]; then
    for tf in "${tenant_files[@]}"; do
      run_single_tenant destroy "$tf"
    done
    return
  fi

  # Multiple tenants — destroy in parallel
  log_info "Destroying ${#tenant_files[@]} tenants in parallel"
  local pids=()
  local keys=()
  local logs=()

  for tf in "${tenant_files[@]}"; do
    local tk
    tk="$(basename "$(dirname "$tf")")"
    local log_file="${INFRA_DIR}/.tenant-parallel-${ENVIRONMENT}-${tk}.log"
    keys+=("$tk")
    logs+=("$log_file")

    run_single_tenant destroy "$tf" true > "$log_file" 2>&1 &
    pids+=($!)
  done

  local any_failed=false
  for i in "${!pids[@]}"; do
    local tenant_exit=0
    wait "${pids[$i]}" || tenant_exit=$?
    cat "${logs[$i]}"
    rm -f "${logs[$i]}"
    if [[ $tenant_exit -eq 0 ]]; then
      log_success "tenant:${keys[$i]} destroy completed successfully"
    else
      log_error "tenant:${keys[$i]} destroy failed (exit code $tenant_exit)"
      any_failed=true
    fi
  done

  if [[ "$any_failed" == "true" ]]; then
    log_error "One or more tenant destroys failed"
    return 1
  fi
}

merge_all_tenants

SCALED_START_TIME=$SECONDS
log_info "Stack engine started at $(_ts) — command: ${COMMAND}, environment: ${ENVIRONMENT}"

case "$COMMAND" in
  validate)
    run_shared validate
    run_tenant_per_tenant validate
    run_phase3_parallel validate
    ;;
  plan)
    run_shared plan
    if ! check_shared_outputs_available; then
      log_warning "Shared stack has no outputs (clean/destroyed environment). Downstream stacks (tenant, foundry, apim, tenant-user-mgmt) cannot be planned until shared is applied."
      log_info "Only the shared plan is available. Run 'apply <env> --auto-approve' to bootstrap the environment first."
      exit 0
    fi
    run_tenant_per_tenant plan
    run_phase3_parallel plan
    ;;
  apply)
    run_shared apply
    run_tenant_per_tenant apply
    run_phase3_parallel apply
    ;;
  destroy)
    run_phase3_parallel destroy
    run_tenant_per_tenant_destroy
    run_shared destroy
    ;;
  *)
    echo "Unknown command: $COMMAND" >&2
    exit 1
    ;;
esac

scaled_elapsed=$(( SECONDS - SCALED_START_TIME ))
scaled_mins=$(( scaled_elapsed / 60 ))
scaled_secs=$(( scaled_elapsed % 60 ))
log_success "Stack engine finished at $(_ts) — total time: ${scaled_mins}m ${scaled_secs}s"
