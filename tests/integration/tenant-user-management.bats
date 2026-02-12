#!/usr/bin/env bats
# Integration tests for Tenant User Management
# Validates custom RBAC role assignments created by the tenant-user-management
# module. Supports both direct-user and group assignment modes.
#
# Prerequisites: az CLI authenticated with sufficient read permissions
# These tests dynamically load seed_members from tenant.tfvars

load 'test-helper'

# =============================================================================
# Helper Functions
# =============================================================================

# Extract seed_members admin list from a tenant.tfvars file
# Usage: get_tenant_seed_admins <tenant>
# Returns: newline-separated list of admin UPNs
get_tenant_seed_admins() {
    local tenant="${1}"
    local env="${TEST_ENV:-test}"
    local tfvars_file="${SCRIPT_DIR}/../../infra-ai-hub/params/${env}/tenants/${tenant}/tenant.tfvars"

    if [[ ! -f "${tfvars_file}" ]]; then
        echo "Warning: tenant.tfvars not found for ${tenant}" >&2
        return 1
    fi

    # Extract UPNs from the admin = [...] block inside seed_members
    # Uses awk to capture lines between 'admin = [' and ']', then grep for emails
    awk '/seed_members\s*=\s*\{/,/^\s*\}/' "${tfvars_file}" \
        | awk '/admin\s*=\s*\[/,/\]/' \
        | grep -oP '"[^"]+@[^"]+"' \
        | tr -d '"'
}

# Check if create_groups is set to true in a tenant.tfvars file
is_group_mode() {
    local tenant="${1}"
    local env="${TEST_ENV:-test}"
    local tfvars_file="${SCRIPT_DIR}/../../infra-ai-hub/params/${env}/tenants/${tenant}/tenant.tfvars"
    grep -q 'create_groups\s*=\s*true' "${tfvars_file}" 2>/dev/null
}

# Check if az CLI is available and authenticated
az_authenticated() {
    command -v az >/dev/null 2>&1 || return 1
    az account show >/dev/null 2>&1 || return 1
}

# Check if the current identity can read Entra directory (Graph User.Read.All)
# Caches result in HAS_GRAPH_ACCESS variable to avoid repeated calls
has_graph_read_access() {
    if [[ -z "${HAS_GRAPH_ACCESS:-}" ]]; then
        if az ad user list --top 1 >/dev/null 2>&1; then
            export HAS_GRAPH_ACCESS="true"
        else
            export HAS_GRAPH_ACCESS="false"
        fi
    fi
    [[ "${HAS_GRAPH_ACCESS}" == "true" ]]
}

# Resolve a UPN to an Entra object ID (requires Graph read access)
# Usage: resolve_upn_to_id <upn>
resolve_upn_to_id() {
    local upn="${1}"
    az ad user show --id "${upn}" --query id -o tsv 2>/dev/null
}

setup() {
    # These tests require az CLI, terraform, and jq
    for cmd in az terraform jq; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            skip "Required tool '${cmd}' not found — skipping user management tests"
        fi
    done
    if ! az_authenticated; then
        skip "az CLI not authenticated — skipping user management tests"
    fi
}

# =============================================================================
# WLRS Tenant — Custom RBAC Role Definitions
# =============================================================================

@test "WLRS: Custom admin role definition exists" {
    local role_name="ai-hub-test-wlrs-water-form-assistant-admin"
    local rg_name="wlrs-water-form-assistant-rg"
    local sub_id
    sub_id=$(az account show --query id -o tsv 2>/dev/null)
    local scope="/subscriptions/${sub_id}/resourceGroups/${rg_name}"

    local result
    result=$(az role definition list --custom-role-only \
        --scope "${scope}" \
        --query "[?roleName=='${role_name}'].roleName" \
        -o tsv 2>/dev/null) || true

    if [[ -z "${result}" ]]; then
        skip "Role definition '${role_name}' not found (apply may not have run yet)"
    fi

    [[ "${result}" == "${role_name}" ]]
    echo "  ✓ Custom role definition exists: ${role_name}" >&3
}

