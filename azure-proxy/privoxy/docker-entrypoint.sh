#!/usr/bin/env sh
set -eu

LISTEN_ADDRESS="${PRIVOXY_LISTEN_ADDRESS:-0.0.0.0:8118}"
LOG_FILE="${PRIVOXY_LOG_FILE:-/var/log/privoxy/logfile}"
LOG_LEVEL="${PRIVOXY_LOG_LEVEL:-0}"
SOCKS_HOST="${SOCKS_HOST:-host.docker.internal}"
SOCKS_PORT="${SOCKS_PORT:-18080}"

mkdir -p "$(dirname "$LOG_FILE")" /etc/privoxy
: > "$LOG_FILE" || true

# Generate a minimal Privoxy config that forwards everything through the SOCKS5 proxy.
# `forward-socks5t` forces remote DNS resolution through SOCKS (critical for Private Endpoints).
cat > /etc/privoxy/config <<EOF
listen-address  $LISTEN_ADDRESS

toggle 1
enable-remote-toggle 0
enable-edit-actions 0
enable-remote-http-toggle 0

# Logging
logdir $(dirname "$LOG_FILE")
logfile $(basename "$LOG_FILE")
debug $LOG_LEVEL

# IMPORTANT: send all traffic via SOCKS5 with remote DNS (socks5t)
forward-socks5t / $SOCKS_HOST:$SOCKS_PORT .
EOF

exec /usr/sbin/privoxy --no-daemon /etc/privoxy/config
