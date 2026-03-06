#!/usr/bin/env bash
# =============================================================================
# run-local.sh – Start the Tenant Onboarding Portal for local development
# =============================================================================
# Usage:
#   ./run-local.sh              # dev auto-login + in-memory storage (default)
#   ./run-local.sh --oidc       # real Keycloak OIDC (reads creds from .env)
#   ./run-local.sh --storage    # real Azure Table Storage (reads URL from .env)
#   ./run-local.sh --oidc --storage
#   ./run-local.sh --port 9000  # custom port (default: 8000)
#   ./run-local.sh --help
#
# Prerequisites:
#   Python ≥ 3.13 on PATH  (python3 or python)
#   uv (recommended) or pip
#
# First run:
#   The script creates a .venv and installs dependencies automatically.
#
# Dev auto-login mode (default):
#   No Keycloak or Azure Storage account required. The app creates a synthetic
#   session for dev@example.com with the portal-admin role — every page works.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ── Defaults ─────────────────────────────────────────────────────────────────
PORT=8000
USE_OIDC=false
USE_STORAGE=false

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --oidc)     USE_OIDC=true;    shift ;;
    --storage)  USE_STORAGE=true; shift ;;
    --port)     PORT="$2";        shift 2 ;;
    --help|-h)
      sed -n '2,20p' "$0" | sed 's/^# \{0,2\}//'
      exit 0 ;;
    *)
      echo "Unknown option: $1  (use --help for usage)" >&2
      exit 1 ;;
  esac
done

# ── Load .env if present ─────────────────────────────────────────────────────
if [[ -f .env ]]; then
  echo "→ Loading .env"
  set -o allexport
  # shellcheck disable=SC1091
  source .env
  set +o allexport
else
  echo "→ No .env found — using defaults (dev auto-login + in-memory storage)"
  echo "  Copy .env.example to .env to customise settings."
fi

# ── Generate a throwaway secret key if one isn't set ─────────────────────────
if [[ -z "${PORTAL_SECRET_KEY:-}" || "$PORTAL_SECRET_KEY" == "change-me-at-least-32-chars-long-here" ]]; then
  echo "→ PORTAL_SECRET_KEY not set — generating a temporary key for this session"
  PORTAL_SECRET_KEY=$(python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null \
    || python  -c "import secrets; print(secrets.token_hex(32))")
  export PORTAL_SECRET_KEY
fi

# ── Disable OIDC / storage when flags are not set ────────────────────────────
if [[ "$USE_OIDC" == "false" ]]; then
  if [[ -n "${PORTAL_OIDC_DISCOVERY_URL:-}" ]]; then
    echo "→ --oidc not passed — overriding PORTAL_OIDC_DISCOVERY_URL to '' (dev auto-login)"
  fi
  export PORTAL_OIDC_DISCOVERY_URL=""
fi

if [[ "$USE_STORAGE" == "false" ]]; then
  if [[ -n "${PORTAL_TABLE_STORAGE_ACCOUNT_URL:-}" || -n "${PORTAL_TABLE_STORAGE_CONNECTION_STRING:-}" ]]; then
    echo "→ --storage not passed — clearing storage vars (in-memory mode)"
  fi
  export PORTAL_TABLE_STORAGE_ACCOUNT_URL=""
  export PORTAL_TABLE_STORAGE_CONNECTION_STRING=""
fi

# ── Virtualenv setup ──────────────────────────────────────────────────────────
VENV=".venv"

if [[ ! -d "$VENV" ]]; then
  echo "→ Creating virtualenv in ${VENV}/"
  if command -v uv &>/dev/null; then
    uv venv "$VENV"
  else
    python3 -m venv "$VENV" 2>/dev/null || python -m venv "$VENV"
  fi
fi

# Activate — Windows (Git Bash / MSYS2) uses Scripts/, Unix uses bin/
if [[ -f "${VENV}/Scripts/activate" ]]; then
  # shellcheck disable=SC1091
  source "${VENV}/Scripts/activate"
else
  # shellcheck disable=SC1091
  source "${VENV}/bin/activate"
fi

# ── Install / sync dependencies ───────────────────────────────────────────────
echo "→ Installing dependencies"
if command -v uv &>/dev/null; then
  uv pip install -q -r requirements.txt
else
  pip install -q -r requirements.txt
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "┌─────────────────────────────────────────────────────┐"
echo "│  Tenant Onboarding Portal – local dev               │"
echo "├─────────────────────────────────────────────────────┤"
printf "│  URL      http://localhost:%-26s│\n" "${PORT}"
if [[ "$USE_OIDC" == "true" ]]; then
  printf "│  Auth     Keycloak OIDC (%-27s│\n" "${PORTAL_OIDC_DISCOVERY_URL:0:25}...)"
else
  echo   "│  Auth     dev auto-login  (dev@example.com + admin) │"
fi
if [[ "$USE_STORAGE" == "true" ]]; then
  printf "│  Storage  Azure Table Storage                        │\n"
else
  echo   "│  Storage  in-memory (data lost on restart)           │"
fi
echo "└─────────────────────────────────────────────────────┘"
echo ""

# ── Run ───────────────────────────────────────────────────────────────────────
exec uvicorn src.main:app \
  --reload \
  --port "$PORT" \
  --log-level info
