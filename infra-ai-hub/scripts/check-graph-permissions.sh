#!/usr/bin/env bash
# =============================================================================
# check-graph-permissions.sh
# =============================================================================
# Called by Terraform external data source to check whether the current
# Azure identity has Microsoft Graph User.Read.All permission.
#
# Returns JSON on stdout (required by the external data source protocol):
#   {"has_user_read_all": "true"}   — permission available
#   {"has_user_read_all": "false"}  — permission missing or check failed
#
# The script intentionally never exits non-zero so Terraform does not fail
# when permissions are absent; it simply reports "false".
# =============================================================================
set -uo pipefail

# external data source sends JSON on stdin — consume it
read -r _INPUT 2>/dev/null || true

# ---------------------------------------------------------------------------
# 1. Acquire a Graph API access token via the current Azure CLI identity
# ---------------------------------------------------------------------------
TOKEN=$(az account get-access-token \
  --resource https://graph.microsoft.com \
  --query accessToken -o tsv 2>/dev/null) || {
  echo '{"has_user_read_all": "false"}'
  exit 0
}

if [[ -z "${TOKEN:-}" ]]; then
  echo '{"has_user_read_all": "false"}'
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Probe Graph API with a minimal call (1 user, 1 field)
#    200 → has User.Read.All    403 → does not
# ---------------------------------------------------------------------------
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer ${TOKEN}" \
  "https://graph.microsoft.com/v1.0/users?\$top=1&\$select=id" 2>/dev/null) || {
  echo '{"has_user_read_all": "false"}'
  exit 0
}

if [[ "${HTTP_STATUS}" == "200" ]]; then
  echo '{"has_user_read_all": "true"}'
else
  echo '{"has_user_read_all": "false"}'
fi
