# Privoxy (HTTP → SOCKS) Bridge

This folder contains a tiny Alpine-based Docker image that runs **Privoxy** as an **HTTP proxy** and forwards all traffic through an existing **SOCKS5** proxy (typically a Chisel client tunnel).

Why this exists:
- Many tools (VS Code REST Client, Postman, browsers) support **HTTP/HTTPS proxies** more reliably than **SOCKS**.
- For Azure Private Endpoints, it’s important to preserve the **real HTTPS hostname** (SNI) and often do **remote DNS**; this bridge uses `forward-socks5t` for that.

## Architecture

```
VS Code / Postman (HTTP proxy)
  -> http://127.0.0.1:8118 (Privoxy)
      -> SOCKS5 (Chisel client tunnel)
          -> Azure PaaS over Private Link
```

## Prerequisites

- A working local SOCKS5 proxy (example: Chisel client) reachable at a host/port.
- Docker Desktop running.

## 1) Start your Chisel SOCKS tunnel

Example (SOCKS available locally on port 18080):

```powershell
docker run --rm -it -p 18080:1080 jpillora/chisel:latest client `
  --auth "tunnel:<PASSWORD>" `
  https://<your-chisel-server-url> `
  0.0.0.0:1080:socks
```

Notes:
- `0.0.0.0:1080:socks` is important when using Docker port publishing.
- Auth format is `username:password`.

## 2) Build the Privoxy bridge image

From repo root:

```powershell
docker build -t local/privoxy-socks-bridge:latest .\http-client\proxy\privoxy
```

## 3) Run Privoxy (HTTP proxy on 8118)

This runs Privoxy on `127.0.0.1:8118` and forwards through the SOCKS proxy.

```powershell
docker run --rm -d --name privoxy \
  -p 127.0.0.1:8118:8118 \
  -e SOCKS_HOST=host.docker.internal \
  -e SOCKS_PORT=18080 \
  local/privoxy-socks-bridge:latest
```

Environment variables:
- `SOCKS_HOST` (default: `host.docker.internal`) — where the SOCKS proxy is reachable from inside the Privoxy container.
- `SOCKS_PORT` (default: `18080`) — your local SOCKS port.

If your SOCKS proxy is not on the host, set `SOCKS_HOST` to the appropriate hostname/IP.

## 4) Verify the bridge is working

Confirm traffic is going through the proxy:

```powershell
curl.exe --proxy http://127.0.0.1:8118 https://ifconfig.me
```

This should return the outbound IP from the tunnel side (not your local public IP).

## 5) Configure clients

### VS Code REST Client

These proxy settings are **Application scoped**, so they must be set in **User Settings (Default profile)**, not workspace settings.

Add:

```jsonc
{
  "http.proxy": "http://127.0.0.1:8118",
  "http.proxySupport": "on",
  "rest-client.useHostProxy": true,
  "rest-client.proxy": "http://127.0.0.1:8118"
}
```

Then run `Developer: Reload Window`.

### Postman

- Settings → Proxy
- Add a custom proxy configuration:
  - Type: HTTP/HTTPS
  - Host: `127.0.0.1`
  - Port: `8118`
- Do **not** enable “proxy auth” unless you configured Privoxy to require it.

## Key Vault / Private Endpoint notes

- Use the real service URL (example):
  - `https://<vault-name>.vault.azure.net/...`
- If you see Key Vault errors indicating public access (or the response headers show your public IP), your client is bypassing the proxy.

## Troubleshooting

- Privoxy container starts but requests fail: confirm the SOCKS proxy is reachable from the Privoxy container.
  - If SOCKS is on the host: use `SOCKS_HOST=host.docker.internal`.
- Curl works with `--proxy socks5h://...` but not with HTTP proxy:
  - Ensure Privoxy is running and `curl --proxy http://127.0.0.1:8118 https://ifconfig.me` works.
- VS Code still goes direct:
  - Ensure you set proxy settings in **User Settings (Default profile)** and reloaded the window.

## Security

- Do not commit access tokens to `.env` files.
- Chisel auth (`--auth tunnel:...`) should be treated as a secret.
