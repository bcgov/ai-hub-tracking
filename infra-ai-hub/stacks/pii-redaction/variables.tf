variable "app_env" {
  description = "Deployment environment (dev, test, prod)"
  type        = string
}

variable "app_name" {
  description = "Application / workload name prefix"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "common_tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  sensitive   = true
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
  sensitive   = true
}

variable "client_id" {
  description = "Service principal / managed identity client ID used for OIDC auth"
  type        = string
  sensitive   = true
}

variable "use_oidc" {
  description = "Use OIDC federated credentials for provider authentication"
  type        = bool
  default     = true
}

variable "shared_config" {
  description = "Shared configuration object (maps to environment tfvars shared_config block)"
  type        = any
}

variable "backend_resource_group" {
  description = "Resource group containing the Terraform state storage account"
  type        = string
}

variable "backend_storage_account" {
  description = "Storage account name for Terraform remote state"
  type        = string
}

variable "backend_container_name" {
  description = "Blob container name for Terraform remote state"
  type        = string
  default     = "tfstate"
}

variable "container_image_tag_svc_pii_redaction" {
  description = "Override container image tag for the PII redaction service (empty = use config default, typically 'latest')"
  type        = string
  default     = ""
}
