# =============================================================================
# SHARED CONFIGURATION - DEV ENVIRONMENT
# =============================================================================
# This file contains shared infrastructure settings for the dev environment.
# All values in this file apply to resources shared across tenants.
# =============================================================================

shared_config = {
  # ---------------------------------------------------------------------------
  # AI Foundry Hub Settings
  # ---------------------------------------------------------------------------
  # The AI Foundry Hub is the central AI/ML workspace that tenants connect to.
  # It provides shared capabilities like model hosting and experiment tracking.
  ai_foundry = {
    name_suffix = "foundry" # Results in: {app_name}-{env}-aihub
    sku         = "S0"      # Only valid SKU for AIServices kind

    # Public access should be disabled in prod; enabled in dev for debugging
    public_network_access_enabled = false

    # Local auth allows key-based access; disable in prod for security
    local_auth_enabled = false

    # Cross-region deployment: Set to "Canada East" for model availability
    # gpt-4.1-mini (2025-04-14) and text-embedding-ada-002 available in Canada East with GlobalStandard deployment
    ai_location = "Canada East"
    # Permanently purge AI Foundry account on destroy to avoid lingering resources
    purge_on_destroy = true
  }

  # ---------------------------------------------------------------------------
  # Log Analytics Workspace
  # ---------------------------------------------------------------------------
  # Centralized logging for all resources. Required for diagnostics.
  log_analytics = {
    enabled        = true
    retention_days = 30 # Dev: 30 days is sufficient
    sku            = "PerGB2018"
  }

  # ---------------------------------------------------------------------------
  # Private Endpoint DNS Wait Settings
  # ---------------------------------------------------------------------------
  # In Azure Landing Zones, private DNS zones are policy-managed.
  # These settings control how long to wait for DNS propagation.
  private_endpoint_dns_wait = {
    timeout       = "15m" # Maximum wait time
    poll_interval = "10s" # How often to check
  }

  # ---------------------------------------------------------------------------
  # API Management (APIM)
  # ---------------------------------------------------------------------------
  # Shared API gateway for all tenant APIs. Uses stv2 with private endpoints.
  apim = {
    enabled = true

    # SKU Options:
    # - StandardV2: Cost-effective, private endpoint support
    # - PremiumV2: VNet injection, multi-region, higher scale
    sku_name = "StandardV2_1"

    # Publisher info (required by APIM)
    publisher_name  = "AI Hub Dev"
    publisher_email = "ai-hub-dev@example.com"

    # VNet integration required for outbound connectivity to private backends
    # Backend services (OpenAI, DocInt, etc.) have public network access disabled
    vnet_injection_enabled = true
    subnet_name            = "apim-subnet"
    subnet_prefix_length   = 27 # /27 = 32 IPs

    # Private DNS zone IDs for private endpoints
    # Leave empty to let Azure Policy manage DNS (Landing Zone pattern)
    private_dns_zone_ids = []

    # Subscription key rotation (runs as Container App Job — see stacks/key-rotation)
    key_rotation = {
      rotation_enabled       = true # Enable rotation in dev
      rotation_interval_days = 1    # Must be less than 90 days (APIM max key lifetime)
    }
  }

  # ---------------------------------------------------------------------------
  # Application Gateway (WAF)
  # ---------------------------------------------------------------------------
  # Optional WAF in front of APIM for additional security and SSL termination.
  app_gateway = {
    enabled = false # Disabled in dev to reduce cost

    # WAF_v2 provides Web Application Firewall capabilities
    sku_name = "WAF_v2"
    sku_tier = "WAF_v2"
    capacity = 1 # Fixed capacity (no autoscale in dev)

    # Autoscale (optional) - set to null to use fixed capacity
    # autoscale = {
    #   min_capacity = 1
    #   max_capacity = 3
    # }

    waf_enabled = true
    waf_mode    = "Detection" # Detection only in dev; Prevention in prod

    # WAF body inspection (CRS 3.2+)
    request_body_check               = true
    request_body_enforcement         = false # Allow large Doc Intelligence payloads
    request_body_inspect_limit_in_kb = 128
    max_request_body_size_kb         = 2000 # ~2MB (provider max)
    file_upload_limit_mb             = 100

    # Subnet settings
    subnet_name          = "appgw-subnet"
    subnet_prefix_length = 27 # /27 = 32 IPs

    # Frontend hostname (must match SSL certificate)
    frontend_hostname = "api-dev.example.com"

    # SSL certificates from Key Vault
    # ssl_certificates = {
    #   primary = {
    #     name                = "api-cert"
    #     key_vault_secret_id = "https://mykv.vault.azure.net/secrets/api-cert"
    #   }
    # }

    # Key Vault for managed identity access to SSL certs
    # key_vault_id = "/subscriptions/.../resourceGroups/.../providers/Microsoft.KeyVault/vaults/..."
  }

  # ---------------------------------------------------------------------------
  # Container Registry (ACR)
  # ---------------------------------------------------------------------------
  # Shared container registry for storing container images.
  container_registry = {
    enabled                       = true
    sku                           = "Basic"
    public_network_access_enabled = true

    # Enable trust policy for signed images (requires Premium)
    enable_trust_policy = false
  }

  # ---------------------------------------------------------------------------
  # Container App Environment
  # ---------------------------------------------------------------------------
  # Serverless container hosting environment for Container App Jobs
  # (e.g., APIM key rotation). Uses /27 ACA subnet from network module.
  container_app_environment = {
    enabled = true

    # Zone redundancy requires /23 subnet and increases cost
    # Disable for dev to save costs
    zone_redundancy_enabled = false

    # ACA subnet configuration (passed to network module)
    subnet_name          = "aca-subnet"
    subnet_prefix_length = 27 # /27 = 32 IPs (minimum for consumption-only without zone redundancy)

    # Workload profiles (optional) - uses consumption-only if empty
    # workload_profiles = {
    #   "dedicated-d4" = {
    #     workload_profile_type  = "D4"
    #     minimum_count          = 1
    #     maximum_count          = 3
    #   }
    # }
  }

  # ---------------------------------------------------------------------------
  # PII Redaction Service
  # ---------------------------------------------------------------------------
  pii_redaction_service = {
    per_batch_timeout_seconds  = 10 # Maximum duration for a single outbound Language API attempt
    transient_retry_attempts   = 4  # Retry count for transient 429 and 5xx Language API responses
    retry_backoff_base_seconds = 1  # Initial exponential backoff delay when Retry-After is absent
    retry_backoff_max_seconds  = 10 # Cap for exponential backoff between retry attempts
  }

  # ---------------------------------------------------------------------------
  # App Configuration
  # ---------------------------------------------------------------------------
  # Centralized configuration store for feature flags and settings.
  app_configuration = {
    enabled = true
    sku     = "standard" # Options: free, standard

    # Public access for dev debugging; disable in prod
    public_network_access = "Disabled"
  }

  # ---------------------------------------------------------------------------
  # Language Service (for PII Detection)
  # ---------------------------------------------------------------------------
  # Azure AI Language Service for enterprise PII detection via APIM policies.
  # Used by pii-anonymization.xml fragment to detect and redact sensitive data.
  language_service = {
    enabled = true
    sku     = "S" # Options: F0 (free), S (standard)

    # Keep disabled - access via private endpoint only
    public_network_access_enabled = false
  }

}

