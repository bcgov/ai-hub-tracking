# -----------------------------------------------------------------------------
# Outputs – Tenant Onboarding Portal Infrastructure
# -----------------------------------------------------------------------------

output "app_service_name" {
  description = "The name of the deployed App Service."
  value       = module.portal.name
}

output "resource_group_name" {
  description = "The resource group containing the deployed App Service."
  value       = data.azurerm_resource_group.portal.name
}

output "app_service_default_hostname" {
  description = "Default hostname of the App Service."
  value       = module.portal.resource_uri
}

output "app_service_principal_id" {
  description = "Managed identity principal ID of the App Service."
  value       = module.portal.system_assigned_mi_principal_id
  sensitive   = true
}

output "staging_slot_hostname" {
  description = "Default hostname of the staging deployment slot. Empty string when enable_deployment_slot is false."
  value       = try(module.portal.deployment_slots["staging"].output.properties.defaultHostName, "")
}

output "storage_account_name" {
  description = "The name of the portal Storage Account used for Azure Table Storage."
  value       = module.portal_storage.name
}

output "storage_account_id" {
  description = "The resource ID of the portal Storage Account used for Azure Table Storage."
  value       = module.portal_storage.resource_id
  sensitive   = true
}

output "table_storage_account_url" {
  description = "The Azure Table Storage endpoint URL used by the portal application."
  value       = local.table_storage_account_url
  sensitive   = true
}
