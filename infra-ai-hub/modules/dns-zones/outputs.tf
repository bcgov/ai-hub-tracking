output "zones" {
  description = <<DESCRIPTION
Map of DNS zones with their names and resource IDs.

Returns a structured map where each key corresponds to a service type and contains:
- name: The DNS zone name
- resource_id: The full Azure resource ID of the DNS zone
DESCRIPTION
  value       = local.dns_zones
}

output "ai_foundry_zones" {
  description = "DNS zones specifically for AI Foundry hub."
  value = {
    openai              = local.dns_zones["ai_foundry_openai"]
    ai_services         = local.dns_zones["ai_foundry_ai_services"]
    cognitive_services  = local.dns_zones["ai_foundry_cognitive_services"]
  }
}

output "cosmos_zone" {
  description = "DNS zone for Cosmos DB SQL API."
  value       = local.dns_zones["cosmos_sql"]
}

output "ai_search_zone" {
  description = "DNS zone for AI Search."
  value       = local.dns_zones["ai_search"]
}

output "key_vault_zone" {
  description = "DNS zone for Key Vault."
  value       = local.dns_zones["key_vault"]
}

output "storage_zones" {
  description = "DNS zones for Storage Account endpoints."
  value = {
    blob  = local.dns_zones["storage_blob"]
    file  = local.dns_zones["storage_file"]
    queue = local.dns_zones["storage_queue"]
    table = local.dns_zones["storage_table"]
    dfs   = local.dns_zones["storage_dfs"]
    web   = local.dns_zones["storage_web"]
  }
}
