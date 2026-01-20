# ============================================================================
# Hub-Level AI Agent Capability Host (Prerequisite)
# ============================================================================
# This creates the hub-level capability host that must exist before
# project-level agent capability hosts can be created.
# This is a workaround for a limitation in the foundry module v0.6.0



# Wait for hub capability host to be ready before creating projects
resource "azapi_resource" "hub_agent_capability_host" {
  count = var.ai_foundry_definition.ai_foundry.create_ai_agent_service ? 1 : 0

  name      = "hub-agents"
  parent_id = var.foundry_ptn.ai_foundry_id
  type      = "Microsoft.CognitiveServices/accounts/capabilityHosts@2025-04-01-preview"
  
  body = {
    properties = {
      capabilityHostKind = "Agents"
    }
  }

  schema_validation_enabled = false
  
  lifecycle {
    ignore_changes = [name]
  }
}
resource "time_sleep" "wait_for_hub_capability_host" {
  count = var.ai_foundry_definition.ai_foundry.create_ai_agent_service && length(var.ai_foundry_definition.ai_projects) == 0 ? 1 : 0

  create_duration = "30s"

  depends_on = [azapi_resource.hub_agent_capability_host]
}