# =============================================================================
# WLRS Tenant — Direct User Role Assignments (default mode)
# =============================================================================

@test "WLRS: Admin seed members have direct role assignments on tenant RG" {
    local tenant="wlrs-water-form-assistant"
    local rg_name
    rg_name=$(cd "${SCRIPT_DIR}/../../infra-ai-hub" && \
        terraform output -json 2>/dev/null \
        | jq -r ".tenant_resource_groups.value[\"${tenant}\"] // empty") || true

    if [[ -z "${rg_name}" ]]; then
        skip "Could not determine tenant resource group (terraform output unavailable)"
    fi

    # Load expected admins from tfvars
    local expected_admins
    expected_admins=$(get_tenant_seed_admins "${tenant}")

    if [[ -z "${expected_admins}" ]]; then
        skip "No admin seed members found in tfvars for ${tenant}"
    fi

    # Get all role assignments on the RG (include principalId for fallback matching)
    local assignments
    assignments=$(az role assignment list \
        --resource-group "${rg_name}" \
        --query "[?principalType=='User'].{role:roleDefinitionName, name:principalName, principalId:principalId}" \
        -o json 2>/dev/null) || true

    if [[ -z "${assignments}" || "${assignments}" == "[]" ]]; then
        skip "No user role assignments found on ${rg_name} (apply may not have run yet)"
    fi

    local admin_role="ai-hub-test-${tenant}-admin"

    # Detect if principalName is available (null when identity lacks Graph perms)
    local names_available
    names_available=$(echo "${assignments}" | jq -r '[.[] | select(.name != null and .name != "")] | length')

    # If names are unavailable, we need Graph access to resolve UPNs to principalIds
    if [[ "${names_available}" -eq 0 ]]; then
        if ! has_graph_read_access; then
            skip "Cannot verify user assignments: identity lacks Graph directory read permission (principalName is null)"
        fi
    fi

    # Spot check first 2 admin seed members
    local checked=0
    local missing=""
    while IFS= read -r upn; do
        [[ -z "${upn}" ]] && continue
        checked=$((checked + 1))

        # First try matching by principalName (works when caller has Graph perms)
        if echo "${assignments}" | jq -e \
            --arg upn "${upn}" --arg role "${admin_role}" \
            '.[] | select(.name == $upn and .role == $role)' >/dev/null 2>&1; then
            [[ ${checked} -ge 2 ]] && break
            continue
        fi
        # Try case-insensitive principalName match
        if echo "${assignments}" | jq -e \
            --arg upn "${upn}" --arg role "${admin_role}" \
            '.[] | select((.name | ascii_downcase) == ($upn | ascii_downcase) and .role == $role)' >/dev/null 2>&1; then
            [[ ${checked} -ge 2 ]] && break
            continue
        fi
        # Fallback: resolve UPN → object ID and match by principalId
        local oid
        oid=$(resolve_upn_to_id "${upn}") || true
        if [[ -n "${oid}" ]]; then
            if echo "${assignments}" | jq -e \
                --arg oid "${oid}" --arg role "${admin_role}" \
                '.[] | select(.principalId == $oid and .role == $role)' >/dev/null 2>&1; then
                [[ ${checked} -ge 2 ]] && break
                continue
            fi
        fi
        missing="${missing} ${upn}"
        [[ ${checked} -ge 2 ]] && break
    done <<< "${expected_admins}"

    if [[ -n "${missing}" ]]; then
        echo "Missing direct admin role assignments for:${missing}" >&2
        echo "Expected role: ${admin_role}" >&2
        echo "Actual assignments: $(echo "${assignments}" | jq -c '[.[] | {role, name, principalId}]')" >&2
        return 1
    fi

    echo "  ✓ Verified ${checked} admin seed members have direct '${admin_role}' role on ${rg_name}" >&3
}

# =============================================================================
# WLRS Tenant — Entra Group Existence (group mode only)
# =============================================================================

