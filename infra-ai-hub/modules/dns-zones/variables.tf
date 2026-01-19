variable "use_platform_landing_zone" {
  type        = bool
  description = <<DESCRIPTION
Flag to indicate if the platform landing zone is enabled.

When true, assumes DNS zones will be created/managed by platform landing zone infrastructure.
When false, references existing DNS zones.
DESCRIPTION
  nullable    = false
  default     = false
}

variable "existing_zones_resource_group_resource_id" {
  type        = string
  description = <<DESCRIPTION
Resource ID of an existing resource group containing private DNS zones.

Required when use_platform_landing_zone is false. This resource group should contain
all necessary private DNS zones for private endpoint DNS integration.
DESCRIPTION
  default     = null
}
