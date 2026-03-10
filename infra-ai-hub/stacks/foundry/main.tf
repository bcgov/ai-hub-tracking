data "terraform_remote_state" "shared" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.backend_resource_group
    storage_account_name = var.backend_storage_account
    container_name       = var.backend_container_name
    key                  = "ai-services-hub/${var.app_env}/shared.tfstate"
    subscription_id      = var.subscription_id
    tenant_id            = var.tenant_id
    client_id            = var.client_id
    use_oidc             = var.use_oidc
  }
}

data "terraform_remote_state" "tenant" {
  for_each = local.enabled_tenants
  backend  = "azurerm"
  config = {
    resource_group_name  = var.backend_resource_group
    storage_account_name = var.backend_storage_account
    container_name       = var.backend_container_name
    key                  = "ai-services-hub/${var.app_env}/tenant-${each.key}.tfstate"
    subscription_id      = var.subscription_id
    tenant_id            = var.tenant_id
    client_id            = var.client_id
    use_oidc             = var.use_oidc
  }
}

module "foundry_project" {
  source   = "../../modules/foundry-project"
  for_each = local.enabled_tenants

  tenant_name       = each.value.tenant_name
  ai_foundry_hub_id = data.terraform_remote_state.shared.outputs.ai_foundry_hub_id
  location          = var.location
  ai_location       = var.shared_config.ai_foundry.ai_location

  ai_model_deployments = {
    for deployment in lookup(lookup(each.value, "openai", {}), "model_deployments", []) :
    deployment.name => {
      name                   = deployment.name
      rai_policy_name        = lookup(deployment, "rai_policy_name", null)
      version_upgrade_option = lookup(deployment, "version_upgrade_option", "OnceNewDefaultVersionAvailable")
      model = {
        format = coalesce(
          # Look up the model name's prefix against the vendor format map in locals.
          one([for prefix, fmt in local.model_format_prefixes : fmt if startswith(lower(deployment.model_name), prefix)]),
          local.default_model_format
        )
        name    = deployment.model_name
        version = deployment.model_version
      }
      scale = {
        type     = lookup(deployment, "scale_type", "Standard")
        capacity = lookup(deployment, "capacity", 10)
      }
      # content_filter: set to null to use Microsoft.DefaultV2 (Azure default).
      # Set to a custom object in the tenant's model_deployments entry to create
      # a tenant-scoped RAI policy for that specific deployment.
      # NOTE: ALL deployments across ALL tenants must have this key (null or object)
      # because Terraform's map(any) requires uniform element shapes.
      content_filter = lookup(deployment, "content_filter", { base_policy_name = "Microsoft.DefaultV2", filters = [] })
    }
  }

  key_vault = {
    enabled     = lookup(lookup(each.value, "key_vault", {}), "enabled", false)
    resource_id = try(data.terraform_remote_state.tenant[each.key].outputs.tenant_key_vaults[each.key].id, null)
    vault_uri   = try(data.terraform_remote_state.tenant[each.key].outputs.tenant_key_vaults[each.key].uri, null)
  }

  storage_account = {
    enabled           = lookup(lookup(each.value, "storage_account", {}), "enabled", false)
    resource_id       = try(data.terraform_remote_state.tenant[each.key].outputs.tenant_storage_accounts[each.key].id, null)
    name              = try(data.terraform_remote_state.tenant[each.key].outputs.tenant_storage_accounts[each.key].name, null)
    blob_endpoint_url = try(data.terraform_remote_state.tenant[each.key].outputs.tenant_storage_accounts[each.key].blob_endpoint, null)
  }

  ai_search = {
    enabled     = lookup(lookup(each.value, "ai_search", {}), "enabled", false)
    resource_id = try(data.terraform_remote_state.tenant[each.key].outputs.tenant_ai_search[each.key].id, null)
  }

  cosmos_db = {
    enabled       = lookup(lookup(each.value, "cosmos_db", {}), "enabled", false)
    resource_id   = try(data.terraform_remote_state.tenant[each.key].outputs.tenant_cosmos_db[each.key].id, null)
    database_name = lookup(lookup(each.value, "cosmos_db", {}), "database_name", "default")
  }

  document_intelligence = {
    enabled     = lookup(lookup(each.value, "document_intelligence", {}), "enabled", false)
    resource_id = try(data.terraform_remote_state.tenant[each.key].outputs.tenant_document_intelligence[each.key].id, null)
    endpoint    = try(data.terraform_remote_state.tenant[each.key].outputs.tenant_document_intelligence[each.key].endpoint, null)
  }

  project_connections = lookup(each.value, "project_connections", {})
  tags                = merge(var.common_tags, lookup(var.tenant_tags, each.key, {}))
}
