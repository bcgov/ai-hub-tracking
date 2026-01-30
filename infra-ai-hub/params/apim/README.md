# APIM Policy Files

This folder contains XML policy files for Azure API Management.

## Structure

```
params/apim/
├── README.md                              # This file
├── global_policy.xml                      # Global policy (base policies, error handling)
├── api_policy.xml.tftpl                   # Dynamic template for tenant-specific policies
├── fragments/                             # Reusable policy fragments
│   ├── cognitive-services-auth.xml        # Managed identity for OpenAI, Document Intel, AI Search
│   ├── storage-auth.xml                   # Managed identity for Blob Storage
│   ├── keyvault-auth.xml                  # Managed identity for Key Vault
│   ├── pii-anonymization.xml              # Azure Language Service PII detection
│   ├── openai-usage-logging.xml           # OpenAI token usage tracking
│   ├── openai-streaming-metrics.xml       # Streaming response metrics
│   ├── tracking-dimensions.xml            # Analytics dimension extraction
│   ├── intelligent-routing.xml            # Multi-backend routing (future)
│   └── ... (other authentication fragments)
└── params/{env}/
    └── tenants/
        └── {tenant-name}/
            └── tenant.tfvars              # Tenant config (includes apim_policies)
```

## Global Policy (`global_policy.xml`)

The global policy is applied at the APIM service level and provides base functionality for all API calls:

### Subscription Key Header (SDK Compatibility)

**Primary Header: `api-key`**

Tenant APIs are configured to use `api-key` as the subscription key header name and query parameter name (instead of APIM defaults like `Ocp-Apim-Subscription-Key` or `subscription-key`).

**Why `api-key`:**
- Compatibility with OpenAI SDK and other AI service client libraries that expect `api-key` header
- Simplifies integration for developers familiar with Azure OpenAI SDK patterns
- Reduces confusion about which header to use

**Supported authentication methods:**
- Header: `api-key: <subscription-key>`
- Query parameter: `?api-key=<subscription-key>`

**Fallback support:**
The global policy still normalizes alternative header formats for backward compatibility:
- `Ocp-Apim-Subscription-Key` - Standard APIM header (legacy)
- `x-api-key` - Common REST API convention

Clients should use `api-key` for consistency with Azure OpenAI SDK conventions.

### Request Correlation & Tracing

- `x-ms-correlation-request-id` - Unique ID for distributed request tracing (set on inbound)
- `x-ms-request-id` - Request ID returned in response headers (set on outbound)
- All error responses include `requestId` in JSON body for support team correlation

### Token Metrics

Emits LLM token metrics for OpenAI requests:
- **Dimensions**: API ID, Subscription ID, Tenant (from X-Tenant-Id header)
- **Metrics**: Total Tokens, Prompt Tokens, Completion Tokens
- **Namespace**: AIHub (in Application Insights)
- Only emitted for requests containing "openai" in path

### Rate Limit Visibility

- `x-ratelimit-remaining-tokens` - Shows remaining tokens in current rate limit window
- Set by the `llm-token-limit` policy (when enabled per-tenant)
- Returned in response headers so clients can implement smart rate limiting

### Throttling Handling (429 Responses)

Special handling for rate limit (429) responses:
- Preserves `Retry-After` header from backend for proper backoff
- Returns structured JSON error with retry guidance
- Includes remaining tokens count for client awareness
- Maintains correlation ID for debugging

Example 429 response:
```json
{
  "error": {
    "code": "429",
    "message": "Too Many Requests - Rate limit exceeded",
    "retryAfter": "30",
    "requestId": "correlation-id-here"
  }
}
```

### Error Handling

All errors (5xx, 4xx, etc.) return structured JSON format:
- Error code (HTTP status)
- Human-readable error message
- Correlation request ID for support tracing

Example error response:
```json
{
  "error": {
    "code": "500",
    "message": "Internal Server Error",
    "requestId": "correlation-id-here"
  }
}
```

### Policy Features

