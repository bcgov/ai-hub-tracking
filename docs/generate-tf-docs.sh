#!/bin/bash
# =============================================================================
# Terraform Documentation Generator
# =============================================================================
# This script automatically generates documentation from Terraform files by
# extracting comments, variable descriptions, and resource information.
#
# Usage: ./generate-tf-docs.sh [options]
#
# Options:
#   -i, --infra-dir    Path to infra directory (default: ../infra)
#   -o, --output       Output file (default: _pages/terraform-reference.html)
#   -h, --help         Show this help message
#
# How it works:
#   1. Scans all .tf files in the infra directory
#   2. Extracts module descriptions from comments at the top of main.tf
#   3. Parses variables.tf to get variable names, types, defaults, and descriptions
#   4. Parses outputs.tf to get output names and descriptions
#   5. Generates an HTML page with all the extracted documentation
#
# Comment Format Expected:
#   # Module: Network
#   # Description: Creates the virtual network and subnets
#   # Author: Your Name
#   # Last Updated: 2025-01-15
# =============================================================================

set -e

# Default values
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="${SCRIPT_DIR}/../infra"
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
        -i|--infra-dir)
            INFRA_DIR="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            head -30 "$0" | tail -25
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
echo -e "Infra directory: ${GREEN}${INFRA_DIR}${NC}"
echo -e "Output file: ${GREEN}${OUTPUT_FILE}${NC}"
echo ""

# Verify infra directory exists
if [ ! -d "$INFRA_DIR" ]; then
    echo -e "${RED}Error: Infra directory not found: ${INFRA_DIR}${NC}"
    exit 1
fi

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
            # Count braces
            brace_count=$((brace_count + $(echo "$line" | tr -cd '{' | wc -c)))
            brace_count=$((brace_count - $(echo "$line" | tr -cd '}' | wc -c)))

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
            brace_count=$((brace_count + $(echo "$line" | tr -cd '{' | wc -c)))
            brace_count=$((brace_count - $(echo "$line" | tr -cd '}' | wc -c)))

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

# Start generating HTML
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

HEADER

# Process root module
echo -e "  ${GREEN}Processing root module...${NC}"
{
    echo "<h2>Root Module</h2>"
    echo "<div class=\"card\">"

    desc=$(extract_file_description "${INFRA_DIR}/main.tf")
    [ -n "$desc" ] && echo "<p>$desc</p>"

    echo "<p><strong>Location:</strong> <code>infra/</code></p>"

    parse_variables "${INFRA_DIR}/variables.tf"
    parse_outputs "${INFRA_DIR}/outputs.tf"
    parse_resources "${INFRA_DIR}/main.tf"

    echo "</div>"
} >> "$OUTPUT_FILE"

# Process each module in modules directory
if [ -d "${INFRA_DIR}/modules" ]; then
    for module_dir in "${INFRA_DIR}/modules"/*/; do
        if [ -d "$module_dir" ]; then
            module_name=$(basename "$module_dir")
            echo -e "  ${GREEN}Processing module: ${module_name}...${NC}"

            {
                echo "<h2 id=\"${module_name}\">Module: ${module_name}</h2>"
                echo "<div class=\"card\" style=\"border-left-color: #8b5cf6;\">"

                # Get description from main.tf or README
                desc=$(extract_file_description "${module_dir}main.tf")
                if [ -z "$desc" ] && [ -f "${module_dir}README.md" ]; then
                    desc=$(head -5 "${module_dir}README.md" | grep -v "^#" | head -1)
                fi
                [ -n "$desc" ] && echo "<p>$desc</p>"

                echo "<p><strong>Location:</strong> <code>infra/modules/${module_name}/</code></p>"

                # List files in module
                echo "<details>"
                echo "<summary style=\"cursor: pointer; color: var(--bc-blue-light);\">Module Files</summary>"
                echo "<ul style=\"margin-top: 0.5rem;\">"
                for tf_file in "${module_dir}"*.tf; do
                    [ -f "$tf_file" ] && echo "<li><code>$(basename "$tf_file")</code></li>"
                done
                echo "</ul>"
                echo "</details>"

                parse_variables "${module_dir}variables.tf"
                parse_outputs "${module_dir}outputs.tf"
                parse_resources "${module_dir}main.tf"

                echo "</div>"
            } >> "$OUTPUT_FILE"
        fi
    done
fi

# Add usage examples section
cat >> "$OUTPUT_FILE" << 'FOOTER'

<h2>Usage Examples</h2>

<div class="card card-gold">
    <h3 style="margin-top: 0;">Calling a Module</h3>
    <pre>module "network" {
  source = "./modules/network"

  resource_group_name = var.resource_group_name
  location            = var.location
  environment         = var.environment
  vnet_address_space  = ["10.0.0.0/16"]
}</pre>
</div>

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
        <strong>Tip:</strong> The documentation generator runs automatically during the docs build process. Simply add your module and push to main.
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
