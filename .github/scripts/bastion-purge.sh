#!/usr/bin/env bash
# bastion-purge.sh — Release the Bastion lock; optionally delete Bastion after hours.
#
# Usage: bastion-purge.sh [--integ-follows]
#
#   --integ-follows  Integration tests will run next and own the Bastion teardown.
#                    Skips the after-hours Delete-BastionHost trigger in this job.
#
# Reads env vars:
#   BASTION_ID             Azure resource ID of the Bastion host
#   BASTION_RESOURCE_GROUP Resource group of the Bastion host
#   TOOLS_SUBSCRIPTION_ID  Azure subscription ID for the tools environment
#
# After-hours logic: if it is at or after 19:00 Pacific Time AND --integ-follows is NOT set,
# the Delete-BastionHost automation runbook is triggered to avoid overnight Bastion costs.
set -uo pipefail

INTEG_FOLLOWS=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --integ-follows) INTEG_FOLLOWS=true; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

RG="${BASTION_RESOURCE_GROUP:?BASTION_RESOURCE_GROUP must be set}"
SUB="${TOOLS_SUBSCRIPTION_ID:?TOOLS_SUBSCRIPTION_ID must be set}"

if [[ -z "${BASTION_ID:-}" ]]; then
  echo "No BASTION_ID resolved; Bastion was never locked — nothing to release."
  exit 0
fi

az lock delete --name lock-bastion --resource "$BASTION_ID" --subscription "$SUB" || true
echo "Lock 'lock-bastion' released."

hour_pt="$(TZ=America/Vancouver date +%H)"
# Force base-10: bash arithmetic treats "08"/"09" as invalid octal, so compare via 10#.
if [[ "$INTEG_FOLLOWS" == "false" && "$((10#$hour_pt))" -ge 19 ]]; then
  echo "After 19:00 PT and no integration tests follow — triggering Delete-BastionHost to save cost."
  AA="$(az automation account list -g "$RG" --subscription "$SUB" --query '[0].name' -o tsv)"
  az automation runbook start -g "$RG" --subscription "$SUB" \
    --automation-account-name "$AA" --name Delete-BastionHost || true
else
  echo "Bastion lock released; Bastion remains running (hour_pt=${hour_pt}, integ_follows=${INTEG_FOLLOWS})."
fi
