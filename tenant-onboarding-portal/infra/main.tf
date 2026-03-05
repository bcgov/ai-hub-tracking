# -----------------------------------------------------------------------------
# Tenant Onboarding Portal – Resources
# -----------------------------------------------------------------------------
# Versions   → versions.tf
# Backend    → backend.tf
# Providers  → providers.tf
# Naming     → locals.tf
# -----------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# App Service Plan
# Hosts the FastAPI portal on a Linux worker. SKU is environment-driven;
# set sku_name = "F1" and enable_always_on = false for free-tier dev slots.
# ---------------------------------------------------------------------------
resource "azurerm_service_plan" "portal" {
  name                = local.app_service_plan_name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.sku_name

  tags = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# ---------------------------------------------------------------------------
# App Service – native Python runtime (Oryx build-during-deployment)
#
# Deployment model:
#   1. GitHub Actions zips the tenant-onboarding-portal/ directory.
#   2. `az webapp deploy --type zip` pushes the zip via the SCM endpoint.
#   3. SCM_DO_BUILD_DURING_DEPLOYMENT=true triggers Oryx to run
#      `pip install -r requirements.txt` inside the App Service sandbox.
#   4. Gunicorn + Uvicorn workers start the FastAPI app on port 8000.
#
# PORTAL_OIDC_CLIENT_AUDIENCE is validated against the `aud` claim in the
# id_token to prevent token-confusion attacks.  If left blank it defaults
# to the client_id inside the Python application.
# ---------------------------------------------------------------------------
resource "azurerm_linux_web_app" "portal" {
  name                = local.app_service_name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.portal.id

  # System-assigned identity used for password-less Table Storage access.
  identity {
    type = "SystemAssigned"
  }

  site_config {
    # always_on must be false for free-tier (F1/D1) SKUs.
    always_on = var.enable_always_on

    application_stack {
      python_version = var.python_version
    }

    # Gunicorn with async Uvicorn workers — matches FastAPI ASGI requirements.
    app_command_line = var.startup_command
  }

  app_settings = merge(
    {
      # Portal runtime secrets — values sourced from Key Vault or pipeline vars.
      "PORTAL_SECRET_KEY"                = var.secret_key
      "PORTAL_OIDC_DISCOVERY_URL"        = var.oidc_discovery_url
      "PORTAL_OIDC_CLIENT_ID"            = var.oidc_client_id
      "PORTAL_OIDC_CLIENT_SECRET"        = var.oidc_client_secret
      "PORTAL_OIDC_CLIENT_AUDIENCE"      = var.oidc_client_audience
      "PORTAL_OIDC_ADMIN_ROLE"           = var.oidc_admin_role
      "PORTAL_TABLE_STORAGE_ACCOUNT_URL" = var.table_storage_account_url
      "PORTAL_ADMIN_EMAILS"              = var.admin_emails
      # Oryx build: installs requirements.txt during zip deployment.
      "SCM_DO_BUILD_DURING_DEPLOYMENT" = "true"
    },
    var.extra_app_settings,
  )

  tags = var.common_tags

  lifecycle {
    ignore_changes = [tags]
  }
}

# ---------------------------------------------------------------------------
# RBAC: portal managed identity → Storage Table Data Contributor
# Enables password-less reads/writes to TenantRequests + TenantRegistry tables.
# Gated by enable_table_rbac so plan-time destroy works cleanly even when
# the storage account ID is unknown (avoids "invalid count argument" errors).
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "portal_table_contributor" {
  count = var.enable_table_rbac ? 1 : 0

  scope                = var.table_storage_account_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_linux_web_app.portal.identity[0].principal_id
}
