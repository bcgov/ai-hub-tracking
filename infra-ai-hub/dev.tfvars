# ========================================================================================================
# Terraform Variables for dev Environment -- Only static values should go here for tools specific tfvars
# NO SECRETS OR SENSITIVE VALUES SHOULD BE STORED IN THESE FILES
# ========================================================================================================
resource_group_name = "ai-hub-dev-rg"
environment_name    = "dev"
tags = {
  Environment  = "dev"
  Project      = "ai-hub"
  Subscription = "da4cf6"
  ManagedBy    = "Terraform"
}
ai_foundry_definition = {
  create_byor      = true
  purge_on_destroy = false

  ai_foundry = {
    name                     = "aihub-foundry-dev"
    disable_local_auth       = false
    allow_project_management = true
    create_ai_agent_service  = false
    sku                      = "S0"
  }

  # Per-project dependency resources (isolated)
  ai_search_definition = {
    project_water_forms_assist = {
      name                          = "aihub-dev-wfa-search"
      sku                           = "standard"
      partition_count               = 1
      replica_count                 = 2
      semantic_search_enabled       = true
      public_network_access_enabled = false
    }
  }
  cosmosdb_definition = {
    project_water_forms_assist = {
      name                          = "aihubdevwfacosmos"
      public_network_access_enabled = false
      analytical_storage_enabled    = true
      automatic_failover_enabled    = false
      local_authentication_disabled = true
    }
  }
  key_vault_definition = {
    project_water_forms_assist = {
      name = "aihubdevwfakv"
      sku  = "standard"
    }
  }
  storage_account_definition = {
    project_water_forms_assist = {
      name                      = "aihubdevwfasa"
      account_kind              = "StorageV2"
      account_tier              = "Standard"
      account_replication_type  = "ZRS"
      shared_access_key_enabled = true
      access_tier               = "Hot"
      endpoints = {
        blob = { type = "blob" }
      }
    }
  }

  # Create a Foundry project and connect to the new resources above
  ai_projects = {
    project_water_forms_assist = {
      name                       = "water-form-assistant"
      sku                        = "S0"
      display_name               = "Water Form Assistant"
      description                = "AI Hub Development Project 1"
      create_project_connections = true
      cosmos_db_connection = {
        new_resource_map_key = "project_water_forms_assist"
      }
      ai_search_connection = {
        new_resource_map_key = "project_water_forms_assist"
      }
      key_vault_connection = {
        new_resource_map_key = "project_water_forms_assist"
      }
      storage_account_connection = {
        new_resource_map_key = "project_water_forms_assist"
      }
    }
  }
}
