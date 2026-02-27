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
  # - Allow with api-key (priority 3): immediately allow any request carrying the
  #     api-key header; header PRESENCE detection is reliable with Any + negation=false.
  # - Allow with Ocp-key (priority 4): same for Ocp-Apim-Subscription-Key.
  #     Two separate Allow rules are needed because WAF evaluates before the AppGW
  #     rewrite that copies Ocp-key → api-key.
  # - Allow with Bearer token (priority 5): same for Authorization: Bearer <key>.
  #     OpenAI-compatible clients (OpenCode, Cursor, Continue) send Bearer tokens.
  #     AppGW rewrite rule maps Bearer → api-key after WAF, so WAF must allow first.
  # - Block unauth API paths (priority 10): block any request to a path beyond root /
  #     that was not caught by p3/p4/p5 (i.e., no auth header). Azure WAF cannot
  #     reliably detect absent headers via negation — the engine skips absent-header
  #     conditions instead of evaluating them as non-matching. The correct pattern is:
  #     Allow-first (p3/p4/p5) + Block-remainder (p10).
  #     NOTE: Azure WAF RequestUri is path-only (e.g. /resolve), not the full URL.
  #     Use ^/[^/?#] — not ://host/path anchoring — to detect non-root paths.
  # - Allow rules (priority 11-25): redundant for authenticated traffic (already
  #     allowed at p3/p4/p5) but kept as defence-in-depth and for OWASP rule bypasses.
  # - Rate-limit rules (priority 90-91): L7 DDoS mitigation
  #     Priority 91 caps unauthenticated root-path traffic (scanners/probes that hit /)
  #     at 2 req/min; all deeper unauthenticated paths are blocked at priority 10.
  default_waf_custom_rules = [
    {
      # Block all traffic not originating from Canada or United States.
      # Evaluated first (priority 1) so it cannot be bypassed by lower-priority Allow rules.
      # NOTE: GeoMatch uses IP-registry allocation (ARIN/RIPE), not physical routing.
      # IPs leased by foreign cloud providers from US-registered 
      # blocks are classified as US and therefore NOT blocked by this rule.
      # Those are handled by RateLimitUnauthenticated (priority 91) and
      # BlockUnauthenticatedApiPaths (priority 10) instead.
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
      # Allow any request that carries the api-key header (authenticated traffic).
      # Azure WAF reliably detects header PRESENCE with Any + negation=false.
      # This must be a lower priority number than BlockUnauthenticatedApiPaths (p10)
      # so authenticated requests escape the block rule entirely.
      name      = "AllowApiKeyHeaderRequests"
      priority  = 3
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestHeaders"
          selector       = "api-key"
          operator       = "Any"
          negation       = false
          match_values   = []
        }
      ]
    },
    {
      # Allow any request that carries the Ocp-Apim-Subscription-Key header.
      # WAF evaluates before AppGW rewrites, so Ocp-key may not yet have been
      # mapped to api-key; both headers must be allowed independently.
      name      = "AllowOcpKeyHeaderRequests"
      priority  = 4
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestHeaders"
          selector       = "Ocp-Apim-Subscription-Key"
          operator       = "Any"
          negation       = false
          match_values   = []
        }
      ]
    },
    {
      # Allow any request that carries an Authorization: Bearer token.
      # OpenAI-compatible clients (OpenCode, Cursor, Continue) use this format.
      # WAF evaluates before AppGW rewrites, so the Bearer token has not yet been
      # mapped to api-key; must be allowed independently at WAF layer.
      # Pattern matches "Bearer " followed by at least one character.
      name      = "AllowBearerTokenRequests"
      priority  = 5
      rule_type = "MatchRule"
      action    = "Allow"
      match_conditions = [
        {
          match_variable = "RequestHeaders"
          selector       = "Authorization"
          operator       = "Regex"
          negation       = false
          match_values   = ["^Bearer .+"]
        }
      ]
    },
    {
      # Block any unauthenticated request to a real API path.
      # Rules p3/p4/p5 allow all requests carrying api-key, Ocp-key, or Bearer token,
      # so only keyless requests reach this rule.  Root / is excluded:
      #   ^/       → anchors to path start (Azure WAF RequestUri is path-only, e.g. /resolve)
      #   [^/?#]   → requires ≥1 non-separator char — bare / or /?q=… produce no match
      name      = "BlockUnauthenticatedApiPaths"
      priority  = 10
      rule_type = "MatchRule"
      action    = "Block"
      match_conditions = [
        {
          match_variable = "RequestUri"
          operator       = "Regex"
          negation       = false
          match_values   = ["^/[^/?#]"]
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
    # Geo-block is priority 1; Allow-with-key is 3-4; block unauth paths is 10; Allow rules are 11-25 (api-key + OCP sibling pairs); rate-limit rules are 90-91.
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
      # Strict rate limit for unauthenticated requests to root path /.
      # All deeper paths without a key are already blocked at priority 10
      # (BlockUnauthenticatedApiPaths). This rule covers the residual: scanners/probes
      # that hit bare / with no key (e.g. Alibaba measurement probes that pass GeoMatch
      # because their IP block is ARIN-registered as US). 2 req/min per source IP.
      # All three auth header conditions use negation=true (AND logic): the rule matches
      # only when ALL three headers are absent — i.e. truly unauthenticated requests.
      name                 = "RateLimitUnauthenticated"
      priority             = 91
      rule_type            = "RateLimitRule"
      action               = "Block"
      rate_limit_duration  = "OneMin"
      rate_limit_threshold = 2
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
        },
        {
          match_variable = "RequestHeaders"
          selector       = "Authorization"
          operator       = "Regex"
          negation       = true
          match_values   = ["^Bearer .+"]
        }
      ]
    }
  ]
}
