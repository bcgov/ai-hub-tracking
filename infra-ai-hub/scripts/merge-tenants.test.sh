#!/bin/bash
# =============================================================================
# Test Script for Tenant Merging in deploy-terraform.sh
# =============================================================================
# Tests the setup_variables function that merges individual tenant tfvars
# files into a combined tenants map.
#
# Usage:
#   ./scripts/merge-tenants.test.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEST_DIR="/tmp/tenant-merge-test-$$"
PASSED=0
FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# =============================================================================
# Test Utilities
# =============================================================================
setup_test_env() {
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR/tenants"
}

cleanup_test_env() {
    rm -rf "$TEST_DIR"
    rm -f "${INFRA_DIR}/.tenants-testenv.auto.tfvars"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="$3"
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓${NC} $message"
        ((PASSED++)) || true
    else
        echo -e "${RED}✗${NC} $message"
        echo -e "  Expected: $expected"
        echo -e "  Actual:   $actual"
        ((FAILED++)) || true
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    
    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}✓${NC} $message"
        ((PASSED++)) || true
    else
        echo -e "${RED}✗${NC} $message"
        echo -e "  Expected to contain: $needle"
        echo -e "  Actual: $haystack"
        ((FAILED++)) || true
    fi
}

assert_file_exists() {
    local file="$1"
    local message="$2"
    
    if [[ -f "$file" ]]; then
        echo -e "${GREEN}✓${NC} $message"
        ((PASSED++)) || true
    else
        echo -e "${RED}✗${NC} $message"
        echo -e "  File not found: $file"
        ((FAILED++)) || true
    fi
}

# =============================================================================
# Merge Function (extracted from deploy-terraform.sh for testing)
# =============================================================================
merge_tenants() {
    local tenants_dir="$1"
    local output_file="$2"
    
    if [[ ! -d "$tenants_dir" ]]; then
        echo "tenants = {}" > "$output_file"
        return 0
    fi
    
    # Collect tenant files into an array
    local -a tenant_files=()
    local tenant_count=0
    
    while IFS= read -r -d '' file; do
        tenant_files+=("$file")
        ((tenant_count++)) || true
    done < <(find "$tenants_dir" -name "tenant.tfvars" -type f -print0 2>/dev/null | sort -z)
    
    if [[ $tenant_count -eq 0 ]]; then
        echo "tenants = {}" > "$output_file"
        return 0
    fi
    
    # Start the combined tenants map
    {
        echo "# Auto-generated - DO NOT EDIT"
        echo "tenants = {"
    } > "$output_file"
    
    # Process each tenant file
    for tenant_file in "${tenant_files[@]}"; do
        local tenant_name
        tenant_name=$(basename "$(dirname "$tenant_file")")
        
        {
            echo ""
            echo "  # From: tenants/${tenant_name}/tenant.tfvars"
            # Extract just the block content (without "tenant = ") and add key prefix
            local block_content
            block_content=$(awk '/^tenant[[:space:]]*=[[:space:]]*\{/,/^\}$/' "$tenant_file" | \
                sed 's/^tenant[[:space:]]*=[[:space:]]*//')
            echo "  \"${tenant_name}\" = ${block_content}"
        } >> "$output_file"
    done
    
    echo "}" >> "$output_file"
}

# =============================================================================
# Tests
# =============================================================================
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Running Tenant Merge Tests${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo ""

# -----------------------------------------------------------------------------
# Test 1: Empty tenants directory
# -----------------------------------------------------------------------------
echo -e "${YELLOW}Test 1: Empty tenants directory${NC}"
setup_test_env
merge_tenants "$TEST_DIR/tenants" "$TEST_DIR/output.tfvars"

assert_file_exists "$TEST_DIR/output.tfvars" "Output file should be created"
content=$(cat "$TEST_DIR/output.tfvars")
assert_equals "tenants = {}" "$content" "Should produce empty tenants map"
cleanup_test_env

# -----------------------------------------------------------------------------
# Test 2: Single tenant
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}Test 2: Single tenant${NC}"
setup_test_env
mkdir -p "$TEST_DIR/tenants/sample-tenant-1"
cat > "$TEST_DIR/tenants/sample-tenant-1/tenant.tfvars" << 'EOF'
# Test tenant 1
tenant = {
    tenant_name  = "sample-tenant-1"
  display_name = "Test Tenant 1"
  enabled      = true
}
EOF

merge_tenants "$TEST_DIR/tenants" "$TEST_DIR/output.tfvars"
content=$(cat "$TEST_DIR/output.tfvars")

assert_contains "$content" '"sample-tenant-1" =' "Should contain tenant key"
assert_contains "$content" 'tenant_name  = "sample-tenant-1"' "Should contain tenant_name"
assert_contains "$content" 'display_name = "Test Tenant 1"' "Should contain display_name"
assert_contains "$content" 'enabled      = true' "Should contain enabled flag"
cleanup_test_env

