#!/usr/bin/env bash
# bastion-purge.sh — Release the Bastion lock; after hours, deallocate the jumpbox VM
#                    and delete the Bastion host to save cost.
#
# Usage: bastion-purge.sh [--integ-follows]
#
#   --integ-follows  Integration tests will run next and own the Bastion teardown.
#                    Skips the after-hours VM deallocate + Delete-BastionHost in this job.
#
# Reads env vars:
#   BASTION_ID             Azure resource ID of the Bastion host
#   BASTION_RESOURCE_GROUP Resource group of the Bastion host.
#                          Defaults to value in .github/lib/constants.sh; override via env.
#   TOOLS_SUBSCRIPTION_ID  Azure subscription ID for the tools environment
#   VM_ID                  Azure resource ID of the jumpbox VM (exported by ensure-bastion.sh;
#                          falls back to the first VM in BASTION_RESOURCE_GROUP)
#
# After-hours logic: if it is at or after 19:00 Pacific Time AND --integ-follows is NOT set,
# the jumpbox VM is deallocated and the Delete-BastionHost automation runbook is triggered to
# avoid overnight Bastion + VM costs.
set -uo pipefail

# Load centralized constants (sets BASTION_RESOURCE_GROUP, etc.).
# Callers may override any variable in the environment before invoking this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/lib/constants.sh
source "$SCRIPT_DIR/../lib/constants.sh"

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
  echo "After 19:00 PT and no integration tests follow — tearing down Bastion + jumpbox to save cost."

  # Deallocate the jumpbox VM (stops compute charges; the OS disk persists, so the next
  # ensure-bastion.sh just restarts it). Mirrors the `az vm start` in ensure-bastion.sh.
  VM="${VM_ID:-}"
  [[ -n "$VM" ]] || VM="$(az vm list -g "$RG" --subscription "$SUB" --query '[0].id' -o tsv 2>/dev/null || true)"
  if [[ -n "$VM" ]]; then
    echo "Deallocating jumpbox VM..."
    az vm deallocate --ids "$VM" --no-wait || true
  else
    echo "No jumpbox VM resolved; nothing to deallocate."
  fi

  AA="$(az automation account list -g "$RG" --subscription "$SUB" --query '[0].name' -o tsv)"
  az automation runbook start -g "$RG" --subscription "$SUB" \
    --automation-account-name "$AA" --name Delete-BastionHost || true
else
  echo "Bastion lock released; Bastion + jumpbox remain running (hour_pt=${hour_pt}, integ_follows=${INTEG_FOLLOWS})."
fi
