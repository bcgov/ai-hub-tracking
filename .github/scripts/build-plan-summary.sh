#!/usr/bin/env bash
# =============================================================================
# Build Plan Summary
# =============================================================================
# Parses a Terraform plan log file and produces structured output suitable for
# GitHub Actions step outputs (plan_comment, has_changes).
#
# Usage:
#   build-plan-summary.sh <log_file> <output_file>
#
# Arguments:
#   log_file    - Path to the raw Terraform plan log (from deploy-terraform.sh)
#   output_file - Path to write GHA step outputs (typically $GITHUB_OUTPUT)
#
# Outputs (written as key=value or heredoc to output_file):
#   has_changes   - "true", "false", or "unknown"
#   plan_comment  - Markdown-formatted plan summary for PR description
#
# Exit codes:
#   0 - Always (parsing failures are not fatal, they produce "unknown")
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
NO_CHANGE_TEXT="No Changes to AI Hub Infra in this PR"
HEREDOC_DELIM="GHADELIM_PLAN"
MAX_SNIPPET_LENGTH=12000
SNIPPET_LINES=220
DEBUG_HEAD_LINES=200

# ---------------------------------------------------------------------------
# Helpers — GHA annotation wrappers (no-op outside Actions)
# ---------------------------------------------------------------------------
gha_notice()  { echo "::notice::plan_summary: $*"; }
gha_warning() { echo "::warning::plan_summary: $*"; }

# ---------------------------------------------------------------------------
# write_output <output_file> <key> <value>
#   Writes a single-line key=value to the output file.
# ---------------------------------------------------------------------------
write_output() {
  local out_file="$1" key="$2" value="$3"
  echo "${key}=${value}" >> "$out_file"
}

# ---------------------------------------------------------------------------
# write_output_heredoc <output_file> <key> <body>
#   Writes a multi-line heredoc block to the output file.
# ---------------------------------------------------------------------------
write_output_heredoc() {
  local out_file="$1" key="$2" body="$3"
  {
    echo "${key}<<${HEREDOC_DELIM}"
    echo "$body"
    echo "${HEREDOC_DELIM}"
  } >> "$out_file"
}

# ---------------------------------------------------------------------------
# clean_ansi <input_file> <output_file>
#   Strips ANSI escape sequences; falls back to copy on failure.
# ---------------------------------------------------------------------------
clean_ansi() {
  local input="$1" output="$2"
  perl -pe 's/\e\[[\d;?]*[ -\/]*[@-~]//g' "$input" > "$output" 2>/dev/null \
    || cp "$input" "$output"
}

# ---------------------------------------------------------------------------
# build_plan_summary <log_file> <output_file>
#   Main entry point.
# ---------------------------------------------------------------------------
build_plan_summary() {
  local log_file="$1"
  local output_file="$2"

  # ------ Guard: missing log file ------
  if [[ -z "$log_file" || ! -f "$log_file" ]]; then
    gha_notice "LOG_FILE missing — setting has_changes=unknown"
    write_output "$output_file" "has_changes" "unknown"
    write_output_heredoc "$output_file" "plan_comment" \
      "Plan output was not found in logs for this run."
    return 0
  fi

  echo "Log file exists: $log_file"

  # ------ Strip ANSI codes ------
  local clean_log="${log_file}.clean"
  clean_ansi "$log_file" "$clean_log"
  echo "Clean log file created at $clean_log"

  # ------ Search for Plan lines ------
  local plan_lines
  plan_lines=$(grep -E -i "Plan: *[0-9]+ *to add, *[0-9]+ *to change, *[0-9]+ *to destroy\." "$clean_log" || true)

  if [[ -z "$plan_lines" ]]; then
    # No Plan lines — check if all stacks said "No changes"
    if grep -q -i "No changes\." "$clean_log"; then
      gha_notice "all stacks report No changes"
      write_output "$output_file" "has_changes" "false"
      write_output_heredoc "$output_file" "plan_comment" "$NO_CHANGE_TEXT"
    else
      local sample
      sample=$(head -n "$DEBUG_HEAD_LINES" "$clean_log" || true)
      gha_warning "no Plan lines and no 'No changes' found — dumping log head"
      write_output "$output_file" "has_changes" "unknown"
      local body
      body=$(printf '%s\n\n%s\n%s\n%s\n%s' \
        "Plan completed but no recognisable summary was found in the logs." \
        "--- Cleaned log head (debug):" \
        '```' \
        "$sample" \
        '```')
      write_output_heredoc "$output_file" "plan_comment" "$body"
    fi
    return 0
  fi

  gha_notice "found changes — $plan_lines"
  write_output "$output_file" "has_changes" "true"

  # ------ Aggregate counts across stacks ------
  local total_add=0 total_change=0 total_destroy=0
  while IFS= read -r line; do
    local add chg dst
    add=$(echo "$line" | grep -oP '(\d+) to add' | grep -oP '\d+')
    chg=$(echo "$line" | grep -oP '(\d+) to change' | grep -oP '\d+')
    dst=$(echo "$line" | grep -oP '(\d+) to destroy' | grep -oP '\d+')
    total_add=$(( total_add + ${add:-0} ))
    total_change=$(( total_change + ${chg:-0} ))
    total_destroy=$(( total_destroy + ${dst:-0} ))
  done <<< "$plan_lines"

  local stack_count
  stack_count=$(echo "$plan_lines" | wc -l | tr -d ' ')
  local summary="${total_add} to add, ${total_change} to change, ${total_destroy} to destroy (across ${stack_count} stack(s))"

  # ------ Extract detail snippet ------
  local start_line snippet
  start_line=$(grep -n "Terraform will perform the following actions:" "$clean_log" | head -n 1 | cut -d: -f1 || true)
  if [[ -n "$start_line" ]]; then
    snippet=$(sed -n "${start_line},$((start_line + SNIPPET_LINES))p" "$clean_log")
  else
    snippet=$(tail -n "$SNIPPET_LINES" "$clean_log")
  fi

  # Escape triple backticks within snippet to avoid breaking markdown
  snippet=$(printf '%s' "$snippet" | sed 's/```/` ` `/g')
  if [[ ${#snippet} -gt $MAX_SNIPPET_LENGTH ]]; then
    snippet="${snippet:0:$MAX_SNIPPET_LENGTH}"
    snippet+=$'\n(truncated, see workflow logs for complete plan)'
  fi

  # ------ Build markdown body ------
  local body
  body=$(cat <<INNEREOF
**Summary:** ${summary}

<details><summary>Show plan details</summary>

\`\`\`hcl
${snippet}
\`\`\`

</details>
INNEREOF
)

  write_output_heredoc "$output_file" "plan_comment" "$body"
}

# ---------------------------------------------------------------------------
# Main — only run when executed directly (not sourced)
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <log_file> <output_file>" >&2
    exit 1
  fi
  build_plan_summary "$1" "$2"
fi
