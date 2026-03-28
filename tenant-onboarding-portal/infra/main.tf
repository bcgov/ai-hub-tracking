# -----------------------------------------------------------------------------
# Tenant Onboarding Portal – Resources
# -----------------------------------------------------------------------------
# Versions   → versions.tf
# Backend    → backend.tf
# Providers  → providers.tf
# Naming     → locals.tf
# -----------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# App Service Plan (AVM)
# Registry: https://registry.terraform.io/modules/Azure/avm-res-web-serverfarm/azurerm/latest
# ---------------------------------------------------------------------------

### Create a resource group which is unique for each PR(non-prod) and single for PROD both lives in same tools environment of Azure
resource "azurerm_resource_group" "portal" {
  name     = local.resource_group_name
  location = var.location
}

module "portal_plan" {
  source  = "Azure/avm-res-web-serverfarm/azurerm"
  version = "2.0.2"

  name      = local.app_service_plan_name
  location  = var.location
  parent_id = azurerm_resource_group.portal.id
  os_type   = "Linux"
  sku_name  = var.sku_name

  # Preserve current behavior rather than inheriting AVM scaling defaults.
  worker_count           = 1
  zone_balancing_enabled = false

  tags = var.common_tags
}

# ---------------------------------------------------------------------------
# App Service (AVM) – native Node runtime with regional VNet integration
# Registry: https://registry.terraform.io/modules/Azure/avm-res-web-site/azurerm/latest
#
# Deployment model:
#   1. GitHub Actions builds tenant-onboarding-portal/frontend, copies it into
#      tenant-onboarding-portal/backend/frontend-dist, then zips the backend app root.
#   2. The deploy wrapper builds a self-contained backend package with frontend assets.
#   3. `az webapp deploy --type zip` pushes the zip and extracts it into wwwroot.
#   4. `node dist/main.js` launches the compiled Nest application on the App Service port.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Storage Account (AVM)
# Registry: https://registry.terraform.io/modules/Azure/avm-res-storage-storageaccount/azurerm/latest
#
# The portal backend uses Azure Table Storage.
# Provision the required tables in Terraform and allow shared-key access so the
# app can use a direct storage connection string for login/session persistence.
# ---------------------------------------------------------------------------
resource "random_string" "storage_suffix" {
  length  = 8
  lower   = true
  numeric = true
  special = false
  upper   = false
}

module "portal_storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.6.8"

  name                = local.storage_account_name
  location            = var.location
  resource_group_name = azurerm_resource_group.portal.name

  public_network_access_enabled = true
  account_replication_type      = var.storage_account_replication_type
  shared_access_key_enabled     = true
  network_rules = {
    bypass                     = ["AzureServices"]
    default_action             = "Allow"
    ip_rules                   = []
    virtual_network_subnet_ids = []
  }
  tables = {
    tenant_requests = {
      name = "TenantRequests"
    }
    tenant_registry = {
      name = "TenantRegistry"
    }
    tenant_user_index = {
      name = "TenantUserIndex"
    }
    tenant_status_index = {
      name = "TenantStatusIndex"
    }
    tenant_access_index = {
      name = "TenantAccessIndex"
    }
    portal_sessions = {
      name = "TenantPortalSessions"
    }
  }

  tags = var.common_tags
}

module "portal" {
  source  = "Azure/avm-res-web-site/azurerm"
  version = "0.21.8"

  name                     = local.app_service_name
  location                 = var.location
  parent_id                = azurerm_resource_group.portal.id
  service_plan_resource_id = module.portal_plan.resource_id

  kind                          = "webapp"
  os_type                       = "Linux"
  public_network_access_enabled = true
  https_only                    = true
  virtual_network_subnet_id     = data.azurerm_subnet.app_service.id

  managed_identities = {
    system_assigned = true
  }

  site_config = {
    always_on         = var.enable_always_on
    app_command_line  = var.startup_command
    health_check_path = "/healthz"

    application_stack = {
      node = {
        node_version = local.portal_node_version
      }
    }
  }

  app_settings = merge(
    {
      "PORTAL_OIDC_DISCOVERY_URL"              = var.oidc_discovery_url
      "PORTAL_OIDC_CLIENT_ID"                  = var.oidc_client_id
      "PORTAL_OIDC_CLIENT_SECRET"              = var.oidc_client_secret
      "PORTAL_OIDC_CLIENT_AUDIENCE"            = var.oidc_client_audience
      "PORTAL_OIDC_ADMIN_ROLE"                 = var.oidc_admin_role
      "PORTAL_TABLE_STORAGE_CONNECTION_STRING" = module.portal_storage.resource.primary_connection_string
      "PORTAL_TABLE_STORAGE_ACCOUNT_URL"       = ""
      "PORTAL_ADMIN_EMAILS"                    = var.admin_emails
      "SCM_DO_BUILD_DURING_DEPLOYMENT"         = "false"
      "WEBSITES_ENABLE_APP_SERVICE_STORAGE"    = "true"
      "PORTAL_HUB_KEYVAULT_URL_DEV"            = var.hub_keyvault_url_dev
      "PORTAL_HUB_KEYVAULT_URL_TEST"           = var.hub_keyvault_url_test
      "PORTAL_HUB_KEYVAULT_URL_PROD"           = var.hub_keyvault_url_prod
      "PORTAL_APIM_GATEWAY_URL_DEV"            = var.apim_gateway_url_dev
      "PORTAL_APIM_GATEWAY_URL_TEST"           = var.apim_gateway_url_test
      "PORTAL_APIM_GATEWAY_URL_PROD"           = var.apim_gateway_url_prod
    },
    var.extra_app_settings,
  )