# =============================================================================
# SUBNET ALLOCATION
# Single source of truth for address space ↔ subnet mapping.
# Outer key = address space CIDR, inner key = subnet name, value = full subnet CIDR.
#
# Supported subnet names (exact keys required by network module):
#   "privateendpoints-subnet"    — Primary PE subnet (no delegation)
#   "privateendpoints-subnet-<n>" — Additional PE subnets, <n> = 1, 2, 3, ...
#   "apim-subnet"               — APIM VNet injection (/27 min)
#   "appgw-subnet"              — Application Gateway (/27 min, no delegation)
#   "aca-subnet"                — Container Apps Environment (/27 min)
#
# CIDRs are explicit — the value is the exact subnet CIDR, not a prefix length.
# Subnets are independent; changing one does not affect others.
#
# --- CURRENT LAYOUT (dev): single /24 ---
#   10.x.x.0/27   privateendpoints-subnet  (32 IPs)
#   10.x.x.32/27  apim-subnet              (32 IPs)
#   10.x.x.64/27  aca-subnet               (32 IPs)
#   10.x.x.96/27  ← unused / reserved
#   10.x.x.128/25 ← unused / reserved
#
# --- GROWTH PATTERNS ---
#
# (A) Enable App Gateway (when WAF needed in dev for parity testing):
#   Add "appgw-subnet" = "10.x.x.96/27" alongside aca-subnet in the existing space.
#   Note: appgw lands at priority 2 (between apim and aca), shifting aca
#   forward — but because CIDRs are computed at plan time, this only matters
#   if aca-subnet doesn't exist yet. If aca is already deployed, add a second
#   address space instead to avoid recomputing aca's CIDR.
#
# (B) More private endpoints (e.g., 10+ PE resources exhaust /27):
#   Add a second address space dedicated to overflow PEs:
#   "10.x.x.0/24" = { "privateendpoints-subnet-1" = "10.x.x.0/27" }
#   The network module will expose the overflow subnet CIDR via
#   private_endpoint_subnet_cidrs_by_key["privateendpoints-subnet-1"] and its ID via
#   private_endpoint_subnet_ids_by_key["privateendpoints-subnet-1"] in the shared stack outputs.
#   Individual tenants are routed to specific PE subnets via
#   pe_subnet_key in each tenant's config (var.tenants[key].pe_subnet_key).
#
# (C) AKS cluster (future, requires /22–/23 for nodes+pods):
#   AKS is not a named subnet type yet — add a new address space with a
#   custom subnet name once AKS support is implemented in the network module.
#   Typical sizing: /22 (1024 IPs) for small clusters, /21 for larger ones.
#   Example (not yet supported):
#   "10.x.x.0/22" = { "aks-nodes-subnet" = "10.x.x.0/22" }
# =============================================================================
# *** subnet_allocation is NOT defined here — it is provided via the
# *** TF_VAR_subnet_allocation environment variable (GitHub environment secret
# *** in CI, or exported locally). This avoids committing IP addresses to the repo.
#
# Example structure (dev, single /24):
#   subnet_allocation = {
#     "10.x.x.0/24" = {
#       "privateendpoints-subnet" = "10.x.x.0/27"  # 32 IPs
#       "apim-subnet"             = "10.x.x.32/27" # 32 IPs
#       "aca-subnet"              = "10.x.x.64/27" # 32 IPs
#     }
#   }

# =============================================================================
# External VNet Peered Projects — Direct APIM Access (bypassing App Gateway)
# Teams with VNet peering can reach APIM directly over private networking.
# Each entry creates an inbound HTTPS NSG rule on the APIM subnet.
# NSGs are stateful — no outbound mirror rule needed.
#
# Format: project-name = { cidrs = ["cidr-1", "cidr-2"], priority = 4xx }
# Project names must be lowercase alphanumeric with hyphens.
# Priorities must be unique per project, in range 400–499. Use gaps (400, 410, 420)
# so inserting a new project never forces renumbering.
#
# Example:
#   external_peered_projects = {
#     "forest-client" = { cidrs = ["10.x.x.0/20"],                   priority = 400 }
#     "nr-data-hub"   = { cidrs = ["10.x.x.0/22", "10.x.x.0/22"], priority = 410 }
#   }
# =============================================================================
# external_peered_projects = {}
