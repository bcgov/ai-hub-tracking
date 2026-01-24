# Integration Tests for AI Services Hub APIM

This directory contains integration tests using [bats-core](https://github.com/bats-core/bats-core) (Bash Automated Testing System) and curl for testing the APIM gateway endpoints.

## Prerequisites

1. **Install bats-core**:
   ```bash
   # On Windows with Git Bash or WSL:
   git clone https://github.com/bats-core/bats-core.git
   cd bats-core
   ./install.sh /usr/local  # or a local path
   
   # Or via npm:
   npm install -g bats
   ```

2. **Required tools**:
   - `curl` - for HTTP requests
   - `jq` - for JSON parsing
   - `terraform` - for extracting output values

3. **Azure authentication** - for extracting subscription keys from terraform output

## Configuration

Tests load configuration from terraform outputs. Set environment variables or run via `run-tests.sh`:

```bash
# Required environment variables (auto-loaded from terraform):
export APIM_GATEWAY_URL="https://ai-services-hub-test-apim.azure-api.net"
export WLRS_SUBSCRIPTION_KEY="<from-terraform-output>"
export SDPR_SUBSCRIPTION_KEY="<from-terraform-output>"
export HTTPS_PROXY="http://127.0.0.1:8118"  # For VPN/proxy access
```

## Running Tests

```bash
# Run all tests with proxy:
./run-tests.sh

# Run specific test file:
bats chat-completions.bats

# Run with verbose output:
bats --tap chat-completions.bats
```

## Test Files

| File | Description |
|------|-------------|
| `chat-completions.bats` | Tests OpenAI chat completion endpoints for both tenants |
| `pii-redaction.bats` | Tests PII redaction policy (WLRS=enabled, SDPR=disabled) |
| `document-intelligence.bats` | Tests Document Intelligence layout analysis endpoints |
| `test-helper.bash` | Shared helper functions and setup |
| `config.bash` | Configuration loader from terraform outputs |

## Test Structure

Each test follows this pattern:
1. **Setup**: Load config and verify prerequisites
2. **Request**: Make API call via curl to APIM gateway
3. **Validate**: Check response status, headers, and body content
4. **Teardown**: Clean up any resources if needed

## APIM Endpoints

- **Chat Completions**: `POST /{tenant}/openai/deployments/{model}/chat/completions?api-version=2024-10-21`
- **Document Intelligence**: `POST /{tenant}/documentintelligence/documentModels/prebuilt-layout:analyze?api-version=2024-02-29-preview`

## Tenant Configuration

| Tenant | PII Redaction | Model |
|--------|---------------|-------|
| wlrs-water-form-assistant | Enabled | gpt-4.1-mini |
| sdpr-invoice-automation | Disabled | gpt-4.1-mini |

## Troubleshooting

1. **Connection refused**: Ensure proxy is running (`http://127.0.0.1:8118`)
2. **401 Unauthorized**: Check subscription key is valid
3. **404 Not Found**: Verify API path and tenant name
4. **500 Internal Server Error**: Check backend service status in Azure Portal
