# =============================================================================
# PII Redaction Service Module
# =============================================================================
# Deploys a Container App (HTTP-triggered) that externalises large-payload PII
# redaction from APIM. APIM routes requests here when a chat payload requires
# more than 5 Language API documents. The service handles sequential batching,
# rolling timeouts, and full-coverage verification.
#
# Ingress: external_enabled=true on an internal CAE → VNet-accessible only
#          (not public). Required because APIM is outside the CAE boundary.
#
# Identity: SystemAssigned MI granted Cognitive Services User on the Language
#           Service so it can call the PII recognition endpoint without keys.
# =============================================================================

# ---------------------------------------------------------------------------
# Force image pull when using :latest tag
# ---------------------------------------------------------------------------
# Terraform cannot detect a new image behind a mutable tag like :latest.
# This resource produces a new timestamp each apply, which is injected as an
# env var so azurerm_container_app detects a diff and updates in-place,
# causing Azure to re-pull the image on the next revision.
resource "terraform_data" "image_refresh" {
  count = var.container_image_tag == "latest" ? 1 : 0
  input = timestamp()
}

# ---------------------------------------------------------------------------
# Container App (HTTP-triggered, VNet-accessible via internal CAE)
# ---------------------------------------------------------------------------
resource "azurerm_container_app" "service" {
  name                         = "${var.name_prefix}-piisvc"
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"

  identity {
    type = "SystemAssigned"
  }

  ingress {
    # external_enabled = true is required for APIM to reach this service.
    # APIM lives in the VNet but outside the Container Apps Environment.
    # With an internal CAE, external_enabled=true exposes the app to the VNet
    # only — it is NOT publicly accessible. external_enabled=false restricts
    # access to apps within the same CAE, which would block APIM entirely.
    # Ref: https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview#ingress-configuration
    external_enabled = true
    target_port      = 8000
    transport        = "http"

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "pii-redaction-service"
      image  = "${var.container_registry_url}/${var.container_image_name}:${var.container_image_tag}"
      cpu    = var.cpu
      memory = var.memory

      # PII service configuration — consumed by Pydantic Settings (PII_ prefix)
      env {
        name  = "PII_LANGUAGE_ENDPOINT"
        value = var.language_endpoint
      }
      env {
        name  = "PII_LANGUAGE_API_VERSION"
        value = var.language_api_version
      }
      env {
        name  = "PII_PER_BATCH_TIMEOUT_SECONDS"
        value = tostring(var.per_batch_timeout_seconds)
      }
      env {
        name  = "PII_TOTAL_PROCESSING_TIMEOUT_SECONDS"
        value = tostring(var.total_processing_timeout_seconds)
      }
      env {
        name  = "PII_MAX_SEQUENTIAL_BATCHES"
        value = tostring(var.max_sequential_batches)
      }
      env {
        name  = "PII_MAX_DOC_CHARS"
        value = tostring(var.max_doc_chars)
      }
      env {
        name  = "PII_MAX_DOCS_PER_CALL"
        value = tostring(var.max_docs_per_call)
      }
      env {
        name  = "PII_LOG_LEVEL"
        value = var.log_level
      }

      # Token that changes each apply when using :latest — forces image re-pull
      env {
        name  = "FORCE_IMAGE_PULL"
        value = var.container_image_tag == "latest" ? terraform_data.image_refresh[0].output : var.container_image_tag
      }

      liveness_probe {
        path                    = "/health"
        port                    = 8000
        transport               = "HTTP"
        initial_delay           = 10
        interval_seconds        = 30
        failure_count_threshold = 3
      }

      readiness_probe {
        path      = "/health"
        port      = 8000
        transport = "HTTP"
      }
    }
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# ---------------------------------------------------------------------------
# RBAC: Container App MI → Language Service (Cognitive Services User)
# Grants the service principal permission to call the Language API using
# DefaultAzureCredential — no API keys stored in environment variables.
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "svc_language_cognitive_user" {
  scope                = var.language_service_id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_container_app.service.identity[0].principal_id
}
