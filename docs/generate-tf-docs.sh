#!/bin/bash
# =============================================================================
# Terraform Documentation Generator
# =============================================================================
# Generates HTML reference documentation from Terraform source files for both
# the initial-setup/infra modules and the infra-ai-hub modules + stacks.
#
# Usage: ./generate-tf-docs.sh [options]
#
# Options:
#   -o, --output       Output file (default: _pages/terraform-reference.html)
#   -h, --help         Show this help message
#
# How it works:
#   1. Scans initial-setup/infra/ for the root module and its sub-modules
#   2. Scans infra-ai-hub/modules/ for the AI Hub shared modules
#   3. Scans infra-ai-hub/stacks/ for the isolated Terraform stacks
#   4. Extracts module descriptions from header comments in main.tf
#   5. Parses variables.tf for variable names, types, defaults, and descriptions
#   6. Parses outputs.tf for output names and descriptions
#   7. Generates a single HTML page with all extracted documentation
#
# Comment Format Expected:
#   # Description: Creates the virtual network and subnets
# =============================================================================

set -e

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INITIAL_SETUP_DIR="${SCRIPT_DIR}/../initial-setup/infra"
AI_HUB_DIR="${SCRIPT_DIR}/../infra-ai-hub"
OUTPUT_FILE="${SCRIPT_DIR}/_pages/terraform-reference.html"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            head -28 "$0" | tail -23
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Terraform Documentation Generator${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Initial setup dir: ${GREEN}${INITIAL_SETUP_DIR}${NC}"
echo -e "AI Hub dir:        ${GREEN}${AI_HUB_DIR}${NC}"
echo -e "Output file:       ${GREEN}${OUTPUT_FILE}${NC}"
echo ""

# Function to extract description from file header comments
# Looks for lines starting with # at the top of the file
extract_file_description() {
    local file="$1"
    local description=""

    # Read first 20 lines and look for description patterns
    while IFS= read -r line; do
        # Skip empty lines at start
        [[ -z "$line" ]] && continue
        # Stop if we hit non-comment line
        [[ ! "$line" =~ ^# ]] && break
        # Extract description
        if [[ "$line" =~ ^#[[:space:]]*Description:[[:space:]]*(.*) ]]; then
            description="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^#[[:space:]]*(.+) ]] && [[ -z "$description" ]]; then
            # Use first comment line as description if no explicit Description:
            description="${BASH_REMATCH[1]}"
        fi
    done < <(head -20 "$file")

    echo "$description"
}

# Function to parse variables from a variables.tf file
# Extracts: name, type, default, description
parse_variables() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return
    fi

    echo "<h4>Variables</h4>"
    echo "<table>"
    echo "<tr><th>Name</th><th>Type</th><th>Default</th><th>Description</th></tr>"

    local in_variable=false
    local var_name=""
    local var_type=""
    local var_default=""
    local var_description=""
    local brace_count=0

    while IFS= read -r line; do
        # Detect variable block start
        if [[ "$line" =~ ^variable[[:space:]]+\"([^\"]+)\" ]]; then
            in_variable=true
            var_name="${BASH_REMATCH[1]}"
            var_type=""
            var_default=""
            var_description=""
            brace_count=0
        fi

        if $in_variable; then
            # Count braces safely (avoid pipefail with set -e)
            local stripped_open="${line//[^\{]/}"
            local stripped_close="${line//[^\}]/}"
            brace_count=$((brace_count + ${#stripped_open} - ${#stripped_close}))

            # Extract type
            if [[ "$line" =~ type[[:space:]]*=[[:space:]]*(.+) ]]; then
                var_type="${BASH_REMATCH[1]}"
                var_type="${var_type%%[[:space:]]*}"  # Remove trailing spaces
            fi

            # Extract default (simplified)
            if [[ "$line" =~ default[[:space:]]*=[[:space:]]*(.+) ]]; then
                var_default="${BASH_REMATCH[1]}"
                var_default="${var_default%%[[:space:]]*}"
                # Clean up quotes
                var_default="${var_default//\"/}"
            fi

            # Extract description
            if [[ "$line" =~ description[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
                var_description="${BASH_REMATCH[1]}"
            fi

            # End of variable block
            if [ $brace_count -le 0 ] && [[ "$line" =~ \} ]]; then
                # Output the variable
                echo "<tr>"
                echo "<td><code>${var_name}</code></td>"
                echo "<td><code>${var_type:-any}</code></td>"
                echo "<td><code>${var_default:-required}</code></td>"
                echo "<td>${var_description:-<em>No description</em>}</td>"
                echo "</tr>"
                in_variable=false
            fi
        fi
    done < "$file"

    echo "</table>"
}

# Function to parse outputs from an outputs.tf file
parse_outputs() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return
    fi

    echo "<h4>Outputs</h4>"
    echo "<table>"
    echo "<tr><th>Name</th><th>Description</th></tr>"

    local in_output=false
    local output_name=""
    local output_description=""
    local brace_count=0

    while IFS= read -r line; do
        # Detect output block start
        if [[ "$line" =~ ^output[[:space:]]+\"([^\"]+)\" ]]; then
            in_output=true
            output_name="${BASH_REMATCH[1]}"
            output_description=""
            brace_count=0
        fi

        if $in_output; then
            local stripped_open="${line//[^\{]/}"
            local stripped_close="${line//[^\}]/}"
            brace_count=$((brace_count + ${#stripped_open} - ${#stripped_close}))

            # Extract description
            if [[ "$line" =~ description[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
                output_description="${BASH_REMATCH[1]}"
            fi

            # End of output block
            if [ $brace_count -le 0 ] && [[ "$line" =~ \} ]]; then
                echo "<tr>"
                echo "<td><code>${output_name}</code></td>"
                echo "<td>${output_description:-<em>No description</em>}</td>"
                echo "</tr>"
                in_output=false
            fi
        fi
    done < "$file"

    echo "</table>"
}

# Function to list resources in a main.tf file
parse_resources() {
    local file="$1"

    if [ ! -f "$file" ]; then
        return
    fi

    local resources=$(grep -E '^resource[[:space:]]+"' "$file" 2>/dev/null | sed 's/resource "\([^"]*\)" "\([^"]*\)".*/\1 (\2)/' || true)

    if [ -n "$resources" ]; then
        echo "<h4>Resources Created</h4>"
        echo "<ul>"
        while IFS= read -r resource; do
            [ -n "$resource" ] && echo "<li><code>$resource</code></li>"
        done <<< "$resources"
        echo "</ul>"
    fi
}

# =============================================================================
# Helper: process a directory as a card (module or stack)
# Usage: process_dir <dir_path> <display_location> <heading_prefix> <border_color> <id_prefix>
# =============================================================================
process_dir() {
    local dir_path="$1"
    local display_location="$2"
    local heading_prefix="$3"
    local border_color="$4"
    local id_prefix="$5"
    local dir_name
    dir_name=$(basename "$dir_path")

    # Skip empty directories (no .tf files)
    local tf_count
    tf_count=$(find "$dir_path" -maxdepth 1 -name "*.tf" 2>/dev/null | wc -l)
    if [ "$tf_count" -eq 0 ]; then
        echo -e "  ${YELLOW}Skipping empty: ${dir_name}${NC}"
        return
    fi

    echo -e "  ${GREEN}Processing ${heading_prefix}: ${dir_name}...${NC}"

    {
        local html_id="${id_prefix}${dir_name}"
        echo "<h3 id=\"${html_id}\">${dir_name}</h3>"
        echo "<div class=\"card\" style=\"border-left-color: ${border_color};\">"

        # Get description from main.tf or README
        local desc=""
        desc=$(extract_file_description "${dir_path}/main.tf")
        if [ -z "$desc" ] && [ -f "${dir_path}/README.md" ]; then
            desc=$(head -5 "${dir_path}/README.md" | grep -v "^#" | head -1 || true)
        fi
        [ -n "$desc" ] && echo "<p>$desc</p>"

        echo "<p><strong>Location:</strong> <code>${display_location}</code></p>"

        # List files
        echo "<details>"
        echo "<summary style=\"cursor: pointer; color: var(--bc-blue-light);\">Files (${tf_count})</summary>"
        echo "<ul style=\"margin-top: 0.5rem;\">"
        for tf_file in "${dir_path}"/*.tf; do
            [ -f "$tf_file" ] && echo "<li><code>$(basename "$tf_file")</code></li>"
        done
        echo "</ul>"
        echo "</details>"

        parse_variables "${dir_path}/variables.tf"
        parse_outputs "${dir_path}/outputs.tf"
        parse_resources "${dir_path}/main.tf"

        echo "</div>"
    } >> "$OUTPUT_FILE"
}

# =============================================================================
# Generate HTML
# =============================================================================
echo -e "${YELLOW}Generating documentation...${NC}"

cat > "$OUTPUT_FILE" << 'HEADER'
<!-- TITLE: Terraform Reference -->
<!-- NAV: terraform -->

<h1>Terraform Reference</h1>

<div class="alert alert-info">
    <span class="alert-icon">🤖</span>
    <div>
        <strong>Auto-Generated Documentation</strong><br>
        This page is automatically generated from Terraform source files. Run <code>./docs/generate-tf-docs.sh</code> to update.
    </div>
</div>

<p>Complete reference documentation for all Terraform modules, variables, and outputs extracted directly from the source code.</p>

<div class="grid grid-2" style="margin-bottom: 2rem;">
    <a href="#section-initial-setup" class="card-link">
        <div class="card" style="border-left-color: #8b5cf6;">
            <h3 style="margin-top: 0;">Initial Setup</h3>
            <p>Network foundation: VNet, Bastion, Jumpbox, self-hosted runners.</p>
        </div>
    </a>
    <a href="#section-ai-hub" class="card-link">
        <div class="card" style="border-left-color: #22c55e;">
            <h3 style="margin-top: 0;">AI Services Hub</h3>
            <p>AI platform: APIM, AI Foundry, tenants, key rotation, WAF.</p>
        </div>
    </a>
</div>

HEADER

# ─────────────────────────────────────────────────────────────────────────────
# Section 1: Initial Setup (initial-setup/infra)
# ─────────────────────────────────────────────────────────────────────────────
if [ -d "${INITIAL_SETUP_DIR}" ]; then
    echo -e "${BLUE}── Initial Setup ──${NC}"
    {
        echo "<h2 id=\"section-initial-setup\">Initial Setup (<code>initial-setup/infra/</code>)</h2>"
        echo "<p>Network foundation layer &mdash; VNet, Bastion, Jumpbox, and self-hosted GitHub runners. Deployed once per environment via <code>initial-setup/infra/deploy-terraform.sh</code>.</p>"
    } >> "$OUTPUT_FILE"

    # Root module
    echo -e "  ${GREEN}Processing root module...${NC}"
    {
        echo "<h3 id=\"initial-root\">Root Module</h3>"
        echo "<div class=\"card\">"

        desc=$(extract_file_description "${INITIAL_SETUP_DIR}/main.tf")
        [ -n "$desc" ] && echo "<p>$desc</p>"

        echo "<p><strong>Location:</strong> <code>initial-setup/infra/</code></p>"

        parse_variables "${INITIAL_SETUP_DIR}/variables.tf"
        parse_outputs "${INITIAL_SETUP_DIR}/outputs.tf"
        parse_resources "${INITIAL_SETUP_DIR}/main.tf"

        echo "</div>"
    } >> "$OUTPUT_FILE"

    # Sub-modules
    if [ -d "${INITIAL_SETUP_DIR}/modules" ]; then
        for module_dir in "${INITIAL_SETUP_DIR}/modules"/*/; do
            [ -d "$module_dir" ] || continue
            module_name=$(basename "$module_dir")
            process_dir "$module_dir" "initial-setup/infra/modules/${module_name}/" "module" "#8b5cf6" "initial-"
        done
    fi
else
    echo -e "${YELLOW}Skipping initial-setup (not found: ${INITIAL_SETUP_DIR})${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Section 2: AI Services Hub (infra-ai-hub)
# ─────────────────────────────────────────────────────────────────────────────
if [ -d "${AI_HUB_DIR}" ]; then
    echo -e "${BLUE}── AI Services Hub ──${NC}"
    {
        echo ""
        echo "<h2 id=\"section-ai-hub\">AI Services Hub (<code>infra-ai-hub/</code>)</h2>"
        echo "<p>Multi-tenant AI platform deployed via 5 isolated Terraform stacks with parallel execution. See <a href=\"decisions.html#adr-013\">ADR-013</a> for architecture rationale.</p>"
    } >> "$OUTPUT_FILE"

    # Stacks
    if [ -d "${AI_HUB_DIR}/stacks" ]; then
        {
            echo "<h2 id=\"ai-hub-stacks\">Stacks</h2>"
            echo "<p>Each stack has its own state file and backend configuration. Deployed in dependency order: shared &rarr; tenant (parallel) &rarr; foundry + apim + tenant-user-mgmt (parallel).</p>"
        } >> "$OUTPUT_FILE"

        # Process stacks in execution order
        for stack_name in shared tenant foundry apim tenant-user-mgmt; do
            stack_dir="${AI_HUB_DIR}/stacks/${stack_name}"
            [ -d "$stack_dir" ] || continue
            process_dir "$stack_dir" "infra-ai-hub/stacks/${stack_name}/" "stack" "#0078d4" "stack-"
        done
    fi

    # Modules
    if [ -d "${AI_HUB_DIR}/modules" ]; then
        {
            echo "<h2 id=\"ai-hub-modules\">Modules</h2>"
            echo "<p>Reusable modules consumed by the stacks above. Each module wraps Azure Verified Modules (AVM) or native <code>azurerm</code>/<code>azapi</code> resources.</p>"
        } >> "$OUTPUT_FILE"

        for module_dir in "${AI_HUB_DIR}/modules"/*/; do
            [ -d "$module_dir" ] || continue
            module_name=$(basename "$module_dir")
            process_dir "$module_dir" "infra-ai-hub/modules/${module_name}/" "module" "#22c55e" "hub-"
        done
    fi
else
    echo -e "${YELLOW}Skipping infra-ai-hub (not found: ${AI_HUB_DIR})${NC}"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Footer: usage examples and conventions
# ─────────────────────────────────────────────────────────────────────────────
cat >> "$OUTPUT_FILE" << 'FOOTER'

<h2>Adding New Modules</h2>

<p>When creating new Terraform modules, follow these conventions to ensure automatic documentation:</p>

<ol>
    <li>Add a description comment at the top of <code>main.tf</code>:
        <pre># Description: This module creates Azure storage accounts with encryption</pre>
    </li>
    <li>Always include <code>description</code> for variables:
        <pre>variable "storage_name" {
  type        = string
  description = "Name of the storage account (must be globally unique)"
}</pre>
    </li>
    <li>Always include <code>description</code> for outputs:
        <pre>output "storage_id" {
  value       = azurerm_storage_account.main.id
  description = "The resource ID of the storage account"
}</pre>
    </li>
    <li>Run the documentation generator:
        <pre>./docs/generate-tf-docs.sh</pre>
    </li>
</ol>

<div class="alert alert-warning">
    <span class="alert-icon">💡</span>
    <div>
        <strong>Tip:</strong> The documentation generator runs automatically during the GitHub Pages build. Push to main and docs are rebuilt.
    </div>
</div>
FOOTER

echo ""
echo -e "${GREEN}✓ Documentation generated successfully!${NC}"
echo -e "  Output: ${OUTPUT_FILE}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo -e "  1. Review the generated documentation"
echo -e "  2. Run ${BLUE}./build.sh${NC} to rebuild all pages"
echo -e "  3. Commit and push to deploy"
