# APIM Policy Files

This folder contains XML policy files for Azure API Management.

## Structure

```
params/apim/
├── README.md                              # This file
├── global_policy.xml                      # Global policy (PII, prompt injection, rate limit)
├── fragments/                             # Reusable policy fragments
│   ├── cognitive-services-auth.xml        # Managed identity for OpenAI, Document Intel, AI Search
│   ├── storage-auth.xml                   # Managed identity for Blob Storage
│   ├── cosmosdb-auth.xml                  # Managed identity for Cosmos DB
│   └── keyvault-auth.xml                  # Managed identity for Key Vault
└── tenants/
    └── {tenant-name}/
        └── api_policy.xml                 # Tenant-specific routing & content safety
```

## Global Policy (`global_policy.xml`)

The global policy is applied at the APIM service level and affects all API calls:

### Content Safety Protection
- **PII Redaction**: Detects and masks Personally Identifiable Information (SSN, credit cards, emails, phone numbers)
- **Prompt Injection Detection**: Identifies and blocks jailbreak patterns and suspicious prompts
- **Per-Tenant Control**: Each tenant can independently enable/disable via `params/{env}/tenants.tfvars`
  - Set `content_safety.pii_redaction_enabled = false` to disable PII masking for that tenant
  - Set `content_safety.prompt_shield_enabled = false` to disable prompt injection detection

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

### Content Safety Opt-Out
Applied at **deploy time** from `params/{env}/tenants.tfvars`:
- If `content_safety.pii_redaction_enabled = false`, sets `X-Skip-PII-Redaction` header
- If `content_safety.prompt_shield_enabled = false`, sets `X-Skip-Prompt-Shield` header
- The global policy checks for these headers and skips content safety for that tenant

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
- `/cosmosdb/*` → `{tenant}-cosmos` backend
- `/keyvault/*` → `{tenant}-keyvault` backend

### Managed Identity Authentication
Each route uses `include-fragment` to include the appropriate authentication:
- `cognitive-services-auth` - For OpenAI, Document Intelligence, AI Search
- `storage-auth` - For Blob Storage
- `cosmosdb-auth` - For Cosmos DB
- `keyvault-auth` - For Key Vault

### Custom Headers
- `X-Tenant-Id`: Identifies the tenant for downstream services
- `x-tokens-consumed`: Shows tokens used (outbound)

## Policy Fragments

Reusable fragments in `fragments/` directory enable code reuse across tenant policies:

### Authentication Fragments

| Fragment | Resource | Resource Scope | Use Case |
|----------|----------|-----------------|----------|
| `cognitive-services-auth.xml` | OpenAI, Document Intelligence, AI Search | `https://cognitiveservices.azure.com` | Language models, document processing, semantic search |
| `storage-auth.xml` | Azure Blob Storage | `https://storage.azure.com/` | Blob uploads/downloads |
| `cosmosdb-auth.xml` | Cosmos DB | `https://cosmos.azure.com` | NoSQL document database |
| `keyvault-auth.xml` | Azure Key Vault | `https://vault.azure.net` | Secrets management |

### Usage Logging & Metrics Fragments

| Fragment | Purpose | Use Case |
|----------|---------|----------|
| `openai-usage-logging.xml` | Logs detailed OpenAI usage to Application Insights | Cost allocation, chargeback, audit trails |
| `openai-streaming-metrics.xml` | Emits token metrics for streaming requests | Accurate streaming token counting, real-time monitoring |
| `tracking-dimensions.xml` | Extracts session/user/app IDs from headers | Per-user analytics, debugging, chargeback |

These fragments log:
- Token usage (prompt, completion, total)
- Routing info (backend, region, deployment)
- Subscription/product context
- Session/user tracking (via headers)

### Content Safety Fragments

| Fragment | Purpose | Use Case |
|----------|---------|----------|
| `pii-anonymization.xml` | Azure Language Service PII detection | Enterprise PII redaction with ML-based detection |

PII anonymization features:
- Calls Azure Language Service API for ML-based entity detection
- Configurable confidence threshold (default: 0.8)
- Entity category exclusions (e.g., skip Organization names)
- Custom regex patterns for domain-specific PII
- Falls back to regex-only when Language Service unavailable

### Routing Fragments

| Fragment | Purpose | Use Case |
|----------|---------|----------|
| `intelligent-routing.xml` | Priority-based backend selection | Load balancing, failover, throttle avoidance |

Intelligent routing features:
- Priority-based backend selection
- Throttling awareness (avoids throttled backends)
- Load balancing across same-priority backends
- Automatic failover to secondary regions

### Fragment Pattern

Each fragment uses Managed Identity to obtain an access token:

```xml
<fragment>
    <authentication-managed-identity 
        resource="{SERVICE_SCOPE}"
        output-token-variable-name="msi-access-token" 
        ignore-error="false" />
</fragment>
```

### Including Fragments in Policies

Use `<include-fragment>` in tenant API policies:

```xml
<policies>
    <inbound>
        <base />
        <!-- Include tracking dimensions for analytics -->
        <include-fragment fragment-id="tracking-dimensions" />
        
        <when condition="@(context.Request.Path.Contains('/storage'))">
            <include-fragment fragment-id="storage-auth" />
        </when>
        <when condition="@(context.Request.Path.Contains('/cosmosdb'))">
            <include-fragment fragment-id="cosmosdb-auth" />
        </when>
    </inbound>
</policies>
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

When adding a new tenant with APIM support:

1. **Add to tenants.tfvars**
   ```hcl
   # In params/{env}/tenants.tfvars
   tenants = {
     "my-new-tenant" = {
       tenant_name  = "my-new-tenant"
       display_name = "My New Tenant"
       enabled      = true
       
       openai = { enabled = true, ... }
       storage_account = { enabled = true, ... }
       # ... enable services as needed
       
       content_safety = {
         pii_redaction_enabled = true
         prompt_shield_enabled = true
       }
     }
   }
   ```

2. **Create Tenant Policy File**
   - Create: `params/apim/tenants/my-new-tenant/api_policy.xml`
   - Start with an existing tenant policy as template
   - Update `X-Tenant-Id` header value to match folder name
   - Update backend routing based on enabled services
   - Use `<include-fragment>` for authentication

3. **Example Tenant Policy**
   ```xml
   <policies>
       <inbound>
           <base />
           <set-header name="X-Tenant-Id" exists-action="override">
               <value>my-new-tenant</value>
           </set-header>
           <choose>
               <when condition="@(context.Request.Path.StartsWith('/openai'))">
                   <set-backend-service base-url="{{my-new-tenant-openai-endpoint}}" />
                   <include-fragment fragment-id="cognitive-services-auth" />
               </when>
               <when condition="@(context.Request.Path.StartsWith('/storage'))">
                   <set-backend-service base-url="{{my-new-tenant-storage-endpoint}}" />
                   <include-fragment fragment-id="storage-auth" />
               </when>
           </choose>
       </inbound>
       <outbound>
           <base />
       </outbound>
   </policies>
   ```

4. **Deploy with Terraform**
   ```bash
   terraform plan -var-file="params/test/shared.tfvars" -var-file="params/test/tenants.tfvars"
   terraform apply -var-file="params/test/shared.tfvars" -var-file="params/test/tenants.tfvars"
   ```

### Important Notes

- **X-Tenant-Id Header**: Must match the folder name (validated at plan time)
- **Policy References**: Backend endpoints must exist and match enabled services
- **Content Safety**: Control via `content_safety` block in tenants.tfvars
- **Fragments**: Use `<include-fragment>` for consistent, DRY authentication code

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
