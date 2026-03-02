# =============================================================================
# Key Rotation Stack
# =============================================================================
# Deploys the APIM key rotation Container App Job.
# Reads shared outputs (CAE, Key Vault, App Insights) and APIM outputs
# (APIM ID/name) via terraform_remote_state.
#
# Phase: 4 (after shared + tenant + apim)
# State key: ai-services-hub/{env}/key-rotation.tfstate
# =============================================================================

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

data "terraform_remote_state" "apim" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.backend_resource_group
    storage_account_name = var.backend_storage_account
    container_name       = var.backend_container_name
    key                  = "ai-services-hub/${var.app_env}/apim.tfstate"
    subscription_id      = var.subscription_id
    tenant_id            = var.tenant_id
    client_id            = var.client_id
    use_oidc             = var.use_oidc
  }
}

# =============================================================================
# KEY ROTATION CONTAINER APP JOB
# =============================================================================
# Cron-triggered Container App Job that rotates APIM subscription keys using
# an alternating primary/secondary pattern. Container image from GHCR.
# =============================================================================
module "key_rotation" {
  source = "../../modules/key-rotation-function"
  # Deploy only when global rotation is on, APIM + CAE exist, AND at least one
  # tenant has opted in.  Without the tenant guard an empty INCLUDED_TENANTS env
  # var would cause the Python runner to process ALL discovered tenants.
  count = (
    local.key_rotation_config.rotation_enabled &&
    local.apim_config.enabled &&
    local.cae_config.enabled &&
    local.rotation_enabled_tenants != ""
  ) ? 1 : 0

  name_prefix         = "${var.app_name}-${var.app_env}"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  resource_group_id   = data.terraform_remote_state.shared.outputs.resource_group_id
  location            = var.location

  # Container App Environment (from shared stack)
  container_app_environment_id = data.terraform_remote_state.shared.outputs.container_app_environment_id

  # Container image from GHCR
  container_registry_url = lookup(local.key_rotation_config, "container_registry_url", "ghcr.io")
  container_image_name   = lookup(local.key_rotation_config, "container_image_name", "bcgov/ai-hub-tracking/jobs/apim-key-rotation")
  container_image_tag    = var.container_image_tag_job_key_rotation != "" ? var.container_image_tag_job_key_rotation : lookup(local.key_rotation_config, "container_image_tag", "latest")

  # Container resources
  cpu    = lookup(local.key_rotation_config, "cpu", 0.5)
  memory = lookup(local.key_rotation_config, "memory", "1Gi")

  # Job scheduling (5-part cron: min hour day month weekday)
  cron_expression = lookup(local.key_rotation_config, "cron_expression", "0 9 * * *")

  # APIM reference (from APIM stack remote state)
  apim_id   = data.terraform_remote_state.apim.outputs.apim_id
  apim_name = data.terraform_remote_state.apim.outputs.apim_name

  # Hub Key Vault reference (from shared stack)
  hub_keyvault_id   = data.terraform_remote_state.shared.outputs.hub_key_vault_id
  hub_keyvault_name = data.terraform_remote_state.shared.outputs.hub_key_vault_name

  # Application config
  environment            = var.app_env
  app_name               = var.app_name
  subscription_id        = var.subscription_id
  rotation_enabled       = local.key_rotation_config.rotation_enabled
  rotation_interval_days = local.key_rotation_config.rotation_interval_days
  dry_run                = lookup(local.key_rotation_config, "dry_run", false)
  included_tenants       = local.rotation_enabled_tenants

  tags = var.common_tags
}
