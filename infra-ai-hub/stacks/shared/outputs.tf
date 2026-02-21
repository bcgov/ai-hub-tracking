output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "resource_group_id" {
  value = azurerm_resource_group.main.id
}

output "private_endpoint_subnet_id" {
  value = module.network.private_endpoint_subnet_id
}

output "private_endpoint_subnet_cidr" {
  value = module.network.private_endpoint_subnet_cidr
}

output "private_endpoint_nsg_id" {
  value = module.network.private_endpoint_nsg_id
}

output "apim_subnet_id" {
  value = module.network.apim_subnet_id
}

output "appgw_subnet_id" {
  value = module.network.appgw_subnet_id
}

output "ai_foundry_hub_id" {
  value = module.ai_foundry_hub.id
}

output "ai_foundry_hub_name" {
  value = module.ai_foundry_hub.name
}

output "ai_foundry_hub_endpoint" {
  value = module.ai_foundry_hub.endpoint
}

output "ai_foundry_hub_principal_id" {
  value = module.ai_foundry_hub.principal_id
}

output "log_analytics_workspace_id" {
  value = module.ai_foundry_hub.log_analytics_workspace_id
}

output "application_insights_id" {
  value = module.ai_foundry_hub.application_insights_id
}

output "application_insights_connection_string" {
  value     = module.ai_foundry_hub.application_insights_connection_string
  sensitive = true
}

output "application_insights_instrumentation_key" {
  value     = module.ai_foundry_hub.application_insights_instrumentation_key
  sensitive = true
}

output "language_service_id" {
  value = var.shared_config.language_service.enabled ? azurerm_cognitive_account.language_service[0].id : null
}

output "language_service_endpoint" {
  value = var.shared_config.language_service.enabled ? azurerm_cognitive_account.language_service[0].endpoint : null
}

output "hub_key_vault_id" {
  value = module.hub_key_vault.resource_id
}

output "hub_key_vault_name" {
  value = module.hub_key_vault.name
}

output "hub_key_vault_uri" {
  value = module.hub_key_vault.uri
}

output "dns_zone_public_ip_id" {
  value = length(module.dns_zone) > 0 ? module.dns_zone[0].public_ip_id : null
}

output "dns_zone_public_ip_address" {
  value = length(module.dns_zone) > 0 ? module.dns_zone[0].public_ip_address : null
}

output "waf_policy_id" {
  value = length(module.waf_policy) > 0 ? module.waf_policy[0].resource_id : null
}

output "app_gateway_id" {
  value = length(module.app_gateway) > 0 ? module.app_gateway[0].id : null
}

output "app_gateway_name" {
  value = length(module.app_gateway) > 0 ? module.app_gateway[0].name : null
}

output "appgw_url" {
  description = "App Gateway frontend URL (https://<frontend_hostname>). Null when App Gateway is not deployed."
  value       = length(module.app_gateway) > 0 ? "https://${lookup(local.appgw_config, "frontend_hostname", "")}" : null
}

output "hub_alerts_action_group_id" {
  description = "Resource ID of the hub monitoring action group. Referenced by the APIM stack to attach APIM resource health alerts."
  value       = length(azurerm_monitor_action_group.hub_alerts) > 0 ? azurerm_monitor_action_group.hub_alerts[0].id : null
}
