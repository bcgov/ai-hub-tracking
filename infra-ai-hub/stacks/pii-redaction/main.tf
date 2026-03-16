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

module "pii_redaction_service" {
  source = "../../modules/pii-redaction-service"
  count  = local.cae_config.enabled && try(local.pii_redaction_config.enabled, true) ? 1 : 0

  name_prefix                  = "${var.app_name}-${var.app_env}"
  resource_group_name          = data.terraform_remote_state.shared.outputs.resource_group_name
  container_app_environment_id = data.terraform_remote_state.shared.outputs.container_app_environment_id
  language_endpoint            = data.terraform_remote_state.shared.outputs.language_service_endpoint
  language_service_id          = data.terraform_remote_state.shared.outputs.language_service_id

  container_registry_url     = lookup(local.pii_redaction_config, "container_registry_url", "ghcr.io")
  container_image_name       = lookup(local.pii_redaction_config, "container_image_name", "bcgov/ai-hub-tracking/pii-redaction-service")
  container_image_tag        = var.container_image_tag_svc_pii_redaction != "" ? var.container_image_tag_svc_pii_redaction : lookup(local.pii_redaction_config, "container_image_tag", "latest")
  language_api_version       = var.language_api_version
  per_batch_timeout_seconds  = lookup(local.pii_redaction_config, "per_batch_timeout_seconds", 10)
  transient_retry_attempts   = lookup(local.pii_redaction_config, "transient_retry_attempts", 4)
  retry_backoff_base_seconds = lookup(local.pii_redaction_config, "retry_backoff_base_seconds", 1)
  retry_backoff_max_seconds  = lookup(local.pii_redaction_config, "retry_backoff_max_seconds", 10)
  max_concurrent_batches     = lookup(local.pii_redaction_config, "max_concurrent_batches", 15)
  max_batch_concurrency      = lookup(local.pii_redaction_config, "max_batch_concurrency", 3)
  max_doc_chars              = lookup(local.pii_redaction_config, "max_doc_chars", 5000)
  max_docs_per_call          = lookup(local.pii_redaction_config, "max_docs_per_call", 5)
  # https://learn.microsoft.com/en-gb/azure/container-apps/containers#allocations
  cpu          = lookup(local.pii_redaction_config, "cpu", 0.25)
  memory       = lookup(local.pii_redaction_config, "memory", "0.5Gi")
  min_replicas = lookup(local.pii_redaction_config, "min_replicas", 1)
  max_replicas = lookup(local.pii_redaction_config, "max_replicas", 5)
  log_level    = lookup(local.pii_redaction_config, "log_level", "INFO")

  tags = var.common_tags
}
