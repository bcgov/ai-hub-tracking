locals {
  apim_config  = var.shared_config.apim
  appgw_config = var.shared_config.app_gateway

  # ---------------------------------------------------------------------------
  # Monitoring configuration with safe defaults
  # ---------------------------------------------------------------------------
  monitoring_config = {
    enabled = lookup(lookup(var.shared_config, "monitoring", {}), "enabled", false)

    # Email addresses sourced from shared_config.monitoring.alert_emails (non-sensitive, env-specific).
    alert_emails = lookup(lookup(var.shared_config, "monitoring", {}), "alert_emails", [])

    # True when at least one notification channel (webhook or email) is provided.
    # Used in the precondition that guards against monitoring being enabled with no receiver.
    has_any_receiver = (
      trim(var.monitoring_webhook_url, " ") != "" ||
      length(lookup(lookup(var.shared_config, "monitoring", {}), "alert_emails", [])) > 0
    )

    # Azure regions to monitor for service health events.
    # Should include the primary deployment region and the AI cross-region location.
    service_health_locations = lookup(
      lookup(var.shared_config, "monitoring", {}),
      "service_health_locations",
      [var.location, lookup(var.shared_config.ai_foundry, "ai_location", var.location)]
    )

    # NOTE: services filter is intentionally omitted — Azure's internal service names
    # differ from portal display names and cause 400 errors. Omitting covers all services
    # in the configured regions, which is more comprehensive.
  }

  dns_zone_config = lookup(var.shared_config, "dns_zone", {
    enabled             = false
    zone_name           = ""
    resource_group_name = ""
    a_record_ttl        = 3600
  })

  apim_gateway_fqdn = "${var.app_name}-${var.app_env}-apim.azure-api.net"

  # ---------------------------------------------------------------------------
  # WAF Defaults — used when not overridden per-environment in shared_config
  # ---------------------------------------------------------------------------

  # Default managed rule sets: OWASP 3.2 + Bot Manager 1.0
  # Overrides disable rules that false-positive on API payloads
  default_waf_managed_rule_sets = [
    {
      type    = "OWASP"
      version = "3.2"
      rule_group_overrides = [
        {
          # General rules — body parsing errors on JSON payloads
          rule_group_name = "General"
          rules = [
            { id = "200002", enabled = false }, # REQBODY_ERROR
            { id = "200003", enabled = false }, # MULTIPART_STRICT_ERROR
          ]
        }
      ]
    },
    {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.0"
      rule_group_overrides = [
        {
          # API clients (curl, SDKs) aren't browsers
          rule_group_name = "UnknownBots"
          rules = [
            { id = "300700", enabled = false }, # Generic unknown bot
            { id = "300300", enabled = false }, # curl user-agent
            { id = "300100", enabled = false }, # Missing common browser headers
          ]
        }
      ]
    }
  ]

  # Default custom WAF rules:
  # - Geo-block rule (priority 1): deny all traffic not originating from CA or US
  # - Allow rules (priority 11-25): bypass managed rules for authenticated API traffic
  #     Each service has two sibling Allow rules — one matching api-key, one matching
  #     Ocp-Apim-Subscription-Key. This is required because WAF evaluates before the
  #     AppGW rewrite rule that copies Ocp-Apim-Subscription-Key → api-key, so the
  #     api-key header does not exist yet at WAF evaluation time for legacy clients.
  # - Rate-limit rules (priority 90-91): L7 DDoS mitigation
  default_waf_custom_rules = [
    {
      # Block all traffic not originating from Canada or United States.
      # Evaluated first (priority 1) so it cannot be bypassed by lower-priority Allow rules.
      name      = "BlockNonCaUsGeo"
      priority  = 1
      rule_type = "MatchRule"
      action    = "Block"
      match_conditions = [
        {
          match_variable = "RemoteAddr"
          operator       = "GeoMatch"
          negation       = true
          match_values   = ["CA", "US"]
        }
      ]
    },
    {
      # Document Intelligence file uploads (binary content types)
      name      = "AllowDocIntelFileUploads"
      priority  = 11
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestUri"
          operator       = "Contains"
          match_values   = ["documentintelligence", "formrecognizer"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "Content-Type"
          operator       = "Contains"
          match_values = [
            "application/octet-stream",
            "image/",
            "application/pdf",
            "multipart/form-data"
          ]
          transforms = ["Lowercase"]
        }
      ]
    },
    {
      # Document Intelligence JSON requests (base64Source payloads) — api-key header
      name      = "AllowDocIntelJsonWithApiKey"
      priority  = 12
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestUri"
          operator       = "Contains"
          match_values   = ["documentintelligence", "formrecognizer", "documentmodels"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "Content-Type"
          operator       = "Contains"
          match_values   = ["application/json"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "api-key"
          operator       = "Regex"
          match_values   = [".+"]
        }
      ]
    },
    {
      # Document Intelligence JSON requests — Ocp-Apim-Subscription-Key header
      # WAF evaluates before AppGW rewrite rules, so OCP key is NOT yet mapped to api-key.
      name      = "AllowDocIntelJsonWithOcpKey"
      priority  = 13
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestUri"
          operator       = "Contains"
          match_values   = ["documentintelligence", "formrecognizer", "documentmodels"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "Content-Type"
          operator       = "Contains"
          match_values   = ["application/json"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "Ocp-Apim-Subscription-Key"
          operator       = "Regex"
          match_values   = [".+"]
        }
      ]
    },
    {
      # OpenAI / GPT chat completions and embeddings — api-key header
      name      = "AllowOpenAiWithApiKey"
      priority  = 20
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestUri"
          operator       = "Contains"
          match_values   = ["/openai/"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "api-key"
          operator       = "Regex"
          match_values   = [".+"]
        }
      ]
    },
    {
      # OpenAI — Ocp-Apim-Subscription-Key header
      name      = "AllowOpenAiWithOcpKey"
      priority  = 21
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestUri"
          operator       = "Contains"
          match_values   = ["/openai/"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "Ocp-Apim-Subscription-Key"
          operator       = "Regex"
          match_values   = [".+"]
        }
      ]
    },
    {
      # AI Search: index schema, queries, and vector search operations — api-key header
      name      = "AllowAiSearchWithApiKey"
      priority  = 22
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestUri"
          operator       = "Contains"
          match_values   = ["/ai-search/"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "api-key"
          operator       = "Regex"
          match_values   = [".+"]
        }
      ]
    },
    {
      # AI Search — Ocp-Apim-Subscription-Key header
      name      = "AllowAiSearchWithOcpKey"
      priority  = 23
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestUri"
          operator       = "Contains"
          match_values   = ["/ai-search/"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "Ocp-Apim-Subscription-Key"
          operator       = "Regex"
          match_values   = [".+"]
        }
      ]
    },
    {
      # Speech Services: TTS (SSML/XML) and STT (audio binary) — api-key header
      name      = "AllowSpeechWithApiKey"
      priority  = 24
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestUri"
          operator       = "Contains"
          match_values   = ["cognitiveservices", "speech/synthesis", "speech/recognition"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "api-key"
          operator       = "Regex"
          match_values   = [".+"]
        }
      ]
    },
    {
      # Speech Services — Ocp-Apim-Subscription-Key header
      name      = "AllowSpeechWithOcpKey"
      priority  = 25
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestUri"
          operator       = "Contains"
          match_values   = ["cognitiveservices", "speech/synthesis", "speech/recognition"]
          transforms     = ["Lowercase"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "Ocp-Apim-Subscription-Key"
          operator       = "Regex"
          match_values   = [".+"]
        }
      ]
    },
    # ----- Rate-Limit Rules (L7 DDoS mitigation) ----------------------------
    # Azure WAF custom rule priorities must be 1–100 (inclusive).
    # Geo-block is priority 1; Allow rules are 11-25 (api-key + OCP sibling pairs); rate-limit rules are 90-91.
    {
      # Global rate limit: max requests per source IP per minute
      name                 = "RateLimitPerSourceIP"
      priority             = 90
      rule_type            = "RateLimitRule"
      action               = "Block"
      rate_limit_duration  = "OneMin"
      rate_limit_threshold = 300
      group_rate_limit_by  = "ClientAddr"
      match_conditions = [
        {
          match_variable = "RemoteAddr"
          operator       = "IPMatch"
          negation       = true
          match_values   = ["127.0.0.1"]
        }
      ]
    },
    {
      # Stricter rate limit for unauthenticated requests
      # (both api-key and Ocp-Apim-Subscription-Key headers are missing)
      name                 = "RateLimitUnauthenticated"
      priority             = 91
      rule_type            = "RateLimitRule"
      action               = "Block"
      rate_limit_duration  = "OneMin"
      rate_limit_threshold = 10
      group_rate_limit_by  = "ClientAddr"
      match_conditions = [
        {
          match_variable = "RequestHeaders"
          selector       = "api-key"
          operator       = "Regex"
          negation       = true
          match_values   = [".+"]
        },
        {
          match_variable = "RequestHeaders"
          selector       = "Ocp-Apim-Subscription-Key"
          operator       = "Regex"
          negation       = true
          match_values   = [".+"]
        }
      ]
    }
  ]
}
