#!/usr/bin/env bash
# extract-import-target.sh
# Extracts Terraform import target information from Terraform "already exists" errors.
#
# Usage:
#   extract-import-target.sh <terraform_output_file>
#   echo "<terraform_output>" | extract-import-target.sh -
#
# Output (on success):
#   <resource_address>\t<azure_resource_id>
#
# Exit codes:
#   0 - Import target found and printed
#   1 - No importable "already exists" error found
#
# Example:
#   $ ./extract-import-target.sh /tmp/terraform-apply.log
#   module.frontend[0].azurerm_linux_web_app.frontend	/subscriptions/.../providers/Microsoft.Web/sites/myapp

set -euo pipefail

extract_import_target() {
    local input="$1"

    local content
    if [[ "$input" == "-" ]]; then
        content="$(cat)"
    elif [[ -f "$input" ]]; then
        content="$(cat "$input")"
    else
        echo "Error: File not found: $input" >&2
        return 1
    fi

    # Check if this is an "already exists" error
    if ! echo "$content" | grep -q "already exists"; then
        return 1
    fi

    # Extract the Terraform resource address from "with <address>," line
    # Example: │   with module.frontend[0].azurerm_linux_web_app.frontend,
    local resource_addr
    resource_addr=$(echo "$content" | grep -oE 'with [^,]+,' | head -1 | sed 's/^with //; s/,$//')

    # Extract the Azure resource ID from lines containing BOTH the ID and "already exists"
    # The format is: Error: a resource with the ID "/subscriptions/..." already exists
    # We need the ID from THAT specific line, not just any /subscriptions/ ID in the file
    local resource_id
    resource_id=$(echo "$content" | grep "already exists" | grep -oE '"/subscriptions/[^"]+"|^/subscriptions/[^"[:space:]]+' | head -1 | tr -d '"')

    if [[ -n "$resource_addr" && -n "$resource_id" ]]; then
        printf '%s\t%s\n' "$resource_addr" "$resource_id"
        return 0
    fi

    return 1
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 1 ]]; then
        echo "Usage: $0 <terraform_output_file>" >&2
        echo "       $0 -    (read from stdin)" >&2
        exit 1
    fi
    extract_import_target "$1"
fi
