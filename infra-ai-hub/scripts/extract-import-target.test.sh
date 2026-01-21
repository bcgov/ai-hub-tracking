#!/usr/bin/env bash
# extract-import-target.test.sh
# Test suite for extract-import-target.sh
#
# Usage:
#   ./extract-import-target.test.sh
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACT_SCRIPT="${SCRIPT_DIR}/extract-import-target.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

log_test() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
}

run_test() {
    local test_name="$1"
    local input="$2"
    local expected_exit="$3"
    local expected_addr="${4:-}"
    local expected_id="${5:-}"

    TESTS_RUN=$((TESTS_RUN + 1))
    log_test "$test_name"

    local output
    local actual_exit
    set +e
    output=$(echo "$input" | "$EXTRACT_SCRIPT" -)
    actual_exit=$?
    set -e

    if [[ $actual_exit -ne $expected_exit ]]; then
        log_fail "Expected exit code $expected_exit, got $actual_exit"
        return 1
    fi

    if [[ $expected_exit -eq 0 ]]; then
        local actual_addr="${output%%$'\t'*}"
        local actual_id="${output#*$'\t'}"

        if [[ "$actual_addr" != "$expected_addr" ]]; then
            log_fail "Expected address '$expected_addr', got '$actual_addr'"
            return 1
        fi

        if [[ "$actual_id" != "$expected_id" ]]; then
            log_fail "Expected ID '$expected_id', got '$actual_id'"
            return 1
        fi
    fi

    log_pass "$test_name"
    return 0
}

# =============================================================================
# POSITIVE TEST CASES
# =============================================================================

echo ""
echo "=========================================="
echo "POSITIVE TEST CASES"
echo "=========================================="