No global policies are enforced by default. All policies are **tenant-opt-in** via the `apim_policies` config:
- **Token Rate Limiting**: Protect backends from token exhaustion (enabled by default, disable per-tenant if needed)
- **PII Anonymization**: Azure Language Service-based entity detection and redaction (enable per-tenant)
- **Usage Logging**: Log OpenAI token consumption to Application Insights (enabled by default)
- **Streaming Metrics**: Emit token metrics for streaming responses (enabled by default)
- **Tracking Dimensions**: Extract custom dimensions from headers for analytics (enabled by default)

### Request/Response Processing

- Adds standard correlation headers for distributed tracing
- Returns 404 for unmatched paths (no catch-all routing)
- Returns structured JSON error responses with request correlation info

### Application Insights Integration

When enabled, the following data is logged:
- API operations and routing decisions
- Request/response headers and bodies (configurable)
- Token consumption metrics
- Tenant and subscription context
- Error details and correlations

## Tenant Policies (Dynamic Templates)

Tenant API policies are **dynamically generated** from `api_policy.xml.tftpl` based on tenant configuration in `params/{env}/tenants/{tenant-name}/tenant.tfvars`.

### Dynamic Template Variables

The template receives these variables from `locals.tf`:

| Variable | Source | Purpose |
|----------|--------|---------|
| `tenant_name` | Tenant key | Sets `X-Tenant-Id` header |
| `tokens_per_minute` | `apim_policies.rate_limiting.tokens_per_minute` | Rate limit setting |
| `openai_enabled` | `tenant.openai.enabled` | Routes `/openai/*` paths |
| `document_intelligence_enabled` | `tenant.document_intelligence.enabled` | Routes `/documentintelligence/*` paths |
| `ai_search_enabled` | `tenant.ai_search.enabled` | Routes `/ai-search/*` paths |
| `storage_enabled` | `tenant.storage_account.enabled` | Routes `/storage/*` paths |
| `rate_limiting_enabled` | `apim_policies.rate_limiting.enabled` | Wraps `llm-token-limit` policy |
| `pii_redaction_enabled` | `apim_policies.pii_redaction.enabled` AND language service enabled | Wraps PII anonymization fragment |
| `usage_logging_enabled` | `apim_policies.usage_logging.enabled` | Wraps OpenAI usage logging fragment |
| `streaming_metrics_enabled` | `apim_policies.streaming_metrics.enabled` | Wraps streaming metrics fragment |
| `tracking_dimensions_enabled` | `apim_policies.tracking_dimensions.enabled` | Wraps tracking dimensions fragment |

### Conditional Policy Inclusion

Policies are included **only when enabled**:

```hcl
# Example: Rate limiting included only when enabled
%{ if rate_limiting_enabled ~}
<llm-token-limit ... />
%{ endif ~}

# Example: PII anonymization included only when enabled AND Language Service available
%{ if pii_redaction_enabled ~}
<include-fragment fragment-id="pii-anonymization" />
%{ endif ~}
```

### Path-Based Routing

Routes requests to appropriate backends based on enabled services:
- `/openai/*` → `{tenant}-openai` backend (if `openai_enabled = true`)
- `/documentintelligence/*`, `/formrecognizer/*`, `/documentmodels/*` → `{tenant}-docint` backend (if `document_intelligence_enabled = true`)
- `/ai-search/*` → `{tenant}-ai-search` backend (if `ai_search_enabled = true`)
- `/storage/*` → `{tenant}-storage` backend (if `storage_enabled = true`)
- Other paths → 404 Not Found

### Managed Identity Authentication

Each route uses `include-fragment` to include the appropriate authentication:
- `cognitive-services-auth` - For OpenAI, Document Intelligence, AI Search
- `storage-auth` - For Blob Storage
- `keyvault-auth` - For Key Vault

### Custom Headers

- `X-Tenant-Id`: Identifies the tenant for downstream services and logging
- `x-ratelimit-remaining-tokens`: Shows tokens remaining in rate limit window (when rate limiting enabled)
- `x-tokens-consumed`: Shows tokens used in the request (when usage logging enabled)

