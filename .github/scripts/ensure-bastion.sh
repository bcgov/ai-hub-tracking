#!/usr/bin/env bash
# ensure-bastion.sh — Provision, lock, and tunnel through Azure Bastion in one step.
#
# Usage: ensure-bastion.sh --privoxy-image <image> [--notes <lock-message>]
#
#   --privoxy-image <image>   Full image ref for the privoxy container
#                             e.g. ghcr.io/bcgov/ai-hub-tracking/azure-proxy/privoxy:latest
#   --notes <message>         Human-readable note stored on the CanNotDelete lock
#                             (default: "Held by GitHub Actions")
#
# Reads env vars:
#   BASTION_RESOURCE_GROUP   resource group containing bastion + jumpbox.
#                             Defaults to value in .github/lib/constants.sh; override via env.
#   TOOLS_SUBSCRIPTION_ID    Azure subscription ID for the tools environment
#   SOCKS_PORT               local SOCKS5 port to open (default: 1080)
#
# Writes to $GITHUB_ENV (inside GitHub Actions):
#   BASTION_NAME, BASTION_ID, VM_ID
#
# Phase 1 — Ensure up
#   If Bastion is absent or not Succeeded, triggers the Create-BastionHost automation runbook
#   (shipped by bcgov/action-deployer-vm-bastion-alz) and waits up to 15 min for it to finish.
#   Also starts the jumpbox VM if it is stopped.
#
# Phase 2 — Lock
#   Acquires a CanNotDelete resource lock so the nightly Delete-BastionHost runbook cannot
#   remove the host mid-deploy. Requires Microsoft.Authorization/locks/* on the scope.
#   Always pair with bastion-purge.sh in an always() step.
#
# Phase 3 — Open tunnel
#   Adds the bastion + ssh Azure CLI extensions, opens an SSH -D SOCKS5 port-forward through
#   Bastion (AAD auth via the OIDC service principal, needs "Virtual Machine Administrator Login"),
#   then starts privoxy to bridge HTTP(S)_PROXY → SOCKS5 with remote DNS.
#   After this script exits, callers should set HTTP_PROXY / HTTPS_PROXY to http://127.0.0.1:8118.
set -euo pipefail

# Load centralized constants (sets BASTION_RESOURCE_GROUP, SOCKS_PORT, etc.).
# Callers may override any variable in the environment before invoking this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/lib/constants.sh
source "$SCRIPT_DIR/../lib/constants.sh"

PRIVOXY_IMAGE=""
NOTES="Held by GitHub Actions"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --privoxy-image) PRIVOXY_IMAGE="$2"; shift 2 ;;
    --notes)         NOTES="$2";         shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -n "$PRIVOXY_IMAGE" ]] || { echo "Usage: $0 --privoxy-image <image> [--notes <msg>]" >&2; exit 1; }

RG="${BASTION_RESOURCE_GROUP:?BASTION_RESOURCE_GROUP must be set}"
SUB="${TOOLS_SUBSCRIPTION_ID:?TOOLS_SUBSCRIPTION_ID must be set}"
SOCKS="${SOCKS_PORT:-1080}"
TUNNEL_LOG="${RUNNER_TEMP:-/tmp}/bastion-tunnel.log"

# ── Phase 1: Ensure Bastion is provisioned ────────────────────────────────────

STATE="$(az network bastion list -g "$RG" --subscription "$SUB" \
  --query '[0].provisioningState' -o tsv 2>/dev/null || true)"

if [[ "$STATE" != "Succeeded" ]]; then
  echo "Bastion not ready (state: ${STATE:-absent}); triggering Create-BastionHost runbook..."
  AA="$(az automation account list -g "$RG" --subscription "$SUB" --query '[0].name' -o tsv)"
  [[ -n "$AA" ]] || { echo "No automation account in $RG — cannot trigger Create-BastionHost. Is enable_bastion_automation set?"; exit 1; }
  az automation runbook start -g "$RG" --subscription "$SUB" \
    --automation-account-name "$AA" --name Create-BastionHost

  for _ in $(seq 1 90); do
    STATE="$(az network bastion list -g "$RG" --subscription "$SUB" \
      --query '[0].provisioningState' -o tsv 2>/dev/null || true)"
    [[ "$STATE" == "Succeeded" ]] && break
    sleep 10
  done
  [[ "$STATE" == "Succeeded" ]] || { echo "Bastion did not reach Succeeded after 15 min"; exit 1; }
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

# ── Phase 3: Open SOCKS tunnel + start privoxy ────────────────────────────────

az extension add --name bastion --yes
az extension add --name ssh --yes

# SSH -D opens a SOCKS5 dynamic port-forward on the runner.
# AAD auth uses the OIDC service principal (needs "Virtual Machine Administrator Login" RBAC).
az network bastion ssh \
  --name "$BASTION_NAME" -g "$RG" --subscription "$SUB" \
  --target-resource-id "$VM_ID" --auth-type AAD \
  -- -D "$SOCKS" -N -q \
     -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
  </dev/null >"$TUNNEL_LOG" 2>&1 &

for _ in $(seq 1 30); do nc -z 127.0.0.1 "$SOCKS" && break; sleep 2; done
nc -z 127.0.0.1 "$SOCKS" || {
  echo "SOCKS tunnel failed to open on port $SOCKS:"
  cat "$TUNNEL_LOG" || true
  exit 1
}
echo "SOCKS5 tunnel open on localhost:$SOCKS"

# privoxy bridges HTTP(S)_PROXY → SOCKS5 with remote DNS (forward-socks5t),
# required for private-endpoint hostnames. --network host reaches the on-host SOCKS port.
docker run -d --name privoxy --network host \
  -e SOCKS_HOST=127.0.0.1 -e SOCKS_PORT="$SOCKS" \
  "$PRIVOXY_IMAGE"
docker logs privoxy
echo "privoxy HTTP bridge ready on localhost:8118"
