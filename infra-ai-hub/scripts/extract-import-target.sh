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

    # Terraform output can contain multiple "already exists" errors; we want the LAST one,
    # and we must pair the correct resource address from the following "with <addr>," line.
    # Also handle escaped quotes (\") and IDs that include a pipe (Diagnostic Settings import IDs).
    local result
    local awk_script
    awk_script="$(mktemp 2>/dev/null || echo "")"
    if [[ -z "$awk_script" ]]; then
        return 1
    fi

    cat >"$awk_script" <<'AWK'
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
        return s
    }
    return ""
}

function extract_id(line, s) {
    # Prefer a quoted (or escaped-quoted) /subscriptions/... pattern
    if (match(line, /\\?\"\/subscriptions\/[^\\\"]+\\?\"/)) {
        s = substr(line, RSTART, RLENGTH)
        sub(/^\\?\"/, "", s)
        sub(/\\?\"$/, "", s)
        sub(/\\$/, "", s)
        return s
    }

    if (match(line, /\/subscriptions\//)) {
        s = substr(line, RSTART)
        sub(/[\"[:space:]].*$/, "", s)
        sub(/\\$/, "", s)
        return s
    }

    return ""
}

BEGIN {
    pending_id = ""
    last_addr = ""
    last_id = ""
    in_error = 0
}

{
    gsub(/\r/, "", $0)
    line = $0

    if (line ~ /already exists/) {
        in_error = 1
    }

    if (in_error) {
        id = extract_id(line)
        if (id != "") {
            pending_id = id
        }
    }

    addr = extract_addr(line)
    if (addr != "" && pending_id != "") {
        last_addr = trim(addr)
        last_id = trim(pending_id)
        pending_id = ""
        in_error = 0
    }
}

END {
    if (last_addr != "" && last_id != "") {
        printf "%s\t%s\n", last_addr, last_id
        exit 0
    }
    exit 1
}
AWK

    result="$(printf '%s\n' "$content" | awk -f "$awk_script" 2>/dev/null)" || true
    rm -f "$awk_script" >/dev/null 2>&1 || true

    if [[ -n "$result" ]]; then
        printf '%s\n' "$result"
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
