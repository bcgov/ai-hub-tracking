#!/usr/bin/env bash
# ensure-bastion.sh — Provision and lock Azure Bastion (tunnel opened separately).
#
# Usage: ensure-bastion.sh [--notes <lock-message>]
#
#   --notes <message>   Human-readable note stored on the CanNotDelete lock
#                       (default: "Held by GitHub Actions")
#
# Reads env vars:
#   BASTION_RESOURCE_GROUP   resource group containing bastion + jumpbox.
#                             Defaults to value in .github/lib/constants.sh; override via env.
#   TOOLS_SUBSCRIPTION_ID    Azure subscription ID for the tools environment
#
# Writes to $GITHUB_ENV (inside GitHub Actions):
#   BASTION_NAME, BASTION_ID, VM_ID
#
# Phase 1 — Ensure up
#   If Bastion is in Deleting state, waits for deletion to finish first.
#   If Bastion is absent or not Succeeded, triggers the Create-BastionHost automation runbook
#   (shipped by bcgov/action-deployer-vm-bastion-alz) and waits for it to finish.
#   Total wait budget across deletion + creation is 25 min.
#   Also starts the jumpbox VM if it is stopped.
#
# Phase 2 — Lock
#   Acquires a CanNotDelete resource lock so the nightly Delete-BastionHost runbook cannot
#   remove the host mid-deploy. Requires Microsoft.Authorization/locks/* on the scope.
#   Always pair with bastion-purge.sh in an always() step.
#
# The SOCKS5 tunnel is opened separately by open-bastion-tunnel.sh, which must run AFTER a
# fresh azure/login. Provisioning waits above can exceed the ~5 min lifetime of the GitHub
# OIDC client assertion; if it expires, the AAD-authenticated `az network bastion ssh` in the
# tunnel step fails with AADSTS700024 (client assertion is not within its valid time range).
set -euo pipefail

# Load centralized constants (sets BASTION_RESOURCE_GROUP, SOCKS_PORT, etc.).
# Callers may override any variable in the environment before invoking this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/lib/constants.sh
source "$SCRIPT_DIR/../lib/constants.sh"

NOTES="Held by GitHub Actions"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes) NOTES="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

RG="${BASTION_RESOURCE_GROUP:?BASTION_RESOURCE_GROUP must be set}"
SUB="${TOOLS_SUBSCRIPTION_ID:?TOOLS_SUBSCRIPTION_ID must be set}"

# ── Phase 1: Ensure Bastion is provisioned ────────────────────────────────────

STATE="$(az network bastion list -g "$RG" --subscription "$SUB" \
  --query '[0].provisioningState' -o tsv 2>/dev/null || true)"

if [[ "$STATE" != "Succeeded" ]]; then
  MAX_POLLS=150  # 25 min total budget (150 × 10 s), shared across deletion-wait + creation-wait
  polls=0

  # If Bastion is mid-deletion, wait for it to disappear before triggering re-create.
  if [[ "$STATE" == "Deleting" ]]; then
    echo "Bastion is being deleted; waiting for deletion to complete before re-creating..."
    while [[ "$polls" -lt "$MAX_POLLS" && "$STATE" == "Deleting" ]]; do
      sleep 10
      polls=$(( polls + 1 ))
      STATE="$(az network bastion list -g "$RG" --subscription "$SUB" \
        --query '[0].provisioningState' -o tsv 2>/dev/null || true)"
    done
    [[ "$STATE" != "Deleting" ]] || { echo "Bastion deletion did not complete within 25 min"; exit 1; }
    echo "Deletion complete (state: ${STATE:-absent})"
  fi

  if [[ "$STATE" != "Succeeded" ]]; then
    echo "Bastion not ready (state: ${STATE:-absent}); triggering Create-BastionHost runbook..."
    AA="$(az automation account list -g "$RG" --subscription "$SUB" --query '[0].name' -o tsv)"
    [[ -n "$AA" ]] || { echo "No automation account in $RG — cannot trigger Create-BastionHost. Is enable_bastion_automation set?"; exit 1; }
    az automation runbook start -g "$RG" --subscription "$SUB" \
      --automation-account-name "$AA" --name Create-BastionHost

    while [[ "$polls" -lt "$MAX_POLLS" ]]; do
      sleep 10
      polls=$(( polls + 1 ))
      STATE="$(az network bastion list -g "$RG" --subscription "$SUB" \
        --query '[0].provisioningState' -o tsv 2>/dev/null || true)"
      [[ "$STATE" == "Succeeded" ]] && break
    done
    [[ "$STATE" == "Succeeded" ]] || { echo "Bastion did not reach Succeeded after 25 min"; exit 1; }
  fi
fi

VM_ID="$(az vm list -g "$RG" --subscription "$SUB" --query '[0].id' -o tsv)"
[[ -n "$VM_ID" ]] || { echo "No jumpbox VM found in $RG — cannot open the tunnel."; exit 1; }
az vm start --ids "$VM_ID" || true

BASTION_NAME="$(az network bastion list -g "$RG" --subscription "$SUB" \
  --query '[0].name' -o tsv)"
BASTION_ID="$(az network bastion show -g "$RG" -n "$BASTION_NAME" \
  --subscription "$SUB" --query id -o tsv)"

echo "Bastion ready: $BASTION_NAME | VM: $VM_ID"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "BASTION_NAME=$BASTION_NAME"
    echo "BASTION_ID=$BASTION_ID"
    echo "VM_ID=$VM_ID"
  } >> "$GITHUB_ENV"
fi

# ── Phase 2: Lock ─────────────────────────────────────────────────────────────

az lock create \
  --name lock-bastion \
  --lock-type CanNotDelete \
  --resource "$BASTION_ID" \
  --subscription "$SUB" \
  --notes "$NOTES" || true

echo "Lock 'lock-bastion' acquired on Bastion."