  deployment_slots = var.enable_deployment_slot ? {
    staging = {
      name                          = "staging"
      public_network_access_enabled = true
      virtual_network_subnet_id     = data.azurerm_subnet.app_service.id

      app_settings = merge(
        {
          "PORTAL_OIDC_DISCOVERY_URL"              = var.oidc_discovery_url
          "PORTAL_OIDC_CLIENT_ID"                  = var.oidc_client_id
          "PORTAL_OIDC_CLIENT_SECRET"              = var.oidc_client_secret
          "PORTAL_OIDC_CLIENT_AUDIENCE"            = var.oidc_client_audience
          "PORTAL_OIDC_ADMIN_ROLE"                 = var.oidc_admin_role
          "PORTAL_TABLE_STORAGE_CONNECTION_STRING" = module.portal_storage.resource.primary_connection_string
          "PORTAL_TABLE_STORAGE_ACCOUNT_URL"       = ""
          "PORTAL_ADMIN_EMAILS"                    = var.admin_emails
          "SCM_DO_BUILD_DURING_DEPLOYMENT"         = "false"
          "WEBSITES_ENABLE_APP_SERVICE_STORAGE"    = "true"
          "PORTAL_HUB_KEYVAULT_URL_DEV"            = var.hub_keyvault_url_dev
          "PORTAL_HUB_KEYVAULT_URL_TEST"           = var.hub_keyvault_url_test
          "PORTAL_HUB_KEYVAULT_URL_PROD"           = var.hub_keyvault_url_prod
          "PORTAL_APIM_GATEWAY_URL_DEV"            = var.apim_gateway_url_dev
          "PORTAL_APIM_GATEWAY_URL_TEST"           = var.apim_gateway_url_test
          "PORTAL_APIM_GATEWAY_URL_PROD"           = var.apim_gateway_url_prod
        },
        var.extra_app_settings,
      )

      site_config = {
        always_on         = var.enable_always_on
        app_command_line  = var.startup_command
        health_check_path = "/healthz"

        application_stack = {
          node = {
            node_version = local.portal_node_version
          }
        }
      }
    }
  } : {}

  tags = var.common_tags
}

# ---------------------------------------------------------------------------
# RBAC: portal managed identity → Storage Table Data Contributor
# Enables password-less reads/writes to the portal's Azure Table Storage tables.
# Gated by enable_table_rbac so plan-time destroy works cleanly even when
# the storage account ID is unknown (avoids "invalid count argument" errors).
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "portal_table_contributor" {
  count = var.enable_table_rbac ? 1 : 0

  scope                = module.portal_storage.resource_id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = module.portal.system_assigned_mi_principal_id
}

resource "azurerm_role_assignment" "portal_table_contributor_tables" {
  for_each = var.enable_table_rbac ? toset([
    "TenantRequests",
    "TenantRegistry",
    "TenantUserIndex",
    "TenantStatusIndex",
    "TenantAccessIndex",
    "TenantPortalSessions",
  ]) : toset([])

  scope                = "${module.portal_storage.resource_id}/tableServices/default/tables/${each.value}"
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = module.portal.system_assigned_mi_principal_id
}

# ---------------------------------------------------------------------------
# RBAC: portal managed identity → Key Vault Secrets User (hub KV per env)
# Enables the portal backend to read APIM primary/secondary keys from each
# hub environment's Key Vault. Gated on the KV ID being supplied so that
# tools/PR-preview deployments (which don't set these variables) plan cleanly.
# ---------------------------------------------------------------------------
resource "azurerm_role_assignment" "portal_mi_hub_kv_secrets_user_dev" {
  count = var.hub_keyvault_id_dev != "" ? 1 : 0

  scope                = var.hub_keyvault_id_dev
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.portal.system_assigned_mi_principal_id
}

resource "azurerm_role_assignment" "portal_mi_hub_kv_secrets_user_test" {
  count = var.hub_keyvault_id_test != "" ? 1 : 0

  scope                = var.hub_keyvault_id_test
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.portal.system_assigned_mi_principal_id
}

resource "azurerm_role_assignment" "portal_mi_hub_kv_secrets_user_prod" {
  count = var.hub_keyvault_id_prod != "" ? 1 : 0

  scope                = var.hub_keyvault_id_prod
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.portal.system_assigned_mi_principal_id
}
