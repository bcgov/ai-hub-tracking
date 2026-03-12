#!/bin/bash
# guard-destructive.sh
# preToolUse hook — denies dangerous bash commands that could destroy infrastructure,
# force-push history, or perform hard-resets without explicit user confirmation.

set -e

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.toolName')

# Only inspect bash tool invocations
if [ "$TOOL_NAME" != "bash" ]; then
  exit 0
fi

TOOL_ARGS=$(echo "$INPUT" | jq -r '.toolArgs // "{}"')
COMMAND=$(echo "$TOOL_ARGS" | jq -r '.command // empty' 2>/dev/null || true)

if [ -z "$COMMAND" ]; then
  exit 0
fi

# -- Force push -----------------------------------------------------------------
if echo "$COMMAND" | grep -qE 'git push.*(--force|-f)\b'; then
  echo '{"permissionDecision":"deny","permissionDecisionReason":"git force-push requires explicit user confirmation"}'
  exit 0
fi

# -- Hard reset -----------------------------------------------------------------
if echo "$COMMAND" | grep -qE 'git reset --hard'; then
  echo '{"permissionDecision":"deny","permissionDecisionReason":"git reset --hard requires explicit user confirmation"}'
  exit 0
fi

# -- rm -rf targeting critical top-level directories ----------------------------
if echo "$COMMAND" | grep -qE 'rm\s+-rf\s+.*(infra-ai-hub|initial-setup|sensitive|ssl_certs|jobs|\.github)'; then
  echo '{"permissionDecision":"deny","permissionDecisionReason":"Recursive deletion of infrastructure or sensitive directories requires explicit user confirmation"}'
  exit 0
fi

# -- Terraform destroy ----------------------------------------------------------
if echo "$COMMAND" | grep -qE 'terraform\s+destroy'; then
  echo '{"permissionDecision":"deny","permissionDecisionReason":"terraform destroy requires explicit user confirmation"}'
  exit 0
fi

# Allow all other commands
exit 0
