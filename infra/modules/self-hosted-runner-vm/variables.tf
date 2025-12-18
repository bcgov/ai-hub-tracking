variable "enabled" {
  description = "Whether to create the self-hosted runner VM resources."
  type        = bool
  default     = false
  nullable    = false
}

variable "app_name" {
  description = "Name of the application"
  type        = string
  nullable    = false
}

variable "location" {
  description = "Azure region for resources"
  type        = string
  nullable    = false
}

variable "resource_group_name" {
  description = "Resource group to create the runner VM in"
  type        = string
  nullable    = false
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  nullable    = false
}

variable "subnet_id" {
  description = "Subnet ID for the runner VM NIC"
  type        = string
  nullable    = false
}

variable "vm_size" {
  description = "Azure VM size for the runner"
  type        = string
  default     = "Standard_B4as_v2"
  nullable    = false
}

variable "os_disk_type" {
  description = "Storage account type for OS disk"
  type        = string
  default     = "Premium_LRS"
  nullable    = false
}

variable "os_disk_size_gb" {
  description = "OS disk size"
  type        = number
  default     = 64
  nullable    = false
}

variable "github_actions_runner_version" {
  description = "GitHub Actions runner version to install (without leading 'v')."
  type        = string
  default     = "2.322.0"
  nullable    = false
}

variable "azure_cli_version" {
  description = "Azure CLI version to install via pip (e.g. 2.67.0)."
  type        = string
  default     = "2.67.0"
  nullable    = false
}

variable "terraform_version" {
  description = "Terraform version to install on the VM (e.g. 1.12.2)."
  type        = string
  default     = "1.12.2"
  nullable    = false
}

variable "kubectl_version" {
  description = "kubectl version to install (e.g. 1.31.0)."
  type        = string
  default     = "1.31.0"
  nullable    = false
}

variable "helm_version" {
  description = "Helm version to install (e.g. 3.16.3)."
  type        = string
  default     = "3.16.3"
  nullable    = false
}

variable "gh_cli_version" {
  description = "GitHub CLI version to install (e.g. 2.63.2)."
  type        = string
  default     = "2.63.2"
  nullable    = false
}
