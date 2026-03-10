#!/usr/bin/env bash
# =============================================================================
# run-local.sh – Start the Tenant Onboarding Portal for local development
# =============================================================================
# Usage:
#   ./backend/run-local.sh                    # mock auth + in-memory storage
#   ./backend/run-local.sh --oidc             # real Keycloak OIDC
#   ./backend/run-local.sh --storage          # real Azure Table Storage
#   ./backend/run-local.sh --oidc --storage
#   ./backend/run-local.sh --port 9000        # backend port (default: 8000)
#   ./backend/run-local.sh --frontend-port 5174
#   ./run-local.sh --help
#
# Prerequisites:
#   Node.js major version matching ../.node-version on PATH
#   npm
#
# Default mode:
#   Starts the backend and the Vite frontend dev server together. The frontend
#   proxies /api and /healthz to the backend and mock auth resolves `dev-token`
#   to a local admin identity when --oidc is not supplied.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
FRONTEND_DIR="$SCRIPT_DIR/../frontend"
PORTAL_ROOT="$SCRIPT_DIR/.."
NODE_VERSION_FILE="${PORTAL_NODE_VERSION_FILE:-$PORTAL_ROOT/.node-version}"

# ── Defaults ─────────────────────────────────────────────────────────────────
PORT=8000
FRONTEND_PORT=5173
USE_OIDC=false
USE_STORAGE=false

required_node_major() {
  if [[ ! -f "$NODE_VERSION_FILE" ]]; then
    echo "Missing Node version file: $NODE_VERSION_FILE" >&2
    exit 1
  fi

  tr -d '[:space:]' < "$NODE_VERSION_FILE"
}

ensure_node_version() {
  local required_major
  local current_major

  if ! command -v node &>/dev/null; then
    echo "node is required to run the portal locally." >&2
    exit 1
  fi

  required_major="$(required_node_major)"
  current_major="$(node -p "process.versions.node.split('.')[0]")"

  if [[ "$current_major" != "$required_major" ]]; then
    echo "Node.js major version ${required_major} is required (found ${current_major})." >&2
    exit 1
  fi
}

cleanup() {
  local exit_code=$?

  if [[ -n "${BACKEND_PID:-}" ]]; then
    kill "$BACKEND_PID" >/dev/null 2>&1 || true
  fi

  if [[ -n "${FRONTEND_PID:-}" ]]; then
    kill "$FRONTEND_PID" >/dev/null 2>&1 || true
  fi

  wait >/dev/null 2>&1 || true
  exit "$exit_code"
}

trap cleanup EXIT INT TERM

# ── Argument parsing ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --oidc)     USE_OIDC=true;    shift ;;
    --storage)  USE_STORAGE=true; shift ;;
    --port)     PORT="$2";        shift 2 ;;
    --frontend-port) FRONTEND_PORT="$2"; shift 2 ;;
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
  echo "→ No .env found — using defaults (dev bearer-token mode + in-memory storage)"
  echo "  Copy .env.example to .env to customise settings."
fi

# ── Disable OIDC / storage when flags are not set ────────────────────────────
if [[ "$USE_OIDC" == "false" ]]; then
  if [[ -n "${PORTAL_OIDC_DISCOVERY_URL:-}" ]]; then
    echo "→ --oidc not passed — overriding PORTAL_OIDC_DISCOVERY_URL to '' (dev bearer-token mode)"
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

# ── Install / sync dependencies ───────────────────────────────────────────────
ensure_node_version

if ! command -v npm &>/dev/null; then
  echo "npm is required to run the portal locally." >&2
  exit 1
fi

echo "→ Installing backend dependencies"
npm install >/dev/null

echo "→ Installing frontend dependencies"
pushd "$FRONTEND_DIR" >/dev/null
npm install >/dev/null
popd >/dev/null

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "┌────────────────────────────────────────────────────────────┐"
echo "│  Tenant Onboarding Portal – local dev                    │"
echo "├────────────────────────────────────────────────────────────┤"
printf "│  Backend  http://localhost:%-34s│\n" "${PORT}"
printf "│  Frontend http://localhost:%-34s│\n" "${FRONTEND_PORT}"
if [[ "$USE_OIDC" == "true" ]]; then
  printf "│  Auth     Keycloak OIDC (%-35s│\n" "${PORTAL_OIDC_DISCOVERY_URL:0:33}...)"
else
  echo   "│  Auth     mock auth (Authorization: Bearer dev-token) │"
fi
if [[ "$USE_STORAGE" == "true" ]]; then
  echo   "│  Storage  Azure Table Storage                         │"
else
  echo   "│  Storage  in-memory (data lost on restart)            │"
fi
echo "└────────────────────────────────────────────────────────────┘"
echo ""

# ── Run ───────────────────────────────────────────────────────────────────────
export PORT
export PORTAL_FRONTEND_DEV_URL="http://localhost:${FRONTEND_PORT}"
PORTAL_API_PORT="$PORT" npm run dev --prefix "$FRONTEND_DIR" -- --port "$FRONTEND_PORT" &
FRONTEND_PID=$!

npm run start:dev &
BACKEND_PID=$!

wait -n "$FRONTEND_PID" "$BACKEND_PID"