# -----------------------------------------------------------------------------
# Test 3: Multiple tenants
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}Test 3: Multiple tenants${NC}"
setup_test_env
mkdir -p "$TEST_DIR/tenants/alpha-tenant"
mkdir -p "$TEST_DIR/tenants/beta-tenant"

cat > "$TEST_DIR/tenants/alpha-tenant/tenant.tfvars" << 'EOF'
tenant = {
  tenant_name  = "alpha-tenant"
  display_name = "Alpha Tenant"
  enabled      = true
}
EOF

cat > "$TEST_DIR/tenants/beta-tenant/tenant.tfvars" << 'EOF'
tenant = {
  tenant_name  = "beta-tenant"
  display_name = "Beta Tenant"
  enabled      = false
}
EOF

merge_tenants "$TEST_DIR/tenants" "$TEST_DIR/output.tfvars"
content=$(cat "$TEST_DIR/output.tfvars")

assert_contains "$content" '"alpha-tenant" =' "Should contain alpha-tenant key"
assert_contains "$content" '"beta-tenant" =' "Should contain beta-tenant key"
assert_contains "$content" 'display_name = "Alpha Tenant"' "Should contain Alpha display_name"
assert_contains "$content" 'display_name = "Beta Tenant"' "Should contain Beta display_name"
cleanup_test_env

# -----------------------------------------------------------------------------
# Test 4: Tenant with nested objects (real-world structure)
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}Test 4: Tenant with nested objects${NC}"
setup_test_env
mkdir -p "$TEST_DIR/tenants/complex-tenant"

cat > "$TEST_DIR/tenants/complex-tenant/tenant.tfvars" << 'EOF'
# Complex tenant with nested config
tenant = {
  tenant_name  = "complex-tenant"
  display_name = "Complex Tenant"
  enabled      = true

  tags = {
    ministry    = "TEST"
    environment = "test"
  }

  storage_account = {
    enabled                  = true
    account_tier             = "Standard"
    account_replication_type = "LRS"
  }

  openai = {
    enabled = true
    sku     = "S0"
    model_deployments = [
      {
        name       = "gpt-4"
        model_name = "gpt-4"
        capacity   = 10
      }
    ]
  }
}
EOF

merge_tenants "$TEST_DIR/tenants" "$TEST_DIR/output.tfvars"
content=$(cat "$TEST_DIR/output.tfvars")

assert_contains "$content" '"complex-tenant" =' "Should contain complex-tenant key"
assert_contains "$content" 'ministry    = "TEST"' "Should contain nested tags"
assert_contains "$content" 'account_tier             = "Standard"' "Should contain storage config"
assert_contains "$content" 'model_deployments = [' "Should contain model_deployments array"
cleanup_test_env

# -----------------------------------------------------------------------------
# Test 5: No tenants directory
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}Test 5: No tenants directory${NC}"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"
merge_tenants "$TEST_DIR/nonexistent" "$TEST_DIR/output.tfvars"
content=$(cat "$TEST_DIR/output.tfvars")

assert_equals "tenants = {}" "$content" "Should produce empty tenants map when dir missing"
cleanup_test_env

# -----------------------------------------------------------------------------
# Test 6: Validate output is valid HCL (using terraform fmt)
# -----------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}Test 6: Validate output is valid HCL${NC}"
setup_test_env
mkdir -p "$TEST_DIR/tenants/valid-tenant"

cat > "$TEST_DIR/tenants/valid-tenant/tenant.tfvars" << 'EOF'
tenant = {
  tenant_name  = "valid-tenant"
  display_name = "Valid Tenant"
  enabled      = true

  key_vault = {
    enabled = false
  }

  storage_account = {
    enabled = true
  }
}
EOF

merge_tenants "$TEST_DIR/tenants" "$TEST_DIR/output.tfvars"

if command -v terraform &> /dev/null; then
    if terraform fmt -check "$TEST_DIR/output.tfvars" &> /dev/null; then
        echo -e "${GREEN}✓${NC} Output is valid HCL (terraform fmt passed)"
        ((PASSED++))
    else
        # Try to format and show diff
        echo -e "${YELLOW}!${NC} Output needs formatting (terraform fmt would modify)"
        # Still valid HCL, just not formatted
        if terraform fmt "$TEST_DIR/output.tfvars" &> /dev/null; then
            echo -e "${GREEN}✓${NC} Output is valid HCL (can be formatted)"
            ((PASSED++))
        else
            echo -e "${RED}✗${NC} Output is NOT valid HCL"
            ((FAILED++))
        fi
    fi
else
    echo -e "${YELLOW}!${NC} Skipping HCL validation (terraform not found)"
fi
cleanup_test_env

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${BLUE}==============================================================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}==============================================================================${NC}"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [[ $FAILED -gt 0 ]]; then
    echo ""
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo ""
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
