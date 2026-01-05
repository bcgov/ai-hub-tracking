#!/usr/bin/env sh

set -eu
set -o pipefail 2>/dev/null || true

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

MAX_RETRIES="${MAX_RETRIES:-30}"
DELAY_SECONDS="${DELAY_SECONDS:-5}"
CHISEL_BIN="${CHISEL_BIN:-/usr/local/bin/chisel}"
CHISEL_PORT="${CHISEL_PORT:-${PORT:-80}}"
CHISEL_HOST="${CHISEL_HOST:-0.0.0.0}"
CHISEL_AUTH="${CHISEL_AUTH:-}"
CHISEL_BACKEND="${CHISEL_BACKEND:-http://127.0.0.1:9999}"
CHISEL_ENABLE_SOCKS5="${CHISEL_ENABLE_SOCKS5:-true}"
CHISEL_EXTRA_ARGS="${CHISEL_EXTRA_ARGS:-}"

if ! command -v "$CHISEL_BIN" >/dev/null 2>&1; then
  echo "$(ts) - ERROR: chisel binary not found at '$CHISEL_BIN'"
  exit 127
fi

if [ -z "$CHISEL_AUTH" ]; then
  echo "$(ts) - ERROR: CHISEL_AUTH is not set or empty; refusing to start unauthenticated tunnel."
  exit 1
fi

# Serve a minimal health endpoint locally; chisel will reverse-proxy normal HTTP requests to it.
# busybox httpd serves files from -h directory.
mkdir -p /var/www
if [ ! -f /var/www/healthz ]; then
  echo '{"status":"healthy"}' > /var/www/healthz
fi

stop=0
status=1

on_term() {
  stop=1
  echo "$(ts) - Received termination signal; stopping."
}
trap on_term INT TERM

attempt=1
while [ "$attempt" -le "$MAX_RETRIES" ] && [ "$stop" -eq 0 ]; do
  echo "$(ts) - Starting health backend on 127.0.0.1:9999"
  httpd -f -p 127.0.0.1:9999 -h /var/www &
  httpd_pid=$!

  echo "$(ts) - Starting chisel server on ${CHISEL_HOST}:${CHISEL_PORT} (attempt $attempt/$MAX_RETRIES)"

  auth_args=""
  if [ -n "$CHISEL_AUTH" ]; then
    auth_args="--auth $CHISEL_AUTH"
  fi

  socks_args=""
  case "${CHISEL_ENABLE_SOCKS5}" in
    1|true|TRUE|yes|YES|on|ON) socks_args="--socks5" ;;
  esac

  # shellcheck disable=SC2086
  "$CHISEL_BIN" server --host "$CHISEL_HOST" --port "$CHISEL_PORT" --backend "$CHISEL_BACKEND" $socks_args $auth_args $CHISEL_EXTRA_ARGS || true
  status=$?

  if kill -0 "$httpd_pid" >/dev/null 2>&1; then
    kill "$httpd_pid" >/dev/null 2>&1 || true
  fi

  if [ "$status" -eq 0 ]; then
    echo "$(ts) - Chisel exited cleanly (code 0). Not retrying."
    exit 0
  fi

  echo "$(ts) - Chisel exited with code $status"
  attempt=$((attempt + 1))

  if [ "$attempt" -le "$MAX_RETRIES" ] && [ "$stop" -eq 0 ]; then
    echo "$(ts) - Retrying in ${DELAY_SECONDS}s..."
    i=0
    while [ "$i" -lt "$DELAY_SECONDS" ]; do
      [ "$stop" -ne 0 ] && break
      sleep 1
      i=$((i + 1))
    done
  fi
done

if [ "$stop" -ne 0 ]; then
  echo "$(ts) - Stopped by signal. Exiting with code $status."
else
  echo "$(ts) - Max retries ($MAX_RETRIES) reached. Exiting with code $status."
fi

exit "$status"