# Test 1: Standard single-line "already exists" error
run_test "Standard single-line error" \
'│ Error: a resource with the ID "/subscriptions/12345678-1234-5678-9abc-def012345678/resourceGroups/my-rg/providers/Microsoft.Web/sites/my-webapp" already exists - to be managed via Terraform this resource needs to be imported into the State.
│ 
│   with module.frontend[0].azurerm_linux_web_app.frontend,
│   on modules/frontend/main.tf line 15, in resource "azurerm_linux_web_app" "frontend":
│   15: resource "azurerm_linux_web_app" "frontend" {' \
    0 \
    "module.frontend[0].azurerm_linux_web_app.frontend" \
    "/subscriptions/12345678-1234-5678-9abc-def012345678/resourceGroups/my-rg/providers/Microsoft.Web/sites/my-webapp"

# Test 2: Multi-line error with repeated ID
run_test "Multi-line error with repeated ID" \
'│ Error: a resource with the ID "/subscriptions/aaa/resourceGroups/rg/providers/Microsoft.Web/sites/app" already exists - to be managed via Terraform
│ 
│   with module.frontend[0].azurerm_linux_web_app.frontend,
│   on modules/frontend/main.tf line 15, in resource "azurerm_linux_web_app" "frontend":
│   15: resource "azurerm_linux_web_app" "frontend" {
│ 
│ a resource with the ID
│ "/subscriptions/aaa/resourceGroups/rg/providers/Microsoft.Web/sites/app"
│ already exists - to be managed via Terraform' \
    0 \
    "module.frontend[0].azurerm_linux_web_app.frontend" \
    "/subscriptions/aaa/resourceGroups/rg/providers/Microsoft.Web/sites/app"

# Test 3: Error with other resource IDs in the output (should pick the one with "already exists")
run_test "Multiple resource IDs - picks correct one" \
'module.network.data.azurerm_virtual_network.main: Read complete [id=/subscriptions/xxx/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet]
╷
│ Error: a resource with the ID "/subscriptions/yyy/resourceGroups/rg/providers/Microsoft.Web/sites/webapp" already exists
│ 
│   with module.backend[0].azurerm_linux_web_app.backend,
│   on modules/backend/main.tf line 20
╵
module.something.data.azurerm_subnet.sub: Reading... [id=/subscriptions/zzz/resourceGroups/rg/providers/Microsoft.Network/subnets/sub]' \
    0 \
    "module.backend[0].azurerm_linux_web_app.backend" \
    "/subscriptions/yyy/resourceGroups/rg/providers/Microsoft.Web/sites/webapp"

# Test 4: Container App resource
run_test "Container App resource" \
'│ Error: a resource with the ID "/subscriptions/sub123/resourceGroups/rg/providers/Microsoft.App/containerApps/my-container-app" already exists
│ 
│   with module.container_apps.azurerm_container_app.app["api"],
│   on modules/container-apps/main.tf line 50' \
    0 \
    'module.container_apps.azurerm_container_app.app["api"]' \
    "/subscriptions/sub123/resourceGroups/rg/providers/Microsoft.App/containerApps/my-container-app"

# Test 5: Storage Account resource
run_test "Storage Account resource" \
'│ Error: a resource with the ID "/subscriptions/sub456/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/mystorageacct" already exists - to be managed via Terraform
│ 
│   with azurerm_storage_account.main,
│   on main.tf line 100' \
    0 \
    "azurerm_storage_account.main" \
    "/subscriptions/sub456/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/mystorageacct"

# Test 6: Key Vault resource with complex module path
run_test "Key Vault with complex module path" \
'│ Error: a resource with the ID "/subscriptions/sub789/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/my-kv" already exists
│ 
│   with module.security[0].module.keyvault.azurerm_key_vault.main,
│   on modules/security/keyvault/main.tf line 5' \
    0 \
    "module.security[0].module.keyvault.azurerm_key_vault.main" \
    "/subscriptions/sub789/resourceGroups/rg/providers/Microsoft.KeyVault/vaults/my-kv"

# Test 7: PostgreSQL Flexible Server
run_test "PostgreSQL Flexible Server" \
'│ Error: a resource with the ID "/subscriptions/abc/resourceGroups/rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/my-pg-server" already exists
│ 
│   with module.postgresql.azurerm_postgresql_flexible_server.main,
│   on modules/postgresql/main.tf line 1' \
    0 \
    "module.postgresql.azurerm_postgresql_flexible_server.main" \
    "/subscriptions/abc/resourceGroups/rg/providers/Microsoft.DBforPostgreSQL/flexibleServers/my-pg-server"

# Test 8: Resource without module prefix
run_test "Resource without module prefix" \
'│ Error: a resource with the ID "/subscriptions/def/resourceGroups/rg/providers/Microsoft.Web/serverfarms/my-plan" already exists
│ 
│   with azurerm_service_plan.main,
│   on main.tf line 50' \
    0 \
    "azurerm_service_plan.main" \
    "/subscriptions/def/resourceGroups/rg/providers/Microsoft.Web/serverfarms/my-plan"

# Test 9: Resource with for_each string key
run_test "Resource with for_each string key" \
'│ Error: a resource with the ID "/subscriptions/ghi/resourceGroups/rg/providers/Microsoft.Network/networkSecurityGroups/nsg-web" already exists
│ 
│   with azurerm_network_security_group.nsgs["web"],
│   on network.tf line 30' \
    0 \
    'azurerm_network_security_group.nsgs["web"]' \
    "/subscriptions/ghi/resourceGroups/rg/providers/Microsoft.Network/networkSecurityGroups/nsg-web"

# Test 10: Very long resource ID (realistic Azure path)
run_test "Long resource ID path" \
'│ Error: a resource with the ID "/subscriptions/12345678-1234-5678-9abc-def012345678/resourceGroups/quickstart-azure-containers-tools/providers/Microsoft.Web/sites/quickstart-azure-containers-tools-frontend" already exists
│ 
│   with module.frontend[0].azurerm_linux_web_app.frontend,
│   on modules/frontend/main.tf line 15' \
    0 \
    "module.frontend[0].azurerm_linux_web_app.frontend" \
    "/subscriptions/12345678-1234-5678-9abc-def012345678/resourceGroups/quickstart-azure-containers-tools/providers/Microsoft.Web/sites/quickstart-azure-containers-tools-frontend"

# Test 10b: Diagnostic Setting ID contains a pipe and may be escaped in logs
run_test "Diagnostic setting ID with pipe" \
'│ Error: a resource with the ID \"/subscriptions/sub123/resourceGroups/quickstart-azure-containers-tools/providers/Microsoft.App/managedEnvironments/env123|diag-setting-name\" already exists - to be managed via Terraform
│
│   with module.container_apps[0].azurerm_monitor_diagnostic_setting.container_app_env_diagnostics,
│   on modules/container-apps/main.tf line 288, in resource "azurerm_monitor_diagnostic_setting" "container_app_env_diagnostics":
│  288: resource "azurerm_monitor_diagnostic_setting" "container_app_env_diagnostics" {' \
    0 \
    "module.container_apps[0].azurerm_monitor_diagnostic_setting.container_app_env_diagnostics" \
    "/subscriptions/sub123/resourceGroups/quickstart-azure-containers-tools/providers/Microsoft.App/managedEnvironments/env123|diag-setting-name"

# =============================================================================
# NEGATIVE TEST CASES
# =============================================================================

echo ""
echo "=========================================="
echo "NEGATIVE TEST CASES"
echo "=========================================="

# Test 11: No error at all - successful apply
run_test "Successful apply (no error)" \
'Apply complete! Resources: 5 added, 2 changed, 0 destroyed.

Outputs:

frontend_url = "https://myapp.azurewebsites.net"' \
    1

# Test 12: Different error type - validation error
run_test "Validation error (not already exists)" \
'│ Error: Invalid value for variable
│ 
│   on variables.tf line 10:
│   10: variable "environment" {
│ 
│ The value "prod" is not valid. Must be one of: dev, staging, production.' \
    1

# Test 13: Different error type - provider error
run_test "Provider authentication error" \
'│ Error: Error building AzureRM Client: obtain subscription() from Azure CLI: parsing json result from the Azure CLI: waiting for the Azure CLI: exit status 1
│ 
│   with provider["registry.terraform.io/hashicorp/azurerm"],
│   on providers.tf line 10, in provider "azurerm":' \
    1

# Test 14: "already exists" text but no resource ID
run_test "already exists text without resource ID" \
'│ Error: The resource name already exists in a different location
│ 
│   with azurerm_resource_group.main,
│   on main.tf line 5' \
    1

# Test 15: Resource ID present but no "already exists"
run_test "Resource ID without already exists error" \
'│ Error: deleting resource "/subscriptions/abc/resourceGroups/rg/providers/Microsoft.Web/sites/app": unexpected status 409
│ 
│   with module.frontend[0].azurerm_linux_web_app.frontend,
│   on modules/frontend/main.tf line 15' \
    1

# Test 16: Empty input
run_test "Empty input" \
'' \
    1

# Test 17: Only whitespace
run_test "Only whitespace" \
'   
   
   ' \
    1

# Test 18: "already exists" in a comment/docs, not an error
run_test "already exists in documentation" \
'# Note: If the resource already exists in Azure, you need to import it first.
# Run: terraform import module.frontend.azurerm_linux_web_app.frontend <resource_id>

Apply complete! Resources: 3 added, 0 changed, 0 destroyed.' \
    1

# Test 19: Dependency lock error
run_test "Dependency lock error" \
'│ Error: Inconsistent dependency lock file
│ 
│ The following dependency selections recorded in the lock file are
│ inconsistent with the current configuration:
│   - provider registry.terraform.io/hashicorp/azurerm: locked version selection 3.0.0 doesn'\''t match the updated version constraints "~> 4.0"' \
    1

# Test 20: Module not found error
run_test "Module not found error" \
'│ Error: Module not installed
│ 
│   on main.tf line 50:
│   50: module "frontend" {
│ 
│ This module is not yet installed. Run "terraform init" to install all modules required by this configuration.' \
    1

# Test 21: State lock error
run_test "State lock error" \
'│ Error: Error acquiring the state lock
│ 
│ Error message: state blob is already locked
│ Lock Info:
│   ID:        12345678-1234-5678-9abc-def012345678
│   Path:      terraform.tfstate
│   Operation: OperationTypeApply' \
    1

# Test 22: Resource with "with" but different error
run_test "Resource reference without already exists" \
'│ Error: Invalid resource type
│ 
│   with module.frontend[0].azurerm_linux_web_app.frontend,
│   on modules/frontend/main.tf line 15
│ 
│ The provider hashicorp/azurerm does not support resource type "azurerm_linux_web_app_typo".' \
    1

# =============================================================================
# EDGE CASES
# =============================================================================

echo ""
echo "=========================================="
echo "EDGE CASES"
echo "=========================================="

# Test 23: Multiple "already exists" errors (return the last one, typically the final failure)
run_test "Multiple already exists errors - returns last" \
'│ Error: a resource with the ID "/subscriptions/aaa/resourceGroups/rg/providers/Microsoft.Web/sites/app1" already exists
│ 
│   with module.frontend[0].azurerm_linux_web_app.app1,
│   on modules/frontend/main.tf line 15
╵
╷
│ Error: a resource with the ID "/subscriptions/bbb/resourceGroups/rg/providers/Microsoft.Web/sites/app2" already exists
│ 
│   with module.frontend[1].azurerm_linux_web_app.app2,
│   on modules/frontend/main.tf line 30' \
    0 \
    "module.frontend[1].azurerm_linux_web_app.app2" \
    "/subscriptions/bbb/resourceGroups/rg/providers/Microsoft.Web/sites/app2"

# Test 24: Mixed line endings
run_test "CRLF line endings" \
$'│ Error: a resource with the ID "/subscriptions/xyz/resourceGroups/rg/providers/Microsoft.Web/sites/app" already exists\r\n│ \r\n│   with module.app.azurerm_linux_web_app.main,\r\n│   on main.tf line 5' \
    0 \
    "module.app.azurerm_linux_web_app.main" \
    "/subscriptions/xyz/resourceGroups/rg/providers/Microsoft.Web/sites/app"

# Test 25: Resource ID with special characters in name
run_test "Resource name with hyphens and numbers" \
'│ Error: a resource with the ID "/subscriptions/sub/resourceGroups/my-rg-123/providers/Microsoft.Web/sites/my-app-prod-v2-001" already exists
│ 
│   with module.frontend[0].azurerm_linux_web_app.frontend,
│   on main.tf line 10' \
    0 \
    "module.frontend[0].azurerm_linux_web_app.frontend" \
    "/subscriptions/sub/resourceGroups/my-rg-123/providers/Microsoft.Web/sites/my-app-prod-v2-001"

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo "=========================================="
echo "TEST SUMMARY"
echo "=========================================="
echo -e "Tests run:    ${TESTS_RUN}"
echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Tests failed: ${RED}${TESTS_FAILED}${NC}"

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo ""
    echo -e "${RED}SOME TESTS FAILED${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    exit 0
fi
