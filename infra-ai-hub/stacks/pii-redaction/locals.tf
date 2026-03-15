locals {
  pii_redaction_config = try(var.shared_config.pii_redaction_service, {})
  cae_config           = var.shared_config.container_app_environment
}
