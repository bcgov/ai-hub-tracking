# =============================================================================
# Key Rotation Function App Module
# =============================================================================
# Deploys an Azure Functions app running a custom container image from GHCR
# for APIM subscription key rotation.
#
# Architecture:
#   - Linux Consumption plan (Flex Consumption not yet GA for containers)
#   - Custom container image from GHCR (no ACR required)
#   - System-assigned Managed Identity for APIM + Key Vault RBAC
#   - Application Insights integration for observability
#   - Timer-triggered: runs daily, checks rotation interval before acting
# =============================================================================

# ---------------------------------------------------------------------------
# Storage Account (required by Azure Functions runtime)
# ---------------------------------------------------------------------------
resource "azurerm_storage_account" "func" {
  name                = replace("${var.name_prefix}rotfn", "-", "")
  resource_group_name = var.resource_group_name
  location            = var.location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"

  # Public access disabled — Functions runtime communicates via internal channel
  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# ---------------------------------------------------------------------------
# App Service Plan (Linux Consumption — Flex Consumption not yet available
# for custom containers as of Feb 2026)
# ---------------------------------------------------------------------------
resource "azurerm_service_plan" "func" {
  name                = "${var.name_prefix}-rotation-plan"
  resource_group_name = var.resource_group_name
  location            = var.location

  os_type  = "Linux"
  sku_name = "Y1" # Consumption plan (pay-per-execution)

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# ---------------------------------------------------------------------------
# Linux Function App (custom container from GHCR)
# ---------------------------------------------------------------------------
resource "azurerm_linux_function_app" "rotation" {
  name                = "${var.name_prefix}-rotation-fn"
  resource_group_name = var.resource_group_name
  location            = var.location

  service_plan_id            = azurerm_service_plan.func.id
  storage_account_name       = azurerm_storage_account.func.name
  storage_account_access_key = azurerm_storage_account.func.primary_access_key

  # Managed identity for APIM + Key Vault RBAC
  identity {
    type = "SystemAssigned"
  }

  # VNet integration for private Key Vault access (optional)
  virtual_network_subnet_id = var.vnet_subnet_id

  site_config {
    application_insights_connection_string = var.application_insights_connection_string

    application_stack {
      docker {
        registry_url = "https://ghcr.io"
        image_name   = var.container_image_name
        image_tag    = var.container_image_tag
      }
    }

    # Always-on not supported on Consumption plan
  }

  app_settings = {
    # Azure Functions runtime
    FUNCTIONS_WORKER_RUNTIME            = "python"
    WEBSITES_ENABLE_APP_SERVICE_STORAGE = "false"

    # GHCR access (public images — no credentials needed for public repos)
    DOCKER_REGISTRY_SERVER_URL = "https://ghcr.io"

    # Application config — consumed by Pydantic Settings
    ENVIRONMENT            = var.environment
    APP_NAME               = var.app_name
    SUBSCRIPTION_ID        = var.subscription_id
    ROTATION_ENABLED       = tostring(var.rotation_enabled)
    ROTATION_INTERVAL_DAYS = tostring(var.rotation_interval_days)
    ROTATION_CRON_SCHEDULE = var.rotation_cron_schedule
    DRY_RUN                = tostring(var.dry_run)
    SECRET_EXPIRY_DAYS     = tostring(var.secret_expiry_days)
    RESOURCE_GROUP         = var.resource_group_name
    APIM_NAME              = var.apim_name
    HUB_KEYVAULT_NAME      = var.hub_keyvault_name
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# ---------------------------------------------------------------------------
# RBAC: Function MI → Hub Key Vault (Secrets Officer)
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "func_kv_secrets_officer" {
  scope                = var.hub_keyvault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = azurerm_linux_function_app.rotation.identity[0].principal_id
}

# ---------------------------------------------------------------------------
# RBAC: Function MI → APIM (API Management Service Contributor)
# Needed for subscription key regeneration via ARM
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "func_apim_contributor" {
  scope                = var.apim_id
  role_definition_name = "API Management Service Contributor"
  principal_id         = azurerm_linux_function_app.rotation.identity[0].principal_id
}

# ---------------------------------------------------------------------------
# RBAC: Function MI → Resource Group (Reader) for resource discovery
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "func_rg_reader" {
  scope                = var.resource_group_id
  role_definition_name = "Reader"
  principal_id         = azurerm_linux_function_app.rotation.identity[0].principal_id
}