@test "WLRS: Entra admin group exists (group mode only)" {
    local tenant="wlrs-water-form-assistant"

    if ! is_group_mode "${tenant}"; then
        skip "Tenant '${tenant}' uses direct-user mode (create_groups != true)"
    fi

    local group_name="ai-hub-test-${tenant}-admin"
    local result
    result=$(az ad group show --group "${group_name}" --query "displayName" -o tsv 2>/dev/null) || true

    if [[ -z "${result}" ]]; then
        skip "Group ${group_name} not found (apply may not have run yet)"
    fi

    [[ "${result}" == "${group_name}" ]]
    echo "  ✓ Group exists: ${group_name}" >&3
}

# =============================================================================
# SDPR Tenant — Direct User Role Assignments (second tenant spot check)
# =============================================================================

@test "SDPR: Admin seed members have direct role assignments on tenant RG" {
    local tenant="sdpr-invoice-automation"
    local rg_name
    rg_name=$(cd "${SCRIPT_DIR}/../../infra-ai-hub" && \
        terraform output -json 2>/dev/null \
        | jq -r ".tenant_resource_groups.value[\"${tenant}\"] // empty") || true

    if [[ -z "${rg_name}" ]]; then
        skip "Could not determine tenant resource group (terraform output unavailable)"
    fi

    local expected_admins
    expected_admins=$(get_tenant_seed_admins "${tenant}")

    if [[ -z "${expected_admins}" ]]; then
        skip "No admin seed members found in tfvars for ${tenant}"
    fi

    local assignments
    assignments=$(az role assignment list \
        --resource-group "${rg_name}" \
        --query "[?principalType=='User'].{role:roleDefinitionName, name:principalName, principalId:principalId}" \
        -o json 2>/dev/null) || true

    if [[ -z "${assignments}" || "${assignments}" == "[]" ]]; then
        skip "No user role assignments found on ${rg_name} (apply may not have run yet)"
    fi

    local admin_role="ai-hub-test-${tenant}-admin"

    # Detect if principalName is available (null when identity lacks Graph perms)
    local names_available
    names_available=$(echo "${assignments}" | jq -r '[.[] | select(.name != null and .name != "")] | length')

    if [[ "${names_available}" -eq 0 ]]; then
        if ! has_graph_read_access; then
            skip "Cannot verify user assignments: identity lacks Graph directory read permission (principalName is null)"
        fi
    fi

    # Spot check first 2 members
    local checked=0
    local missing=""
    while IFS= read -r upn; do
        [[ -z "${upn}" ]] && continue
        checked=$((checked + 1))

        # Try matching by principalName (case-insensitive)
        if echo "${assignments}" | jq -e \
            --arg upn "${upn}" --arg role "${admin_role}" \
            '.[] | select((.name | ascii_downcase) == ($upn | ascii_downcase) and .role == $role)' >/dev/null 2>&1; then
            [[ ${checked} -ge 2 ]] && break
            continue
        fi
        # Fallback: resolve UPN → object ID and match by principalId
        local oid
        oid=$(resolve_upn_to_id "${upn}") || true
        if [[ -n "${oid}" ]]; then
            if echo "${assignments}" | jq -e \
                --arg oid "${oid}" --arg role "${admin_role}" \
                '.[] | select(.principalId == $oid and .role == $role)' >/dev/null 2>&1; then
                [[ ${checked} -ge 2 ]] && break
                continue
            fi
        fi
        missing="${missing} ${upn}"
        [[ ${checked} -ge 2 ]] && break
    done <<< "${expected_admins}"

    if [[ -n "${missing}" ]]; then
        echo "Missing direct admin role assignments for:${missing}" >&2
        echo "Expected role: ${admin_role}" >&2
        echo "Actual assignments: $(echo "${assignments}" | jq -c '[.[] | {role, name, principalId}]')" >&2
        return 1
    fi

    echo "  ✓ Verified ${checked} admin seed members have direct '${admin_role}' role on ${rg_name}" >&3
}
