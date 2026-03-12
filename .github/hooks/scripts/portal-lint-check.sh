#!/bin/bash
# postToolUse hook: run full pre-commit validation suite on the affected portal package after every
# TypeScript file edit or create. Checks run in order: format:check → lint → typecheck (backend only).
# Output from postToolUse hooks is ignored by the agent; results are written to .github/hooks/logs/portal-lint.log.
#
# Input (stdin): JSON with shape { "toolName": "...", "toolArgs": "..." }
# For edit/create tools, toolArgs contains a "path" or "filePath" field.

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.toolName')

# Only trigger on file edit or create operations
if [ "$TOOL_NAME" != "edit" ] && [ "$TOOL_NAME" != "create" ] && [ "$TOOL_NAME" != "create_file" ]; then
  exit 0
fi

# Extract the file path from tool args (the field name varies across agent versions)
TOOL_ARGS=$(echo "$INPUT" | jq -r '.toolArgs // "{}"')
FILE_PATH=$(echo "$TOOL_ARGS" | jq -r '.path // .filePath // .file // empty' 2>/dev/null || true)

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# Only process TypeScript/JavaScript files
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx) ;;
  *) exit 0 ;;
esac

REPO_ROOT="$(pwd)"
LOG_DIR="$REPO_ROOT/.github/hooks/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/portal-lint.log"

# Helper: run a single npm script and log the result
run_check() {
  local label="$1" script="$2" dir="$3"
  echo "--- $label ---" >> "$LOG"
  cd "$dir"
  if npm run "$script" 2>&1 | tee -a "$LOG"; then
    echo "--- $label PASSED ---" >> "$LOG"
  else
    echo "--- $label FAILED ---" >> "$LOG"
  fi
  cd "$REPO_ROOT"
  echo "" >> "$LOG"
}

RAN_CHECK=0

# backend — mirrors .pre-commit-config.yaml: portal-backend-lint (lint + format:check)
if echo "$FILE_PATH" | grep -q "tenant-onboarding-portal/backend"; then
  echo "=== Backend pre-commit checks: $FILE_PATH @ $(date) ===" >> "$LOG"
  run_check "lint"         "lint"         "$REPO_ROOT/tenant-onboarding-portal/backend"
  run_check "format:check" "format:check" "$REPO_ROOT/tenant-onboarding-portal/backend"
  RAN_CHECK=1
fi

# frontend — mirrors .pre-commit-config.yaml: portal-frontend-lint (lint + format:check)
if echo "$FILE_PATH" | grep -q "tenant-onboarding-portal/frontend"; then
  echo "=== Frontend pre-commit checks: $FILE_PATH @ $(date) ===" >> "$LOG"
  run_check "lint"         "lint"         "$REPO_ROOT/tenant-onboarding-portal/frontend"
  run_check "format:check" "format:check" "$REPO_ROOT/tenant-onboarding-portal/frontend"
  RAN_CHECK=1
fi

if [ "$RAN_CHECK" -eq 0 ]; then
  exit 0
fi

echo "" >> "$LOG"

# postToolUse output is ignored; always exit 0
exit 0
