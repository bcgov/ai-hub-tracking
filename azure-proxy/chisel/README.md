# Azure  Proxy

A secure tunnel proxy for local development access to Azure PaaS  using [Chisel](https://github.com/jpillora/chisel). This service creates a reverse proxy that allows developers to securely connect to Azure-hosted PaaS  from their local machines without exposing the  to public internet access.

## Overview

The Azure  Proxy is built on Chisel, a fast TCP/UDP tunnel over HTTP. It provides:

- **Secure tunneling**: HTTPS-based communication with mandatory authentication
- **Local port forwarding**: Maps a local port to the remote Azure PaaS 
- **Health checks**: Built-in health endpoint for monitoring and orchestration
- **Container-native**: Docker containerized for consistent deployment across environments
- **Automatic restart**: Includes retry logic for resilience

## Architecture

```
Local Machine (Port 5432)
        ↓
Chisel Client
        ↓
HTTPS Connection
        ↓
Azure Web App (Chisel Server)
        ↓
Azure PaaS 
```

## Local Development Setup

### Prerequisites

- Docker installed and running
- Access to the Azure Chisel server endpoint
- The Chisel authentication token

### Running Locally with Docker

Use the following command to establish a secure tunnel to the Azure PaaS :

```bash
docker run --rm -it -p 5462:5432 jpillora/chisel:latest client \
  --auth "tunnel:XXXXXXX" \
  https://${azure-db-proxy-app-service-url} \
  0.0.0.0:5432:${postgres_hostname}$:5432
```

#### Command Breakdown

- `--rm`: Automatically remove the container when it exits
- `-it`: Run in interactive mode with a TTY
- `-p 5462:5432`: Map local port `5462` to container port `5432` (PaaS default)
- `jpillora/chisel:latest client`: Use Chisel in client mode to create an outbound tunnel
- `--auth "tunnel:XXXXXX"`: Authentication credentials for the Chisel server, replace with exact cred
- `https://${azure-db-proxy-app-service-url}`: The public URL of the Chisel server running in Azure, replace with actual URL
- `0.0.0.0:5432:${postgres_hostname}:5432`: Forward all interfaces on port 5432 to the remote PaaS  on port 5432, replace actual host

#### Connecting to the Proxied 

Once the Chisel tunnel is running, connect to PaaS using after replacing with actual values:

```bash
psql -h localhost -p 5462 -U ${postgres_user} -d ${postgres_db}
```

Or in your application configuration, use:

```
 Host: localhost
Port: 5462
Username: ${postgres_user}
: ${postgres_db}
```

## Azure Deployment

### Infrastructure as Code (Terraform)

The Azure  Proxy is deployed as an Azure App Service using Terraform. Key resources:

- **App Service Plan**: Linux-based hosting for the proxy container
- **Web App**: Runs the Chisel server container
- **Application Insights**: Monitoring and diagnostics
- **Virtual Network Integration**: Securely connects to your VNet

### Terraform Variables

### Required Environment Variables

When deployed to Azure App Service, the following environment variables are automatically configured:

| Variable | Purpose |
|----------|---------|
| `PORT` | The port Chisel server listens on (default: `80`) |
| `WEBSITES_PORT` | Azure App Service port mapping (default: `80`) |
| `CHISEL_AUTH` | Authentication token for Chisel server (e.g., `tunnel:password`) |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Application Insights monitoring |
| `APPINSIGHTS_INSTRUMENTATIONKEY` | Application Insights instrumentation |

## Docker Image

### Building the Image

The Docker image is multi-stage and includes:

1. **Stage 1**: Extract Chisel binary from the official Chisel image
2. **Stage 2**: Minimal Alpine Linux base with only necessary dependencies

Build locally:

```bash
docker build -t azure-proxy:latest .
```

### Running the Image

The container is designed to run as a Chisel server. Basic startup:

```bash
docker run -d \
  -p 80:80 \
  -e CHISEL_AUTH="tunnel:your-auth-token" \
  -e PORT=80 \
  azure-db-proxy:latest
```

## Environment Variables

### Chisel Configuration

- **`CHISEL_AUTH`** (required): Authentication credentials in format `username:password`. Example: `tunnel:XXXXXX`
  - When set, clients must authenticate with these credentials
  - If not set, the server runs unauthenticated (not recommended for production)

- **`CHISEL_PORT`** (optional): Port the Chisel server listens on. Default: `80`
  - Must match the exposed port when running in containers

- **`CHISEL_HOST`** (optional): Host address to bind to. Default: `0.0.0.0` (all interfaces)

- **`CHISEL_ENABLE_SOCKS5`** (optional): Enable SOCKS5 proxy support. Default: `true`
  - Set to `false` if SOCKS5 is not needed

- **`CHISEL_EXTRA_ARGS`** (optional): Additional Chisel server arguments for advanced configuration

### Health Monitoring

- **`MAX_RETRIES`** (optional): Maximum retry attempts on failure. Default: `30`

- **`DELAY_SECONDS`** (optional): Delay between retries in seconds. Default: `5`

## Health Checks

### Health Endpoint

The proxy includes a built-in health check endpoint:

```
GET /healthz
```

**Response:**
```json
{
  "status": "healthy"
}
```



## Startup Process

The `start-chisel.sh` script orchestrates the startup:

1. **Validates Chisel binary**: Ensures Chisel is available
2. **Starts health backend**: Launches a minimal HTTP server on port 9999 for health checks
3. **Starts Chisel server**: Launches the tunnel server with configured authentication
4. **Health check reverse proxy**: Chisel reverse-proxies `/healthz` requests to the health backend
5. **Retry logic**: Automatically restarts on failure (up to `MAX_RETRIES` times)
6. **Graceful shutdown**: Responds to termination signals and cleans up processes

## Security Considerations

### Authentication

- Always set `CHISEL_AUTH` with a strong password in production
- Use format: `username:password` (e.g., `tunnel:YourSecurePasswordHere`)
- Store the password securely

### Network Security

- The proxy should only be accessible from trusted networks
- Restrict inbound access using ip restriction on app service
- Use HTTPS for all client connections to the proxy

###  Access

- The proxy does not store or log  credentials
- PaaS credentials are handled separately on the client side
- Always use encrypted connections (SSL/TLS) when available

## Accessing Azure Portal or services from local
### Using firefox with a proxy extension to login to azure portal to access PaaS Services.
- Add SmartProxy extension for firefox and add these details for proxy server (local)
        server = localhost port =18080 or the port you used to run chisel client for socks, 
- check the checkbox Proxy DNS when using socks5
- proxy portocol is SOCKS5
- now you should be able to access cosmosdb or other services running in your vnet and environment.
 ![proxy-setup-image](firefox_proxy_setup.png)
### Using the http privoxy proxy for postman or running api code locally
- follow the readme in [privoxy](../privoxy/README.md) 

## Monitoring and Logs

### Application Insights

The proxy sends logs and metrics to Application Insights when configured:

- HTTP request logs
- Container logs
- Platform diagnostics
- Performance metrics

View logs in Azure Portal:
1. Navigate to the App Service resource
2. Go to **Application Insights** → **Application Map** or **Logs**

### Container Logs

View real-time logs in Azure Portal:

```
App Service → Log stream
```

Or via Azure CLI:

```bash
az webapp log tail --resource-group <rg-name> --name <web-app-name>
```

## Troubleshooting

### Connection Refused

**Problem**: `Connection refused` when connecting to `localhost:5462`

**Solution**: 
- Verify the Chisel tunnel is running: `docker ps`
- Check the port mapping: `-p 5462:5432` must be in the docker command
- Ensure the Azure proxy endpoint is reachable

### Authentication Failed

**Problem**: `Authorization failed` or `Auth failed` in logs

**Solution**:
- Verify the `--auth` parameter matches the server's `CHISEL_AUTH` setting
- Ensure the password is correct and not expired
- Check Azure Key Vault for the current credentials

### Cannot Resolve Hostname

**Problem**: `Cannot resolve hostname 'xxxxx..azure.com'`

**Solution**:
- Verify the Azure proxy server has network access to the PaaS 
- Check Network Security Group (NSG) rules allow outbound traffic on port 5432
- Ensure the PaaS server name is correct

### High Latency

**Problem**: Slow  connections through the proxy

**Solution**:
- The Chisel server adds minimal overhead; check the Azure App Service plan tier
- Upgrade to a higher SKU (B2, B3, S1) if running on B1
- Check network latency between regions

## Related Resources

- [Chisel Documentation](https://github.com/jpillora/chisel)
- [Azure App Service Documentation](https://docs.microsoft.com/azure/app-service/)
- [Azure PaaS Documentation](https://docs.microsoft.com/azure/PaaS/)
- [Azure Key Vault for Secrets Management](https://docs.microsoft.com/azure/key-vault/)

## Contributing

All changes follow the project's [Developer SDLC](https://bcgov.github.io/ai-hub-tracking/workflows.html) — branch, PR with automated checks, merge to main.

When modifying the proxy:

1. Create a feature branch from `main`
2. Update `Dockerfile` for image changes
3. Update `start-chisel.sh` for startup logic changes
4. Test locally with the Docker command above
5. Update this README with any new features or configuration options
6. Open a PR (must follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) title format) — container builds run automatically via `.builds.yml`
