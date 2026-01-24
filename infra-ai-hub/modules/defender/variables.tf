variable "resource_types" {
  description = "Map of Defender for Cloud resource types to enable with their configuration. Keys are resource type names (e.g., 'Api', 'StorageAccounts'), values are objects with subplan."
  type = map(object({
    subplan = optional(string, null)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.resource_types : contains([
        "AI",
        "Api",
        "AppServices",
        "Arm",
        "CloudPosture",
        "ContainerRegistry",
        "Containers",
        "CosmosDbs",
        "Dns",
        "KeyVaults",
        "KubernetesService",
        "OpenSourceRelationalDatabases",
        "SqlServers",
        "SqlServerVirtualMachines",
        "StorageAccounts",
        "VirtualMachines"
      ], k)
    ])
    error_message = "resource_types keys must be valid Defender for Cloud resource type names."
  }
}
