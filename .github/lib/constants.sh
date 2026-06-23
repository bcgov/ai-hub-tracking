#!/usr/bin/env bash
# .github/lib/constants.sh — Centralized constants for ai-hub-tracking.
#
# Usage in shell scripts (auto-resolves path relative to this file):
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "$SCRIPT_DIR/../lib/constants.sh"       # from .github/scripts/
#   source "$SCRIPT_DIR/../../.github/lib/constants.sh"  # from elsewhere
#
# Usage in GitHub Actions workflow run: steps (after checkout):
#   source .github/lib/constants.sh
#   echo "TF_VERSION=$TF_VERSION" >> "$GITHUB_ENV"
#
# All variables use ${VAR:-default} so callers can override by setting VAR in
# the environment before sourcing this file.

# ── Terraform ─────────────────────────────────────────────────────────────────
# Pin shared across all workflows. Change here; every job picks it up.
export TF_VERSION="${TF_VERSION:-1.12.2}"

# ── Azure region ──────────────────────────────────────────────────────────────
export LOCATION="${LOCATION:-Canada Central}"

# ── Resource groups ───────────────────────────────────────────────────────────
# Tools-env shared infra (initial-setup/infra Terraform root).
export RG_INITIAL_SETUP="${RG_INITIAL_SETUP:-ai-hub-tools}"
# Dedicated Bastion + jumpbox RG (bcgov/action-deployer-vm-bastion-alz,
# resource_group_name input in .github/workflows/.deployer.yml).
export BASTION_RESOURCE_GROUP="${BASTION_RESOURCE_GROUP:-ai-hub-bastion-tools}"

# ── App identity ──────────────────────────────────────────────────────────────
export APP_NAME="${APP_NAME:-ai-hub}"                 # initial-setup/infra
export APP_ENV_TOOLS="${APP_ENV_TOOLS:-tools}"

# ── Bastion / tunnel ports ────────────────────────────────────────────────────
# SOCKS5 port opened by ensure-bastion.sh on the runner.
export SOCKS_PORT="${SOCKS_PORT:-1080}"
# Privoxy HTTP/HTTPS proxy port (bridges HTTP_PROXY → SOCKS5).
export PRIVOXY_PORT="${PRIVOXY_PORT:-8118}"
# Local-dev bastion-proxy.sh SOCKS port (matches docker-compose.yml).
export BASTION_PROXY_PORT="${BASTION_PROXY_PORT:-8228}"
