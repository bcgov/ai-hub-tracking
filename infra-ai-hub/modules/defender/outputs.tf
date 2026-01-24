output "enabled_resource_types" {
  description = "List of Defender for Cloud resource types that are enabled"
  value       = keys(var.resource_types)
}

output "pricing_ids" {
  description = "Map of resource type to pricing resource ID"
  value = {
    for k, v in azurerm_security_center_subscription_pricing.this : k => v.id
  }
}
