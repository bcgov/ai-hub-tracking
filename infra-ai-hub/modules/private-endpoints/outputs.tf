output "ai_foundry_pe_id" {
  description = "Resource ID of the AI Foundry private endpoint."
  value       = var.enabled && length(azurerm_private_endpoint.ai_foundry_pe) > 0 ? azurerm_private_endpoint.ai_foundry_pe[0].id : null
}

output "ai_foundry_pe_name" {
  description = "Name of the AI Foundry private endpoint."
  value       = var.enabled && length(azurerm_private_endpoint.ai_foundry_pe) > 0 ? azurerm_private_endpoint.ai_foundry_pe[0].name : null
}

output "cosmos_db_pe_ids" {
  description = "Map of Cosmos DB private endpoint IDs."
  value       = { for key, pe in azurerm_private_endpoint.cosmos_db_pe : key => pe.id }
}

output "ai_search_pe_ids" {
  description = "Map of AI Search private endpoint IDs."
  value       = { for key, pe in azurerm_private_endpoint.ai_search_pe : key => pe.id }
}

output "key_vault_pe_ids" {
  description = "Map of Key Vault private endpoint IDs."
  value       = { for key, pe in azurerm_private_endpoint.keyvault_pe : key => pe.id }
}

output "storage_pe_ids" {
  description = "Map of Storage Account private endpoint IDs."
  value       = { for key, pe in azurerm_private_endpoint.storage_pe : key => pe.id }
}

output "all_pe_details" {
  description = "Complete details of all private endpoints created."
  value = var.enabled ? {
    ai_foundry = length(azurerm_private_endpoint.ai_foundry_pe) > 0 ? {
      id       = azurerm_private_endpoint.ai_foundry_pe[0].id
      name     = azurerm_private_endpoint.ai_foundry_pe[0].name
      location = azurerm_private_endpoint.ai_foundry_pe[0].location
    } : null
    cosmos_db = {
      for key, pe in azurerm_private_endpoint.cosmos_db_pe : key => {
        id       = pe.id
        name     = pe.name
        location = pe.location
      }
    }
    ai_search = {
      for key, pe in azurerm_private_endpoint.ai_search_pe : key => {
        id       = pe.id
        name     = pe.name
        location = pe.location
      }
    }
    key_vault = {
      for key, pe in azurerm_private_endpoint.keyvault_pe : key => {
        id       = pe.id
        name     = pe.name
        location = pe.location
      }
    }
    storage = {
      for key, pe in azurerm_private_endpoint.storage_pe : key => {
        id       = pe.id
        name     = pe.name
        location = pe.location
      }
    }
  } : null
}
