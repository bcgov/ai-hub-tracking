# =============================================================================
# AI Foundry Project Module
# =============================================================================
# Creates AI Foundry projects and connections for a single tenant.
# This module is designed to be called SERIALLY to avoid ETag conflicts
# when multiple tenants modify the shared AI Foundry hub concurrently.
#
# ARCHITECTURE:
# - The tenant module creates all tenant resources (KeyVault, Storage, etc.)
# - This module is called AFTER tenant module completes
# - Projects are created serially (one at a time) to avoid Azure API conflicts
# - Connections within a project are also serialized via depends_on chains
# =============================================================================

# =============================================================================
# AI FOUNDRY PROJECT
# =============================================================================
resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview"
  name      = "${local.name_prefix}-project"
  location  = var.ai_location # Must match parent hub location
  parent_id = var.ai_foundry_hub_id

  identity {
    type = "SystemAssigned"
  }

  body = {
    sku = {
      name = "S0"
    }
    properties = {
      displayName = var.tenant_name
      description = "AI Foundry project for ${var.tenant_name}"
    }
  }

  tags = var.tags

  response_export_values = [
    "identity.principalId",
    "properties.internalId"
  ]

  schema_validation_enabled = false

  lifecycle {
    ignore_changes = [tags]
  }
}

# =============================================================================
# ROLE ASSIGNMENTS FOR AI FOUNDRY PROJECT
# Grant the project's managed identity access to tenant resources
# =============================================================================

# Key Vault access for AI Foundry Project
resource "azurerm_role_assignment" "project_to_keyvault" {
  count = var.key_vault.enabled ? 1 : 0

  scope                = var.key_vault.resource_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = local.project_principal_id
}

# Storage access for AI Foundry Project
resource "azurerm_role_assignment" "project_to_storage" {
  count = var.storage_account.enabled ? 1 : 0

  scope                = var.storage_account.resource_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = local.project_principal_id
}

# AI Search access for AI Foundry Project
resource "azurerm_role_assignment" "project_to_search" {
  count = var.ai_search.enabled ? 1 : 0

  scope                = var.ai_search.resource_id
  role_definition_name = "Search Index Data Contributor"
  principal_id         = local.project_principal_id
}

# Cosmos DB access for AI Foundry Project
resource "azurerm_role_assignment" "project_to_cosmos" {
  count = var.cosmos_db.enabled ? 1 : 0

  scope                = var.cosmos_db.resource_id
  role_definition_name = "Cosmos DB Account Reader Role"
  principal_id         = local.project_principal_id
}

# Document Intelligence access for AI Foundry Project
resource "azurerm_role_assignment" "project_to_docint" {
  count = var.document_intelligence.enabled ? 1 : 0

  scope                = var.document_intelligence.resource_id
  role_definition_name = "Cognitive Services User"
  principal_id         = local.project_principal_id
}

# OpenAI access for AI Foundry Project
resource "azurerm_role_assignment" "project_to_openai" {
  count = var.openai.enabled ? 1 : 0

  scope                = var.openai.resource_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = local.project_principal_id
}

# =============================================================================
# PROJECT CONNECTIONS
# These create AI Foundry project connections to tenant resources
# Connections are SERIALIZED via depends_on to avoid ETag conflicts
# =============================================================================

# Connection to Key Vault
resource "azapi_resource" "connection_keyvault" {
  count = var.key_vault.enabled && var.project_connections.key_vault ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "keyvault-${local.name_prefix}"
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      authType      = "AAD"
      category      = "AzureKeyVault"
      target        = var.key_vault.resource_id
      isSharedToAll = false
      metadata = {
        ApiType    = "Azure"
        ApiVersion = "7.4"
      }
    }
  }

  schema_validation_enabled = false

  depends_on = [azurerm_role_assignment.project_to_keyvault]
}

# Connection to Storage Account
resource "azapi_resource" "connection_storage" {
  count = var.storage_account.enabled && var.project_connections.storage ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "storage-${local.name_prefix}"
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      authType      = "AAD"
      category      = "AzureBlob"
      target        = var.storage_account.blob_endpoint_url
      isSharedToAll = false
      metadata = {
        AccountName   = var.storage_account.name
        ContainerName = "default"
      }
    }
  }

  schema_validation_enabled = false

  depends_on = [
    azurerm_role_assignment.project_to_storage,
    azapi_resource.connection_keyvault # Serialize connection operations
  ]
}

# Connection to AI Search
resource "azapi_resource" "connection_ai_search" {
  count = var.ai_search.enabled && var.project_connections.ai_search ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "aisearch-${local.name_prefix}"
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      authType      = "AAD"
      category      = "CognitiveSearch"
      target        = var.ai_search.resource_id
      isSharedToAll = false
      metadata = {
        ApiType    = "Azure"
        ApiVersion = "2024-05-01-preview"
      }
    }
  }

  schema_validation_enabled = false

  depends_on = [
    azurerm_role_assignment.project_to_search,
    azapi_resource.connection_storage # Serialize connection operations
  ]
}

# Connection to Cosmos DB
resource "azapi_resource" "connection_cosmos" {
  count = var.cosmos_db.enabled && var.project_connections.cosmos_db ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "cosmosdb-${local.name_prefix}"
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      authType      = "AAD"
      category      = "CosmosDb"
      target        = var.cosmos_db.resource_id
      isSharedToAll = false
      metadata = {
        ApiType    = "Azure"
        DatabaseId = var.cosmos_db.database_name
      }
    }
  }

  schema_validation_enabled = false

  depends_on = [
    azurerm_role_assignment.project_to_cosmos,
    azapi_resource.connection_ai_search # Serialize connection operations
  ]
}

# Connection to OpenAI
resource "azapi_resource" "connection_openai" {
  count = var.openai.enabled && var.project_connections.openai ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "openai-${local.name_prefix}"
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      authType      = "AAD"
      category      = "AzureOpenAI"
      target        = var.openai.resource_id
      isSharedToAll = false
      metadata = {
        ApiType    = "Azure"
        ApiVersion = "2024-06-01"
      }
    }
  }

  schema_validation_enabled = false

  depends_on = [
    azurerm_role_assignment.project_to_openai,
    azapi_resource.connection_cosmos # Serialize connection operations
  ]
}

# Connection to Document Intelligence
resource "azapi_resource" "connection_docint" {
  count = var.document_intelligence.enabled && var.project_connections.document_intelligence ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "docint-${local.name_prefix}"
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      authType      = "AAD"
      category      = "CognitiveService"
      target        = var.document_intelligence.endpoint
      isSharedToAll = false
      metadata = {
        ApiType = "Azure"
        Kind    = "FormRecognizer"
      }
    }
  }

  schema_validation_enabled = false

  depends_on = [
    azurerm_role_assignment.project_to_docint,
    azapi_resource.connection_openai # Serialize connection operations
  ]
}