### Document Intelligence Async Operations (Operation-Location Header Rewrite)

For Document Intelligence async operations that return `202 Accepted` responses, APIM automatically rewrites the `Operation-Location` header to route subsequent polling requests back through the APIM gateway.

**Background:**
- Document Intelligence async operations (e.g., document analysis, custom model training) return a `202 Accepted` status with an `Operation-Location` header
- The header contains a polling URL to check operation status: `https://{resource}.cognitiveservices.azure.com/documentintelligence/...`
- Clients (SDKs, custom code) automatically poll this URL until the operation completes

**Problem without rewrite:**
- If clients poll the direct `*.cognitiveservices.azure.com` URL, they bypass APIM
- This breaks:
  - Managed identity authentication (clients would need direct credentials)
  - Consistent network routing (private endpoint access)
  - APIM logging and monitoring
  - Rate limiting and policy enforcement

**APIM Solution:**
The tenant policy template includes an `<outbound>` policy that rewrites the `Operation-Location` header when present:
- Detects `Operation-Location` header in backend responses
- Replaces the backend hostname (`{resource}.cognitiveservices.azure.com`) with the APIM gateway host
- Preserves the request path (e.g., `/documentintelligence/documentModels/...`)
- Inserts the tenant API path prefix (e.g., `/{tenant}`)

**Example:**
```
Backend returns:
  Operation-Location: https://tenant-docint.cognitiveservices.azure.com/documentintelligence/documentModels/prebuilt-read/analyzeResults/abc123

APIM rewrites to:
  Operation-Location: https://apim-gateway.azure-api.net/tenant/documentintelligence/documentModels/prebuilt-read/analyzeResults/abc123
```

**Client behavior:**
- Clients continue polling the rewritten `Operation-Location` URL
- All polling requests flow through APIM with the same authentication and policies
- Transparent to the client - SDK polling logic works unchanged

**Implementation:**
```xml
<outbound>
    <base />
    <!-- Rewrite Operation-Location header for Document Intelligence async operations -->
    <choose>
        <when condition="@(context.Response.Headers.ContainsKey("Operation-Location"))">
            <set-header name="Operation-Location" exists-action="override">
                <value>@{
                    var originalLocation = context.Response.Headers.GetValueOrDefault("Operation-Location", "");
                    var backendUrl = new Uri(originalLocation);
                    var apimUrl = context.Request.OriginalUrl;
                    return $"{apimUrl.Scheme}://{apimUrl.Host}/{tenant}{backendUrl.PathAndQuery}";
                }</value>
            </set-header>
        </when>
    </choose>
</outbound>
```

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

PII anonymization via Language Service:
- Calls Azure Language Service `/language/:analyze-text` API for entity detection
- Named value: `piiServiceUrl` points to Language Service endpoint
- Only included when:
  - Tenant has `apim_policies.pii_redaction.enabled = true`
  - AND Language Service is enabled in shared config
- Detects and redacts: emails, phone numbers, URLs, social security numbers, credit card numbers, addresses, etc.

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

## Language Service PII Detection

This repo supports ML-based PII anonymization by calling Azure AI Language Service (Text Analytics) from APIM policies via the `pii-anonymization.xml` fragment.

### Infrastructure Components

When `shared_config.language_service.enabled` is true, Terraform deploys:
- A shared Azure Cognitive Account with `kind = "TextAnalytics"` for PII detection
- A private endpoint to the Language Service resource
- A DNS wait step (`wait-for-dns-zone.sh`) to allow Azure Policy / landing-zone DNS zone group management to complete

Security-related settings:
- `local_auth_enabled = false` (managed identity only; disables key-based authentication)
- Network ACL default action is deny
- Private endpoint access pattern is used (public access can be disabled via `public_network_access_enabled`, and is configured as disabled in shared tfvars)

### APIM Integration

APIM is integrated with Language Service using:

**Named Value: `piiServiceUrl`**
- Value is the Language Service endpoint without a trailing slash
- The PII fragment expects the base endpoint in this format

