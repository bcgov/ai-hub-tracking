output "resource_id" {
  description = "Resource ID of the WAF policy"
  value       = azurerm_web_application_firewall_policy.this.id
}

output "name" {
  description = "Name of the WAF policy"
  value       = azurerm_web_application_firewall_policy.this.name
}

output "http_listener_ids" {
  description = "Associated HTTP listener IDs"
  value       = azurerm_web_application_firewall_policy.this.http_listener_ids
}

output "path_based_rule_ids" {
  description = "Associated path-based rule IDs"
  value       = azurerm_web_application_firewall_policy.this.path_based_rule_ids
}
