# Capability Hosts Module

This module creates hub-level AI agent capability hosts for Azure AI Foundry. The capability host is a prerequisite resource that must exist at the hub level before project-level agent capability hosts can be created.

## Purpose

Creates the hub-level AI agent capability host required for enabling AI agent services in Azure AI Foundry. This is a workaround for a limitation in the foundry pattern module v0.6.0 where the hub capability host must be created before any projects that use agent services.

## Features

- Conditional creation based on `create_ai_agent_service` flag
- Automatic wait time after creation to ensure resource readiness
- Proper dependency management with AI Foundry hub

## Usage

```hcl
module "capability_hosts" {
  source = "./modules/capability-hosts"
  
  ai_foundry_definition = {
    ai_foundry = {
      create_ai_agent_service = true
    }
    ai_projects = []
  }
  
  foundry_ptn = {
    ai_foundry_id = "/subscriptions/.../providers/Microsoft.CognitiveServices/accounts/my-hub"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| azapi | ~> 2.4 |
| time | ~> 0.12 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| ai_foundry_definition | Configuration for AI Foundry and agent capability host creation | <pre>object({<br>  ai_foundry = optional(object({<br>    create_ai_agent_service = optional(bool, false)<br>  }))<br>  ai_projects = optional(list(object({<br>    name = string<br>  })), [])<br>})</pre> | n/a | yes |
| foundry_ptn | Output from the AI Foundry pattern module | <pre>object({<br>  ai_foundry_id = string<br>})</pre> | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| hub_agent_capability_host_id | Resource ID of the hub-level AI agent capability host |
| hub_agent_capability_host_name | Name of the hub-level AI agent capability host |
| agent_service_enabled | Whether the AI agent service is enabled and capability host created |

## Resources Created

- `azapi_resource.hub_agent_capability_host` - Hub-level agent capability host (conditional)
- `time_sleep.wait_for_hub_capability_host` - Wait resource for capability host readiness (conditional)

## Dependencies

This module depends on:
- AI Foundry hub being created by the foundry pattern module
- Azure API provider for preview API access

## Notes

- The capability host uses a preview API version (2025-04-01-preview)
- A 30-second wait time is added when no projects are defined to ensure readiness
- The name "hub-agents" is fixed and managed by lifecycle rules
- This is a temporary workaround until the foundry pattern module handles this internally
