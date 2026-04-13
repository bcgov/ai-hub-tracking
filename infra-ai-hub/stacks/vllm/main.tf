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

# Hugging Face token from hub Key Vault (only resolved when a secret name is configured).
# Set shared_config.vllm.huggingface_secret_name to the Key Vault secret name that holds
# the token. Omit to deploy without a token (suitable for ungated public models).
data "azurerm_key_vault_secret" "huggingface_token" {
  count        = local.vllm_enabled && try(local.vllm_config.huggingface_secret_name, "") != "" ? 1 : 0
  name         = local.vllm_config.huggingface_secret_name
  key_vault_id = data.terraform_remote_state.shared.outputs.hub_key_vault_id
}

module "vllm_service" {
  source = "../../modules/vllm-service"
  count  = local.vllm_enabled ? 1 : 0

  app_name            = "${var.app_name}-${var.app_env}"
  resource_group_name = data.terraform_remote_state.shared.outputs.resource_group_name
  location            = var.location
  common_tags         = var.common_tags
  scripts_dir         = "${path.root}/../../scripts"

  infrastructure_subnet_id   = data.terraform_remote_state.shared.outputs.vllm_aca_subnet_id
  private_endpoint_subnet_id = data.terraform_remote_state.shared.outputs.private_endpoint_subnet_id
  log_analytics_workspace_id = data.terraform_remote_state.shared.outputs.log_analytics_workspace_id

  model_id               = try(local.vllm_config.model_id, "google/gemma-4-31B-it")
  image                  = try(local.vllm_config.image, "vllm/vllm-openai:latest")
  offline_mode           = try(local.vllm_config.offline_mode, false)
  model_source           = try(local.vllm_config.model_source, "huggingface")
  azureml_registry       = try(local.vllm_config.azureml_registry, null)
  quantization           = try(local.vllm_config.quantization, null)
  max_model_len          = try(local.vllm_config.max_model_len, 32768)
  gpu_memory_utilization = try(local.vllm_config.gpu_memory_utilization, 0.9)
  workload_profile_type  = try(local.vllm_config.workload_profile_type, "Consumption-GPU-NC24-A100")
  registry_sku           = try(local.vllm_config.registry_sku, "Basic")

  # scale-to-zero by default; GPU cold-start for Gemma 4 31B is 5-10 minutes
  min_replicas = try(local.vllm_config.min_replicas, 0)
  max_replicas = try(local.vllm_config.max_replicas, 1)

  model_cache_share_quota_gb = try(local.vllm_config.model_cache_share_quota_gb, 64)

  huggingface_token = length(data.azurerm_key_vault_secret.huggingface_token) > 0 ? data.azurerm_key_vault_secret.huggingface_token[0].value : ""

  private_endpoint_dns_wait                = try(var.shared_config.private_endpoint_dns_wait, {})
  wait_for_private_endpoint_dns_zone_group = try(local.vllm_config.wait_for_private_endpoint_dns_zone_group, false)
}

# Grants the module's user-assigned identity permission to download model assets from
# the AzureML registry. Assigned at the registry scope so the identity can list and
# download any model version registered there. The role assignment must exist before the
# Container App's init container first runs; creating the identity in the module and the
# role assignment here (in the stack) ensures the correct sequencing — the module output
# is only available after the identity resource is created, guaranteeing the assignment
# happens before the Container App is provisioned.
resource "azurerm_role_assignment" "azureml_registry_user" {
  count = local.use_azureml_source ? 1 : 0

  scope                = local.vllm_config.azureml_registry.registry_resource_id
  role_definition_name = "AzureML Registry User"
  principal_id         = module.vllm_service[0].azureml_downloader_principal_id
}
