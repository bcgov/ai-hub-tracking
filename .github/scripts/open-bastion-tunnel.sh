#!/usr/bin/env bash
# open-bastion-tunnel.sh — Open a SOCKS5 tunnel through Azure Bastion + start privoxy.
#
# Usage: open-bastion-tunnel.sh --privoxy-image <image>
#
#   --privoxy-image <image>   Full image ref for the privoxy container
#                             e.g. ghcr.io/bcgov/ai-hub-tracking/azure-proxy/privoxy:latest
#
# Reads env vars:
#   BASTION_RESOURCE_GROUP   resource group containing bastion + jumpbox (from constants.sh).
#   TOOLS_SUBSCRIPTION_ID    Azure subscription ID for the tools environment.
#   SOCKS_PORT               local SOCKS5 port to open (default: 1080).
#   BASTION_NAME, VM_ID      exported by ensure-bastion.sh via $GITHUB_ENV; auto-discovered if absent.
#
# Run this AFTER ensure-bastion.sh AND a fresh azure/login. The AAD-authenticated
# `az network bastion ssh` needs a GitHub OIDC client assertion that is still within its
# ~5 min validity window; provisioning waits inside ensure-bastion.sh can exhaust it,
# which surfaces as AADSTS700024 (client assertion is not within its valid time range).
#
# After this script exits, set HTTP_PROXY / HTTPS_PROXY to http://127.0.0.1:8118.
set -euo pipefail

# Load centralized constants (sets BASTION_RESOURCE_GROUP, SOCKS_PORT, etc.).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/lib/constants.sh
source "$SCRIPT_DIR/../lib/constants.sh"

PRIVOXY_IMAGE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --privoxy-image) PRIVOXY_IMAGE="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -n "$PRIVOXY_IMAGE" ]] || { echo "Usage: $0 --privoxy-image <image>" >&2; exit 1; }

RG="${BASTION_RESOURCE_GROUP:?BASTION_RESOURCE_GROUP must be set}"
SUB="${TOOLS_SUBSCRIPTION_ID:?TOOLS_SUBSCRIPTION_ID must be set}"
SOCKS="${SOCKS_PORT:-1080}"
TUNNEL_LOG="${RUNNER_TEMP:-/tmp}/bastion-tunnel.log"

# Reuse values exported by ensure-bastion.sh; fall back to discovery for standalone runs.
BASTION_NAME="${BASTION_NAME:-$(az network bastion list -g "$RG" --subscription "$SUB" --query '[0].name' -o tsv)}"
[[ -n "$BASTION_NAME" ]] || { echo "No Bastion found in $RG — run ensure-bastion.sh first." >&2; exit 1; }
VM_ID="${VM_ID:-$(az vm list -g "$RG" --subscription "$SUB" --query '[0].id' -o tsv)}"
[[ -n "$VM_ID" ]] || { echo "No jumpbox VM found in $RG — cannot open the tunnel." >&2; exit 1; }

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
