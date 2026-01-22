# APIM Policy Files

This folder contains XML policy files for Azure API Management.

## Structure

```
params/apim/
├── README.md                           # This file
├── global_policy.xml                   # Global policy applied to ALL APIs
├── fragments/                          # Reusable policy fragments
│   ├── cognitive-services-auth.xml     # Managed identity auth for Cognitive Services
│   └── storage-auth.xml                # Managed identity auth for Azure Storage
└── tenants/
    └── {tenant-name}/
        └── api_policy.xml              # Tenant-specific API policy
```

## Global Policy (`global_policy.xml`)

The global policy is applied at the APIM service level and affects all API calls. It includes:

### Request Correlation
- Adds `x-ms-correlation-request-id` header for distributed tracing
- Adds `x-ms-request-id` response header

### Token Metrics (LLM APIs)
Uses `llm-emit-token-metric` to track LLM token consumption:
- **Dimensions**: API ID, Subscription ID, Tenant
- **Metrics**: Prompt Tokens, Completion Tokens, Total Tokens
- **Destination**: Application Insights

### Response Headers
- `x-ratelimit-remaining-tokens`: Shows tokens remaining in rate limit window

### Error Handling
Returns structured JSON errors with:
- Error code
- Error message
- Request ID for correlation

## Tenant Policies (`tenants/{tenant-name}/api_policy.xml`)

Each tenant has their own API-level policy for:

### Token Rate Limiting
Uses `llm-token-limit` policy:
- **Default**: 10,000 tokens-per-minute per subscription
- **Counter key**: Subscription ID
- **Response**: 429 Too Many Requests when exceeded

### Path-Based Routing
Routes requests to appropriate backends based on URL path:
- `/openai/*` → `{tenant}-openai` backend
- `/documentintelligence/*` or `/formrecognizer/*` → `{tenant}-docint` backend
- `/storage/*` or `/blobs/*` → `{tenant}-storage` backend
- Default → `{tenant}-openai` backend

### Managed Identity Authentication
Each route uses `authentication-managed-identity`:
- **Cognitive Services**: `https://cognitiveservices.azure.com`
- **Azure Storage**: `https://storage.azure.com/`

### Custom Headers
- `X-Tenant-Id`: Identifies the tenant for downstream services
- `x-tokens-consumed`: Shows tokens used (outbound)

## Policy Fragments

Reusable fragments in `fragments/` directory:

1. **cognitive-services-auth.xml**: Managed identity auth for Azure Cognitive Services
2. **storage-auth.xml**: Managed identity auth for Azure Storage

Include in policies via:
```xml
<include-fragment fragment-id="cognitive-services-auth" />
```

## Backend Configuration

APIM backends are created per tenant in Terraform:
- `{tenant}-openai` - Routes to Azure OpenAI endpoint
- `{tenant}-docint` - Routes to Document Intelligence endpoint  
- `{tenant}-storage` - Routes to Storage Account blob endpoint

## Application Insights Integration

- APIM logger with connection string from AI Foundry Hub
- Diagnostic settings:
  - Request/response body logging (1KB limit)
  - Key header logging (X-Tenant-Id, Authorization, etc.)
  - 100% sampling (adjust in production)
  - W3C correlation protocol

## Adding a New Tenant

1. Create folder: `params/apim/tenants/{new-tenant-name}/`
2. Copy `api_policy.xml` from an existing tenant
3. Update the `X-Tenant-Id` header value to match the folder name
4. Update `set-backend-service` backend IDs to use new tenant name
5. Adjust `llm-token-limit` tokens-per-minute as needed
6. Run `terraform apply` to create backends and deploy policy

## Policy Inheritance

```
Global Policy (service level)
    └── Product Policy (optional)
        └── API Policy (tenant level) ← tenant-specific policies go here
            └── Operation Policy (optional)
```

Each level uses `<base />` to inherit from parent policies.

## Testing Policies

Use the APIM Test tab in Azure Portal or call via API:

```bash
# Test token rate limiting (should return remaining tokens header)
curl -X POST "https://{apim-gateway}/tenant/openai/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Ocp-Apim-Subscription-Key: {key}" \
  -d '{"model": "gpt-4", "messages": [{"role": "user", "content": "Hello"}]}'

# Check response headers for:
# x-ratelimit-remaining-tokens: 9950
# x-tokens-consumed: 50
```
