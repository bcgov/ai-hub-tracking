#!/bin/bash
# postToolUse hook: run full pre-commit validation suite on the affected package after every
# Python or TypeScript file edit or create.
#
# Packages covered:
#   - tenant-onboarding-portal/backend  → ESLint + Prettier
#   - tenant-onboarding-portal/frontend → ESLint + Prettier
#   - jobs/apim-key-rotation            → ruff lint + format check + pytest + docs build
#   - pii-redaction-service             → ruff lint + format check + pytest + docs build
#
# Checks run in order: lint → format:check → tests → docs build (Python packages).
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

# Only process TypeScript/JavaScript or Python files
case "$FILE_PATH" in
  *.ts|*.tsx|*.js|*.jsx|*.py) ;;
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

# key-rotation function — mirrors .pre-commit-config.yaml: key-rotation-lint + key-rotation-tests + key-rotation-docs
if echo "$FILE_PATH" | grep -q "jobs/apim-key-rotation"; then
  echo "=== Key Rotation pre-commit checks: $FILE_PATH @ $(date) ===" >> "$LOG"
  echo "--- ruff check ---" >> "$LOG"
  (cd "$REPO_ROOT/jobs/apim-key-rotation" && uv run ruff check . 2>&1 | tee -a "$LOG") && \
    echo "--- ruff check PASSED ---" >> "$LOG" || echo "--- ruff check FAILED ---" >> "$LOG"
  echo "" >> "$LOG"
  echo "--- ruff format:check ---" >> "$LOG"
  (cd "$REPO_ROOT/jobs/apim-key-rotation" && uv run ruff format --check . 2>&1 | tee -a "$LOG") && \
    echo "--- ruff format:check PASSED ---" >> "$LOG" || echo "--- ruff format:check FAILED ---" >> "$LOG"
  echo "" >> "$LOG"
  echo "--- pytest ---" >> "$LOG"
  (cd "$REPO_ROOT/jobs/apim-key-rotation" && uv run pytest 2>&1 | tee -a "$LOG") && \
    echo "--- pytest PASSED ---" >> "$LOG" || echo "--- pytest FAILED ---" >> "$LOG"
  echo "" >> "$LOG"
  echo "--- docs build ---" >> "$LOG"
  (cd "$REPO_ROOT" && bash docs/build.sh 2>&1 | tee -a "$LOG") && \
    echo "--- docs build PASSED ---" >> "$LOG" || echo "--- docs build FAILED ---" >> "$LOG"
  echo "" >> "$LOG"
  RAN_CHECK=1
fi

# pii-redaction-service — mirrors .pre-commit-config.yaml: pii-redaction-lint + pii-redaction-tests + pii-redaction-docs
if echo "$FILE_PATH" | grep -q "pii-redaction-service"; then
  echo "=== PII Redaction Service pre-commit checks: $FILE_PATH @ $(date) ===" >> "$LOG"
  echo "--- ruff check ---" >> "$LOG"
  (cd "$REPO_ROOT/pii-redaction-service" && uv run ruff check . 2>&1 | tee -a "$LOG") && \
    echo "--- ruff check PASSED ---" >> "$LOG" || echo "--- ruff check FAILED ---" >> "$LOG"
  echo "" >> "$LOG"
  echo "--- ruff format:check ---" >> "$LOG"
  (cd "$REPO_ROOT/pii-redaction-service" && uv run ruff format --check . 2>&1 | tee -a "$LOG") && \
    echo "--- ruff format:check PASSED ---" >> "$LOG" || echo "--- ruff format:check FAILED ---" >> "$LOG"
  echo "" >> "$LOG"
  echo "--- pytest ---" >> "$LOG"
  (cd "$REPO_ROOT/pii-redaction-service" && uv run pytest 2>&1 | tee -a "$LOG") && \
    echo "--- pytest PASSED ---" >> "$LOG" || echo "--- pytest FAILED ---" >> "$LOG"
  echo "" >> "$LOG"
  echo "--- docs build ---" >> "$LOG"
  (cd "$REPO_ROOT" && bash docs/build.sh 2>&1 | tee -a "$LOG") && \
    echo "--- docs build PASSED ---" >> "$LOG" || echo "--- docs build FAILED ---" >> "$LOG"
  echo "" >> "$LOG"
  RAN_CHECK=1
fi

if [ "$RAN_CHECK" -eq 0 ]; then
  exit 0
fi

echo "" >> "$LOG"

# postToolUse output is ignored; always exit 0
exit 0
