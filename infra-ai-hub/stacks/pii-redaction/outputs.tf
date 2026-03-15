output "pii_redaction_service" {
  description = "PII Redaction Container App details (null when not deployed)"
  value = length(module.pii_redaction_service) > 0 ? {
    container_app_id   = module.pii_redaction_service[0].container_app_id
    container_app_fqdn = module.pii_redaction_service[0].container_app_fqdn
    principal_id       = module.pii_redaction_service[0].principal_id
  } : null
}
