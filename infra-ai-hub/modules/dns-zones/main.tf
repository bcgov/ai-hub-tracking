locals {
  # Define all DNS zone names required for AI Foundry and dependencies
  dns_zone_definitions = {
    key_vault = {
      name = "privatelink.vaultcore.azure.net"
    }
    apim = {
      name = "privatelink.azure-api.net"
    }
    cosmos_sql = {
      name = "privatelink.documents.azure.com"
    }
    cosmos_mongo = {
      name = "privatelink.mongo.cosmos.azure.com"
    }
    cosmos_cassandra = {
      name = "privatelink.cassandra.cosmos.azure.com"
    }
    cosmos_gremlin = {
      name = "privatelink.gremlin.cosmos.azure.com"
    }
    cosmos_table = {
      name = "privatelink.table.cosmos.azure.com"
    }
    cosmos_analytical = {
      name = "privatelink.analytics.cosmos.azure.com"
    }
    cosmos_postgres = {
      name = "privatelink.postgres.cosmos.azure.com"
    }
    storage_blob = {
      name = "privatelink.blob.core.windows.net"
    }
    storage_queue = {
      name = "privatelink.queue.core.windows.net"
    }
    storage_table = {
      name = "privatelink.table.core.windows.net"
    }
    storage_file = {
      name = "privatelink.file.core.windows.net"
    }
    storage_dfs = {
      name = "privatelink.dfs.core.windows.net"
    }
    storage_web = {
      name = "privatelink.web.core.windows.net"
    }
    ai_search = {
      name = "privatelink.search.windows.net"
    }
    container_registry = {
      name = "privatelink.azurecr.io"
    }
    app_configuration = {
      name = "privatelink.azconfig.io"
    }
    ai_foundry_openai = {
      name = "privatelink.openai.azure.com"
    }
    ai_foundry_ai_services = {
      name = "privatelink.services.ai.azure.com"
    }
    ai_foundry_cognitive_services = {
      name = "privatelink.cognitiveservices.azure.com"
    }
  }

  # Build resource IDs for existing zones when not using platform landing zone
  dns_zones = !var.use_platform_landing_zone ? {
    for key, value in local.dns_zone_definitions : key => {
      name        = value.name
      resource_id = "${coalesce(var.existing_zones_resource_group_resource_id, "notused")}/providers/Microsoft.Network/privateDnsZones/${value.name}"
    }
  } : {}
}
