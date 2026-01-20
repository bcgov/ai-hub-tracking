variable "ai_foundry_definition" {
  type = object({
    ai_foundry = optional(object({
      create_ai_agent_service = optional(bool, false)
    }), {})
    ai_projects = optional(map(object({
      name = string
    })), {})
  })
  description = <<DESCRIPTION
Configuration for AI Foundry and agent capability host creation.

- `ai_foundry.create_ai_agent_service` - (Optional) Whether to create the hub-level AI agent capability host. Default is false.
- `ai_projects` - (Optional) List of AI project configurations. Default is an empty list.

This configuration determines whether the hub-level agent capability host should be created and helps coordinate timing with project creation.
DESCRIPTION
  nullable    = false
}

variable "foundry_ptn" {
  type = object({
    ai_foundry_id = string
  })
  description = <<DESCRIPTION
Output from the AI Foundry pattern module.

- `ai_foundry_id` - Resource ID of the AI Foundry hub.

This is used to create the hub-level capability host as a child resource of the AI Foundry hub.
DESCRIPTION
  nullable    = false
}