**RBAC:**
- APIM's managed identity is assigned the `Cognitive Services User` role on the shared Language Service resource

### Policy Fragment Deep Dive: `fragments/pii-anonymization.xml`

**Purpose:**
Detect and mask PII in text content using Language Service PII entity recognition.

**Prerequisites / Inputs (variables must be set by the caller policy):**
- `piiInputContent`: the input text to analyze (typically the request body)
- `piiAnonymizationEnabled`: `"true"` or `"false"`

**Required APIM Named Value:**
- `piiServiceUrl`: Language Service base endpoint URL

**Output:**
- `piiAnonymizedContent`: anonymized/redacted text output

**Auth:**
- Uses `authentication-managed-identity` to obtain an AAD token for `https://cognitiveservices.azure.com`
- Sets `Authorization: Bearer <token>`
- Deletes any `api-key` header

**API Call:**
- Endpoint: `{{piiServiceUrl}}/language/:analyze-text?api-version=2025-11-15-preview`
- Method: `POST`
- Timeout: `20` seconds
- `ignore-error="true"` (errors are handled with fallback behavior)
- API version `2025-11-15-preview` is documented at [Microsoft Learn: PII Detection](https://learn.microsoft.com/en-us/azure/ai-services/language-service/personally-identifiable-information/overview)

**Request Body (high level):**
- `kind`: `PiiEntityRecognition`
- `parameters`:
  - `modelVersion`: `latest`
  - `redactionPolicy`:
    - `policyKind`: `CharacterMask`
    - `redactionCharacter`: `#`
- `analysisInput.documents[0]`:
  - `id`: `"1"`
  - `language`: `"en"`
  - `text`: `piiInputContent`

**Response Handling:**
- Extracts `results.documents[0].redactedText` as the anonymized output
- Captures diagnostics:
  - `piiDetectionStatusCode`
  - `piiEntityCount` (from `results.documents[0].entities`)
  - `piiEntityTypes` (unique entity categories from `entities[*].category`)
  - `piiContentChanged` (compares input vs anonymized)

**Diagnostics & Logging:**
The fragment emits a `trace` event (source `pii-anonymization`) to Application Insights with detailed metadata:
- `request-id`: Correlation ID from the APIM context for distributed tracing
- `tenant-id`: Tenant identifier for per-tenant analytics
- `pii-status-code`: HTTP status code from the Language Service API response
- `pii-entity-count`: Number of PII entities detected in the request
- `pii-entity-types`: Comma-separated list of unique entity categories (e.g., "Email,SSN,CreditCard")
- `pii-content-changed`: Boolean flag indicating whether any redaction occurred (true if input differs from output)

These diagnostics enable monitoring of PII detection effectiveness, Language Service API health, and understanding which entity types are most commonly detected across tenants.

**Fallback Behavior:**
- If PII anonymization is disabled, the fragment passes through the original `piiInputContent`
- If the Language Service call fails or the response can't be parsed, the fragment returns the original input text (best-effort redaction)

**Advanced PII Options:**

The fragment supports additional configuration variables set by the tenant policy template based on `apim_policies.pii_redaction` settings:

1. **`piiExcludedCategories`** (string, comma-separated list)
   - Maps to Language Service `excludePiiCategories` parameter
   - When non-empty, excludes specific PII categories from detection
   - Example categories: `"PhoneNumber,Address,Email"`
   - See [Microsoft Learn: PII Entity Categories](https://learn.microsoft.com/en-us/azure/ai-services/language-service/personally-identifiable-information/concepts/entity-categories)
   - If empty or not set, all categories are detected

2. **`piiDetectionLanguage`** (string, default `"en"`)
   - Controls the `documents[0].language` field in the Language Service request
   - Affects detection accuracy for language-specific PII entities
   - Examples: `"en"`, `"fr"`, `"es"`

3. **`piiPreserveJsonStructure`** (boolean, default `true`)
   - Enables post-processing restoration of structural JSON values after redaction
   - Prevents Language Service from masking common structural strings (e.g., OpenAI message roles like `"user"`, `"system"`, `"assistant"`)
   - Works by pattern-matching masked values (e.g., `"####"` → `"user"`) against a whitelist

4. **`piiStructuralWhitelist`** (string, comma-separated list)
   - Additional quoted string values to preserve beyond the default whitelist
   - Used in conjunction with `piiPreserveJsonStructure`
   - Example: `"customRole,metadata,specialField"`
   - Values are restored if they match the length of masked `#####` patterns

**Request Structure Changes:**
- When `piiExcludedCategories` is non-empty, the fragment conditionally includes the `excludePiiCategories` parameter in the Language Service API request body
- The `documents[0].language` field is set from `piiDetectionLanguage`
- Post-processing (if `piiPreserveJsonStructure` is true) restores whitelisted values after Language Service returns the redacted text

### Template Generation Mechanics: `api_policy.xml.tftpl`

Tenant API policies are generated dynamically from `api_policy.xml.tftpl` using tenant configuration:
- Routing blocks are generated only for services enabled for that tenant (for example OpenAI, Document Intelligence, AI Search, Storage)
- APIM policy features are included only when enabled by per-tenant flags (for example rate limiting, PII redaction, usage logging, streaming metrics, tracking dimensions)

**PII Redaction Flow (OpenAI Requests):**
When PII redaction is enabled (`apim_policies.pii_redaction.enabled` is true AND `shared_config.language_service.enabled` is true), the tenant policy template:
1. Extracts the request body as text and sets it to the `piiInputContent` variable
2. Sets PII configuration variables from tenant settings:
   - `piiExcludedCategories` (from `apim_policies.pii_redaction.excluded_categories`)
   - `piiDetectionLanguage` (from `apim_policies.pii_redaction.detection_language`, default `"en"`)
   - `piiPreserveJsonStructure` (from `apim_policies.pii_redaction.preserve_json_structure`, default `true`)
   - `piiStructuralWhitelist` (from `apim_policies.pii_redaction.structural_whitelist`)
3. Includes the `pii-anonymization` fragment, which uses these variables to call Language Service and sets `piiAnonymizedContent`
4. Explicitly applies the anonymized content back to the request body using `<set-body>` with `@((string)context.Variables["piiAnonymizedContent"])`
5. Forwards the modified request to the OpenAI backend

This explicit `set-body` step ensures the redacted content is written back to the request before backend routing.

**OpenAI Usage Logging Flow:**
Before including the `openai-usage-logging` fragment, the tenant policy template sets routing metadata variables:
- `backendId`: APIM backend identifier (e.g., `tenant-openai`)
- `routeLocation`: Azure region for the backend (single-backend for now)
- `routeName`: Route identifier for future intelligent routing
- `deploymentName`: Extracted from the URL path using regex (e.g., `/deployments/gpt-4/` → `gpt-4`)

These variables are passed to the `openai-usage-logging` fragment, which includes them in the Application Insights trace along with token usage data. This enables detailed cost allocation, chargeback analytics, and deployment-level monitoring even in the current single-backend setup.

### Configuration Schema Change

PII settings are now controlled under `apim_policies`:
- **New:** `apim_policies.pii_redaction.enabled`
- **Old:** `content_safety.pii_redaction_enabled` (legacy approach used for opt-out decisions in earlier policies)

Additionally, global policy loading changed:
- The global APIM policy is loaded from file
- PII redaction is handled in tenant API policies via the `pii-anonymization` fragment (not via a templated global policy)

### Performance Considerations

PII anonymization adds an extra network call from APIM to Language Service for requests where it is enabled. The Language Service call uses a fixed timeout of 20 seconds; failures fall back to passing through the original content.

### Troubleshooting

**DNS / Private Endpoint Readiness:**
- Terraform includes a DNS wait step for the Language Service private endpoint; ensure private DNS zone group integration is complete

**Auth / RBAC:**
- Ensure APIM managed identity has `Cognitive Services User` on the shared Language Service resource (initial deployment may see transient failures during role assignment propagation)

**Incorrect `piiServiceUrl`:**
- The fragment expects the base endpoint without a trailing slash (APIM named value uses `trimsuffix(..., "/")`)

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

1. **Create Tenant Configuration**
   ```bash
   # Create tenant config file
   mkdir -p params/{env}/tenants/my-new-tenant
   touch params/{env}/tenants/my-new-tenant/tenant.tfvars
   ```

2. **Add Tenant Configuration Block**
   
   In `params/{env}/tenants/my-new-tenant/tenant.tfvars`:
   ```hcl
   tenant = {
     tenant_name  = "my-new-tenant"
     display_name = "My New Tenant"
     enabled      = true
     
     # Enable services needed by this tenant
     openai = {
       enabled = true
       sku     = "S0"
       model_deployments = [
         { name = "gpt-4", model_name = "gpt-4", ... }
       ]
     }
     
     storage_account = {
       enabled = true
       account_tier = "Standard"
     }
     
     # APIM Policies - all features available per-tenant
     apim_policies = {
       rate_limiting = {
         enabled           = true
         tokens_per_minute = 10000
       }
       pii_redaction = {
         enabled = true  # Enable/disable as needed
       }
       usage_logging = {
         enabled = true
       }
       streaming_metrics = {
         enabled = true
       }
       tracking_dimensions = {
         enabled = true
       }
       intelligent_routing = {
         enabled = false  # For future multi-backend setup
       }
     }
     
     apim_auth = {
       mode              = "subscription_key"
       store_in_keyvault = false
     }
     
     apim_diagnostics = {
       sampling_percentage = 100
       verbosity           = "information"
     }
     
     # ... other service configs
   }
   ```

3. **Deploy with Terraform**
   
   The deploy script automatically:
   - Discovers tenant config files in `params/{env}/tenants/*/tenant.tfvars`
   - Generates dynamic API policies from `api_policy.xml.tftpl`
   - Creates APIM resources (API, backends, policies, etc.)
   
   ```bash
   ./scripts/deploy-terraform.sh plan test
   ./scripts/deploy-terraform.sh apply test
   ```

### Key Configuration Options

#### `apim_policies` Block

All policy features are consolidated under `apim_policies` for easy per-tenant control:

```hcl
apim_policies = {
  # Token rate limiting (protects backend from token exhaustion)
  rate_limiting = {
    enabled           = true          # Set to false to disable rate limiting
    tokens_per_minute = 10000         # Tokens per minute per subscription
  }
  
  # PII anonymization via Azure Language Service
  pii_redaction = {
    enabled = true  # Set to false to disable PII detection
  }
  
  # OpenAI token usage logging to Application Insights
  usage_logging = {
    enabled = true  # Set to false to disable usage tracking
  }
  
  # Streaming response metrics
  streaming_metrics = {
    enabled = true  # Set to false to disable streaming metrics
  }
  
  # Analytics dimension extraction from headers
  tracking_dimensions = {
    enabled = true  # Set to false to disable dimension tracking
  }
  
  # Multi-backend intelligent routing (future use)
  intelligent_routing = {
    enabled = false
  }
}
```

### Important Notes

- **No Static Policy Files**: Tenant policies are auto-generated from the template, no XML editing needed
- **Configuration-Driven**: Change behavior by updating `apim_policies` flags in `tenant.tfvars`
- **X-Tenant-Id Header**: Automatically set to the tenant name from the config key
- **Service Routing**: Backends are created only for enabled services
- **PII Redaction**: Only included if enabled AND Language Service is available
- **Fragments**: Used internally by generated policies for consistent authentication

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
  -H "api-key: {subscription-key}" \
  -d '{"model": "gpt-4", "messages": [{"role": "user", "content": "Hello"}]}'

# Alternative: Use query parameter
curl -X POST "https://{apim-gateway}/tenant/openai/chat/completions?api-key={subscription-key}" \
  -H "Content-Type: application/json" \
  -d '{"model": "gpt-4", "messages": [{"role": "user", "content": "Hello"}]}'

# Check response headers for:
# x-ratelimit-remaining-tokens: 9950
# x-tokens-consumed: 50
```
