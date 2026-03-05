# -----------------------------------------------------------------------------
# Tenant Onboarding Portal – App Service Module
# -----------------------------------------------------------------------------
# Deploys the FastAPI portal on Azure App Service (Linux) using the
# native Python runtime (Oryx build).  No container image required.
# Uses the existing Storage Account for Table Storage.
# -----------------------------------------------------------------------------

resource "azurerm_service_plan" "portal" {
  name                = "asp-${var.app_env}-portal"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.sku_name

  tags = var.tags
}

resource "azurerm_linux_web_app" "portal" {
  name                = "app-${var.app_env}-ai-hub-portal"
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.portal.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on = var.sku_name != "F1"

    application_stack {
      python_version = var.python_version
    }

    app_command_line = var.startup_command
  }

  app_settings = merge(
    {
      "PORTAL_SECRET_KEY"                       = var.secret_key
      "PORTAL_OIDC_DISCOVERY_URL"               = var.oidc_discovery_url
      "PORTAL_OIDC_CLIENT_ID"                   = var.oidc_client_id
      "PORTAL_OIDC_CLIENT_SECRET"               = var.oidc_client_secret
      "PORTAL_TABLE_STORAGE_ACCOUNT_URL"        = var.table_storage_account_url
      "PORTAL_ADMIN_EMAILS"                     = var.admin_emails
      "SCM_DO_BUILD_DURING_DEPLOYMENT"          = "true"
    },
    var.extra_app_settings,
  )

  tags = var.tags
}

# Grant the portal's managed identity access to Table Storage
resource "azurerm_role_assignment" "portal_table_contributor" {
  count                = var.table_storage_account_id != "" ? 1 : 0
  scope                = var.table_storage_account_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_linux_web_app.portal.identity[0].principal_id
}
