# =============================================================================
# Key Rotation Container App Job Module
# =============================================================================
# Deploys a Container App Job with a cron trigger that runs the APIM key
# rotation container image from GHCR.
#
# Architecture:
#   - Container App Job (scheduled cron trigger)
#   - Consumption workload profile (pay-per-execution)
#   - System-assigned Managed Identity for APIM + Key Vault RBAC
#   - 0.5 vCPU / 1 GiB RAM per execution
#   - Image pulled from GHCR (public — no credentials needed)
# =============================================================================

# ---------------------------------------------------------------------------
# Container App Job (cron-triggered)
# ---------------------------------------------------------------------------
resource "azurerm_container_app_job" "rotation" {
  name                         = "${var.name_prefix}-rotation-job"
  resource_group_name          = var.resource_group_name
  location                     = var.location
  container_app_environment_id = var.container_app_environment_id

  replica_timeout_in_seconds = var.replica_timeout_seconds
  replica_retry_limit        = var.replica_retry_limit

  # Consumption workload profile — pay-per-execution
  workload_profile_name = "Consumption"

  schedule_trigger_config {
    cron_expression          = var.cron_expression
    parallelism              = 1
    replica_completion_count = 1
  }

  identity {
    type = "SystemAssigned"
  }

  template {
    container {
      name   = "key-rotation"
      image  = "${var.container_registry_url}/${var.container_image_name}:${var.container_image_tag}"
      cpu    = var.cpu
      memory = var.memory

      # Application config — consumed by Pydantic Settings
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      env {
        name  = "APP_NAME"
        value = var.app_name
      }
      env {
        name        = "SUBSCRIPTION_ID"
        secret_name = "subscription-id"
      }
      env {
        name  = "ROTATION_ENABLED"
        value = tostring(var.rotation_enabled)
      }
      env {
        name  = "ROTATION_INTERVAL_DAYS"
        value = tostring(var.rotation_interval_days)
      }
      env {
        name  = "DRY_RUN"
        value = tostring(var.dry_run)
      }
      env {
        name  = "SECRET_EXPIRY_DAYS"
        value = tostring(var.secret_expiry_days)
      }
      env {
        name  = "RESOURCE_GROUP"
        value = var.resource_group_name
      }
      env {
        name  = "APIM_NAME"
        value = var.apim_name
      }
      env {
        name  = "HUB_KEYVAULT_NAME"
        value = var.hub_keyvault_name
      }
    }
  }

  secret {
    name  = "subscription-id"
    value = var.subscription_id
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# ---------------------------------------------------------------------------
# RBAC: Job MI → Hub Key Vault (Secrets Officer)
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "job_kv_secrets_officer" {
  scope                = var.hub_keyvault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_container_app_job.rotation.identity[0].principal_id
}

# ---------------------------------------------------------------------------
# RBAC: Job MI → APIM (API Management Service Contributor)
# Needed for subscription key regeneration via ARM
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "job_apim_contributor" {
  scope                = var.apim_id
  role_definition_name = "API Management Service Contributor"
  principal_id         = azurerm_container_app_job.rotation.identity[0].principal_id
}

# ---------------------------------------------------------------------------
# RBAC: Job MI → Resource Group (Reader) for resource discovery
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "job_rg_reader" {
  scope                = var.resource_group_id
  role_definition_name = "Reader"
  principal_id         = azurerm_container_app_job.rotation.identity[0].principal_id
}
