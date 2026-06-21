# Privoxy (HTTP → SOCKS) Bridge

This folder contains a tiny Alpine-based Docker image that runs **Privoxy** as an **HTTP proxy** and forwards all traffic through an existing **SOCKS5** proxy — the SOCKS5 proxy opened by **Azure Bastion native client tunnelling** (see [`initial-setup/infra/scripts/bastion-proxy.md`](../../initial-setup/infra/scripts/bastion-proxy.md)).

Why this exists:
- Many tools (VS Code REST Client, Postman, browsers, the Azure CLI, Terraform) support **HTTP/HTTPS proxies** more reliably than **SOCKS**.
- For Azure Private Endpoints, it’s important to preserve the **real HTTPS hostname** (SNI) and do **remote DNS**; this bridge uses `forward-socks5t` for that (DNS is resolved on the jumpbox side, where Azure Private DNS resolves the private IPs).

## Architecture

```
VS Code / Postman / Terraform (HTTP proxy)
  -> http://127.0.0.1:8118 (Privoxy)
      -> SOCKS5 (Azure Bastion tunnel → jumpbox, via the Bastion proxy script)
          -> Azure PaaS over Private Link
```

## Prerequisites

- A working local SOCKS5 proxy from Azure Bastion (see step 1).
- Docker Desktop running.

## 1) Start your Bastion SOCKS tunnel

The Bastion + jumpbox are provisioned by the `bcgov/action-deployer-vm-bastion-alz` action in the
`ai-hub-tools` resource group (tools subscription). That action also publishes the tunnel script, so
fetch it from upstream (we don't vendor it) and open a SOCKS5 proxy through Bastion native
tunnelling (default port `8228`):

```bash
curl -fsSL \
  https://raw.githubusercontent.com/bcgov/action-deployer-vm-bastion-alz/v1.0.0/bastion-consumer-scripts/bastion-proxy.sh \
  -o bastion-proxy.sh && chmod +x bastion-proxy.sh

./bastion-proxy.sh -g ai-hub-tools -b ai-hub-bastion -v ai-hub-jumpbox \
  -s <tools-subscription-id> -t <tenant-id> -p 8228
```

This prints `SOCKS5 proxy ready on localhost:8228`. Leave it running. Full instructions (PowerShell,
options, troubleshooting) are in [`initial-setup/infra/scripts/bastion-proxy.md`](../../initial-setup/infra/scripts/bastion-proxy.md).

## 2) Build the Privoxy bridge image (optional — a prebuilt image is published to GHCR)

From this folder:

```bash
docker build -t local/privoxy-socks-bridge:latest .
```

## 3) Run Privoxy (HTTP proxy on 8118)

This runs Privoxy on `127.0.0.1:8118` and forwards through the Bastion SOCKS proxy.

```bash
docker run --rm -d --name privoxy \
  -p 127.0.0.1:8118:8118 \
  -e SOCKS_HOST=host.docker.internal \
  -e SOCKS_PORT=8228 \
  ghcr.io/bcgov/ai-hub-tracking/azure-proxy/privoxy:latest
```

Or use the repo's [`docker-compose.yml`](../../docker-compose.yml): `docker compose up -d`.

Environment variables:
- `SOCKS_HOST` (default: `host.docker.internal`) — where the SOCKS proxy is reachable from inside the Privoxy container.
- `SOCKS_PORT` (default: `8228`) — the local SOCKS port that `bastion-proxy.sh` opened.

## 4) Verify the bridge is working

```bash
curl.exe --proxy http://127.0.0.1:8118 https://ifconfig.me
```

This should return the outbound IP from the jumpbox side (not your local public IP).

## 5) Configure clients

### VS Code REST Client

These proxy settings are **Application scoped**, so they must be set in **User Settings (Default profile)**, not workspace settings.

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

- Use the real service URL (example): `https://<vault-name>.vault.azure.net/...`
- If you see Key Vault errors indicating public access (or the response headers show your public IP), your client is bypassing the proxy.

## Troubleshooting

- Privoxy container starts but requests fail: confirm the Bastion SOCKS proxy is still running
  (the Bastion proxy script) and reachable from the Privoxy container.
  - If SOCKS is on the host: use `SOCKS_HOST=host.docker.internal`.
- `curl --proxy socks5h://...` works but the HTTP proxy doesn’t:
  - Ensure Privoxy is running and `curl --proxy http://127.0.0.1:8118 https://ifconfig.me` works.
- VS Code still goes direct:
  - Ensure you set proxy settings in **User Settings (Default profile)** and reloaded the window.

## Security

- Bastion tunnel access is authenticated with Entra ID + RBAC (no shared tunnel password).
- Do not commit access tokens to `.env` files.
